import redis
import threading
import time
import random
from scapy.all import Ether, IP, Raw, UDP, sendp
import sys

interface=sys.argv[1]
mac_count=int(sys.argv[2])
packets_per_second=int(sys.argv[3])

"""
Redis connection
"""
redis_conn = redis.Redis(host='localhost', port=6379, db=0)
QUEUE_NAME = "mac_queue"

"""
Generate random MAC with trailing 04
"""
def generate_mac():
    return "04:" + ":".join(f"{random.randint(0, 255):02x}" for _ in range(5))

def generate_ip():
    return "192.168." + ".".join(str(random.randint(1, 254)) for _ in range(2))

"""
Send packet function
"""
def send_packet(mac, source_ip, destination_ip):
    udp_payload = "Generated testpaket by manymacs2.py!"
    pkt = (     Ether(src=mac, dst='02:01:01:01:01:01') / 
                IP(src=source_ip, dst=destination_ip) /
                UDP(sport=40333, dport=40333) /
                Raw(load=udp_payload))
    sendp(pkt, iface=interface, verbose=False)

"""
Create list of unique macs
"""
def create_mac_list(count):
    macs = []
    for _ in range(count):
        macs.append(generate_mac())
    macs = list(set(macs))
    return macs

"""
Enqueue MACs in Redis
"""
def enqueue_macs(rate_per_second, macs):
    interval = 1 / rate_per_second
    for mac in macs:
        redis_conn.rpush(QUEUE_NAME, mac)
#        print(f"[PRODUCER] Enqueued MAC: {mac}")
#        time.sleep(interval)

"""
Worker function
"""
def worker(thread_id):
    while True:
        mac = redis_conn.lpop(QUEUE_NAME)
        if mac:
            print(f"[THREAD-{thread_id}] Processing MAC: {mac.decode()}")
            destination_ip = generate_ip()
            source_ip = "192.168.51.2"
            send_packet(mac, source_ip, destination_ip)
        else:
            time.sleep(0.2)  

"""
Create sum of workers
"""
def start_consumers(thread_count=3):
    for i in range(thread_count):
        t = threading.Thread(target=worker, args=(i,))
        t.daemon = True
        t.start()

# Hauptprogramm
if __name__ == "__main__":
    start_consumers(thread_count=16)
    macs = create_mac_list(mac_count)
    enqueue_macs(rate_per_second=packets_per_second, macs=macs)
    print("Producer done. Waiting for consumers...")
    time.sleep(1000000) 

