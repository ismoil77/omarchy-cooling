#!/bin/bash
# One-time install of the full-speed switch (asks for your password once).
#   helper/install.sh            install
#   helper/install.sh remove     take it all out again
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = remove ]; then
  sudo systemctl disable --now ismoil-fans-auto.service 2>/dev/null || true
  sudo rm -f /usr/local/libexec/ismoil-fans-max /usr/share/polkit-1/actions/io.github.ismoil77.fans.policy /etc/systemd/system/ismoil-fans-auto.service
  sudo systemctl daemon-reload
  echo "Removed. Fans stay on the firmware's automatic curve."
  exit 0
fi
sudo install -D -o root -g root -m 0755 "$here/ismoil-fans-max" /usr/local/libexec/ismoil-fans-max
sudo install -D -o root -g root -m 0644 "$here/io.github.ismoil77.fans.policy" /usr/share/polkit-1/actions/io.github.ismoil77.fans.policy
sudo install -D -o root -g root -m 0644 "$here/ismoil-fans-auto.service" /etc/systemd/system/ismoil-fans-auto.service
sudo systemctl daemon-reload
sudo systemctl enable --now ismoil-fans-auto.service
echo "Installed. Max in the Cooling widget now asks for your password once per session."
