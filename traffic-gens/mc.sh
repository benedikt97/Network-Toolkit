#!/usr/bin/env sh

MCAST="224.4.3.4"
IFACE="192.168.30.33"

set -x

while date; do
  socat -s -dd UDP4-RECV:0,ip-add-membership=${MCAST}:${IFACE} - > /dev/null;
  sleep 5;
done
