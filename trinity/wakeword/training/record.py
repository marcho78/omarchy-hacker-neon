# Records the mic through the same chain wake.py uses (the live channel, its
# offset removed, boosted and soft-limited) to a 16 kHz WAV, until stopped.
#
#     record.py OUT.wav [GAIN]
import json, signal, subprocess, sys, wave
import numpy as np

RATE = 16000
FRAME = 1280


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
    out = sys.argv[1]
    gain = float(sys.argv[2]) if len(sys.argv) > 2 else 400
    channels = mic_channels()
    record = subprocess.Popen(
        ["pw-record", "--raw", "--rate", str(RATE), "--channels", str(channels), "--format", "s16", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    w = wave.open(out, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    offset = None
    energy = np.zeros(channels)
    settle = int(RATE * 0.35)
    print(json.dumps({"ready": True, "channels": channels}), flush=True)
    try:
        while True:
            raw = record.stdout.read(FRAME * channels * 2)
            if not raw or len(raw) < FRAME * channels * 2:
                break
            frames = np.frombuffer(raw, dtype=np.int16).reshape(-1, channels).astype(np.float32)
            if offset is None:
                offset = frames[0].copy()
            rate = 0.02 if settle > 0 else 0.001
            offset += (frames.mean(axis=0) - offset) * min(1.0, rate * len(frames))
            ac = frames - offset
            energy = energy * 0.9 + (ac ** 2).mean(axis=0)
            best = int(np.argmax(energy))
            if settle > 0:
                settle -= len(frames)
                continue
            boosted = np.tanh(ac[:, best] * gain / 30000.0) * 30000.0
            w.writeframes(boosted.astype(np.int16).tobytes())
    finally:
        w.close()
        record.terminate()


if __name__ == "__main__":
    main()
