# The background data from the openWakeWord notebook, read without the old
# datasets package: the same AudioSet part, room echoes and an hour of music,
# as 16 kHz 16-bit WAVs.
import io, os, time, zipfile
from pathlib import Path
import numpy as np, soundfile as sf, librosa, scipy.io.wavfile, pyarrow.parquet as pq
from huggingface_hub import snapshot_download
from tqdm import tqdm


def save(path, audio, sr):
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != 16000:
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
    scipy.io.wavfile.write(path, 16000, (np.clip(audio, -1, 1) * 32767).astype(np.int16))


os.makedirs("audioset_16k", exist_ok=True)
bad = 0
for row in tqdm(pq.read_table("audioset/09.parquet", columns=["video_id", "audio"]).to_pylist(), mininterval=10):
    try:
        name = os.path.splitext(os.path.basename(row["audio"]["path"] or row["video_id"]))[0] + ".wav"
        audio, sr = sf.read(io.BytesIO(row["audio"]["bytes"]), dtype="float32")
        save(os.path.join("audioset_16k", name), audio, sr)
    except Exception:
        bad += 1
print("AUDIOSET DONE", len(os.listdir("audioset_16k")), "skipped", bad, flush=True)

snapshot_download("davidscripka/MIT_environmental_impulse_responses", repo_type="dataset", local_dir="mit_rirs_src")
os.makedirs("mit_rirs", exist_ok=True)
for f in sorted(Path("mit_rirs_src/16khz").glob("*.wav")):
    audio, sr = sf.read(f, dtype="float32")
    save(os.path.join("mit_rirs", f.name), audio, sr)
print("RIRS DONE", len(os.listdir("mit_rirs")), flush=True)

# The music archive downloads alongside; wait for it.
while not os.path.exists("fma_small.done"):
    if os.path.exists("fma_small.failed"):
        raise RuntimeError("the music archive did not download")
    time.sleep(5)
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
