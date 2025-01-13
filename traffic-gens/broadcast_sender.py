#!/usr/bin/env python

import socket
import struct
import time
import os
import sys





if __name__ == '__main__':
  if len(sys.argv) != 3:
    print('broadcast_sender.py [INTERFACE] [PORT]')
    exit()
  i = 1
  DST_IP = '255.255.255.255'
  UDP_PORT = int(sys.argv[2])
  INTERFACE = sys.argv[1]

  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
  sock.bind((INTERFACE ,0))
  sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)


  while True:
    s = 'This is some Airplane-Related Broadcast - ID: ' + str(i) + ' TIME: ' + str(time.time())
    m = bytes(s, 'utf-8')
    sock.sendto(m, (DST_IP, UDP_PORT))
    i += 1
    print('sending: ' + s)
    time.sleep(0.1)
