// Microphone and speaker, through PipeWire's pw-record and pw-cat, as raw
// 16-bit mono PCM at the session's rate.

import { spawn, execFileSync } from "node:child_process";
import { RATE } from "./session.mjs";

const FORMAT = ["--raw", "--rate", String(RATE), "--format", "s16"];

// How many channels the default microphone has. A mic array such as a
// MacBook's reports its channels as AUX0, AUX1, ..., which PipeWire cannot mix
// down to mono on its own (it hands back silence), so the channels are
// recorded as they are and mixed here.
function micChannels() {
  try {
    const info = execFileSync("wpctl", ["inspect", "@DEFAULT_AUDIO_SOURCE@"], { encoding: "utf8" });
    const match = info.match(/audio\.channels = "(\d+)"/);
    return match ? Math.max(1, Number(match[1])) : 1;
  } catch {
    return 1;
  }
}

// The microphone is boosted by this much. A MacBook's T2 mic on Linux comes in
// some 50 dB quieter than normal speech, too quiet for the server to notice.
// Loud peaks are rounded off by a soft limiter rather than clipped.
const GAIN = 400;
const LIMIT = 30000;

// A noise gate: boosted that much, the room's hiss alone would sound like
// someone talking, so while the mic hears no more than hiss (its level, before
// the boost, stays under GATE_OPEN) it is turned down to GATE_FLOOR. Normal
// speech comes in at 15 to 50 before the boost, hiss at 1 to 4.
const GATE_OPEN = 9;
const GATE_FLOOR = 0.15;

function limit(sample) {
  return LIMIT * Math.tanh(sample / LIMIT);
}

// Streams the default microphone as mono; onChunk gets each block of PCM and
// onLevels each channel's loudness (rms, offset removed) per block, for
// diagnosing.
//
// On a mic array not every channel is a microphone: on a MacBook one is dead
// and one holds a constant offset with no sound in it. So the channel whose
// signal actually moves the most (sound, with any constant offset removed) is
// the one used, and it is boosted with its offset removed.
export function record(onChunk, onLevels) {
  const channels = micChannels();
  const proc = spawn("pw-record", [...FORMAT, "--channels", String(channels), "-"], { stdio: ["ignore", "pipe", "ignore"] });
  const frame = channels * 2;
  let rest = Buffer.alloc(0);
  // Per channel: a slow running average (the offset), and how much sound there
  // has been around it, decaying so the choice follows the mic as it is now.
  const offset = new Array(channels).fill(0);
  const energy = new Array(channels).fill(0);
  let warm = false;
  // The mic clicks as it starts; boosted, that is a burst at full volume, so
  // the first third of a second is sent as silence, while the offsets settle.
  let settling = Math.round(RATE * 0.35);
  // How far open the gate is, eased so it doesn't chop the start and end of
  // words.
  let gate = GATE_FLOOR;

  proc.stdout.on("data", (data) => {
    const buf = rest.length ? Buffer.concat([rest, data]) : data;
    const frames = Math.floor(buf.length / frame);
    rest = buf.subarray(frames * frame);
    if (frames === 0) return;

    if (!warm) {
      for (let c = 0; c < channels; c++) offset[c] = buf.readInt16LE(c * 2);
      warm = true;
    }
    const sums = new Array(channels).fill(0);
    for (let f = 0; f < frames; f++) {
      for (let c = 0; c < channels; c++) {
        const s = buf.readInt16LE(f * frame + c * 2);
        offset[c] += (s - offset[c]) * (settling > 0 ? 0.02 : 0.001);
        const ac = s - offset[c];
        sums[c] += ac * ac;
      }
    }
    for (let c = 0; c < channels; c++) energy[c] = energy[c] * 0.9 + sums[c] / frames;
    let best = 0;
    for (let c = 1; c < channels; c++) if (energy[c] > energy[best]) best = c;

    // Open quickly when the chosen channel rises above hiss, close slowly.
    const level = Math.sqrt(sums[best] / frames);
    const target = level >= GATE_OPEN ? 1 : GATE_FLOOR;
    const out = Buffer.alloc(frames * 2);
    for (let f = 0; f < frames; f++) {
      if (settling > 0) {
        settling--;
        continue;
      }
      gate += (target - gate) * (target > gate ? 0.01 : 0.0004);
      const ac = (buf.readInt16LE(f * frame + best * 2) - offset[best]) * GAIN * gate;
      out.writeInt16LE(Math.round(limit(ac)), f * 2);
    }
    if (onLevels) onLevels(sums.map((sum) => Math.round(Math.sqrt(sum / frames))));
    onChunk(out);
  });
  return { stop: () => proc.kill(), channels };
}

// Plays PCM blocks on the default speaker as they arrive. end() lets what is
// queued finish; stop() cuts it off.
export function player(onFinished) {
  const proc = spawn("pw-cat", ["--playback", ...FORMAT, "--channels", "1", "-"], { stdio: ["pipe", "ignore", "ignore"] });
  proc.on("exit", () => onFinished && onFinished());
  proc.stdin.on("error", () => {});
  return {
    write: (pcm) => proc.stdin.writable && proc.stdin.write(pcm),
    end: () => proc.stdin.end(),
    stop: () => proc.kill(),
  };
}
