# Setting up Agent Radar: instructions for AI agents

You've been asked to install Agent Radar, an Omarchy shell plugin (id
`marcho.radar`) that shows the user's herdr coding agents on the desktop.
[README.md](README.md) describes it. Follow these steps in order.

## Rules

- Work only in the user's own folders (`~/.config/omarchy/plugins/`). Never
  edit `/usr/share/omarchy`.
- Ask the user before installing any package.
- Tell the user before a step that reloads their shell (the rescan and the
  enable): their bar and desktop stop answering for up to half a minute.
- Don't change any file in this plugin except the one line step 3 names.

## 1. Check what's needed

```bash
omarchy version          # built on Omarchy 4.5
command -v herdr         # herdr must be installed
herdr api snapshot       # must print JSON; if it fails, herdr isn't running
command -v python3 hyprctl
```

If herdr isn't installed, stop and tell the user: the radar needs it
(https://herdr.dev). If `herdr api snapshot` fails, ask the user to start herdr.

## 2. Install

This plugin is in the omarchy-hacker-neon repo, at `plugins/marcho.radar`. If
the user wants the whole look, follow the repo's top-level `AGENTS.md`
instead, which installs this plugin too. To install only this plugin, copy it
so the folder name is the plugin id, then make the shell find it and turn it
on:

```bash
cp -r <this-folder> ~/.config/omarchy/plugins/marcho.radar
omarchy-shell shell rescanPlugins
omarchy plugin enable marcho.radar
```

If `omarchy plugin enable` prints "omarchy-shell is not responding", the shell
is still reloading. Wait 30 seconds and run it again; don't run the rescan
again, as each rescan reloads it once more.

If `~/.config/omarchy/plugins/marcho.radar` already exists, stop and ask the
user what to do.

## 3. Point it at herdr

The shell runs without the user's terminal `PATH`, so `Radar.qml` runs herdr
by its full path, set to herdr installed through mise:

```qml
readonly property string herdr: home + "/.local/share/mise/shims/herdr"
```

Check whether that file exists:

```bash
test -x ~/.local/share/mise/shims/herdr && echo ok
```

- **It exists:** change nothing.
- **It doesn't:** put the full path from `command -v herdr` in that line, in
  `~/.config/omarchy/plugins/marcho.radar/Radar.qml`, for example
  `readonly property string herdr: "/usr/bin/herdr"`. The shell reloads the
  plugin by itself when the file changes.

If the plugin was installed with `omarchy plugin add`, this edit is a local
change in its git clone. Tell the user: `omarchy plugin update marcho.radar`
may then stop with "you have local changes"; undo the line
(`git -C ~/.config/omarchy/plugins/marcho.radar checkout Radar.qml`), update,
and make the change again.

## 4. Check it works

```bash
omarchy plugin list | grep marcho.radar   # should say enabled
```

Then ask the user to look at the top-left corner of their desktop, under the
bar (windows may cover it). It should show AGENT RADAR with a cell for each
herdr agent. If it says **HERDR OFFLINE**, herdr isn't running or step 3's
path is wrong.

## Good to know

- The `[ HIDE ]` button and the RADAR tab run `~/.local/bin/o-widgets`, which
  the repo's setup installs from `scripts/`. Without it, hiding does nothing
  and the radar works the same.
- Every agent that isn't Codex is labelled CLD on its cell.
- Known issue: with no agents, a hidden radar's RADAR tab ends up outside its
  window and can't be clicked. `~/.local/bin/o-widgets show radar` (or
  Super+Alt+W) brings the radar back.

## Undo

```bash
omarchy plugin disable marcho.radar       # off, kept installed
omarchy plugin remove marcho.radar --yes  # removed completely
```
