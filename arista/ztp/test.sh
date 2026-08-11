#!/bin/bash

for mode in "isc" "avd" "eos"; do
    ./setup_arista_wifi_ztp.sh -devices both -platform $mode -ipversion 4 -network 192.168.51.0/24 -nameserver 8.8.8.8 -netmask 255.255.255.0 -gateway 192.168.51.1 -range-begin 192.168.51.100 -range-end 192.168.51.200 -cvcue redirector.online.spectraguard.net -matchstring ARISTA-AP\* -tftp 192.168.51.250 -tftp-path ztp.conf
    ./setup_arista_wifi_ztp.sh -devices both -platform $mode -ipversion 6 -network 2a02:8071:280:ee1f::/64 -nameserver 2001:4860:4860::8888 -cvcue redirector.online.spectraguard.net -matchstring ARISTA-AP-C-\* -tftp 2a02:8071:280:ee1f:be24:11ff:fead:2cea -tftp-path ztp.conf
done