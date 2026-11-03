// The background service: holds Trinity's voice session, answers the talk key,
// and tells the on-screen orb what is going on.
//
// It listens on a socket in the runtime dir for lines:
//
//   talk          start a conversation; while Trinity speaks, cut her off and
//                 listen; while she listens, end the conversation
//   stop          end the conversation
//   say <text>    a typed message
//   mode voice    replies to typed messages are spoken and shown (the default)
//   mode text     replies to typed messages are shown only
//   wake on|off   listen for "Hey Trinity" or not (remembered)
//   mute on|off|toggle   muted: the wake word off, and any conversation
//                 ended, her voice cut off (the bar's mute button, Super+Alt+M)
//   board clear   take the list off the desktop
//   video stop    stop the video on the desktop
//   watch         keep this connection open and stream events to it, one JSON
//                 object a line (the orb uses this)
//
// Events: {type:"state", state:"idle"|"listening"|"thinking"|"speaking",
// conversing}, {type:"you", text}, {type:"reply.delta", text}, {type:"reply",
// text}, {type:"level", value} (0 to 1, how loud she is right now, for the
// mouth), {type:"mode", mode}, {type:"wake", on}, {type:"board", board} (the
// list on the desktop, or null), {type:"video", video} (the video on the
// desktop, or null), {type:"videoControl", command, seconds}, {type:"error",
// text}.
//
// A session opens when first needed and closes 15 seconds after last use (xAI
// bills open time), so nothing is connected while Trinity is idle. In a
// conversation she listens again after each answer, and it ends when the user
// says goodbye (the agent's end-call tool), presses the key, or says nothing for
// 30 seconds.

import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { connect, send, sendText, RATE } from "./session.mjs";
import { tools, perform, userSpoke, onBoard, onVideo } from "./actions.mjs";
import { recordUsage, recordTextInput, recordSession } from "./usage.mjs";
import { record, player } from "./audio.mjs";
import { wakeWord } from "./wake.mjs";
import { greeting } from "./greeting.mjs";
import { memoryInstructions } from "./memory.mjs";

export const SOCKET = path.join(process.env.XDG_RUNTIME_DIR || "/tmp", "trinity.sock");
// Settings that last across restarts: {"wakeWord": true|false}.
const SETTINGS = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "trinity", "settings.json");
// xAI bills the whole time a session is open, so it closes soon after use.
const IDLE_CLOSE_MS = 15000;
// How long Trinity waits for the user to speak: after the talk key, and
// between turns, where the user may be thinking before the next question. xAI
// bills every second the session is open, so the wait is kept short.
const FIRST_TURN_MS = 15000;
const BETWEEN_TURNS_MS = 30000;
// A guard against a mic left open by mistake.
const MAX_LISTEN_MS = 300000;
// Her voice's loudness, as an rms, that opens the mouth all the way.
const FULL_LEVEL = 9000;

let ws = null;
let connecting = null;
let mic = null;
let speaker = null;
let speaking = false;
// From the end of the user's turn until her reply starts.
let thinking = false;
// A conversation lasts from the talk key until the user stops talking to her.
let conversing = false;
// Set when the agent ends the call (the user said goodbye): the conversation
// closes once her goodbye has been spoken.
let endAfterReply = false;
// How many times the user has spoken in this conversation.
let turns = 0;
let heardSpeech = false;
let idleTimer = null;
let noSpeechTimer = null;
let maxListenTimer = null;
// Audio from the greeting the agent starts on its own is not played: only
// replies after the user has spoken or typed are.
let userTurn = false;
// How replies to typed messages come back, and whether the current turn's
// replies are only shown: from a typed message in text mode until the user next
// speaks or types, so the answer after a desktop action stays quiet too.
let mode = "voice";
// Whether the orb's chat is open: the conversation doesn't time out meanwhile.
let chatOpen = false;
let muteTurn = false;
// When the current reply's audio started playing and how much has been queued,
// so each mouth level goes out as its audio is heard.
let playStart = 0;
let playQueued = 0;
let levelTimers = [];

const watchers = new Set();

function loadSettings() {
  try {
    return { wakeWord: true, ...JSON.parse(fs.readFileSync(SETTINGS, "utf8")) };
  } catch {
    return { wakeWord: true };
  }
}

