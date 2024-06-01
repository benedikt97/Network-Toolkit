#!/usr/bin/env python

import socket
import struct
import time



if __name__ == '__main__':
  i = 1
  MCAST_GRP = '239.1.47.11'
  MCAST_PORT = 5001
  INTERFACE = '172.30.0.10'

  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
  sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 32)
  sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(INTERFACE))



  while True:
    s = 'This is some Airplane-Related Multicast! - ID: ' + str(i) + ' TIME: ' + str(time.time())
    m = bytes(s, 'utf-8')
    sock.sendto(m, (MCAST_GRP, MCAST_PORT))
    i += 1
    print('sending')
    time.sleep(0.01)
