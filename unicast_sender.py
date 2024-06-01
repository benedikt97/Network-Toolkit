#!/usr/bin/env python

import socket
import struct
import time



if __name__ == '__main__':
  i = 1
  DST_IP = '127.0.0.1'
  UDP_PORT = 5001
  INTERFACE = '127.0.0.1'

  sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)

  while True:
    s = 'This is some Airplane-Related Multicast! - ID: ' + str(i) + ' TIME: ' + str(time.time())
    m = bytes(s, 'utf-8')
    sock.sendto(m, (DST_IP, UDP_PORT))
    i += 1
    print('sending: ' + s)
    time.sleep(0.01)
