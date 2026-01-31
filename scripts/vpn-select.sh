#!/bin/bash
set -eEo pipefail

# Configuration
CONFIGS_PATH="/etc/wireguard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn.conf"

# Detect all VPN configs
mapfile -t VPN_CONFIGS < <(ls "${CONFIGS_PATH}"/*.conf 2>/dev/null | xargs -n 1 basename -s .conf 2>/dev/null | sort)

if [[ ${#VPN_CONFIGS[@]} -eq 0 ]]; then
  notify-send "VPN Selector" "No WireGuard configs found in ${CONFIGS_PATH}"
  exit 0
fi

# Get current VPN
source "${CONFIG_FILE}" 2>/dev/null || CURRENT_VPN="${VPN_CONFIGS[0]}"

# Select VPN via rofi/dmenu/terminal fallback
if command -v rofi &>/dev/null; then
  SELECTED_VPN=$(printf "%s\n" "${VPN_CONFIGS[@]}" | rofi -dmenu -p "Select VPN" -format 's')
elif command -v dmenu &>/dev/null; then
  SELECTED_VPN=$(printf "%s\n" "${VPN_CONFIGS[@]}" | dmenu -p "Select VPN")
else
  echo "Available VPNs:"
  for i in "${!VPN_CONFIGS[@]}"; do
    echo "$((i+1))) ${VPN_CONFIGS[i]}"
  done
  read -rp "Select VPN [1-${#VPN_CONFIGS[@]}] (0 to cancel): " choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#VPN_CONFIGS[@]} )); then
    SELECTED_VPN="${VPN_CONFIGS[choice-1]}"
  else
    notify-send "VPN Selector" "Selection cancelled"
    exit 0
  fi
fi

[[ -z "${SELECTED_VPN}" ]] && exit 0

# Disconnect current VPN if connected
if ip link show | grep -q "${CURRENT_VPN}"; then
  sudo wg-quick down "${CURRENT_VPN}"
fi

# Connect selected VPN
sudo wg-quick up "${SELECTED_VPN}"

# Save selection
echo "VPN_NAME=\"${SELECTED_VPN}\"" > "${CONFIG_FILE}"

# Notify
notify-send "VPN Selector" "Connected to ${SELECTED_VPN}"
