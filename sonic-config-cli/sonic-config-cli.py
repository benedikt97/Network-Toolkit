#!/usr/bin/python3

import os
import json
import pandas as pd
import sys
from sonic.sonictoolset import *


config_jsons = []
cmd = ''
sonic_mgmt_ips = []
username = 'admin'
password = 'YourPaSsWoRd'

with open('hosts', 'r') as f:
     lines = f.read().splitlines()
     for line in lines:
          sonic_mgmt_ips.append(line)

def userloop():
     print('Configured Management IPs:')
     print(sonic_mgmt_ips)
     print('Loaded Configs: \r\n')
     for d in config_jsons:
          print(d['DEVICE_METADATA']['localhost']['hostname'])
     if len(config_jsons) == 0:
          print('!!! Please start with [0] - Pulling Configs from Devices !!!')       
     cmd = input('''
Next Command? 
[#] Configuration Management            [##] Configuration Tasks                [##] Show-Outputs
-------------------------------------------------------------------------------------------------------------
[0]Pull configs from devices                                                    [20] Show VXLAN-Port-Mappings
[1]Show loaded Config*                                                          [21] Show VLXAN-Tunnel
[2]Save config on device                                                        [22] Show MAC-Table
[3]Dump loaded config to json*                                                  [23] Show IP-Routing-Table
[4]Reset devices                                                                [24] Show VLANs
[5]Push loaded configs to Devices*                                              [25] Show IP Interface
                                                                                [26] Show Interface
                                                                                [27] Show BGP Peers
                                                                                [28] Show LLDP
                                                                                [29] Show remote Macs
                                                                                [30] Show EVPN routes
[##] Configuration Checks              [##] Additional Tasks
--------------------------------------------------------------------------------------------------------------
[40] Test Loopback connectivity*       [50] Disable GRO on all Interfaces
                                       [51] Show vtysh config
* Needs loaded Configurations
\r\n''')
     return(cmd)


print('### NLAB Interactive SONiC Configuration CLI fpr BGP-EVPN ### \r\n')
while(cmd != 'exit'):
        cmd = userloop()
        match cmd:
          case '0':
            print('[0]- Pulling Config from Devices...')
            config_jsons = get_config(username, password, sonic_mgmt_ips)
          case 'a':
            print('[a]- Pulling Config from Devices...')
            config_jsons = get_config_cli(username, password, sonic_mgmt_ips)
          case '1':
            print('[1]- Show Config from Devices...')
            i = 0
            for config in config_jsons:
                 print('['+str(i)+'] - ' + config['DEVICE_METADATA']['localhost']['hostname'])
                 i += 1
            input_i = input('Specifiy Config by ID: ')
            print('Available Keys: ')
            for config_element in config_jsons[int(input_i)]:
               print(config_element)
            input_y = input('Specifiy Config by Key or type "ALL": ')
            try:
               if not 'ALL' in input_y:
                    while(input_y != 'exit'):
                         print(json.dumps(config_jsons[int(input_i)][input_y]))
                         input_y = input('Type another Key or "exit" to return: ')
                         
               else:                               
                    print(json.dumps(config_jsons[int(input_i)], indent='    '))
            except():
               print('Bad ID')
            input('Press return to continue...')
          case '2':
             save_config(username, password,sonic_mgmt_ips)
          case '3':
             backup_config(config_jsons,username, password)
          case '4':
             reset_config(username, password, sonic_mgmt_ips)
          case '5':
             push_config(config_jsons, sonic_mgmt_ips, username, password)

          case '6':
             cmd = input('Command: ')
             for ip in sonic_mgmt_ips:
                print(sshcmd(ip, cmd, username, password).decode('utf-8'))

          case '20':
             show_vxlan_port_mapping(sonic_mgmt_ips, username, password)
          case '21':
             show_bgp_partner(sonic_mgmt_ips, username, password)
          case '22':
             show_mac(sonic_mgmt_ips, username, password)
          case '23':
             show_iproute(sonic_mgmt_ips, username, password)
          case '24':
             show_vlan(sonic_mgmt_ips, username, password)
          case '25':
             show_ip_interface(sonic_mgmt_ips, username, password)
          case '26':
             show_interface_status(sonic_mgmt_ips, username, password)
          case '27':
             show_bgp(sonic_mgmt_ips, username, password)
          case '28':
             show_lldp(sonic_mgmt_ips, username, password)
          case '29':
             show_vxlan_remotemac(sonic_mgmt_ips, username, password)
          case '30':
             show_evpn_table(sonic_mgmt_ips, username, password)
          

          case '40':
            validate_underlay(config_jsons, username, password)
          case '50':
            disable_gro(sonic_mgmt_ips, username, password)
          case '51':
            show_vtysh_config(sonic_mgmt_ips, username, password)






