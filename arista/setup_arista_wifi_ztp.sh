#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors (disabled for non-TTY)
if [[ -t 1 ]]; then
    BOLD='\033[1m' DIM='\033[2m' RED='\033[0;31m' GREEN='\033[0;32m'
    YELLOW='\033[0;33m' CYAN='\033[0;36m' RESET='\033[0m'
else
    BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

print_header()  { echo -e "\n${BOLD}${CYAN}$1${RESET}"; }
print_success() { echo -e "  ${GREEN}[OK]${RESET} $1"; }
print_error()   { echo -e "  ${RED}[ERROR]${RESET} $1" >&2; }
print_warn()    { echo -e "  ${YELLOW}[WARN]${RESET} $1"; }
print_info()    { echo -e "  ${DIM}$1${RESET}"; }

banner() {
    echo -e "${BOLD}${CYAN}"
    cat <<'BANNER'
    _         _     _          __________  ____
   / \   _ __(_)___| |_ __ _  |__  /_   _|  _ \
  / _ \ | '__| / __| __/ _` |   / /  | | | |_) |
 / ___ \| |  | \__ \ || (_| |  / /_  | | |  __/
/_/   \_\_|  |_|___/\__\__,_| /____| |_| |_|
BANNER
    echo -e "${RESET}"
    echo -e "  ${DIM}Zero-Touch Provisioning for Arista Access Points${RESET}"
    echo -e "  ${DIM}Generates ISC DHCP server configurations for AP onboarding${RESET}"
    echo ""
}

# Validation
validate_ipv4() {
    local IFS='.'; read -ra o <<< "$1"
    [[ ${#o[@]} -ne 4 ]] && return 1
    for n in "${o[@]}"; do
        [[ ! "$n" =~ ^[0-9]+$ ]] && return 1
        (( n > 255 )) && return 1
    done
    return 0
}

validate_ipv6() {
    [[ "$1" =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]] || [[ "$1" =~ :: ]]
}

validate_cidr() {
    [[ "$1" =~ ^(.+)/([0-9]+)$ ]] || return 1
    local ip="${BASH_REMATCH[1]}" prefix="${BASH_REMATCH[2]}"
    if [[ "$IPVERSION" == "4" ]]; then
        validate_ipv4 "$ip" || return 1
        (( prefix > 32 )) && return 1
    else
        (( prefix > 128 )) && return 1
    fi
    return 0
}

validate_netmask() {
    validate_ipv4 "$1" || return 1
    local IFS='.'; read -ra o <<< "$1"
    local inv=$(( ~((o[0]<<24)+(o[1]<<16)+(o[2]<<8)+o[3]) & 0xFFFFFFFF ))
    (( (inv & (inv + 1)) == 0 ))
}

# CIDR helpers
cidr_to_netmask() {
    local mask=$(( 0xFFFFFFFF << (32 - $1) & 0xFFFFFFFF ))
    printf "%d.%d.%d.%d" $(( (mask>>24)&0xFF )) $(( (mask>>16)&0xFF )) $(( (mask>>8)&0xFF )) $(( mask&0xFF ))
}

network_base() {
    local IFS='.'; read -ra o <<< "${1%%/*}"
    echo "${o[0]}.${o[1]}.${o[2]}"
}

# DHCPv6 Option 17 generator (replaces isc_dhcp6_generate_option17.py)
generate_option17() {
    local server="$1" magic="SPECTRATALK"
    local sub1_len sub4_len
    printf -v sub1_len '%02x' "${#server}"
    printf -v sub4_len '%02x' "${#magic}"
    echo -n "\\x00\\x00\\x42\\x05\\x00\\x01\\x00\\x${sub1_len}${server}\\x00\\x04\\x00\\x${sub4_len}${magic}"
}

# Config generator (envsubst on template files)
generate_config() {
    export NETWORK_ADDR="${NETWORK%%/*}"
    export TFTP_BLOCK=""
    if [[ -n "$TFTP" ]]; then
        TFTP_BLOCK=$(printf 'class "Arista-CCS" {\n    match if substring(option vendor-class-identifier, 0, 6) = "Arista";\n    option bootfile-name "http://%s/ztp.conf";\n}\n' "$TFTP")
        export TFTP_BLOCK
    fi
    local template="${SCRIPT_DIR}/templates/dhcpd_v${IPVERSION}.conf"
    envsubst < "$template"
}

# Help
show_help() {
    banner
    echo -e "${BOLD}USAGE${RESET}"
    echo -e "  $0 ${DIM}[options]${RESET}"
    echo -e "  $0 ${DIM}(no arguments = interactive mode)${RESET}"
    echo ""
    echo -e "${BOLD}GENERAL OPTIONS${RESET}"
    echo -e "  ${CYAN}-h${RESET}              Show this help message"
    echo -e "  ${CYAN}-i${RESET}              Launch guided interactive setup"
    echo -e "  ${CYAN}-ipversion${RESET}      ${DIM}<4|6>${RESET}                IP version"
    echo -e "  ${CYAN}-network${RESET}        ${DIM}<CIDR>${RESET}               Subnet (e.g. 192.168.10.0/24)"
    echo -e "  ${CYAN}-nameserver${RESET}     ${DIM}<IP>${RESET}                 DNS server address"
    echo -e "  ${CYAN}-cvcue${RESET}          ${DIM}<IP|cloud>${RESET}           CV-CUE server or ${YELLOW}cloud${RESET} for Arista cloud"
    echo -e "  ${CYAN}-mode${RESET}           ${DIM}<generate|install|test>${RESET}"
    echo ""
    echo -e "${BOLD}IPv4 OPTIONS${RESET} ${DIM}(auto-derived from CIDR if omitted)${RESET}"
    echo -e "  ${CYAN}-netmask${RESET}        ${DIM}<MASK>${RESET}     ${CYAN}-gateway${RESET}      ${DIM}<IP>${RESET}"
    echo -e "  ${CYAN}-range-begin${RESET}    ${DIM}<IP>${RESET}       ${CYAN}-range-end${RESET}    ${DIM}<IP>${RESET}"
    echo -e "  ${CYAN}-matchstring${RESET}    ${DIM}<PATTERN>${RESET}  ${CYAN}-tftp${RESET}         ${DIM}<IP>${RESET} (optional)"
    echo ""
    echo -e "${BOLD}MODES${RESET}"
    echo -e "  ${GREEN}generate${RESET}  Print config to stdout ${DIM}(default)${RESET}"
    echo -e "  ${YELLOW}install${RESET}   Write config and restart isc-dhcp-server ${DIM}(Ubuntu only)${RESET}"
    echo -e "  ${CYAN}test${RESET}      Test DHCP/DNS connectivity ${DIM}(requires -interface)${RESET}"
    echo ""
    echo -e "${BOLD}EXAMPLES${RESET}"
    echo -e "  ${DIM}# IPv4 — minimal (netmask, gateway, range auto-derived from CIDR)${RESET}"
    echo -e "  $0 -ipversion 4 -network 192.168.51.0/24 -nameserver 192.168.51.250 -cvcue 10.113.204.10"
    echo ""
    echo -e "  ${DIM}# IPv6${RESET}"
    echo -e "  $0 -ipversion 6 -network fd12:100:100:40::/64 \\"
    echo -e "     -nameserver fd12:100:100:40::1 -cvcue fd12:100:100:40::100 -matchstring 'ARISTA-AP-C-*'"
    echo ""
    exit 0
}

# Interactive prompts
prompt_value() {
    local prompt_text="$1" default_val="$2" var_name="$3" validator="$4" required="${5:-true}"
    while true; do
        if [[ -n "$default_val" ]]; then
            echo -en "  ${BOLD}${prompt_text}${RESET} ${DIM}[${default_val}]${RESET}: "
        else
            echo -en "  ${BOLD}${prompt_text}${RESET}: "
        fi
        local input; read -r input
        [[ -z "$input" && -n "$default_val" ]] && input="$default_val"
        [[ -z "$input" && "$required" == "true" ]] && { print_error "This field is required."; continue; }
        [[ -n "$validator" && -n "$input" ]] && ! $validator "$input" && { print_error "Invalid format. Please try again."; continue; }
        eval "export $var_name=\"$input\""
        return 0
    done
}

prompt_choice() {
    local prompt_text="$1" options="$2" default_val="$3" var_name="$4"
    while true; do
        echo -en "  ${BOLD}${prompt_text}${RESET} ${DIM}(${options})${RESET} ${DIM}[${default_val}]${RESET}: "
        local input; read -r input
        [[ -z "$input" ]] && input="$default_val"
        [[ "$options" == *"$input"* ]] && { eval "export $var_name=\"$input\""; return 0; }
        print_error "Please choose one of: ${options}"
    done
}

print_summary() {
    print_header "Configuration Summary"
    printf "  ${BOLD}%-18s${RESET} %s\n" "Mode:" "$MODE" "IP Version:" "IPv${IPVERSION}" "Network:" "$NETWORK"
    if [[ "$IPVERSION" == "4" ]]; then
        printf "  ${BOLD}%-18s${RESET} %s\n" "Netmask:" "$NETMASK" "Gateway:" "$GATEWAY" "DHCP Range:" "${RANGESTART} - ${RANGEEND}"
    fi
    printf "  ${BOLD}%-18s${RESET} %s\n" "Nameserver:" "$NAMESERVER" "CV-CUE Server:" "$CVCUE"
    [[ -n "$MATCHSTRING" ]] && printf "  ${BOLD}%-18s${RESET} %s\n" "VCI Match:" "$MATCHSTRING"
    [[ -n "$TFTP" ]] && printf "  ${BOLD}%-18s${RESET} %s\n" "TFTP Server:" "$TFTP"
    echo ""
}

interactive_setup() {
    banner

    print_header "Step 1: What would you like to do?"
    echo -e "\n  ${GREEN}generate${RESET}  Generate DHCP config and print to stdout"
    echo -e "  ${YELLOW}install${RESET}   Generate, write to disk, and restart isc-dhcp-server ${DIM}(Ubuntu only)${RESET}"
    echo -e "  ${CYAN}test${RESET}      Test DHCP and DNS connectivity on an existing setup\n"
    prompt_choice "Mode" "generate/install/test" "generate" "MODE"

    print_header "Step 2: IP Version"
    echo ""
    prompt_choice "Which IP version?" "4/6" "4" "IPVERSION"

    if [[ "$MODE" == "test" ]]; then
        print_header "Step 3: Test Interface"
        echo ""
        prompt_value "Network interface (e.g. ens18, eth0)" "" "INTERFACE"
        echo -en "\n  ${BOLD}Run test?${RESET} ${DIM}[Y/n]${RESET}: "
        read -r confirm
        [[ "$confirm" =~ ^[Nn] ]] && { print_warn "Aborted."; exit 0; }
        return
    fi

    print_header "Step 3: Network Configuration"
    echo ""
    if [[ "$IPVERSION" == "4" ]]; then
        prompt_value "Subnet (CIDR, e.g. 192.168.10.0/24)" "" "NETWORK" "validate_cidr"
        local prefix="${NETWORK##*/}"
        local base; base=$(network_base "$NETWORK")
        local auto_netmask; auto_netmask=$(cidr_to_netmask "$prefix")
        echo ""
        print_info "Auto-derived from /${prefix}: netmask=${auto_netmask}  gateway=${base}.1  range=${base}.100-${base}.200"
        echo ""
        prompt_value "Netmask" "$auto_netmask" "NETMASK" "validate_netmask"
        prompt_value "Default gateway" "${base}.1" "GATEWAY" "validate_ipv4"
        prompt_value "DHCP range start" "${base}.100" "RANGESTART" "validate_ipv4"
        prompt_value "DHCP range end" "${base}.200" "RANGEEND" "validate_ipv4"
    else
        prompt_value "Subnet (CIDR, e.g. fd12:100:100:40::/64)" "" "NETWORK" "validate_cidr"
    fi

    print_header "Step 4: Services"
    echo ""
    local ip_validator="validate_ipv4"; [[ "$IPVERSION" == "6" ]] && ip_validator="validate_ipv6"
    prompt_value "DNS nameserver" "" "NAMESERVER" "$ip_validator"
    echo -e "\n  ${DIM}Tip: Enter ${YELLOW}cloud${DIM} to use Arista's cloud redirector${RESET}"
    prompt_value "CV-CUE server address" "" "CVCUE"
    local default_match="ARISTA-AP*"; [[ "$IPVERSION" == "6" ]] && default_match="ARISTA-AP-C-*"
    prompt_value "VCI match pattern" "$default_match" "MATCHSTRING"
    if [[ "$IPVERSION" == "4" ]]; then
        print_info "Optional: TFTP server for CCS/DCS device boot (leave empty to skip)"
        prompt_value "TFTP server" "" "TFTP" "" "false"
    fi

    [[ "$CVCUE" == "cloud" ]] && export CVCUE="redirector.online.spectraguard.net"
    print_summary

    echo -en "  ${BOLD}Proceed?${RESET} ${DIM}[Y/n]${RESET}: "
    read -r confirm
    [[ "$confirm" =~ ^[Nn] ]] && { print_warn "Aborted."; exit 0; }
    echo ""
}

# Flag parsing
MODE="generate"
INTERACTIVE=false
[[ $# -eq 0 ]] && INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -ipversion)     export IPVERSION="$2";     shift 2 ;;
        -network)       export NETWORK="$2";       shift 2 ;;
        -range-begin)   export RANGESTART="$2";    shift 2 ;;
        -range-end)     export RANGEEND="$2";      shift 2 ;;
        -netmask)       export NETMASK="$2";       shift 2 ;;
        -gateway)       export GATEWAY="$2";       shift 2 ;;
        -nameserver)    export NAMESERVER="$2";     shift 2 ;;
        -cvcue)         export CVCUE="$2";         shift 2 ;;
        -mode)          MODE="$2";                 shift 2 ;;
        -interface)     INTERFACE="$2";            shift 2 ;;
        -matchstring)   export MATCHSTRING="$2";   shift 2 ;;
        -tftp)          export TFTP="$2";          shift 2 ;;
        -i|--interactive) INTERACTIVE=true;        shift ;;
        -h|--help)      show_help ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ "$INTERACTIVE" == true ]] && interactive_setup
