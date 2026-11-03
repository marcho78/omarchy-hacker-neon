#!/usr/bin/env bash
# Jumps to a Herdr agent: focuses its pane in Herdr, then brings Herdr's window
# (the Herdscope app, or a terminal running herdr) to the front.
#   focus.sh <pane id>
set -u
herdr="$HOME/.local/share/mise/shims/herdr"
[[ -x $herdr ]] || herdr=herdr
"$herdr" agent focus "$1" >/dev/null 2>&1 || exit 1
address=$(hyprctl clients -j | python3 -c '
import json, sys
clients = json.load(sys.stdin)
match = [c for c in clients if "herdscope" in (c.get("class") or "").lower() or "herdr" in (c.get("class") or "").lower()]
match = match or [c for c in clients if "herdr" in (c.get("title") or "").lower()]
print(match[0]["address"] if match else "")
')
[[ -n $address ]] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null
exit 0
