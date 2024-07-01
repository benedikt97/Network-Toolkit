# Simulation eines Verbindungstrecke mit schlechter Metrik

![Alt text](drawing.png?raw=true "Title")
                
                
## Bind eth0 and eth1 to a bridge
ip link set eth0 down
ip link set eth1 down

brctl addbr br-trash
brctl addif br-trash eth0
brctö addif br-trash eth1

ip link set br-trash up
ip link set eth0 up
ip link set eth1 up

## Make Network trashy
### Static Delay
sudo tc qdisc add dev eth0 root netem delay 100ms

### Normal distributed
netem delay <mean> <standard deviation> distribution <distribution name>
sudo tc qdisc add dev eth0 root netem delay 100ms 50ms distribution normal

### Packet loss
sudo tc qdisc add dev eth0 root netem loss 30%
sudo tc qdisc add dev eth0 root netem loss 30% 50%

### Duplicate Packets
sudo tc qdisc add dev eth0 root duplicate 50%

### Packet corruption
sudo tc qdisc add dev eth0 root netem corrupt 30%

### Limiter
sudo tc qdisc add dev eth0 root netem rate 10Mbit


## Remove all Rules
sudo tc qdisc delete dev eth0 root
sudo tc qdisc show

