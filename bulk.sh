#!/bin/bash

if [[ ( $@ == "--help") ||  $@ == "-h" || $# -ne 4 ]]
then 
	echo "Usage: $0 [network] [user] [password] [command]"
	echo "This tool scans network with fping, and establishs ssh connection to every found ip in a tmux pannel"
	exit 0
fi 

# Datei mit der Liste der IP-Adressen
active_ips=$(fping -qag $1)

# Schleife durch jede IP-Adresse in der Liste
echo "$active_ips" | while IFS= read -r ip; do
  if nc -z "$ip" 22; then
    echo $ip
    sshpass -p $3 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$ip $4 & 
  fi
done

