#!/bin/bash

##
# This script only works with interfaces configured with static  ifcfg-* files.
# It monitors the link state of the given interface and removes the default route defined in the route-* 
# file when the interface goes down. If the interface goes up again, the route are reapplied.
# 
# Usage:
# ./link-monitor.sh eth0
#
w# This script should be installed as service and run in the background.
##

INTERFACE=$1

echo "Monitoring $INTERFACE"

while true; do
	LINK_STATUS=$(cat /sys/class/net/$INTERFACE/carrier 2>/dev/null)
	ROUTES=$(cat /etc/sysconfig/network-scripts/route-$INTERFACE | grep default)
	if [[ "$LINK_STATUS" == "0" ]] && ip route | grep "$INTERFACE" | grep -q "default"; then
		if [[ -n $ROUTES ]]; then 
			while read -r ROUTE; do
				echo "Removing ${ROUTE}"
				ip route del $ROUTE
			done <<< "$ROUTES"
		fi
	fi
	if [[ "$LINK_STATUS" == "1" ]] && ! ip route | grep "$INTERFACE" | grep -q "default"; then
		if [[ -n $ROUTES ]]; then	
			while read -r ROUTE; do
				echo "Adding ${ROUTE}"
				ip route add $ROUTE
			done <<< "$ROUTES"
		fi
	fi
	sleep 5
done 
