# Agent Radar

An Omarchy shell plugin that puts your [herdr](https://herdr.dev) coding agents
on the desktop. Each agent is a hex cell, grouped under its workspace, lit by
what it's doing. Click one to jump to it.

It sits in the top-left corner of every screen, under the bar and behind your
windows, and follows your Omarchy theme's colors.

## What it shows

- **A cell per agent,** in honeycomb rows under each herdr workspace's name:
  - cyan ◉ **working** (breathing)
  - yellow ⚠ **needs you**: waiting at a question or approval (blinking)
  - green ✓ **done**
  - dim ○ **idle**
- **The header:** how many agents there are and how many are working, or
  **HERDR OFFLINE** when it can't reach herdr.
- **Hover** a cell to see its task at the foot of the cells.
- **The list** under the cells: the agents that want attention, needing you
  first, then working, then done.
- **Click** a cell or a row to jump to that agent: herdr focuses it, and its
  window (Herdscope, or a terminal running herdr) comes to the front.

It reads herdr every 2 seconds with one `herdr api snapshot` call. Nothing
leaves your computer.

## Requirements

- Omarchy 4.5 (built on 4.5.0rc1)
- herdr (built with 0.9.5)
- `python3` and `hyprctl` (Hyprland), used to jump to an agent

## Install

This plugin is part of [omarchy-hacker-neon](../../README.md), whose setup
installs it with everything else. To install only this plugin, copy this
folder to `~/.config/omarchy/plugins/marcho.radar`
(the folder name must be the plugin id), then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable marcho.radar
```

The shell reloads its plugins after a rescan and doesn't answer for a while.
If `omarchy plugin enable` says the shell isn't responding, wait half a minute
and run it again.

**Using an AI agent?** Point it at this folder and ask it to set the plugin up.
[AGENTS.md](AGENTS.md) has its instructions.

## Paths to know

Two paths in the plugin are set for the author's machine:

| Path | Used for | If you don't have it |
|---|---|---|
| `~/.local/share/mise/shims/herdr` (in `Radar.qml`) | running herdr | The radar shows **HERDR OFFLINE**. Put your herdr's full path in the `herdr` line of `Radar.qml` (find it with `command -v herdr`). |
| `~/.local/bin/o-widgets` (in `Radar.qml`), installed from the repo's `scripts/` | the `[ HIDE ]` button and the RADAR tab | Hiding does nothing; the radar works the same. |

The shell is started without your terminal's `PATH`, so herdr needs its full
path. `focus.sh` tries the mise path, then plain `herdr`.

Whether it's hidden is read from `~/.local/state/o-interfaces/widgets.json`,
which the `o-widgets` script writes. Without that file the radar always shows.

## Known issue

With no agents the radar's panel is short, and when it's hidden its RADAR tab
ends up outside its window, so there's no tab to click to bring it back. Use
Super+Alt+W (tick the radar), or run `~/.local/bin/o-widgets show radar`.

## Turn it off or remove it

```bash
omarchy plugin disable marcho.radar      # off, kept installed
omarchy plugin remove marcho.radar --yes # removed
```

## Files

| File | What it is |
|---|---|
| `manifest.json` | The plugin's id, name and entry point |
| `Radar.qml` | Reads herdr, keeps the agents and the hidden state |
| `RadarWindow.qml` | The panel on each screen: cells, list, scan line |
| `EdgeTab.qml` | The tab a hidden radar leaves at the screen's edge |
| `focus.sh` | Jumps to an agent: `herdr agent focus`, then its window to the front |
| `i18n/en.json` | The panel's words |
