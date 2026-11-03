#!/usr/bin/env bash
# Installs the Trinity service as a systemd user service, so it starts with the
# desktop session, restarts if it crashes, and Super+Z always has it to talk to.
#
#   trinity/install-service.sh            install and start it
#   trinity/install-service.sh --remove   stop and remove it
set -euo pipefail

unit_dir="$HOME/.config/systemd/user"
unit="$unit_dir/trinity.service"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
service="$here/service/trinity.mjs"

if [[ ${1:-} == "--remove" ]]; then
  systemctl --user disable --now trinity.service 2>/dev/null || true
  rm -f "$unit"
  systemctl --user daemon-reload
  echo "Trinity service removed."
  exit 0
fi

# The node that runs Trinity: mise's current one, through its stable "latest"
# link, so a node update doesn't break the service.
node="$HOME/.local/share/mise/installs/node/latest/bin/node"
[[ -x $node ]] || node="$(command -v node || true)"
if [[ -z $node || ! -x $node ]]; then
  echo "node not found; install it first." >&2
  exit 1
fi
[[ -f $service ]] || { echo "Missing $service" >&2; exit 1; }

mkdir -p "$unit_dir"
cat > "$unit" <<EOF
[Unit]
Description=Trinity voice agent
After=graphical-session.target pipewire.service
PartOf=graphical-session.target
# Her mic and wake word don't recover when PipeWire restarts under them, so
# she restarts with it.
PartOf=pipewire.service

[Service]
ExecStart=$node $service serve
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# A copy started by hand (for testing) would fight this one over the socket.
pkill -f "trinity.mjs serve" 2>/dev/null || true

systemctl --user daemon-reload
systemctl --user enable --now trinity.service
sleep 1
if systemctl --user is-active --quiet trinity.service; then
  echo "Trinity service is running and will start with your desktop."
  echo "Logs: journalctl --user -u trinity -f"
else
  echo "Trinity service didn't start; see: journalctl --user -u trinity -n 20" >&2
  exit 1
fi