function saveSettings() {
  try {
    fs.mkdirSync(path.dirname(SETTINGS), { recursive: true });
    const tmp = `${SETTINGS}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(settings, null, 2) + "\n");
    fs.renameSync(tmp, SETTINGS);
  } catch (err) {
    log("can't save settings:", err.message);
  }
}

const settings = loadSettings();

// The wake word. While she rests it starts a conversation, as the talk key
// does; while she speaks it cuts her off and she listens. While she listens or
// thinks it does nothing, so saying it mid-conversation never ends one.
const detector = wakeWord(() => {
  if (!conversing || speaking) talk();
}, log);

function setWakeWord(on) {
  settings.wakeWord = on;
  saveSettings();
  if (on) detector.start();
  else detector.stop();
  emit({ type: "wake", on });
}

// The desktop board: the list she last put on the wallpaper, {title, items,
// pinned, at}, or null. It clears itself after BOARD_MS unless pinned.
const BOARD_MS = 10 * 60000;
let board = null;
let boardTimer = null;

function setBoard(next) {
  clearTimeout(boardTimer);
  board = next ? { ...next, at: Date.now() } : null;
  if (board && !board.pinned) boardTimer = setTimeout(() => setBoard(null), BOARD_MS);
  emit({ type: "board", board });
}
onBoard(setBoard);

// The video on the desktop, {id, title, channel, duration, at}, or null; the
// orb plays it. Controls are passed on as they come.
let video = null;

function setVideo(next) {
  video = next ? { ...next, at: Date.now() } : null;
  emit({ type: "video", video });
}
onVideo((v) => {
  if (v.type === "play") setVideo(v.video);
  else if (v.type === "control" && v.command === "stop") setVideo(null);
  else emit({ type: "videoControl", command: v.command, seconds: v.seconds });
});

// Desktop actions the agent asked for in the response under way, whose
// results go back before she answers with them.
let toolCalls = [];

// An action's result (not billed as a text input).
function output(callId, result) {
  send(ws, { type: "conversation.item.create", item: { type: "function_call_output", call_id: callId, output: JSON.stringify(result) } });
}

function log(...args) {
  console.log(new Date().toISOString(), ...args);
}

function emit(event) {
  const line = JSON.stringify(event) + "\n";
  for (const conn of watchers) conn.write(line);
}

let lastState = "";
function emitState() {
  const state = speaking ? "speaking" : thinking ? "thinking" : mic ? "listening" : "idle";
  const key = state + conversing;
  if (key === lastState) return;
  lastState = key;
  emit({ type: "state", state, conversing });
}

// With no orb watching (it isn't running), problems still need to reach the
// user, so they go out as a notification too.
function report(text) {
  log(text);
  emit({ type: "error", text });
  if (watchers.size === 0) spawn("notify-send", ["-a", "Trinity", "Trinity", text]);
}

function keepAlive() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (!mic && !speaking && !thinking && ws) {
      log("idle, closing session");
      ws.close();
    }
  }, IDLE_CLOSE_MS);
}

async function session() {
  if (ws && ws.readyState === 1) return ws;
  if (!connecting) {
    const opened = Date.now();
    connecting = connect(onEvent, tools(), memoryInstructions())
      .then((socket) => {
        ws = socket;
        ws.on("close", () => {
          recordSession((Date.now() - opened) / 1000);
          log("session closed");
          stopListening();
          stopSpeaking();
          ws = null;
          userTurn = false;
          conversing = false;
          thinking = false;
          emitState();
        });
        log("session open");
        return ws;
      })
      .finally(() => (connecting = null));
  }
  return connecting;
}

function onEvent(event) {
  switch (event.type) {
    // The agent's own greeting, started before the user has said anything: it
    // is not wanted, and the server only hears speech once it ends.
    case "response.created":
      if (!userTurn) send(ws, { type: "response.cancel" });
      break;
    // The server marks where speech ends, but leaves asking for the reply to us.
    case "input_audio_buffer.committed":
      send(ws, { type: "response.create" });
      break;
    case "input_audio_buffer.speech_started":
      heardSpeech = true;
      userTurn = true;
      turns++;
      muteTurn = false;
      userSpoke();
      clearTimeout(noSpeechTimer);
      break;
    case "input_audio_buffer.speech_stopped":
      stopListening();
      thinking = true;
      emitState();
      break;
    case "conversation.item.input_audio_transcription.completed":
      if (event.transcript) {
        log("you:", event.transcript);
        emit({ type: "you", text: event.transcript });
      }
      break;
    case "response.output_audio_transcript.delta":
      if (userTurn) emit({ type: "reply.delta", text: event.delta });
      break;
    case "response.output_audio_transcript.done":
      if (userTurn && event.transcript) {
        log("trinity:", event.transcript);
        emit({ type: "reply", text: event.transcript });
      }
      break;
    case "response.output_audio.delta":
      if (!userTurn || muteTurn) break;
      play(Buffer.from(event.delta, "base64"));
      break;
    case "response.output_audio.done":
      if (speaker) speaker.end();
      break;
    // A tool call. The agent's end-call tool means the user has said goodbye:
    // the agent says goodbye too, and the conversation ends after. Any other is
    // a desktop action, run here. Each result goes back as it comes in; the
    // reply that uses them is asked for once the response is done.
    case "response.function_call_arguments.done": {
      const name = String(event.name || "");
      // xAI runs its own web and X searches; they arrive here too but are not
      // ours to run or answer.
      if (name === "web_search" || name === "x_search") break;
      if (name.startsWith("end_call")) {
        log("goodbye");
        endAfterReply = true;
        toolCalls.push(Promise.resolve(output(event.call_id, { ok: true })));
        break;
      }
      log("action:", name, event.arguments);
      emit({ type: "action", name });
      toolCalls.push(
        perform(name, event.arguments).then((result) => {
          log("action result:", name, JSON.stringify(result).slice(0, 300));
          output(event.call_id, result);
        }),
      );
      break;
    }
    case "response.done":
      keepAlive();
      recordUsage(event.usage, event.response?.output);
      // After tool calls, the agent answers with their results.
      if ((event.response?.output || []).some((item) => item.type === "function_call") && toolCalls.length) {
        const calls = toolCalls.splice(0);
        thinking = !speaker;
        emitState();
        Promise.all(calls).then(() => send(ws, { type: "response.create" }));
        break;
      }
      if (event.response?.status === "cancelled" || speaker) break;
      thinking = false;
      emitState();
      if (mic || !conversing || !userTurn) break;
      // A reply with nothing to play (a tool call, a shown-only reply, or a
      // failure) still hands the turn back, unless it ended the call and the
      // goodbye is to come.
      if (endAfterReply) endConversation();
      else listen();
      break;
    case "error":
      log("error:", event.error?.message || JSON.stringify(event));
      break;
    case "socket.error":
      log("socket error:", event.error.message);
      break;
  }
}

// Plays a block of her voice, and sends the orb its loudness at the moment it
// will be heard, so the mouth moves with the sound rather than ahead of it.
function play(pcm) {
  if (!speaker) {
    speaking = true;
    thinking = false;
    playStart = Date.now();
    playQueued = 0;
    speaker = player(() => {
      speaker = null;
      speaking = false;
      clearLevels();
      emitState();
      keepAlive();
      // In a conversation, Trinity listens again once she has finished, after
      // a beat so the tail of her own voice isn't picked up, unless that was
      // her goodbye.
      if (endAfterReply) return endConversation();
      if (conversing) setTimeout(() => conversing && !mic && !speaking && listen(), 300);
    });
    emitState();
  }
  speaker.write(pcm);
  // Loudness in steps of 50 ms, each sent when its audio plays.
  const step = Math.round(RATE * 0.05) * 2;
  for (let start = 0; start < pcm.length; start += step) {
    let sum = 0;
    let count = 0;
    for (let i = start; i + 1 < Math.min(pcm.length, start + step); i += 2) {
      const sample = pcm.readInt16LE(i);
      sum += sample * sample;
      count++;
    }
    const value = Math.min(1, Math.sqrt(sum / Math.max(1, count)) / FULL_LEVEL);
    const at = playStart + ((playQueued + start) / 2 / RATE) * 1000;
    levelTimers.push(setTimeout(() => emit({ type: "level", value: Math.round(value * 100) / 100 }), Math.max(0, at - Date.now())));
  }
  playQueued += pcm.length;
}

function clearLevels() {
  for (const timer of levelTimers) clearTimeout(timer);
  levelTimers = [];
  emit({ type: "level", value: 0 });
}

// The talk key. It starts a conversation: Trinity greets, listens, answers, and
// listens again until nobody speaks for a while. Pressed while she is speaking,
// it cuts her off and she listens; pressed while she is listening or thinking,
// it ends the conversation.
async function talk() {
  if (conversing && speaking) {
    stopSpeaking();
    return listen();
  }
  if (conversing) return endConversation();
  conversing = true;
  turns = 0;
  endAfterReply = false;
  return greet() ? undefined : listen();
}

// Plays the recorded greeting, if there is one; she listens once it ends (as
// after any reply). The session opens meanwhile, so the wait is hidden.
function greet() {
  const recorded = greeting();
  if (!recorded) return false;
  stopSpeaking();
  emit({ type: "reply", text: recorded.text });
  play(recorded.audio);
  speaker.end();
  session().catch(() => {});
  return true;
}

function endConversation() {
  conversing = false;
  endAfterReply = false;
  stopListening();
  stopSpeaking();
  emitState();
  log("conversation ended");
  // xAI bills the open session, and the next call reconnects behind the
  // greeting, so it closes now. With the chat open a typed message may follow,
  // so the usual idle close applies instead.
  if (ws && !chatOpen) ws.close();
}

// A typed message. In voice mode the reply is spoken and shown, in text mode
// only shown.
async function say(text) {
  let socket;
  try {
    socket = await session();
  } catch (err) {
    return report(`Can't reach xAI: ${err.message}`);
  }
  stopSpeaking();
  userSpoke();
  // In a voice conversation the mic rests while she answers, so she doesn't
  // hear herself; it opens again after, as for a spoken question.
  if (mic) stopListening();
  if (conversing) turns++;
  userTurn = true;
  muteTurn = mode === "text";
  thinking = true;
  emitState();
  log("you (typed):", text);
  recordTextInput();
  sendText(socket, text);
  keepAlive();
}

