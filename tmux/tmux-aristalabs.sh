#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <target> <password>"
    echo "Example: $0 admin@192.168.1.50 mySecretPassword"
    exit 1
fi

TARGET="$1"
PASSWORD="$2"
SESSION="net_topo"
CMD="sshpass -p '$PASSWORD' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null '$TARGET'"

tmux new-session -d -s "$SESSION" -n "Devices-0"
tmux set-option -t "$SESSION" mouse on

DEVICE=14
DEVICECOUNTER=1
WINDOWS=$(( ($DEVICE) / 4 ))

for (( i=1; i<=$WINDOWS; i++ )); do
    WIN="Devices-$i"
    tmux new-window -t "$SESSION" -n $WIN
done

for (( i=0; i<=$WINDOWS; i++ )); do
    WIN="Devices-$i"
    tmux split-window -h -t "$SESSION:$WIN"
    tmux split-window -v -t "$SESSION:$WIN"
    tmux select-pane -t "$SESSION:$WIN.0"
    tmux split-window -v -t "$SESSION:$WIN"
    
    tmux select-layout -t "$SESSION:$WIN" tiled
    
	 
    for PANE in 0 1 2 3; do
        tmux send-keys -t "$SESSION:$WIN.$PANE" "$CMD" C-m
	sleep 0.2
        tmux send-keys -t "$SESSION:$WIN.$PANE" "98" C-m
	sleep 0.2 
	if [ "$DEVICECOUNTER"  -le "$DEVICE" ]; then
        	tmux send-keys -t "$SESSION:$WIN.$PANE" "$DEVICECOUNTER" C-m
	fi
	DEVICECOUNTER=$((DEVICECOUNTER+1))
    done
done

tmux attach-session -t "$SESSION"
