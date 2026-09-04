#!/bin/bash

# Configuration
IFACE="$1"                                      # Change to your interface name (e.g., enp3s0)
CONF_FILE="./wired-8021x.conf"  # Path to the config file above

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

echo "1. Bringing up interface $IFACE..."
ip link set dev "$IFACE" down

ip link set dev "$IFACE" up

echo "2. Cleaning up previous sessions..."
wpa_cli -i "$IFACE" terminate >/dev/null 2>&1
dhclient -x "$IFACE" >/dev/null 2>&1
sleep 1

echo "3. Starting 802.1X authentication..."
# -B runs it in the background, -D wired specifies the wired driver
wpa_supplicant -i "$IFACE" -D wired -c "$CONF_FILE"

# Wait a few seconds for the EAP handshake to complete before requesting an IP
echo "Waiting 10 seconds for authentication to establish..."
sleep 10

echo "4. Requesting IP address via DHCP..."
dhclient -v "$IFACE"

echo "5. Network configuration complete:"
ip -4 addr show dev "$IFACE"
