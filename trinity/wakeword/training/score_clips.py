# Scores wake word models on WAV clips: each clip is fed the way wake.py feeds
# the mic (80 ms blocks), between a second of silence on each side, and the
# best score is kept. "loud" also boosts the clip to the level the mic comes in
# at and soft-limits it, as wake.py does.
import glob, os, sys, wave
import numpy as np
from openwakeword.model import Model

clips_dir, models = sys.argv[1], sys.argv[2:]


def read(path):
    with wave.open(path) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)


def best(model, name, audio):
    model.reset()
    padded = np.concatenate([np.zeros(16000), audio, np.zeros(16000)]).astype(np.int16)
    top = 0.0
    for i in range(0, len(padded) - 1280 + 1, 1280):
        top = max(top, float(model.predict(padded[i:i + 1280])[name]))
    return top


def loud(audio):
    rms = np.sqrt((audio ** 2).mean()) or 1
    return np.tanh(audio * (20000 / rms) / 30000) * 30000


for path in models:
    model = Model(wakeword_model_paths=[path])
    name = next(iter(model.models))
    for kind in ("pos", "neg"):
        files = sorted(glob.glob(os.path.join(clips_dir, kind, "*.wav")))
        plain = [best(model, name, read(f)) for f in files]
        boosted = [best(model, name, loud(read(f))) for f in files]
        hit = lambda s: sum(x >= 0.5 for x in s)
        print(f"{name:16} {kind}: plain {hit(plain)}/{len(files)} hit (median {np.median(plain):.3f})   loud {hit(boosted)}/{len(files)} hit (median {np.median(boosted):.3f})", flush=True)
