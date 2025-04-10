#!/bin/bash

if [[ ( $@ == "--help") ||  $@ == "-h" || $# -ne 3 ]]
then 
	echo "Usage: $0 [network] [user] [password]"
	echo "This tool scans network with fping, and establishs ssh connection to every found ip in a tmux pannel"
	exit 0
fi 

# Datei mit der Liste der IP-Adressen
active_ips=$(fping -qag $1)

# Name der neuen tmux-Session
session_name="ssh_connections"

# Neue tmux-Session erstellen
tmux new-session -d -s "$session_name"

# Zähler für die Panels
panel_counter=0

# Schleife durch jede IP-Adresse in der Liste
printf "%s\n" $active_ips | while IFS= read -r ip; do
  echo "$ip - Testing"
  if nc -z "$ip" 22; then
    echo "$ip - SSH Port open"
#    if sshpass -p $3 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$ip ls; then
      echo "$ip - Login succesful"
      if [ $panel_counter -eq 0 ]; then
        # Das erste Panel wird automatisch erstellt
        tmux send-keys -t "$session_name.$panel_counter" "sshpass -p $3 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$ip" C-m
      else
        # Neues Panel für die nächste IP-Adresse
        tmux split-window -t "$session_name" -h
        tmux select-layout -t "$session_name" tiled
        tmux send-keys -t "$session_name.$panel_counter" "sshpass -p $3 ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $2@$ip" C-m
      fi
      panel_counter=$((panel_counter + 1))
    fi
#  fi
done 

# tmux-Session öffnen
#tmux attach-session -t "$session_name"
echo "Created tmux session $session_name"