async function listen() {
  stopSpeaking();
  let socket;
  try {
    socket = await session();
  } catch (err) {
    conversing = false;
    emitState();
    return report(`Can't reach xAI: ${err.message}`);
  }
  if (!conversing || mic) return;
  heardSpeech = false;
  // How loud the mic is, logged each second it hears sound, to tell a quiet
  // mic from a problem elsewhere: the mix sent, and each of the mic's channels.
  let level = { sum: 0, count: 0, peak: 0, channels: null, at: Date.now() };
  mic = record(
    (pcm) => {
      send(socket, { type: "input_audio_buffer.append", audio: pcm.toString("base64") });
      for (let i = 0; i + 1 < pcm.length; i += 2) {
        const sample = pcm.readInt16LE(i);
        level.sum += sample * sample;
        level.count++;
        level.peak = Math.max(level.peak, Math.abs(sample));
      }
      if (Date.now() - level.at >= 1000) {
        const rms = Math.round(Math.sqrt(level.sum / Math.max(1, level.count)));
        if (rms >= 500) log(`mic level: rms ${rms}, peak ${level.peak}${level.channels ? `, channels rms ${level.channels.join("/")}` : ""}`);
        level = { sum: 0, count: 0, peak: 0, channels: null, at: Date.now() };
      }
    },
    (channels) => {
      level.channels = level.channels ? level.channels.map((v, c) => Math.max(v, channels[c])) : channels;
    },
  );
  log("listening");
  emitState();
  waitForSpeech();
  maxListenTimer = setTimeout(() => {
    stopListening();
    emitState();
  }, MAX_LISTEN_MS);
  keepAlive();
}

