#!/usr/bin/env python3
import socket
import struct
import os


B_UDP_PORT = 5001
B_INTERFACE = '255.255.255.255'

U_DST_IP = '192.168.30.51'
U_UDP_PORT = 5002
U_INTERFACE = '192.168.30.16'


b_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
b_sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
b_sock.bind((B_INTERFACE, B_UDP_PORT))
u_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)



while True:
  m = b_sock.recv(1500)
  print(m)
  u_sock.sendto(m, (U_DST_IP, U_UDP_PORT))
  print('send!')