#!/usr/bin/env node
// Trinity: a voice and chat agent for the Omarchy desktop.
//
//   trinity serve   run the background service (systemd starts it)
//   trinity talk    start or stop listening (the talk key, Super+Z)
//   trinity stop    end the conversation
//   trinity say <text>   send a typed message
//   trinity watch   stream events to stdout, commands from stdin (the orb)
//   trinity greeting "<text>"   record the greeting she says when called
//   trinity mute [on|off|toggle]   mute her (toggle by default)
//   trinity         typed chat in the terminal, replies as text
//
// The xAI API key comes from XAI_API_KEY, or else ~/.config/trinity/xai-api-key
// (which should be readable by its owner only).

import readline from "node:readline";
import { connect, sendText } from "./session.mjs";
import { serve, command, watch } from "./serve.mjs";
import { recordGreeting } from "./greeting.mjs";

const mode = process.argv[2];

if (mode === "serve") serve();
else if (mode === "talk" || mode === "stop") command(mode);
else if (mode === "say") command(`say ${process.argv.slice(3).join(" ")}`);
else if (mode === "watch") watch();
else if (mode === "mute") command(`mute ${process.argv[3] || "toggle"}`);
else if (mode === "greeting") greetingCommand(process.argv.slice(3).join(" ").trim());
else chat();

async function greetingCommand(text) {
  if (!text) {
    console.error('Usage: trinity greeting "Hi, how can I help?"');
    process.exit(1);
  }
  try {
    const { transcript, seconds } = await recordGreeting(text);
    console.log(`Recorded ${seconds.toFixed(1)}s. She said: ${transcript}`);
    process.exit(0);
  } catch (err) {
    console.error(`Couldn't record the greeting: ${err.message}`);
    process.exit(1);
  }
}

// Each line typed is sent as a message and the reply's transcript printed as it
// streams in. Messages go out one at a time, each after the previous reply, so
// every message gets its own answer; piped input gets all its replies before
// the chat closes.
async function chat() {
  const queued = [];
  let awaiting = false;
  let inputEnded = false;
  let replying = false;
  let ws;

  const prompt = () => process.stdout.write("\nyou> ");

  function sendNext() {
    if (awaiting || !ws || queued.length === 0) return;
    awaiting = true;
    sendText(ws, queued.shift());
  }

  function finish() {
    if (inputEnded && !awaiting && queued.length === 0) ws.close();
    else prompt();
  }

  const input = readline.createInterface({ input: process.stdin });
  input.on("line", (line) => {
    const text = line.trim();
    if (!text) return prompt();
    queued.push(text);
    sendNext();
  });
  input.on("close", () => {
    inputEnded = true;
    if (ws && !awaiting && queued.length === 0) ws.close();
  });

  try {
    ws = await connect((event) => {
      switch (event.type) {
        case "response.output_audio_transcript.delta":
        case "response.output_text.delta":
          if (!awaiting) break; // the agent's own greeting
          if (!replying) process.stdout.write("trinity> ");
          replying = true;
          process.stdout.write(event.delta);
          break;
        case "response.done":
          // A message sent while the agent greets cancels the greeting; only a
          // finished reply answers one.
          if (event.response?.status === "cancelled" || !awaiting) break;
          if (replying) process.stdout.write("\n");
          replying = false;
          awaiting = false;
          sendNext();
          finish();
          break;
        case "error":
          console.error(`\nerror: ${event.error?.message || JSON.stringify(event)}`);
          break;
      }
    });
  } catch (err) {
    console.error(`Connection failed: ${err.message}`);
    process.exit(1);
  }

  ws.on("close", (code) => {
    console.log(`\nDisconnected (${code}).`);
    process.exit(0);
  });
  console.log("Connected to Trinity. Type a message, Ctrl+D to quit.");
  if (queued.length === 0 && inputEnded) return ws.close();
  sendNext();
  if (!awaiting) prompt();
}
