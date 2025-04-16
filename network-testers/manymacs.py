from scapy.all import Ether, sendp
import random
import time
import sys
import concurrent.futures

interface = sys.argv[1]

def random_mac():
    return ':'.join(['{:02x}'.format(random.randint(0, 255)) for _ in range(6)])


def send_packet(mac):
    pkt = Ether(src=mac, dst='02:01:01:01:01:01')
    sendp(pkt, iface=interface, verbose=False)
    print(pkt)    

num_packets = 1000000

macs = []
for i in range(num_packets):
    macs.append(random_mac())
print('Created list - now sending:')

#for mac in macs:
#    send_packet(mac)
#    print(mac)
#    time.sleep(0.01)

with concurrent.futures.ThreadPoolExecutor(max_workers=100) as executor:
    executor.map(send_packet, macs)
