#!/usr/bin/env python3
import socket
import struct
import os
import sys

if len(sys.argv) != 2:
   print('unicast_receiver_udp.py [PORT]')
   exit()

UDP_PORT = int(sys.argv[1])
IS_ALL_IPS = True
INTERFACE = ''


sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.bind(('', UDP_PORT))


print('Listening on: ' + str(UDP_PORT))
while True:
  # For Python 3, change next line to "print(sock.recv(10240))"
  m = sock.recv(1500).decode('utf-8', errors="ignore")
  print(m)
