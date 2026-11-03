"""Trinity's wake word: listens to the microphone on this computer and prints a
line each time it hears the wake word. Nothing is sent anywhere.

    wake.py [--model PATH] [--threshold 0.5] [--gain 400] [--scores]

The mic is read the way the Trinity service reads it (see service/audio.mjs):
on a mic array not every channel is a microphone, so the channel with the most
sound is used, its constant offset removed, and it is boosted, since a
MacBook's T2 mic comes in some 50 dB quieter than normal speech.

The model is hey_trinity.onnx beside this file: openWakeWord trained on
synthetic voices plus recordings of the user, made through this same chain.

--scores prints how sure the detector was each second, for testing.
"""

import argparse
import json
import os
import subprocess
import sys
import time

import numpy as np
from openwakeword.model import Model

RATE = 16000
FRAME = 1280  # 80 ms, what openWakeWord takes at a time


def mic_channels():
    try:
        info = subprocess.run(["wpctl", "inspect", "@DEFAULT_AUDIO_SOURCE@"], capture_output=True, text=True, timeout=5).stdout
        for line in info.splitlines():
            if "audio.channels" in line:
                return max(1, int(line.split("=")[1].strip().strip('"')))
    except Exception:
        pass
    return 1


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=os.path.join(here, "hey_trinity.onnx"))
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--gain", type=float, default=400)
    parser.add_argument("--scores", action="store_true")
    args = parser.parse_args()

    model = Model(wakeword_model_paths=[args.model])
    name = next(iter(model.models))
    channels = mic_channels()
    record = subprocess.Popen(
        ["pw-record", "--raw", "--rate", str(RATE), "--channels", str(channels), "--format", "s16", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    offset = None
    energy = np.zeros(channels)
    settle = int(RATE * 0.35)  # the mic's start-up click
    last_hit = 0.0
    second_best = 0.0
    second_level = 0.0
    second_at = time.time()
    print(json.dumps({"ready": True, "model": name, "channels": channels}), flush=True)

    while True:
        raw = record.stdout.read(FRAME * channels * 2)
        if not raw or len(raw) < FRAME * channels * 2:
            break
        frames = np.frombuffer(raw, dtype=np.int16).reshape(-1, channels).astype(np.float32)
        if offset is None:
            offset = frames[0].copy()
        rate = 0.02 if settle > 0 else 0.001
        # A running offset per channel, close enough over one 80 ms block.
        offset += (frames.mean(axis=0) - offset) * min(1.0, rate * len(frames))
        ac = frames - offset
        energy = energy * 0.9 + (ac ** 2).mean(axis=0)
        best = int(np.argmax(energy))
        if settle > 0:
            settle -= len(frames)
            continue
        boosted = np.tanh(ac[:, best] * args.gain / 30000.0) * 30000.0
        score = float(model.predict(boosted.astype(np.int16))[name])

        second_best = max(second_best, score)
        second_level = max(second_level, float(np.sqrt((boosted ** 2).mean())))
        now = time.time()
        if args.scores and now - second_at >= 1:
            print(json.dumps({"score": round(second_best, 3), "level": round(second_level)}), flush=True)
            second_best = 0.0
            second_level = 0.0
            second_at = now
        # One wake per utterance: the score stays high for a few frames.
        if score >= args.threshold and now - last_hit > 2:
            last_hit = now
            print(json.dumps({"wake": name, "score": round(score, 3)}), flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