[[ "$CVCUE" == "cloud" ]] && export CVCUE="redirector.online.spectraguard.net"

if [[ -z "$IPVERSION" ]]; then
    print_error "IP version is required (-ipversion 4|6)"
    echo -e "  Run ${CYAN}$0 --help${RESET} or ${CYAN}$0 -i${RESET}"
    exit 1
fi

# Test mode
if [[ "$MODE" == "test" ]]; then
    [[ -z "$INTERFACE" ]] && { print_error "Test mode requires -interface"; exit 1; }
    print_header "Testing DHCP and DNS"
    command -v dhclient &>/dev/null || { print_error "dhclient required: apt install isc-dhcp-client"; exit 1; }
    print_success "dhclient found"
    if [[ "$IPVERSION" == "4" ]]; then
        print_header "DNS Lookup"
        nslookup "wifi-security-server"
        print_header "DHCP Test on ${INTERFACE}"
        timeout 5 tcpdump -c 2 -v -nni "$INTERFACE" port 68 and port 67 &
        timeout 5 dhclient -cf "${SCRIPT_DIR}/isc_dhcp_ap_client.conf" -d -v -sf /bin/true -lf /tmp/test.leases "$INTERFACE" 2>/dev/null
        [[ -n "$CVCUE" ]] && { print_header "CV-CUE Connectivity"; nc -zv "$CVCUE" 3851; }
    else
        print_header "DHCP Test on ${INTERFACE}"
        timeout 5 tcpdump -c 2 -v -nni "$INTERFACE" port 68 and port 67 &
        timeout 5 dhclient -cf "${SCRIPT_DIR}/isc_dhcp6_ap_client.conf" -6 -d -v -sf /bin/true -lf /tmp/test.leases "$INTERFACE" 2>/dev/null
        [[ -n "$CVCUE" ]] && { print_header "CV-CUE Connectivity"; nc -zv "$CVCUE" 3851; }
    fi
    exit 0
