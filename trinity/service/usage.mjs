// Trinity's own use of the xAI API, added up per day for the Neon HUD:
// voice (how long sessions were open, which is what xAI bills), how long she
// spoke, text tokens, text inputs (typed messages; actions' results are free),
// and web and X searches.
//
// Every response.done reports its usage; its billable_audio_seconds is the
// session's running total so far, not the reply's, so voice is counted once
// per session, from its open time, by recordSession. The totals go to
// ~/.local/state/trinity/usage.json:
//   {"days": {"2026-10-28": {"voiceSeconds", "spokenSeconds", "audioTokensIn",
//    "audioTokensOut", "textTokensIn", "textTokensOut", "textInputs",
//    "webSearches", "xSearches", "replies"}}}
// Two weeks are kept.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const FILE = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state"), "trinity", "usage.json");
const KEEP_DAYS = 14;

function today() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

const EMPTY = {
  voiceSeconds: 0, spokenSeconds: 0, audioTokensIn: 0, audioTokensOut: 0, textTokensIn: 0, textTokensOut: 0,
  textInputs: 0, webSearches: 0, xSearches: 0, replies: 0,
};

function load() {
  try {
    const data = JSON.parse(fs.readFileSync(FILE, "utf8"));
    if (data && typeof data.days === "object") return data;
  } catch {}
  return { days: {} };
}

// Adds one reply's usage. Searches are the server's web_search and x_search
// calls among the reply's output.
export function recordUsage(usage, output) {
  if (!usage && !(output || []).length) return;
  update((day) => {
    const u = usage || {};
    const n = (v) => Number(v) || 0;
    day.spokenSeconds += n(u.output_audio_seconds);
    day.audioTokensIn += n(u.input_token_details && u.input_token_details.audio_tokens);
    day.audioTokensOut += n(u.output_token_details && u.output_token_details.audio_tokens);
    day.textTokensIn += n(u.input_token_details && u.input_token_details.text_tokens);
    day.textTokensOut += n(u.output_token_details && u.output_token_details.text_tokens);
    for (const item of output || []) {
      if (item.type !== "function_call") continue;
      if (item.name === "web_search") day.webSearches++;
      if (item.name === "x_search") day.xSearches++;
    }
    day.replies++;
  });
}

// A session that has closed: xAI bills the whole time it was open, by the
// second, rounded up.
export function recordSession(seconds) {
  if (seconds > 0) update((day) => (day.voiceSeconds += Math.ceil(seconds)));
}

// A typed message sent into the conversation (xAI bills a fee per text input).
export function recordTextInput() {
  update((day) => day.textInputs++);
}

function update(change) {
  const data = load();
  const key = today();
  const day = (data.days[key] = Object.assign({}, EMPTY, data.days[key] || {}));
  change(day);

  const keys = Object.keys(data.days).sort();
  for (const old of keys.slice(0, Math.max(0, keys.length - KEEP_DAYS))) delete data.days[old];
  data.updatedAt = new Date().toISOString();
  try {
    fs.mkdirSync(path.dirname(FILE), { recursive: true });
    const tmp = `${FILE}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(data, null, 1) + "\n");
    fs.renameSync(tmp, FILE);
  } catch {}
}
