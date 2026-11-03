# Omarchy Hacker Neon: instructions for AI agents

You've been asked to set up the Hacker Neon look on the user's Omarchy
desktop: a theme, three shell plugins (Neon Dock, Neon HUD, Agent Radar), a
widget script and its keys, herdr, and optionally Trinity, a voice assistant.
[README.md](README.md) describes it for people; read it first. This file is
the setup, step by step, as it was tested on a fresh Omarchy 4.5.0rc3.

Run every command from this repo's folder unless it says otherwise.

## Rules

- Work only in the user's own folders (`~/.config/`, `~/.local/`). Never edit
  `/usr/share/omarchy`.
- **Before you change anything, tell the user the plan** (the steps below,
  which ones you'll do) and wait for their yes.
- Ask before installing any package, and before Trinity (step 8).
- Before overwriting or editing a file of theirs, look at it first; back up
  `~/.config/hypr/bindings.lua` before adding to it
  (`cp ~/.config/hypr/bindings.lua ~/.config/hypr/bindings.lua.bak-hacker-neon`).
- If `~/.config/omarchy/themes/hacker-neon` or any of
  `~/.config/omarchy/plugins/marcho.{dock,hud,radar,trinity}` already exists,
  stop and ask the user what to do.
- Tell the user before a step that reloads their shell (the rescan, the
  enables): their bar and desktop stop answering for up to half a minute.
- Never print, log or ask for an API key. Trinity's xAI key is saved by the
  user themselves (see `trinity/AGENTS.md`).

## 1. Check the machine

```bash
omarchy version            # built on 4.5.0rc1, tested on 4.5.0rc3
omarchy-version-channel    # the test machine was on rc
omarchy plugin list | grep -E "omarchy\.(dock|agents)"
command -v python3 mise
ls ~/.config/omarchy/themes ~/.config/omarchy/plugins 2>/dev/null
```

- If the version is below 4.5, tell the user: this was built and tested on
  Omarchy 4.5 (the `rc` channel). Moving there is their call
  (`omarchy channel set rc`, then a reboot); don't do it for them unasked.
- If `omarchy.agents` isn't enabled, tell them the HUD's `// AI USAGE` panel
  needs Omarchy's Agents widget on the bar; the rest works without it.

## 2. The theme

```bash
mkdir -p ~/.config/omarchy/themes
cp -r theme/hacker-neon ~/.config/omarchy/themes/
omarchy theme set hacker-neon
omarchy theme current      # should print: Hacker Neon
```

The theme's icons are `Yaru-prussiangreen`, from `yaru-icon-theme`, which
Omarchy installs (`pacman -Q yaru-icon-theme`).

## 3. The plugins

```bash
mkdir -p ~/.config/omarchy/plugins
for p in marcho.dock marcho.hud marcho.radar; do
  cp -r plugins/$p ~/.config/omarchy/plugins/
  omarchy plugin validate ~/.config/omarchy/plugins/$p && echo "$p valid"
done
omarchy-shell shell rescanPlugins
```

Then, one at a time:

```bash
omarchy plugin disable omarchy.dock
omarchy plugin enable marcho.dock
omarchy plugin enable marcho.hud
omarchy plugin enable marcho.radar
```

If a command prints "omarchy-shell is not responding", the shell is still
reloading: wait 5 seconds and run that same command again, up to a minute.
Don't run the rescan again; each rescan reloads the shell once more.

Check: `omarchy plugin list | grep -E "marcho\.|omarchy\.dock"` should show the
three `marcho.*` enabled and `omarchy.dock` disabled.

## 4. The settings

```bash
omarchy dock autohide on
omarchy bar set omarchy.agents refreshIntervalSec 30 --json
```

## 5. herdr

The Agent Radar runs herdr from `~/.local/share/mise/shims/herdr`, the path
mise gives it:

```bash
mise use -g herdr@0.9.5
~/.local/share/mise/shims/herdr --version    # herdr 0.9.5
```

If the user already has herdr installed another way, don't install a second
one: put its full path (`command -v herdr`) in the `herdr` line of
`~/.config/omarchy/plugins/marcho.radar/Radar.qml` instead (see
`plugins/marcho.radar/AGENTS.md`, step 3).

The radar shows HERDR OFFLINE until herdr runs. Tell the user to start it
(`herdr` in a terminal); their agents appear on the radar as they start.

## 6. The widget script

```bash
mkdir -p ~/.local/bin
install -m 755 scripts/o-widgets ~/.local/bin/
~/.local/bin/o-widgets status     # prints the state as JSON
```

The HUD, the radar and Trinity run it from that exact path.

## 7. The keys

Back up `~/.config/hypr/bindings.lua`, read it, and if Super+Alt+H, Super+Alt+W
or Super+Alt+X is already bound, show the user and ask. Then append the
widget lines from `hypr/bindings.lua` (the three `o.bind` lines and the
`local o_widgets` line above them; leave Trinity's commented lines out unless
step 8 is done). Hyprland reloads on its own. Check:

```bash
omarchy menu keybindings --print | grep -i widgets   # the three keys
```

## 8. Trinity (only if the user wants her)

Ask first. She needs an xAI account (an API key and a voice agent they create),
Node, a systemd user service, and, for "Hey Trinity", a wake word model they
train on their own voice. Without the model she works with Super+Z and typed
chat. If they want her, follow [trinity/AGENTS.md](trinity/AGENTS.md) from
its step 1, with `<this-folder>` meaning this repo's `trinity/` folder.

## 9. Check it works

Ask the user to look at their desktop (windows may cover it):

- **The theme:** dark green, a code-rain wallpaper, a green-to-cyan border on
  the focused window.
- **The Agent Radar,** top left: `// AGENT RADAR`, then HERDR OFFLINE or the
  agents.
- **The Neon HUD,** top right: `// SYSTEM` with moving numbers, and
  `// AI USAGE` if their Agents widget has records.
- **The Neon Dock:** on a floating workspace (Omarchy's workspace layout
  toggle), at the bottom when the pointer reaches the edge.
- **Super+Alt+H** hides all the widgets; pressing it again brings them back.

## Good to know

- Omarchy's screensaver and lock come on when the desktop is idle; they follow
  the theme too.
- The Agent Radar's RADAR tab doesn't show when the radar has no agents (see
  README, Known issues). `~/.local/bin/o-widgets show radar` brings it back.
- Trinity, without an xAI key: Super+Z does nothing visible; the reason ("No
  xAI API key") is only in her log (`journalctl --user -u trinity`). If she
  doesn't answer, check that first (see README, Known issues).
- Each plugin has its own `AGENTS.md` with how it works, for changes the user
  asks for later.

## Undo

```bash
omarchy theme set <a theme the user picks>
rm -rf ~/.config/omarchy/themes/hacker-neon
omarchy plugin disable marcho.dock
omarchy plugin disable marcho.hud
omarchy plugin disable marcho.radar
omarchy plugin enable omarchy.dock
rm -rf ~/.config/omarchy/plugins/marcho.dock ~/.config/omarchy/plugins/marcho.hud ~/.config/omarchy/plugins/marcho.radar
rm ~/.local/bin/o-widgets
mv ~/.config/hypr/bindings.lua.bak-hacker-neon ~/.config/hypr/bindings.lua
```

Ask before removing herdr (`mise uninstall herdr`); the user may use it for
other things. For Trinity, see `trinity/AGENTS.md`, Undo.
