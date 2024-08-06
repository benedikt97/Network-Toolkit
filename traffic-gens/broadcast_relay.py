#!/usr/bin/env python3
import socket
import struct
import os


B_UDP_PORT = 5001
B_INTERFACE = '192.168.30.51'

U_DST_IP = '192.168.30.16'
U_UDP_PORT = 5002
U_INTERFACE = '192.168.30.51'


b_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
b_sock.bind((B_INTERFACE, UDP_PORT))
u_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)



while True:
  m = b_sock.recv(1500)
  u_sock.sendto(m, (U_DST_IP, U_UDP_PORT))
  print('send!')