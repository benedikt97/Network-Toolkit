#!/bin/bash

#set -x 
# Initialize variables
IP_VERSION=""
NETWORK=""

show_help() {
    echo "Usage: $0 [-h] [-ipversion] [-network] [-gateway] [-nameserver] [-cvcue] [-matchstring] [-mode]"
    echo ""
    echo "Options:"
    echo "  -h                                          Show this help message and exit"
    echo "  -devicetype     <wired|wifi>                Specify Arista device type                              (v4 and v6)"
    echo "  -ipversion      <4|6>                       Specify IP-Version"
    echo "  -network        <192.168.10.1/24>           Specify the subnet used for the dhcp pool               (v4 and v6)"
    echo "  -nameserver     <192.168.10.250>            Specify the nameserver                                  (v4 and v6)"
    echo "  -cvcue          <192.168.10.145|cloud>    Specify the ip address of your cv-cue server            (v4 and v6)"
    echo ""
    echo "  -range-begin    <192.168.10.100>            Specify the subnet used for the dhcp pool               (Only for v4)"
    echo "  -range-end      <192.168.10.200>            Specify the subnet used for the dhcp pool               (Only for v4)"
    echo "  -netmask        <255.255.255.0>             Specify the subnet mask                                 (Only for v4)"
    echo "  -gateway        <192.168.10.1>              Specify the subnet used for the dhcp pool               (Only for v4)"
    echo ""
    echo "  -matchstring    <ARISTA-AP-C-*>             Specify the VCI Matchstring for DHCP - regex allowed    (Only for v6)"
    echo ""
    echo "  -interface      <ens18>                     Specify the interface on which the DHCP server runs     (Only for testing)"
    echo ""
    echo "  -mode           <install|test>              Install and configure isc-dhcp automatically            (Only for Ubuntu)"
    echo ""
    echo "This script generates configurations to build a zero-touch environment for Arista Access-Points."
    echo "Modes:" 
    echo "  generate: Only generates config and prints to stdout"
    echo "  install: Tryes to configure the local ISC-DHCP-SERVER directly"
    echo "  test: Test the components needed for ztp (Needs: -ipversion, -interface)"
    echo " Warning: Installation mode is disruptive and should only be executed on a unconfigured machine"
    echo ""
    echo "Examples:"
    echo "v4: ./setup_arista_wifi_ztp.sh \\"
    echo "                    -ipversion 4 \\"
    echo "                    -network 192.168.51.0/24 \\"
    echo "                    -netmask 255.255.255.0 \\"
    echo "                    -range-begin 192.168.51.100 \\"
    echo "                    -range-end 192.168.51.200 \\"
    echo "                    -gateway 192.168.51.1 \\" 
    echo "                    -nameserver 192.168.51.250 \\"
    echo "                    -cvcue 10.113.204.10 \\"
    echo "                    -mode generate "
    echo ""
    echo "v6: ./setup_arista_wifi_ztp.sh \\"
    echo "                    -ipversion 6 \\"
    echo "                    -network fd12:100:100:40::/64 \\"
    echo "                    -nameserver fd12:100:100:40::1 \\"
    echo "                    -cvcue fd12:100:100:40::100 \\"
    echo "                    -matchstring "ARISTA-AP-C-*" \\" 
    echo "                    -mode generate "
    exit 1
}

log() {
    echo ""
    echo "-> "$0": "$1""
    echo ""
}

MODE="generate"
while [[ $# -gt 0 ]]; do
    case $1 in
        -devicetype | --devicetype )
            export TYPE="$2"
            shift 2 
            ;;
        -ipversion | --ipversion )
            export IPVERSION="$2"
            shift 2 
            ;;
        -network | --network )
            export NETWORK="$2"
            shift 2 
            ;;
        -range-begin | --range-begin )
            export RANGESTART="$2"
            shift 2 
            ;;
        -range-end | --range-end )
            export RANGEEND="$2"
            shift 2 
            ;;
        -netmask | --netmask )
            export NETMASK="$2"
            shift 2 
            ;;
        -gateway | --gateway )
            export GATEWAY="$2"
            shift 2 
            ;;
        -nameserver | --nameserver )
            export NAMESERVER="$2"
            shift 2 
            ;;
        -cvcue | --cvcue )
            export CVCUE="$2"
            shift 2 
            ;;
        -mode | --mode )
            MODE="$2"
            shift 2 
            ;;
        -interface | --interface )
            INTERFACE="$2"
            shift 2 
            ;;
        -matchstring | --matchstring )
            export MATCHSTRING="$2"
            shift 2 
            ;;
        -tftp | --tftp )
            export TFTP="$2"
            shift 2 
            ;;
        -h | --help )
            show_help
            exit 0
            ;;
        * )
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
done


