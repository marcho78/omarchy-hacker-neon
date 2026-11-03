# Cuts a recording into the bursts of speech in it, each saved as its own WAV
# with a little quiet kept on each side.
#
#     split.py IN.wav OUT_DIR PREFIX [MAX_SECONDS]
#
# Speech is any 20 ms stretch louder than THRESHOLD; pauses shorter than
# MERGE_GAP join the bursts on either side. Bursts longer than MAX_SECONDS are
# cut into pieces of that length.
import os, sys, wave
import numpy as np

RATE = 16000
STEP = 320  # 20 ms
THRESHOLD = 5000
MERGE_GAP = 0.35
PAD = 0.25
MIN_LEN = 0.3

src, out_dir, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
max_len = float(sys.argv[4]) if len(sys.argv) > 4 else 2.5
os.makedirs(out_dir, exist_ok=True)

with wave.open(src) as w:
    audio = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
frames = audio[: len(audio) // STEP * STEP].astype(np.float32).reshape(-1, STEP)
loud = np.sqrt((frames ** 2).mean(axis=1)) > THRESHOLD

bursts = []
for i, on in enumerate(loud):
    if not on:
        continue
    t = i * STEP / RATE
    if bursts and t - bursts[-1][1] <= MERGE_GAP:
        bursts[-1][1] = t + STEP / RATE
    else:
        bursts.append([t, t + STEP / RATE])

saved = []
for start, end in bursts:
    if end - start < MIN_LEN:
        continue
    pieces = int(np.ceil((end - start) / max_len))
    for p in range(pieces):
        s = start + p * (end - start) / pieces
        e = start + (p + 1) * (end - start) / pieces
        a = max(0, int((s - PAD) * RATE))
        b = min(len(audio), int((e + PAD) * RATE))
        path = os.path.join(out_dir, f"{prefix}_{len(saved):03d}.wav")
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(audio[a:b].tobytes())
        saved.append(round(e - s, 2))

print(len(saved), "clips, seconds of speech each:", saved)
