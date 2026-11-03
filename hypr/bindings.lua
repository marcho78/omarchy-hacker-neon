-- omarchy-hacker-neon: the keys to add to ~/.config/hypr/bindings.lua.

-- Desktop widgets (the Neon HUD's panels, the Agent Radar, and Trinity's board
-- and video): hide or show them all, clear Trinity's board, or pick which show.
local o_widgets = (os.getenv("HOME") or "") .. "/.local/bin/o-widgets"
o.bind("SUPER + ALT + H", "Widgets: hide or show all", o_widgets .. " clean")
o.bind("SUPER + ALT + X", "Widgets: clear Trinity's board", o_widgets .. " clear")
o.bind("SUPER + ALT + W", "Widgets: pick which show", o_widgets .. " menu")

-- Trinity, only if you install her (see trinity/README.md). Put in your node's
-- full path (command -v node) and this repo's path, then remove the "-- ".
-- o.bind("SUPER + Z", "Trinity: talk", "<node> <repo>/trinity/service/trinity.mjs talk")
-- o.bind("SUPER + ALT + M", "Trinity: mute or unmute", "<node> <repo>/trinity/service/trinity.mjs mute toggle")
