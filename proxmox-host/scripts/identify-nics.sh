#!/usr/bin/env bash
# Identifies every network interface's speed and lets you blink its LED
# to physically confirm cabling, before assigning VLAN roles.
# Run directly on each Proxmox host (ceres/eros/pallas) as root.
set -euo pipefail

echo "== Interfaces on $(hostname) =="
ip -br link show

echo ""
echo "== Speed per interface (10000Mb/s = 10G pair, 1000Mb/s = 1G pair) =="
for iface in $(ip -br link show | awk '{print $1}' | grep -v '^lo$'); do
  speed=$(ethtool "$iface" 2>/dev/null | grep -oP 'Speed: \K.*' || echo "unknown")
  echo "$iface -> $speed"
done

echo ""
read -p "Enter an interface name to blink its LED (or press Enter to skip): " target
if [ -n "${target:-}" ]; then
  echo "Blinking $target for 15 seconds — check the physical port now."
  ethtool -p "$target" 15
fi