// Ends the conversation if the user says nothing for a while. With the chat
// open the user may be typing instead, so it keeps waiting.
function waitForSpeech() {
  clearTimeout(noSpeechTimer);
  noSpeechTimer = setTimeout(
    () => {
      if (heardSpeech || !mic) return;
      if (chatOpen) return waitForSpeech();
      log("no speech heard");
      endConversation();
    },
    turns > 0 ? BETWEEN_TURNS_MS : FIRST_TURN_MS,
  );
}

function stopListening() {
  clearTimeout(noSpeechTimer);
  clearTimeout(maxListenTimer);
  if (!mic) return;
  mic.stop();
  mic = null;
  log("stopped listening");
}

function stopSpeaking() {
  if (!speaking) return;
  if (speaker) speaker.stop();
  speaker = null;
  speaking = false;
  clearLevels();
  send(ws, { type: "response.cancel" });
  log("cut off");
}

function handle(line, conn) {
  const [command, ...rest] = line.split(" ");
  const arg = rest.join(" ").trim();
  if (command !== "say") log("command:", line);
  if (command === "talk") talk();
  else if (command === "stop") endConversation();
  else if (command === "say" && arg) say(arg);
  else if (command === "mode" && (arg === "voice" || arg === "text")) {
    mode = arg;
    emit({ type: "mode", mode });
  } else if (command === "board" && arg === "clear") {
    setBoard(null);
  } else if (command === "video" && arg === "stop") {
    setVideo(null);
  } else if (command === "wake" && (arg === "on" || arg === "off")) {
    setWakeWord(arg === "on");
  } else if (command === "mute" && (arg === "on" || arg === "off" || arg === "toggle")) {
    const muting = arg === "toggle" ? settings.wakeWord : arg === "on";
    if (muting) endConversation();
    setWakeWord(!muting);
    log(muting ? "muted" : "unmuted");
  } else if (command === "chat" && (arg === "open" || arg === "closed")) {
    // Opening the chat counts as being in the conversation, and closing it
    // gives the user the usual wait between turns before it ends.
    chatOpen = arg === "open";
    if (conversing) turns = Math.max(turns, 1);
    if (!chatOpen && mic) waitForSpeech();
  } else if (command === "watch") {
    watchers.add(conn);
    conn.on("close", () => watchers.delete(conn));
    conn.on("error", () => watchers.delete(conn));
    lastState = "";
    emitState();
    conn.write(JSON.stringify({ type: "mode", mode }) + "\n");
    conn.write(JSON.stringify({ type: "wake", on: settings.wakeWord }) + "\n");
    conn.write(JSON.stringify({ type: "board", board }) + "\n");
    conn.write(JSON.stringify({ type: "video", video }) + "\n");
    return true;
  }
  return false;
}

