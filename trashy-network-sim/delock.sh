#!/bin/sh

ip link set enx88c9b3beeb69 down
ip link set enx88c9b3beeb6a down
ip link set enx88c9b3beeb6b down
ip link set enx88c9b3beeb6c down

brctl addbr br-delay
brctl addif br-delay enx88c9b3beeb6b
brctl addif br-delay enx88c9b3beeb6c

brctl addbr br-loss
brctl addif br-loss enx88c9b3beeb69
brctl addif br-loss enx88c9b3beeb6a

ip link set br-delay up
ip link set enx88c9b3beeb6b up
ip link set enx88c9b3beeb6c up

ip link set br-loss up
ip link set enx88c9b3beeb69 up
ip link set enx88c9b3beeb6a up


sudo tc qdisc add dev enx88c9b3beeb6b root netem delay 15ms 5ms distribution normal
sudo tc qdisc add dev enx88c9b3beeb6c root netem delay 15ms 5ms distribution normal

sudo tc qdisc add dev enx88c9b3beeb69 root netem loss 1% 80%
sudo tc qdisc add dev enx88c9b3beeb6a root netem loss 1% 80%
