#!/bin/bash
set -eEo pipefail

# Configuration
CONFIGS_PATH="/etc/wireguard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/vpn.conf"

# Detect all VPN configs (try normal read, then sudo-enabled reads)
mapfile -t VPN_CONFIGS < <(ls "${CONFIGS_PATH}"/*.conf 2>/dev/null | xargs -n 1 basename -s .conf 2>/dev/null | sort)

if [[ ${#VPN_CONFIGS[@]} -eq 0 ]]; then
  # Try to use sudo-find (installer adds a sudoers rule for this exact find invocation)
  if command -v sudo &>/dev/null; then
    # First try non-interactive sudo (won't prompt for password)
    if sudo -n true 2>/dev/null; then
      mapfile -t VPN_CONFIGS < <(sudo /usr/bin/find "${CONFIGS_PATH}" -maxdepth 1 -name "*.conf" -exec basename -s .conf {} \; 2>/dev/null | sort)
    else
      # Interactive sudo: allow user to enter password if needed
      mapfile -t VPN_CONFIGS < <(sudo /usr/bin/find "${CONFIGS_PATH}" -maxdepth 1 -name "*.conf" -exec basename -s .conf {} \; 2>/dev/null | sort)
    fi
  fi
fi

if [[ ${#VPN_CONFIGS[@]} -eq 0 ]]; then
  notify-send "VPN Selector" "No WireGuard configs found in ${CONFIGS_PATH}"
  exit 0
fi

# Get current VPN (try to source, then try sudo-read if file unreadable)
CURRENT_VPN=""
if [[ -f "${CONFIG_FILE}" ]]; then
  if source "${CONFIG_FILE}" 2>/dev/null; then
    CURRENT_VPN="${VPN_NAME}"
  else
    if command -v sudo &>/dev/null; then
      SUDO_CONTENT=$(sudo cat "${CONFIG_FILE}" 2>/dev/null || true)
      if [[ -n "${SUDO_CONTENT}" ]]; then
        CURRENT_VPN=$(echo "${SUDO_CONTENT}" | sed -n 's/.*VPN_NAME=["'"']\?\([^"'"']*\)["'"']\?.*/\1/p')
      fi
    fi
  fi
fi

if [[ -z "${CURRENT_VPN}" ]]; then
  CURRENT_VPN="${VPN_CONFIGS[0]}"
fi

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

# Save selection (try normal write, fall back to sudo tee if permission denied)
if ! echo "VPN_NAME=\"${SELECTED_VPN}\"" > "${CONFIG_FILE}" 2>/dev/null; then
  if command -v sudo &>/dev/null; then
    echo "VPN_NAME=\"${SELECTED_VPN}\"" | sudo tee "${CONFIG_FILE}" >/dev/null
    # attempt to ensure the file is owned by the current user
    if command -v sudo &>/dev/null; then
      sudo chown "${SUDO_USER:-${USER}}":"${SUDO_USER:-${USER}}" "${CONFIG_FILE}" 2>/dev/null || true
      sudo chmod 600 "${CONFIG_FILE}" 2>/dev/null || true
    fi
  else
    notify-send "VPN Selector" "Failed to write ${CONFIG_FILE}: permission denied"
    exit 1
  fi
fi

# Notify
notify-send "VPN Selector" "Connected to ${SELECTED_VPN}"
