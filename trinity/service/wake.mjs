// The "Hey Trinity" wake word: runs the detector (trinity/wakeword/wake.py) on
// this computer and calls onWake each time it hears the phrase. No audio
// leaves the computer for this; the mic only goes to xAI once a conversation
// starts.

import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "wakeword");
const PYTHON = path.join(DIR, ".venv", "bin", "python");
const SCRIPT = path.join(DIR, "wake.py");
// Should the detector stop on its own (the mic going away, a crash), it starts
// again after this.
const RESTART_MS = 5000;

export function wakeWord(onWake, log) {
  let child = null;
  let wanted = false;
  let restartTimer = null;

  function start() {
    wanted = true;
    clearTimeout(restartTimer);
    if (child) return;
    child = spawn(PYTHON, [SCRIPT], { stdio: ["ignore", "pipe", "ignore"] });
    let buffer = "";
    child.stdout.on("data", (data) => {
      buffer += data.toString();
      const lines = buffer.split("\n");
      buffer = lines.pop();
      for (const line of lines) {
        let event;
        try {
          event = JSON.parse(line);
        } catch {
          continue;
        }
        if (event.ready) log("wake word listening");
        if (event.wake) {
          log(`wake word heard (${event.score})`);
          onWake();
        }
      }
    });
    // It can't start at all (no detector installed): said once, not retried.
    child.on("error", (err) => {
      log("wake word can't start:", err.message);
      child = null;
      wanted = false;
    });
    child.on("exit", (code) => {
      child = null;
      if (!wanted) return;
      log(`wake word stopped (${code}), starting again`);
      restartTimer = setTimeout(start, RESTART_MS);
    });
  }

  function stop() {
    wanted = false;
    clearTimeout(restartTimer);
    if (child) child.kill();
  }

  return { start, stop };
}