export function serve() {
  try {
    fs.unlinkSync(SOCKET);
  } catch {}
  const server = net.createServer((conn) => {
    let buffer = "";
    let watching = false;
    conn.on("data", (data) => {
      buffer += data.toString();
      const lines = buffer.split("\n");
      buffer = lines.pop();
      for (const line of lines) if (line.trim() && handle(line.trim(), conn)) watching = true;
    });
    // A one-off command arrives without a newline and ends the connection.
    conn.on("end", () => {
      if (buffer.trim()) handle(buffer.trim(), conn);
      if (!watching) conn.end();
    });
    conn.on("error", () => {});
  });
  server.listen(SOCKET, () => {
    fs.chmodSync(SOCKET, 0o600);
    log(`Trinity service ready on ${SOCKET}`);
    if (settings.wakeWord) detector.start();
  });
  for (const signal of ["SIGINT", "SIGTERM"]) {
    process.on(signal, () => {
      detector.stop();
      stopListening();
      stopSpeaking();
      if (ws) ws.close();
      server.close();
      process.exit(0);
    });
  }
}

// Sends a command to the running service.
export function command(line) {
  const conn = net.createConnection(SOCKET);
  conn.on("connect", () => conn.end(line));
  conn.on("error", () => {
    console.error("The Trinity service isn't running (systemctl --user start trinity).");
    spawn("notify-send", ["-a", "Trinity", "Trinity", "The Trinity service isn't running."]);
    process.exitCode = 1;
  });
}

// Streams the service's events to stdout and passes lines from stdin to it as
// commands, reconnecting if the service restarts. The orb runs this.
export function watch() {
  const input = [];
  let conn = null;
  process.stdin.setEncoding("utf8");
  let pending = "";
  process.stdin.on("data", (data) => {
    pending += data;
    const lines = pending.split("\n");
    pending = lines.pop();
    for (const line of lines) {
      if (!line.trim()) continue;
      if (conn && !conn.destroyed) conn.write(line.trim() + "\n");
      else input.push(line.trim());
    }
  });
  process.stdin.on("end", () => process.exit(0));

  function open() {
    conn = net.createConnection(SOCKET);
    conn.on("connect", () => {
      conn.write("watch\n");
      process.stdout.write(JSON.stringify({ type: "service", up: true }) + "\n");
      for (const line of input.splice(0)) conn.write(line + "\n");
    });
    conn.on("data", (data) => process.stdout.write(data));
    conn.on("error", () => {});
    conn.on("close", () => {
      process.stdout.write(JSON.stringify({ type: "service", up: false }) + "\n");
      setTimeout(open, 2000);
    });
  }
  open();
}
