#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root."
  exit 1
fi

RECONFIGURE=0
if [[ "$1" == "--reconfigure" ]]; then
  RECONFIGURE=1
fi

for i in {1..4}; do
  IFACE="eth$i"
  NS="ns$i"

  # Unconfigure logic if the flag is passed
  if [ "$RECONFIGURE" -eq 1 ]; then
    # Check if the namespace exists before trying to clean it up
    if ip netns list | grep -q "^$NS\b"; then
      echo "Unconfiguring $IFACE and removing namespace $NS..."
      
      # Release DHCP lease and kill dhclient process
      ip netns exec "$NS" dhclient -x "$IFACE" 2>/dev/null || true
      
      # If the interface is currently in the namespace, move it back to default (PID 1)
      if ip netns exec "$NS" ip link show "$IFACE" >/dev/null 2>&1; then
        ip netns exec "$NS" ip link set "$IFACE" down
        ip netns exec "$NS" ip link set "$IFACE" netns 1
      fi
      
      # Delete the namespace for a completely fresh state
      ip netns del "$NS" 2>/dev/null || true
    fi
  fi

  # Original configuration logic
  if ip netns exec "$NS" ip link show "$IFACE" >/dev/null 2>&1; then
    echo "Interface $IFACE is already in namespace $NS. Current state:"
    ip netns exec "$NS" ip -br a
    ip netns exec "$NS" ip -br l
    ip netns exec "$NS" fping -t 20 1.1.1.1
  else
    echo "Configuring $IFACE in namespace $NS..."

    ip netns add "$NS" 2>/dev/null || true

    if ip link show "$IFACE" >/dev/null 2>&1; then
      ip link set "$IFACE" netns "$NS"
      ip netns exec "$NS" ip link set lo up
      ip netns exec "$NS" ip link set "$IFACE" up
      ip netns exec "$NS" timeout 5 dhclient
   #   ip netns exec "$NS" dhclient -nw "$IFACE"
    else
      echo "Warning: Interface $IFACE not found in the default namespace. It may not exist or is in another namespace."
    fi
  fi
  echo "----------------------------------------"
done
