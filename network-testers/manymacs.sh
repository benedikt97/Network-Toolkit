#!/bin/bash

NIC=$1
COUNT=$2
for i in $(seq 1 $COUNT); do
    VNIC="macvlan$i"
    MAC=$(printf '02:%02X:%02X:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    ip link add link "$NIC" name "$VNIC" address "$MAC" type macvlan
    ip link set "$VNIC" up

    echo "Erstellt: $VNIC mit MAC $MAC"
done
