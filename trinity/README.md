# Trinity

A voice and chat assistant for the Omarchy desktop. You call her with
**Super+Z** (or "Hey Trinity", once you've trained the wake word), talk, and
she answers in her own voice and acts on your desktop: windows, settings,
apps, YouTube on the desktop, lists on the wallpaper, your herdr coding
agents, and more. A holographic orb shows while she listens and talks; click
it to type instead.

She runs on xAI's realtime voice API with a voice agent you create in your own
xAI account (the voice is **Eve**). Everything else runs on your computer.

**This is the author's setup as it is,** to show how it's done. A few paths and
one ID are set for the author's machine; [Setup](#setup) lists each one and
what to change. [AGENTS.md](AGENTS.md) lets an AI agent do the setup for you.

## What she can do

| Area | Actions |
|---|---|
| Windows | List, open apps, focus, close, move to another workspace, maximize, fullscreen, minimize, float or tile, two side by side, switch workspace, workspace layout |
| System | Volume, brightness, Wi-Fi, Bluetooth, do not disturb, night light, lock the screen |
| Look | List and change themes, next wallpaper, the app drawer |
| Screen | Screenshots, screen recording, read the text on the screen or a screenshot (recognized on your computer; only the text goes to xAI) |
| Files and web | Write a file, open a file, open a link, press keys, type text |
| Desktop | Put a list on the wallpaper (it decodes line by line), clear it, hide or show the desktop widgets, play a YouTube video (on the desktop, full screen or a pop-out window) and control it |
| Apps | [Uber Notebook](https://github.com/marcho78/ubernotebook) (notes), [Uber TV](https://github.com/marcho78/uber-tv) (channels, guide, recordings), [Hill Chart](https://github.com/marcho78/omarchy-hillchart), and each app's guide |
| Coding agents | Everything in [herdr](https://herdr.dev): workspaces, tabs, panes, agents; read what an agent is doing, jump to it, give it a task |
| Memory | Remember something you ask her to, recall it, forget it |
| xAI's own | Web search, X search, ending the call |

Actions that close, remove or run things, replace a file, type into a
terminal, or give an agent a task ask you first.

## How it works

```
 Super+Z / "Hey Trinity"          the orb, chat, board, video, mute button
          │                                      ▲
          ▼                                      │ trinity watch (events)
 ┌─────────────────────── service (Node) ────────┴──────┐
 │ serve.mjs   the service: conversation, mic, speaker   │
 │ session.mjs the xAI realtime session ──────────────────┼──▶ xAI voice agent
 │ actions.mjs the actions she can take                  │    (only while talking)
 │ wake.mjs ─▶ wakeword/wake.py (openWakeWord, local)     │
 └───────────────────────────────────────────────────────┘
```

- **`service/`** runs as a systemd user service (`trinity.mjs serve`). It
  listens for the wake word on your computer, and only opens a session with
  xAI when you talk to her. xAI bills every second a session is open, so it
  closes 15 seconds after use.
- **A conversation** starts with her recorded greeting, then she listens
  again after each answer. It ends when you say goodbye, press Super+Z, or
  say nothing for 30 seconds.
- **Audio** goes through PipeWire (`pw-record`, `pw-cat`). The mic only goes
  to xAI during a conversation.
- **`plugin/`** is an Omarchy shell plugin (`marcho.trinity`): the orb and
  chat window, the board on the wallpaper, the video, and a mute button for
  the bar. It follows the service through `trinity.mjs watch`.
- **`wakeword/wake.py`** runs the "Hey Trinity" detector on your computer.
  **No model is included:** the author's was trained on their own voice. See
  [Train your own wake word](#train-your-own-wake-word).

| File | What it is |
|---|---|
| `service/trinity.mjs` | The command: `serve`, `talk`, `stop`, `say`, `watch`, `greeting`, `mute`, or a typed chat |
| `service/serve.mjs` | The service: conversation, wake word, greeting, board and video state |
| `service/session.mjs` | The xAI session: agent ID, voice, audio format, turn detection |
| `service/actions.mjs` | Every action, and which ones ask first |
| `service/audio.mjs` | Mic and speaker through PipeWire |
| `service/wake.mjs` | Runs `wakeword/wake.py` and restarts it if it stops |
| `service/greeting.mjs` | Records and plays the greeting |
| `service/memory.mjs` | What she remembers |
| `service/usage.mjs` | Her xAI use per day |
| `plugin/` | The shell plugin (orb, chat, board, video, mute button) |
| `wakeword/wake.py` | The wake word detector |
| `wakeword/training/` | The scripts for training your own wake word |
| `install-service.sh` | Installs (or `--remove`s) the systemd user service |

## Requirements

- **Omarchy 4.5** (built on 4.5.0rc1), with PipeWire.
- **Node** (with npm).
- **An xAI account:** an API key, and a voice agent you create (step 3 below).
- **For the wake word:** Python 3.12 and [uv](https://docs.astral.sh/uv/), and
  a model you train.
- **For some actions:**
  - `wtype`, to press keys and type text
  - `grim` and `tesseract` (with English data), to read the screen
  - `yt-dlp` and [Uber TV](https://github.com/marcho78/uber-tv), to play
    videos (the video plays through Uber TV's streamer)
  - [herdr](https://herdr.dev), for the coding agents
  - [Uber Notebook](https://github.com/marcho78/ubernotebook) and
    [Hill Chart](https://github.com/marcho78/omarchy-hillchart), for those
    apps

Any of these can be missing; only the actions that use it won't work.

## Setup

1. **This folder** is `trinity/` in the omarchy-hacker-neon repo; keep the
   repo where it will stay. Below, `<folder>` means this folder's full path,
   for example `~/projects/omarchy-hacker-neon/trinity`.

2. **Install the service's package:**

   ```bash
   cd <folder>/service && npm install
   ```

3. **Connect your xAI account.**
   - Save your API key in `~/.config/trinity/xai-api-key`, readable only by
     you:

     ```bash
     mkdir -p ~/.config/trinity && chmod 700 ~/.config/trinity
     $EDITOR ~/.config/trinity/xai-api-key   # paste the key, save
     chmod 600 ~/.config/trinity/xai-api-key
     ```

     (Or set `XAI_API_KEY` in the service's environment.)
   - In the xAI console, **create a voice agent**: write its instructions (who
     she is and how she talks), and turn on web search, X search and the
     end-call tool. The service adds the voice, the audio settings, her
     actions and her memory to every session.
   - Put the agent's ID in `service/session.mjs`:

     ```js
     export const AGENT_ID = "agent_...";
     ```

4. **Change the paths set for the author's machine:**

   | Where | Set to | Change it to |
   |---|---|---|
   | `plugin/Trinity.qml` and `plugin/MuteButton.qml`: `node` | `~/.local/share/mise/installs/node/latest/bin/node` | Your node's full path (`command -v node`) |
   | `plugin/Trinity.qml` and `plugin/MuteButton.qml`: `service` | `~/projects/o-interfaces/trinity/service/trinity.mjs` | `<folder>/service/trinity.mjs` |
   | `plugin/Trinity.qml`: `widgetsTool` | `~/.local/bin/o-widgets` | Nothing: the repo's setup installs `o-widgets` there. Without it, `[ HIDE ]` on the board and video does nothing. |
   | `plugin/Video.qml`: `streamer` | Uber TV's `om-pg-streamer` | Nothing, if Uber TV is installed |
   | `service/actions.mjs`: the app guides (near `notes:`, `tv:`, `hill:`) | The apps' installed plugin folders | Nothing, if the apps are installed under those ids |

5. **Set the mic boost.** Both places boost the mic 400×, for a MacBook's T2
   mic, which comes in about 50 dB quieter than normal speech. For any other
   mic, start at 1 and raise it if she can't hear you:
   - `service/audio.mjs`: `const GAIN = 400;`
   - `wakeword/wake.py`: `--gain` (default 400)

6. **Install the plugin** (its folder name must be its id):

   ```bash
   cp -r <folder>/plugin ~/.config/omarchy/plugins/marcho.trinity
   omarchy-shell shell rescanPlugins
   omarchy plugin enable marcho.trinity --section right
   ```

   The shell reloads its plugins after a rescan and doesn't answer for a
   while; if the enable says it isn't responding, wait half a minute and run
   it again. `--section right` puts the mute button on the right of the bar.

7. **Install the service:**

   ```bash
   <folder>/install-service.sh
   ```

8. **Mute the wake word** until you have a model (it's on by default):

   ```bash
   node <folder>/service/trinity.mjs mute on
   ```

9. **Add the keys** to `~/.config/hypr/bindings.lua`, with your node's full
   path and your folder:

   ```lua
   o.bind("SUPER + Z", "Trinity: talk", "<node> <folder>/service/trinity.mjs talk")
   o.bind("SUPER + ALT + M", "Trinity: mute or unmute", "<node> <folder>/service/trinity.mjs mute toggle")
   ```

10. **Record her greeting**, in her voice, once:

    ```bash
    node <folder>/service/trinity.mjs greeting "Hi Alex, how can I help?"
    ```

    It's saved on your computer and played each time you call her, so it's
    instant and free. Without one, she just listens.

## Using her

| To | Do |
|---|---|
| Talk | **Super+Z**, then speak. Press it again to stop her or cut her off. |
| Talk hands-free | Say **"Hey Trinity"** (needs a trained model, and the wake word unmuted) |
| Type | Click the orb for the chat window, or run `node <folder>/service/trinity.mjs` for a chat in the terminal |
| Send one message | `node <folder>/service/trinity.mjs say "turn on night light"` |
| Mute or unmute the wake word | The mic button on the bar, **Super+Alt+M**, or `trinity.mjs mute on\|off\|toggle` |
| End a conversation | Say goodbye, press Super+Z, or stay quiet for 30 seconds |
| Make her remember | "Remember that ..." (she only keeps what you ask her to) |
| See what she did | `journalctl --user -u trinity -f` (every action is logged) |

## The desktop board and video

Two things she can put on your desktop, between the Agent Radar and the HUD,
behind your windows. Both need Trinity running with your xAI key; the video
also needs `yt-dlp` and [Uber TV](https://github.com/marcho78/uber-tv).

### The board: lists that decode onto the wallpaper

Ask for anything as a list: *"put today's top news on my desktop"*, *"show my
to-dos on screen"*, *"list what my agents are doing"*. She says a one-line
summary out loud and puts the list on the wallpaper:

- A header, `// TRINITY · <TITLE> · <time> · <n> ITEMS`, a glowing rule, then
  the lines, each arriving as scrambled glyphs that resolve into its text, one
  after another.
- Up to 12 lines, each with an optional tag in front, a source or a category
  such as `REUTERS` or `TODO`.
- It clears itself after 10 minutes, unless you ask her to keep it there
  (then the header says `PINNED`).
- A new list replaces the one before, and shows even if the board was hidden.

| To | Do |
|---|---|
| Take it away | `[ CLEAR ]` on the board, **Super+Alt+X**, or *"clear the screen"* |
| Tuck it away | `[ HIDE ]`: it leaves a **BRIEF** tab at the top edge; click the tab to bring it back |

### The video: YouTube on the desktop

Ask *"play the newest Kurzgesagt video"*, *"play some lofi hip hop"*, or give her
a YouTube link. She finds it with `yt-dlp`, and it plays on the desktop in a
16:9 frame with a glowing green edge, with its title, time and a progress line
under it. It plays the best H.264 up to 1080p, with the video's original
audio, through Uber TV's streamer. Live streams haven't been tested.

It comes in three sizes:

| Size | What it is | Get there |
|---|---|---|
| On the desktop | Under the bar, behind your windows | Where it starts; `[ ↙ BACK TO DESKTOP ]`, Esc, or *"put it back on the desktop"* |
| Full screen | Over everything, the bar included; the controls fade after 2.5 seconds and come back when the mouse moves | `[ ⤢ FULL SCREEN ]`, double-click the picture, or *"full screen"* |
| Pop-out window | A small window in front of everything, on every workspace: Omarchy's picture-in-picture rule floats and pins it at 600×338 in the top right and keeps it 16:9; you can move and resize it | `[ ⧉ POP OUT ]`, or *"pop it out"* |

| To | Do |
|---|---|
| Pause or play | Click the picture, `[ ❚❚ PAUSE ]` / `[ ▶ PLAY ]`, Space, or *"pause"* |
| Jump | Click the progress line; ← and → skip 10 seconds (full screen and pop-out); or *"skip ahead two minutes"* |
| Louder or quieter | ↑ and ↓ (full screen), or *"louder"* / *"quieter"* |
| Leave full screen | Esc, F, or double-click |
| Stop | `[ ■ STOP ]`, or *"stop the video"*; it also stops at the end |
| Hide it | `[ HIDE ]` (on the desktop only): it leaves a **VIDEO** tab at the bottom edge, and the sound keeps playing |
| Close the pop-out | Super+W puts the video back on the desktop |

From a terminal or a script:

- `~/.local/bin/o-widgets hide|show brief` (the board) or `video`
- `omarchy-shell marcho.trinity.video status|toggle|stop|full|window|panel`

## What stays on your computer

| Where | What |
|---|---|
| `~/.config/trinity/` | `xai-api-key` (yours only, mode 600), `settings.json` (wake word on or off), `orb.json` (where the orb sits) |
| `~/.local/share/trinity/` | `greeting.pcm` and `greeting.json`, `memory.json`, your wake word recordings |
| `~/.local/state/trinity/` | `usage.json`, her xAI use per day |

The wake word, screen reading and memory all run on your computer. Your voice
goes to xAI only while you're in a conversation; read screens go as text only.

## Train your own wake word

There's no ready-made "Hey Trinity" model, and one trained on someone else's
voice won't hear yours well: the author's first two models, trained on
synthetic voices only (1,000, then 20,000 clips), caught **none** of the
author's real tries. Adding recordings of the author's own voice fixed it. So
you train one on synthetic voices **and** on your own recordings, with
[openWakeWord](https://github.com/dscripka/openWakeWord)'s training script, on
any Linux machine with an NVIDIA GPU: your own, or one rented by the hour from
any cloud. The author used an H200 (an H100 does as well): each training run
took 10–25 minutes, the whole job about 2 hours, setup included.

The author's scripts are in `wakeword/training/`:

| File | What it does | Runs on |
|---|---|---|
| `record.py` | Records the mic through `wake.py`'s exact chain (the loudest channel, its offset removed, your gain, a soft limit) to a 16 kHz WAV | This computer |
| `split.py` | Cuts a recording into one clip per burst of speech | This computer |
| `score_clips.py` | Scores models on a folder of clips with `pos/` and `neg/` in it | This computer |
| `data3.py`, `fma.py` | Fetch the background noise, room echoes and music the notebook uses | GPU machine |
| `my_model.yaml` | The training settings: "hey trinity", 20,000 clips, 50,000 steps | GPU machine |
| `train_big.sh` | Generates the synthetic clips, augments them and trains | GPU machine |
| `train_voice.sh` | Adds your recordings and trains again | GPU machine |
| `gpu-machine-packages.txt` | The exact Python packages that worked on the GPU machine | GPU machine |

1. **Set up the wake word's environment** on this computer; the recorder uses
   it too:

   ```bash
   cd <folder>/wakeword
   uv venv -p 3.12 .venv
   VIRTUAL_ENV=.venv uv pip install openwakeword==0.4.0 onnxruntime
   ```

2. **Record yourself,** with the same gain you gave `wake.py` (Setup, step 5).
   The recording must go through the same chain as detection, or the model
   learns the wrong sound.

   ```bash
   cd <folder>/wakeword/training
   ../.venv/bin/python record.py wake.wav 1    # say "Hey Trinity" ~30 times, 2–3 s apart, varied; Ctrl+C to stop
   ../.venv/bin/python record.py talk.wav 1    # talk normally ~45 s, with look-alike words ("Trinity", "infinity"), never the phrase
   ../.venv/bin/python split.py wake.wav voice/wake mine
   ../.venv/bin/python split.py talk.wav voice/talk talk 2.0
   ```

   Pause between tries; said back to back, they run together. Check the clip
   lengths `split.py` prints: a "Hey Trinity" is about 0.8–1.0 seconds, and
   much shorter or longer clips are noises to delete. Move 5 of each into
   `voice/test/pos` and `voice/test/neg` to test with.

3. **Set up the GPU machine** in `~/oww`, the folder the scripts expect:
   - `openwakeword/`: a clone of openWakeWord
   - `piper-sample-generator/`: [piper-sample-generator](https://github.com/rhasspy/piper-sample-generator)
     at tag `v2.0.0`, with the voice model openWakeWord's notebook names
   - `.venv/`: Python 3.10 with the packages in `gpu-machine-packages.txt`
   - `my_model.yaml`, `train_big.sh`, `train_voice.sh`, `data3.py`, `fma.py`
   - the notebook's precomputed speech features
     (`openwakeword_features_ACAV100M_2000_hrs_16bit.npy`, 17 GB) and
     `validation_set_features.npy`
   - the background data: `python data3.py` and `python fma.py` make
     `audioset_16k/`, `mit_rirs/` and `fma/`

   openWakeWord's notebook (`notebooks/automatic_model_training.ipynb`) no
   longer runs as written; these are the fixes that made it work:

   | Problem | Fix |
   |---|---|
   | The pinned packages need an older Python | Python 3.10 from uv (`uv venv --python 3.10 --python-preference only-managed`); a system Python may lack the headers `webrtcvad` builds with |
   | `webrtcvad` needs `pkg_resources` | `setuptools<70` |
   | TensorFlow 2.8: "Descriptors cannot be created directly" | `protobuf==3.20.3` |
   | `datasets` 2.14.6: no `pyarrow.PyExtensionType` | `pyarrow==15.0.2` |
   | `torch_audiomentations`: no `torchaudio.set_audio_backend` | `torch==2.1.2 torchaudio==2.1.2` (cu121) |
   | Exporting: "Module onnx is not installed" | `onnx==1.14.1` |
   | `from generate_samples import ...` fails | piper-sample-generator at tag `v2.0.0` |
   | The notebook's `bal_train09.tar` is gone | AudioSet is now parquet; `data3.py` reads it straight from the file |

   Free notebook services were tried first and dropped: their newer Python
   and NumPy broke the notebook at every step.

4. **Train** on the GPU machine:

   ```bash
   cd ~/oww
   bash train_big.sh     # 20,000 synthetic clips, augmented, then trained
   ```

   On a first run, delete `train_big.sh`'s `cp ... hey_trinity_v1.onnx` line:
   it keeps the previous model, and there isn't one yet. Then copy your
   `voice/wake` and `voice/talk` folders to `~/oww/voice/` and:

   ```bash
   bash train_voice.sh   # adds your clips (each "Hey Trinity" ×160, your talk ×70) and trains again
   ```

   The model is `~/oww/my_custom_model/hey_trinity.onnx`. Copy it to this
   computer, and shut down a rented machine when you're done.

5. **Check before trying it live,** on this computer:

   ```bash
   cd <folder>/wakeword/training
   ../.venv/bin/python score_clips.py voice/test hey_trinity.onnx
   ```

   It should catch your `pos` clips and none of the `neg` ones. Lowering the
   trigger point doesn't rescue a model that doesn't know your voice: its
   misses score near zero.

6. **Install it:**

   ```bash
   cp hey_trinity.onnx <folder>/wakeword/
   <folder>/wakeword/.venv/bin/python <folder>/wakeword/wake.py --scores   # say "Hey Trinity": prints its score each second
   node <folder>/service/trinity.mjs mute off
   ```

The author's model caught 4 of 5 recordings it hadn't trained on and about 6
of 10 live tries (all the ones not rushed), with no false triggers in normal
talk.

Your recordings (`voice/`, `wake.wav`, `talk.wav`) are your voice: keep them
out of anything you publish.

## Known issue

Without an xAI key, Super+Z does nothing you can see: the reason ("No xAI API
key") is only in her log, `journalctl --user -u trinity`. Save your key
(Setup, step 3) and she answers.

## Remove her

```bash
<folder>/install-service.sh --remove
omarchy plugin remove marcho.trinity --yes
```

Then take the two key bindings out of `~/.config/hypr/bindings.lua`, and
delete `~/.config/trinity`, `~/.local/share/trinity` and
`~/.local/state/trinity` if you want her data gone too.
