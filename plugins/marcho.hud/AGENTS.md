# Neon HUD: instructions for AI agents

You've been asked to set up the Neon HUD, an Omarchy shell plugin (id
`marcho.hud`), or to work on it. [README.md](README.md) describes what the
user sees. This file says how it works and how to set it up.

## Rules

- Work only in the user's own folders (`~/.config/omarchy/plugins/`,
  `~/.config/hypr/`). Never edit `/usr/share/omarchy`.
- Ask the user before installing any package or changing any setting.
- Tell the user before a step that reloads their shell (the rescan and the
  enable): their bar and desktop stop answering for up to half a minute.
- Don't change the plugin's files unless the user asks for one of the changes
  below.

## How it works

- **`Hud.qml`** is the plugin's service (its entry point in `manifest.json`).
  - Every 2 seconds it reads `/proc/stat` (CPU: the share of time not idle or
    waiting on I/O since the last read), `/proc/meminfo` (memory in use:
    `MemTotal` minus `MemAvailable`) and `/proc/net/dev` (bytes in and out per
    second over every interface but `lo`).
  - It reads one usage record per agent in `agentIds` (`claude`, `grok`,
    `codex`) from `~/.local/state/omarchy/agents/usage/<id>.json`. It watches
    the files, and reloads them and runs `omarchy-default-agent` every 60
    seconds.
  - It reads `~/.local/state/trinity/usage.json` for the API · TRINITY (XAI)
    section, which stays hidden while that file doesn't exist.
  - It reads the theme's `cyan`, `yellow` and `red` from
    `~/.local/state/omarchy/current/theme/colors.toml`, and again on every
    theme switch.
  - It reads which panels are hidden from
    `~/.local/state/o-interfaces/widgets.json` (`hidden.system`,
    `hidden.usage`, `clean`), and runs
    `~/.local/bin/o-widgets hide|show system|usage` when a
    `[ HIDE ]` button or a tab is clicked.
  - It opens one `HudWindow` per screen.
- **`HudWindow.qml`** is one screen's panels: a layer-shell window in the
  top-right corner, on Hyprland's bottom layer (behind windows), namespace
  `neon-hud`. Only the `[ HIDE ]` buttons and the SYS and AI tabs take clicks.
- **The usage record fields it uses:** `name`, `tierLabel`,
  `todayTotalTokens`, `recentDays[].messageCount` (each day's tokens) and
  `limits[]` with `label`, `percent` (0 to 1) and `resetsAt`.
- **Omarchy's Agents bar widget** (`omarchy.agents`) writes those records by
  running `omarchy-agent-usage-update`: every `refreshIntervalSec` seconds
  (900 by default, at least 30), and at most every 180 when an agent is near a
  limit. Without that widget, the records don't update.

## Set it up

### 1. Check what's needed

```bash
omarchy version                            # built on Omarchy 4.5
omarchy plugin list | grep omarchy.agents  # the Agents widget; should say enabled
ls ~/.local/state/omarchy/agents/usage/    # one .json per agent with usage
```

If the Agents widget isn't enabled or there are no records, tell the user: the
`// SYSTEM` panel works without them, but `// AI USAGE` won't show until the
Agents widget is on the bar and their agents are signed in.

### 2. Install

This plugin is in the omarchy-hacker-neon repo, at `plugins/marcho.hud`. If
the user wants the whole look, follow the repo's top-level `AGENTS.md`
instead, which installs this plugin too. To install only this plugin, copy it
so the folder name is the plugin id, then make the shell find it and turn it
on:

```bash
cp -r <this-folder> ~/.config/omarchy/plugins/marcho.hud
omarchy-shell shell rescanPlugins
omarchy plugin enable marcho.hud
```

If `omarchy plugin enable` prints "omarchy-shell is not responding", the shell
is still reloading. Wait 30 seconds and run it again; don't run the rescan
again, as each rescan reloads it once more.

If `~/.config/omarchy/plugins/marcho.hud` already exists, stop and ask the
user what to do.

### 3. Offer the options

Ask the user whether they want any of these; do only the ones they choose:

- **Faster usage updates** (every 30 seconds instead of 15 minutes):
  `omarchy bar set omarchy.agents refreshIntervalSec 30 --json`
- **More agents:** add `kimi` and/or `fireworks` to `agentIds` in
  `~/.config/omarchy/plugins/marcho.hud/Hud.qml` (only ids that have a record
  in the usage folder show).
- **Frosted glass** behind the panels: the README's "Frosted glass" snippet, in
  `~/.config/hypr/looknfeel.lua`. Read the file first; if it already sets
  blur or window rules, show the user the conflict instead of adding.

The shell reloads the plugin by itself when its files change.

If the plugin was installed with `omarchy plugin add`, an edit to `Hud.qml` is
a local change in its git clone. Tell the user: `omarchy plugin update
marcho.hud` may then stop with "you have local changes"; undo the edit
(`git -C ~/.config/omarchy/plugins/marcho.hud checkout Hud.qml`), update, and
make it again.

### 4. Check it works

```bash
omarchy plugin list | grep marcho.hud   # should say enabled
```

Then ask the user to look at the top-right corner of their desktop, under the
bar (windows may cover it). They should see `// SYSTEM` with moving CPU,
memory and network numbers, and `// AI USAGE` under it if they have records.

## Good to know

- The `[ HIDE ]` buttons and the SYS and AI tabs run `~/.local/bin/o-widgets`,
  which the repo's setup installs from `scripts/`. Without it, hiding does
  nothing and the panels work the same.
- The API · TRINITY (XAI) section is for the author's own voice assistant and
  stays hidden on other machines. Its cost line is an estimate from xAI's
  prices: $0.08 per voice minute and $0.004 per text input.

## Undo

```bash
omarchy plugin disable marcho.hud       # off, kept installed
omarchy plugin remove marcho.hud --yes  # removed completely
```

Undo any option from step 3 the same way it was made.
