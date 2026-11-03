# The hour of music from the openWakeWord notebook: the first 120 clips of the
# FMA small archive, as 16 kHz 16-bit WAVs.
import io, os, zipfile
import numpy as np, soundfile as sf, librosa, scipy.io.wavfile


def save(path, audio, sr):
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
    scipy.io.wavfile.write(path, 16000, (np.clip(audio, -1, 1) * 32767).astype(np.int16))


os.makedirs("fma", exist_ok=True)
bad = 0
with zipfile.ZipFile("fma_small.zip") as z:
    for n in sorted(n for n in z.namelist() if n.endswith(".mp3")):
        if len(os.listdir("fma")) >= 3600 // 30:
            break
        try:
            audio, sr = sf.read(io.BytesIO(z.read(n)), dtype="float32")
            save(os.path.join("fma", os.path.basename(n).replace(".mp3", ".wav")), audio, sr)
        except Exception:
            bad += 1
print("FMA DONE", len(os.listdir("fma")), "skipped", bad, flush=True)
print("ALL DONE", flush=True)
