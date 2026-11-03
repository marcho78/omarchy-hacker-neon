# Neon HUD

An Omarchy shell plugin that puts two panels on the desktop, `// SYSTEM` and
`// AI USAGE`. They show live CPU, memory and network use, and how much of
your AI agents' tokens and limits you've used.

The panels sit in the top-right corner of every screen, under the bar and
behind your windows, and follow your Omarchy theme's colors. Clicks go through
them to the desktop, except on their `[ HIDE ]` buttons.

## What it shows

**`// SYSTEM`** (marked LIVE), updated every 2 seconds:

- **CPU:** a meter and a percentage.
- **MEM:** a meter, a percentage, and used / total in GB.
- **NET:** download ▼ and upload ▲ speed, over every network interface but
  loopback.

**`// AI USAGE`**, for each agent with a usage record (Claude, Grok and Codex):

- Its name and plan. Omarchy's default agent has a **DEFAULT** tag.
- **TODAY** and **WEEK** tokens, and a bar for each of the last 7 days. Today's
  bar is cyan.
- Each limit: a meter, how much is used, and when it resets. A meter turns
  yellow from 75% and red from 90%.

The panel only shows when there's at least one record (or Trinity's usage
file, below).

**API · TRINITY (XAI)** is a section under the agents, for the author's own
voice assistant. It only shows when `~/.local/state/trinity/usage.json`
exists, so on other machines it stays hidden.

## Where the numbers come from

- CPU, memory and network: `/proc/stat`, `/proc/meminfo` and `/proc/net/dev`.
- Agent usage: the records Omarchy's **Agents** bar widget writes, one per
  agent, in `~/.local/state/omarchy/agents/usage/`. The HUD reads them as they
  change, and checks again every minute.
- The default agent: `omarchy-default-agent`.

Nothing leaves your computer. The usage records hold counts, dates and limits,
not API keys.

## Requirements

- Omarchy 4.5 (built on 4.5.0rc1).
- For `// AI USAGE`: Omarchy's **Agents** widget on the bar (`omarchy.agents`),
  with your agents signed in. It updates the records every 15 minutes by
  default, and more often when an agent is close to a limit. To update them
  every 30 seconds (the shortest it allows):

  ```bash
  omarchy bar set omarchy.agents refreshIntervalSec 30 --json
  ```

## Install

This plugin is part of [omarchy-hacker-neon](../../README.md), whose setup
installs it with everything else. To install only this plugin, copy this
folder to `~/.config/omarchy/plugins/marcho.hud` (the
folder name must be the plugin id), then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable marcho.hud
```

The shell reloads its plugins after a rescan and doesn't answer for a while.
If `omarchy plugin enable` says the shell isn't responding, wait half a minute
and run it again.

**Using an AI agent?** Point it at this folder and ask it to set the plugin up.
[AGENTS.md](AGENTS.md) has its instructions.

## Paths to know

| Path | Used for | If you don't have it |
|---|---|---|
| `~/.local/state/omarchy/agents/usage/<agent>.json` | `// AI USAGE` | That panel doesn't show. |
| `~/.local/bin/o-widgets` (in `Hud.qml`), installed from the repo's `scripts/` | the `[ HIDE ]` buttons and the SYS and AI tabs | Hiding does nothing; the panels work the same. |
| `~/.local/state/o-interfaces/widgets.json` | whether a panel is hidden (written by `o-widgets`) | The panels always show. |
| `~/.local/state/trinity/usage.json` | API · TRINITY (XAI) | That section stays hidden. |

## Showing more agents

The agents shown are listed in `Hud.qml`, in the order shown:

```qml
readonly property var agentIds: ["claude", "grok", "codex"]
```

Omarchy also keeps records for `kimi` and `fireworks`. Add their ids to the
list to show them.

## Frosted glass (optional)

The panels are see-through. To blur what's behind them, Hyprland needs blur on
and a layer rule for the HUD's layer, `neon-hud`. The Hacker Neon theme does it
in its `hyprland.lua`; shortened, with blur on for the HUD and off for windows:

```lua
hl.config({ decoration = { blur = { enabled = true, size = 4, passes = 2 } } })

hl.layer_rule({
  match = { namespace = "^neon-hud$" },
  blur = true,
  ignore_alpha = 0.3,
})

hl.window_rule({
  match = { class = ".*" },
  no_blur = true,
})
```

## Turn it off or remove it

```bash
omarchy plugin disable marcho.hud      # off, kept installed
omarchy plugin remove marcho.hud --yes # removed
```

## Files

| File | What it is |
|---|---|
| `manifest.json` | The plugin's id, name and entry point |
| `Hud.qml` | Reads the numbers and the hidden state; one window per screen |
| `HudWindow.qml` | The two panels on a screen, their meters, day bars and tabs |
| `EdgeTab.qml` | The tab a hidden panel leaves at the screen's edge |
| `i18n/en.json` | The panels' words |
