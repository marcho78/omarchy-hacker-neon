// A realtime session with Trinity's saved xAI agent.
//
// What the agent does on its own, and how a session handles it:
// - It greets as soon as a session opens. connect() resolves only once the
//   session is set up, and a message or speech sent then cancels the greeting
//   (its response.done carries status "cancelled").
// - session.update clears the agent's instructions unless they are sent again,
//   so setup() copies them from the first session.updated.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import WebSocket from "ws";

export const AGENT_ID = "agent_KpbV5OX2nCtdtK80";
const URL = `wss://api.x.ai/v1/realtime?agent_id=${AGENT_ID}`;
const KEY_FILE = path.join(os.homedir(), ".config", "trinity", "xai-api-key");

// Trinity's voice and audio: Eve, 16-bit mono PCM at 24 kHz both ways, and the
// server deciding when the user has stopped talking. It waits for a second and
// a half of silence first, so a pause to think mid-sentence isn't taken as the
// end of it.
export const RATE = 24000;
const SESSION = {
  voice: "eve",
  audio: {
    input: { format: { type: "audio/pcm", rate: RATE } },
    output: { format: { type: "audio/pcm", rate: RATE } },
  },
  turn_detection: { type: "server_vad", silence_duration_ms: 1500, prefix_padding_ms: 400 },
};

export function apiKey() {
  if (process.env.XAI_API_KEY) return process.env.XAI_API_KEY.trim();
  try {
    return fs.readFileSync(KEY_FILE, "utf8").trim();
  } catch {
    throw new Error(`No xAI API key: set XAI_API_KEY or save it in ${KEY_FILE}`);
  }
}

// Opens a session and applies Trinity's voice and audio settings, and adds
// `tools` (function tools) to the agent's own (its web and X search, its
// end-call tool), and `extra` to its instructions. Resolves with the socket
// once the agent has acknowledged them; onEvent sees every event.
export function connect(onEvent, tools = [], extra = "") {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(URL, { headers: { Authorization: `Bearer ${apiKey()}` } });
    let configured = false;

    ws.on("message", (raw) => {
      const event = JSON.parse(raw.toString());
      if (event.type === "session.updated" && !configured) {
        configured = true;
        const ours = new Set(tools.map((t) => t.name));
        const theirs = (event.session.tools || []).filter((t) => !ours.has(t.name || (t.function && t.function.name)));
        ws.send(JSON.stringify({ type: "session.update", session: { ...SESSION, instructions: (event.session.instructions || "") + extra, tools: theirs.concat(tools) } }));
        return;
      }
      if (event.type === "session.updated" && configured && ws.readyState === WebSocket.OPEN && !ws.ready) {
        ws.ready = true;
        resolve(ws);
      }
      onEvent(event);
    });
    ws.on("error", (err) => (ws.ready ? onEvent({ type: "socket.error", error: err }) : reject(err)));
    ws.on("unexpected-response", (req, res) => {
      let body = "";
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => reject(new Error(`xAI refused the connection (${res.statusCode}): ${body.slice(0, 200)}`)));
    });
  });
}

export function send(ws, event) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(event));
}

export function sendText(ws, text) {
  send(ws, { type: "conversation.item.create", item: { type: "message", role: "user", content: [{ type: "input_text", text }] } });
  send(ws, { type: "response.create" });
}
