// Trinity's greeting when a conversation starts ("Hi Alex, how can I help?"):
// recorded once in her own voice, then played from the file, so it is instant
// and costs nothing each time.
//
//   trinity greeting "<text>"   record (or re-record) the greeting
//
// The audio (16-bit mono PCM at 24 kHz) and its text are kept with the user's
// data, in ~/.local/share/trinity/greeting.pcm and greeting.json.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { connect, sendText } from "./session.mjs";
import { recordUsage, recordTextInput, recordSession } from "./usage.mjs";

const DIR = path.join(process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share"), "trinity");
const AUDIO = path.join(DIR, "greeting.pcm");
const TEXT = path.join(DIR, "greeting.json");

// The recorded greeting, {text, audio}, or null when there is none.
export function greeting() {
  try {
    return { text: JSON.parse(fs.readFileSync(TEXT, "utf8")).text, audio: fs.readFileSync(AUDIO) };
  } catch {
    return null;
  }
}

// Has Trinity say the text once and saves her voice. Only the reply to our
// message is kept: the agent's own greeting when the session opens is
// cancelled by it.
export async function recordGreeting(text) {
  const chunks = [];
  let ours = null;
  let sent = false;
  let transcript = "";
  let done;
  const finished = new Promise((resolve) => (done = resolve));
  const opened = Date.now();
  const ws = await connect((event) => {
    if (event.type === "response.created" && sent && !ours) ours = event.response?.id;
    if (!ours || (event.response_id && event.response_id !== ours)) return;
    if (event.type === "response.output_audio.delta") chunks.push(Buffer.from(event.delta, "base64"));
    if (event.type === "response.output_audio_transcript.done") transcript = event.transcript || "";
    if (event.type === "response.done" && event.response?.id === ours) {
      recordUsage(event.usage, event.response?.output);
      done();
    }
  });
  sent = true;
  recordTextInput();
  sendText(ws, `Say exactly this, warmly, and nothing else: "${text}"`);
  await finished;
  ws.close();
  recordSession((Date.now() - opened) / 1000);
  const audio = Buffer.concat(chunks);
  if (!audio.length) throw new Error("No audio came back.");
  fs.mkdirSync(DIR, { recursive: true, mode: 0o700 });
  fs.writeFileSync(AUDIO, audio, { mode: 0o600 });
  fs.writeFileSync(TEXT, JSON.stringify({ text }, null, 2) + "\n", { mode: 0o600 });
  return { transcript, seconds: audio.length / 2 / 24000 };
}
