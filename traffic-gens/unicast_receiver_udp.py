#!/usr/bin/env python3
import socket
import struct
import os


UDP_PORT = 5002
IS_ALL_IPS = True
INTERFACE = '192.168.30.16'


sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.bind(('', UDP_PORT))


last_id = 0
last_time = 0
message = []
message.append('Multicast-Tester - Benedikt Heuser')
message.append('Listening on: ' + str(UDP_PORT))
message.append('placeholder')
while True:
  clear = lambda: os.system('clear')
  # For Python 3, change next line to "print(sock.recv(10240))"
  m = sock.recv(1500).decode('utf-8')
  clear()
  mr = 'Received Message: ' + m
  message[2] = mr
  id = int(m.split()[7])
  time = float(m.split()[9])
  if id != (last_id+1) and last_id != 0:
    missed_time = time - last_time
    missed_mcs = id - last_id
    message.append('Missed ' + str(missed_mcs) + ' Multicasts for ' + str(missed_time) + ' seconds.')
  if id == last_id and last_id != 0:
    message.append('Multicast with ID: ' + str(id) + ' received two times')
  last_id = id
  last_time = time
  print('\n'.join(message))
