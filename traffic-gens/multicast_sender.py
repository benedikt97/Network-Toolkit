#!/usr/bin/env python

import socket
import struct
import time
import sys    

if len(sys.argv) != 4:
   print('multicast_sender.py [INTERFACE] [MCAST_GRP] [MCAST_PORT]')
   exit()


if __name__ == '__main__':
  i = 1
  MCAST_GRP = sys.argv[2]
  MCAST_PORT = int(sys.argv[3])
  INTERFACE = sys.argv[1]

  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
  sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 32)
  sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(INTERFACE))



  while True:
    s = 'This is some Airplane-Related Multicast! - ID: ' + str(i) + ' TIME: ' + str(time.time())
    m = bytes(s, 'utf-8')
    sock.sendto(m, (MCAST_GRP, MCAST_PORT))
    i += 1
    print('sending')
    time.sleep(0.001)