fi

# Auto-derive defaults & validate
if [[ "$IPVERSION" == "4" ]]; then
    DHCPCONFIG="/etc/dhcp/dhcpd.conf"
    if [[ -n "$NETWORK" ]]; then
        local_prefix="${NETWORK##*/}"
        base=$(network_base "$NETWORK")
        [[ -z "$NETMASK" ]]    && export NETMASK=$(cidr_to_netmask "$local_prefix")
        [[ -z "$GATEWAY" ]]    && export GATEWAY="${base}.1"
        [[ -z "$RANGESTART" ]] && export RANGESTART="${base}.100"
        [[ -z "$RANGEEND" ]]   && export RANGEEND="${base}.200"
    fi
    [[ -z "$MATCHSTRING" ]] && export MATCHSTRING="ARISTA-AP*"

    missing=()
    [[ -z "$NETWORK" ]]    && missing+=("-network")
    [[ -z "$NETMASK" ]]    && missing+=("-netmask")
    [[ -z "$GATEWAY" ]]    && missing+=("-gateway")
    [[ -z "$RANGESTART" ]] && missing+=("-range-begin")
    [[ -z "$RANGEEND" ]]   && missing+=("-range-end")
    [[ -z "$NAMESERVER" ]] && missing+=("-nameserver")
    [[ -z "$CVCUE" ]]      && missing+=("-cvcue")
    [[ ${#missing[@]} -gt 0 ]] && { print_error "Missing required options: ${missing[*]}"; exit 1; }

    validate_cidr "$NETWORK"     || { print_error "Invalid IPv4 CIDR: $NETWORK"; exit 1; }
    validate_ipv4 "$NAMESERVER"  || { print_error "Invalid nameserver: $NAMESERVER"; exit 1; }
    validate_ipv4 "$GATEWAY"     || { print_error "Invalid gateway: $GATEWAY"; exit 1; }
    validate_ipv4 "$RANGESTART"  || { print_error "Invalid range-begin: $RANGESTART"; exit 1; }
    validate_ipv4 "$RANGEEND"    || { print_error "Invalid range-end: $RANGEEND"; exit 1; }
    validate_netmask "$NETMASK"  || { print_error "Invalid netmask: $NETMASK"; exit 1; }
else
    DHCPCONFIG="/etc/dhcp/dhcpd6.conf"
    [[ -z "$MATCHSTRING" ]] && export MATCHSTRING="ARISTA-AP-C-*"

    missing=()
    [[ -z "$NETWORK" ]]    && missing+=("-network")
    [[ -z "$NAMESERVER" ]] && missing+=("-nameserver")
    [[ -z "$CVCUE" ]]      && missing+=("-cvcue")
    [[ ${#missing[@]} -gt 0 ]] && { print_error "Missing required options: ${missing[*]}"; exit 1; }

    export MAGICSTRING
    MAGICSTRING=$(generate_option17 "$CVCUE")
fi

# Output config
show_config() {
    echo -e "${DIM}─────────────────────────────────────────────${RESET}"
    echo "$1"
    echo -e "${DIM}─────────────────────────────────────────────${RESET}"
}

ISCCONFIG=$(generate_config)

if [[ "$MODE" == "generate" ]]; then
    print_header "Generated ISC DHCP Configuration"
    show_config "$ISCCONFIG"
    print_success "Copy the content above into ${CYAN}${DHCPCONFIG}${RESET}"
fi

if [[ "$MODE" == "install" ]]; then
    print_header "Install Mode"
    grep -q Ubuntu /etc/os-release 2>/dev/null || { print_error "Install mode is only supported on Ubuntu."; exit 1; }
    print_success "Ubuntu detected"
    command -v dhcpd &>/dev/null || { print_error "isc-dhcp-server not installed: apt install isc-dhcp-server"; exit 1; }
    print_success "isc-dhcp-server found"
    ip route get "$GATEWAY" &>/dev/null || { print_error "No interface in target subnet (${NETWORK})."; exit 1; }
    print_success "Interface reachable in target subnet"
    echo ""
    show_config "$ISCCONFIG"
    echo ""
    print_warn "This will overwrite ${CYAN}${DHCPCONFIG}${RESET} and restart isc-dhcp-server."
    echo -en "  ${BOLD}Proceed?${RESET} ${DIM}[y/N]${RESET}: "
    read -r confirm
    [[ ! "$confirm" =~ ^[Yy] ]] && { print_warn "Aborted."; exit 0; }
    echo "$ISCCONFIG" | tee "$DHCPCONFIG" > /dev/null
    systemctl restart isc-dhcp-server.service
    print_success "Configuration written and isc-dhcp-server restarted."
    systemctl status isc-dhcp-server.service --no-pager -l
fi
