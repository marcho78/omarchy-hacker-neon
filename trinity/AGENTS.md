# Trinity: instructions for AI agents

You've been asked to set up Trinity, a voice and chat assistant for the
Omarchy desktop, or to work on her. [README.md](README.md) describes what she
does and how she's built; read it first. This file says how to set her up for
the user, step by step.

## Rules

- **The xAI API key is the user's secret.** Never print it, log it, put it in a
  file other than `~/.config/trinity/xai-api-key`, or ask the user to paste it
  into the chat. Have them save it to that file themselves (step 3).
- Work only in this folder and the user's own config (`~/.config/`,
  `~/.local/`). Never edit `/usr/share/omarchy`.
- Ask the user before installing any package, changing their key bindings, or
  starting the service.
- Tell the user before a step that reloads their shell (the rescan and the
  enable): their bar and desktop stop answering for up to half a minute.
- Don't change Trinity's code beyond the settings listed in step 4 and 5,
  unless the user asks.
- The wake word model isn't included. Don't download someone else's; the user
  trains their own (README, "Train your own wake word").

## 1. Check what's there

```bash
omarchy version                       # built on Omarchy 4.5
command -v node npm pw-record pw-cat  # needed
command -v wtype grim tesseract yt-dlp herdr uv   # optional, per action
ls ~/.config/omarchy/plugins/ | grep -E "marcho78\.(om-pg|uber-notebook|hillchart)"
```

Tell the user which optional parts are missing and what they're for (README,
"Requirements"). Missing ones only disable the actions that use them:

| Missing | Effect |
|---|---|
| `wtype` | She can't press keys or type text |
| `grim`, `tesseract` | She can't read the screen |
| `yt-dlp` or Uber TV (`marcho78.om-pg`) | She can't play videos |
| `herdr` | No coding-agent actions |
| [Uber Notebook](https://github.com/marcho78/ubernotebook), [Hill Chart](https://github.com/marcho78/omarchy-hillchart) | No notes or hill chart actions |
| `uv` | Needed later, for the wake word only |

If `~/.config/omarchy/plugins/marcho.trinity` or
`~/.config/systemd/user/trinity.service` already exists, stop and ask the user
what to do.

## 2. Install the service's package

```bash
cd <this-folder>/service && npm install
```

## 3. Connect xAI

- **The key:** ask the user to save their xAI API key themselves:

  ```bash
  mkdir -p ~/.config/trinity && chmod 700 ~/.config/trinity
  $EDITOR ~/.config/trinity/xai-api-key
  chmod 600 ~/.config/trinity/xai-api-key
  ```

  Check it exists without reading it: `test -s ~/.config/trinity/xai-api-key`.
- **The agent:** the user creates a voice agent in the xAI console, writes its
  instructions, and turns on web search, X search and the end-call tool. Ask
  them for the agent's ID (it starts with `agent_`; it isn't secret) and put
  it in `service/session.mjs`:

  ```js
  export const AGENT_ID = "agent_...";
  ```

## 4. Change the author's paths

| File | Line | Change to |
|---|---|---|
| `plugin/Trinity.qml` | `readonly property string node:` | the full path from `command -v node` |
| `plugin/Trinity.qml` | `readonly property string service:` | `<this-folder>/service/trinity.mjs` |
| `plugin/MuteButton.qml` | `readonly property string node:` | the same node path |
| `plugin/MuteButton.qml` | `readonly property string service:` | the same service path |

Leave these unless the user asks:

- `plugin/Trinity.qml`, `widgetsTool`: `~/.local/bin/o-widgets`, which the
  repo's setup installs from `scripts/`. Without it, `[ HIDE ]` on the board
  and the video does nothing.
- `plugin/Video.qml`, `streamer`: Uber TV's streamer, right when Uber TV is
  installed.
- `service/actions.mjs`, the app guide paths near `notes:`, `tv:` and `hill:`:
  right when those apps are installed under the author's plugin ids.

`install-service.sh` finds node itself (mise's, then the one on `PATH`).

## 5. Set the mic boost

Both of these boost the mic 400×, tuned for a MacBook's T2 mic (about 50 dB
quieter than normal speech):

- `service/audio.mjs`: `const GAIN = 400;`
- `wakeword/wake.py`: `--gain` default `400`

Ask the user what computer and mic they have. On anything but a MacBook's T2
mic, set both to `1`; if she can't hear them later, raise both together.

## 6. Install the plugin

The folder name must be the plugin's id:

```bash
cp -r <this-folder>/plugin ~/.config/omarchy/plugins/marcho.trinity
omarchy-shell shell rescanPlugins
omarchy plugin enable marcho.trinity --section right
omarchy plugin list | grep marcho.trinity    # should say enabled
```

If `omarchy plugin enable` prints "omarchy-shell is not responding", the shell
is still reloading. Wait 30 seconds and run it again; don't run the rescan
again, as each rescan reloads it once more.

## 7. Install and start the service

```bash
<this-folder>/install-service.sh
node <this-folder>/service/trinity.mjs mute on   # no wake word model yet
```

`install-service.sh` prints whether the service is running. If not:
`journalctl --user -u trinity -n 30`.

## 8. Add the keys

Ask first, then add to `~/.config/hypr/bindings.lua` (read the file; if Super+Z
or Super+Alt+M is already bound, show the user and ask):

```lua
o.bind("SUPER + Z", "Trinity: talk", "<node> <this-folder>/service/trinity.mjs talk")
o.bind("SUPER + ALT + M", "Trinity: mute or unmute", "<node> <this-folder>/service/trinity.mjs mute toggle")
```

## 9. The greeting

Ask the user what she should say when called, then:

```bash
node <this-folder>/service/trinity.mjs greeting "Hi <name>, how can I help?"
```

It prints what she said. It uses a few seconds of their xAI time.

## 10. Check it works

- Ask the user to press **Super+Z** and say something. The orb should appear,
  she should answer, and the log should show it:
  `journalctl --user -u trinity -f`.
- Typed, without the mic: `node <this-folder>/service/trinity.mjs say "hello"`.
- If she doesn't hear them: the mic boost (step 5), or the default input in
  their sound settings.
- If nothing happens on Super+Z, check her log for "No xAI API key": without
  the key she shows nothing on screen (a known issue).

## The wake word, later

To help the user train their own model, follow README, "Train your own wake
word", with the scripts in `wakeword/training/`:

- Recording and checking run on their computer. Give `record.py` the same
  gain as `wake.py` (step 5).
- Training runs on a Linux machine with an NVIDIA GPU that the user chooses
  (their own, or one they rent). Ask before renting or setting up anything,
  and remind them to shut a rented machine down afterwards.
- Their recordings are their voice: copy them only to that training machine,
  never anywhere else.

When the model is trained:

```bash
cp <their-model>.onnx <this-folder>/wakeword/hey_trinity.onnx
cd <this-folder>/wakeword
# only if .venv doesn't exist yet (the training steps make it):
uv venv -p 3.12 .venv
VIRTUAL_ENV=.venv uv pip install openwakeword==0.4.0 onnxruntime
.venv/bin/python wake.py --scores    # they say "Hey Trinity"; scores should jump
node <this-folder>/service/trinity.mjs mute off
```

The service runs `wakeword/.venv/bin/python wake.py`, so the environment must
be in that exact place.

## Undo

```bash
<this-folder>/install-service.sh --remove
omarchy plugin remove marcho.trinity --yes
```

Take the two bindings out of `~/.config/hypr/bindings.lua`. Ask before deleting
`~/.config/trinity`, `~/.local/share/trinity` or `~/.local/state/trinity`:
they hold the user's key, greeting, memory and usage.
