#!/bin/bash

SCRIPT_NAME=$(basename -- "$0")
log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
log_error() { printf '[%s] Error: %s\n' "$SCRIPT_NAME" "$*" >&2; }
log_command() {
  "$@" > >(while IFS= read -r line; do log "$line"; done) 2>&1
}

# Configuration
IFACE="$1"                                      # Change to your interface name (e.g., enp3s0)
CONF_FILE="./wired-8021x.conf"  # Path to the config file above

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  log_error 'This script must be run as root.'
  exit 1
fi

log "1. Bringing up interface $IFACE..."
log_command ip link set dev "$IFACE" down

log_command ip link set dev "$IFACE" up

log '2. Cleaning up previous sessions...'
wpa_cli -i "$IFACE" terminate >/dev/null 2>&1
dhclient -x "$IFACE" >/dev/null 2>&1
sleep 1

log '3. Starting 802.1X authentication...'
# Keep the supplicant in the foreground internally; this script backgrounds it.
log_command wpa_supplicant -i "$IFACE" -D wired -c "$CONF_FILE" &

# Wait a few seconds for the EAP handshake to complete before requesting an IP
log 'Waiting 5 seconds for authentication to establish...'
sleep 5

log '4. Requesting IP address via DHCP...'
log_command dhclient -v "$IFACE"

log '5. Network configuration complete:'
log_command ip -4 addr show dev "$IFACE"