if [[ -z "$IPVERSION" ]]; then
    show_help
fi
if [[ "$CVCUE" == "cloud" ]]; then
    export CVCUE="redirector.online.spectraguard.net"
fi

# --- Testing ---
if [[ "$MODE" == "test" ]]; then
    if [[ -z "$IPVERSION" ]] || [[ -z "$INTERFACE" ]]; then
        echo "Error: Missing required options."
        exit 1
    fi
    --- Testing ---
    log "Testing DHCP and DNS"
    { which -s dhclient && log "[OK] Testing DHCP and DNS"; }|| { log "[FAIL] dhclient is needed - 'please install with apt install ISC-DHCP-CLIENT'" && exit 1; }
    if [[ "$IPVERSION" == "4" ]]; then
        log "DNS:"
        nslookup "wifi-security-server"
        log "DHCP: Testing on "$INTERFACE""
        timeout 5 tcpdump -c 2 -v -nni $INTERFACE port 68 and port 67 &
        timeout 5 dhclient -cf isc_dhcp_ap_client.conf -d -v -sf /bin/true -lf /tmp/test.leases $INTERFACE 2>/dev/null
        log "Testing connectivity to CV-CUE"
        nc -zv "$CVCUE" 3851
    fi
    if [[ "$IPVERSION" == "6" ]]; then
        log "To be implemented..." 
    fi
    exit 0 
fi


# --- Input Validation ---
if [[ "$IPVERSION" == "4" ]]; then
    DHCPCONFIG="/etc/dhcp/dhcpd.conf"
    if [[ -z "$NETWORK" ]] || [[ -z "$NAMESERVER" ]] || [[ -z "$MODE" ]] || [[ -z "$NETMASK" ]] || [[ -z "$GATEWAY" ]] || [[ -z "$RANGESTART" ]] || [[ -z "$RANGEEND" ]]; then
        echo "Error: Missing required options."
        exit 1
    fi
fi
if [[ "$IPVERSION" == "6" ]]; then
    DHCPCONFIG="/etc/dhcp/dhcpd6.conf"
    if [[ -z "$NETWORK" ]] || [[ -z "$NAMESERVER" ]] || [[ -z "$MODE" ]] || [[ -z "$CVCUE" ]] || [[ -z "$MATCHSTRING" ]]; then
        echo "Error: Missing required options."
        exit 1
    fi
    export MAGICSTRING=$(python3 isc_dhcp6_generate_option17.py "$CVCUE")
fi


# --- Execution ---
if [[ "$MODE" == "generate" ]]; then
    ISCCONFIG=$(dhcp=true dns=true python3  isc-dhcp-generate.py isc_dhcp_arista_ztp_wifi.j2)
    log "[OK] COPY FROM NEXT LINE"
    echo "$ISCCONFIG"
fi

if [[ "$MODE" == "install" ]]; then
    ISCCONFIG=$(dhcp=true python3  isc-dhcp-generate.py isc_dhcp_arista_ztp_wifi.j2)
    log "Configuring of ISC DHCP Server"
    { grep /etc/os-release -qe Ubuntu && log "[OK] Check if Disto is Ubuntu"; } || { echo "Only allowed on Ubuntu - exiting" && exit 1; }
    { which -s dhcpd && log "[OK] Check if ISC-DHCP-SERVER is installed"; } || { log "[FAIL] isc-dhcp-server is needed - 'please install with apt install isc-dhcp-server'" && exit 1; }
    { ip route get "$GATEWAY" > /dev/null && log "[OK] Check if Server has an interface in desired pool"; } || { log "[FAIL] isc-dhcp-server is needed - 'please install with apt install isc-dhcp-server'" && exit 1; }
    log "[OK] Configure and restart ISC-DHCP-SERVER"
    echo "$ISCCONFIG" | tee "$DHCPCONFIG" > /dev/null
    systemctl restart isc-dhcp-server.service
    systemctl | grep isc-dhcp-server
fi
