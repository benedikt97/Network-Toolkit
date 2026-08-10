#!/bin/bash

# =============================================================================
# Arista ZTP DHCP Utility
#
# Generates DHCP configuration, installs ISC DHCP configuration, or emulates
# Arista devices while testing DHCP connectivity.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Terminal Presentation
#
# Colours are disabled for redirected output so generated configuration can be
# copied directly into a DHCP server configuration file.
# =============================================================================

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
    echo -e "  ${DIM}Generates ISC DHCP, Arista EOS, or AVD DHCP configurations for onboarding${RESET}"
    echo ""
}

# =============================================================================
# Input Validation and Network Helpers
#
# These functions validate interactive and command-line input, then derive the
# IPv4 values consumed by the selected configuration template.
# =============================================================================

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
    local address=$(( o[0] * 16777216 + o[1] * 65536 + o[2] * 256 + o[3] ))
    local inv=$(( 0xFFFFFFFF - address ))
    (( (inv & (inv + 1)) == 0 ))
}

# CIDR helpers
cidr_to_netmask() {
    local prefix="$1" index
    local -a octets=(0 0 0 0)
    local -a partial_masks=(0 128 192 224 240 248 252 254)

    for ((index = 0; index < 4; index++)); do
        if (( prefix >= 8 )); then
            octets[index]=255
            prefix=$(( prefix - 8 ))
        elif (( prefix > 0 )); then
            octets[index]=${partial_masks[prefix]}
            prefix=0
        fi
    done

    printf '%s.%s.%s.%s' "${octets[0]}" "${octets[1]}" "${octets[2]}" "${octets[3]}"
}

network_base() {
    local IFS='.'; read -ra o <<< "${1%%/*}"
    echo "${o[0]}.${o[1]}.${o[2]}"
}

# =============================================================================
# DHCP Vendor Option Encoders
#
# Vendor discovery payloads are encoded here for ISC DHCP, EOS, and AVD output.
# =============================================================================

generate_option17() {
    local server="$1" magic="SPECTRATALK"
    local sub1_len sub4_len
    printf -v sub1_len '%02x' "${#server}"
    printf -v sub4_len '%02x' "${#magic}"
    echo -n "\\x00\\x00\\x42\\x05\\x00\\x01\\x00\\x${sub1_len}${server}\\x00\\x04\\x00\\x${sub4_len}${magic}"
}

# EOS expects option payloads as one continuous hexadecimal string.
ascii_to_hex() {
    printf '%s' "$1" | od -An -tx1 | tr -d ' \n'
}

generate_eos_option43() {
    local server="$1" magic="SPECTRATALK" server_len magic_len
    printf -v server_len '%02x' "${#server}"
    printf -v magic_len '%02x' "${#magic}"
    printf '01%s%s04%s%s' "$server_len" "$(ascii_to_hex "$server")" "$magic_len" "$(ascii_to_hex "$magic")"
}

generate_eos_option17() {
    local server="$1" magic="SPECTRATALK" server_len magic_len
    printf -v server_len '%04x' "${#server}"
    printf -v magic_len '%04x' "${#magic}"
    printf '000042050001%s%s0004%s%s' "$server_len" "$(ascii_to_hex "$server")" "$magic_len" "$(ascii_to_hex "$magic")"
}

# =============================================================================
# Configuration Rendering
#
# Device-specific snippets are assembled first and substituted into the
# platform and IP-version template selected by the user.
# =============================================================================

generate_config() {
    export NETWORK_ADDR="${NETWORK%%/*}"
    export WIFI_BLOCK="" TFTP_BLOCK="" EOS_WIFI_BLOCK="" EOS_TFTP_BLOCK="" AVD_WIFI_BLOCK="" AVD_TFTP_BLOCK=""
    if [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]]; then
        if [[ "$PLATFORM" == "isc" && "$IPVERSION" == "4" ]]; then
            WIFI_BLOCK=$(printf 'option space arista;\noption arista.cv-cue-server code 1 = text;\noption arista.magic-string code 4 = text;\n\nclass "Arista-AP" {\n    match if option vendor-class-identifier ~= "%s";\n    vendor-option-space arista;\n    option arista.cv-cue-server "%s";\n    option arista.magic-string "SPECTRATALK";\n}\n' "$MATCHSTRING" "$CVCUE")
        elif [[ "$PLATFORM" == "isc" ]]; then
            WIFI_BLOCK=$(printf '  if substring(option dhcp6.vendor-class, 6, 15) ~= "%s" {\n    option dhcp6.vendor-opts "%s";\n    option dhcp6.bootfile-url "my-startup-config";\n  }' "$MATCHSTRING" "$MAGICSTRING")
        elif [[ "$PLATFORM" == "eos" && "$IPVERSION" == "4" ]]; then
            EOS_WIFI_BLOCK=$(printf '   !\n   vendor-option ipv4 Arista\n      sub-option 1 type string data "%s"\n      sub-option 4 type string data "SPECTRATALK"' "$CVCUE")
        elif [[ "$PLATFORM" == "eos" ]]; then
            EOS_WIFI_BLOCK=$(printf '      option 17 hex %s' "$(generate_eos_option17 "$CVCUE")")
        fi
    fi
    if [[ "$PLATFORM" == "avd" && ( "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ) ]]; then
        if [[ "$IPVERSION" == "4" ]]; then
            AVD_WIFI_BLOCK=$(printf '    # WiFi vendor discovery options for Arista access points.\n    ipv4_vendor_options:\n      - vendor_id: Arista\n        sub_options:\n          - code: 1\n            string: "%s"\n          - code: 4\n            string: "SPECTRATALK"' "$CVCUE")
        else
            AVD_WIFI_BLOCK=$(printf '    # DHCPv6 option 17 is emitted through the eos_cli escape hatch.\n    eos_cli: |-\n      option 17 hex %s' "$(generate_eos_option17 "$CVCUE")")
        fi
    fi
    if [[ ( "$DEVICE_TYPE" == "dcs-ccs" || "$DEVICE_TYPE" == "both" ) && -n "$TFTP" ]]; then
        local tftp_path="${TFTP_PATH:-ztp.conf}"
        tftp_path="${tftp_path#/}"
        if [[ "$PLATFORM" == "isc" ]]; then
            TFTP_BLOCK=$(printf 'class "Arista-CCS" {\n    match if substring(option vendor-class-identifier, 0, 6) = "Arista";\n    option bootfile-name "http://%s/%s";\n}\n' "$TFTP" "$tftp_path")
            export TFTP_BLOCK
        elif [[ "$PLATFORM" == "eos" && "$IPVERSION" == "4" ]]; then
            EOS_TFTP_BLOCK=$(printf '   tftp server option 66 ipv4 %s\n   tftp server file ipv4 http://%s/%s' "$TFTP" "$TFTP" "$tftp_path")
            export EOS_TFTP_BLOCK
        fi
    fi
    if [[ "$PLATFORM" == "avd" && ( "$DEVICE_TYPE" == "dcs-ccs" || "$DEVICE_TYPE" == "both" ) && -n "$TFTP" && "$IPVERSION" == "4" ]]; then
        AVD_TFTP_BLOCK=$(printf '    tftp_server:\n      option_66_ipv4: %s\n      file_ipv4: "http://%s/%s"' "$TFTP" "$TFTP" "$tftp_path")
    fi
    local template
    if [[ "$PLATFORM" == "isc" ]]; then
        template="${SCRIPT_DIR}/templates/dhcpd_v${IPVERSION}.conf"
    elif [[ "$PLATFORM" == "eos" ]]; then
        template="${SCRIPT_DIR}/templates/eos_dhcp_v${IPVERSION}.conf"
    else
        template="${SCRIPT_DIR}/templates/avd_dhcp_v${IPVERSION}.yml"
    fi
    envsubst < "$template"
}

# =============================================================================
# Help, Command Rendering, and Interactive Workflow
#
# Generate and install share the same data collection. Test mode branches early
# because it only needs an IP version, device identity, and network interface.
# =============================================================================

show_help() {
    banner
    echo -e "${BOLD}USAGE${RESET}"
    echo -e "  $0 ${DIM}[options]${RESET}"
    echo -e "  $0 ${DIM}(no arguments = interactive mode)${RESET}"
    echo ""
    echo -e "${BOLD}GENERAL OPTIONS${RESET}"
    echo -e "  ${CYAN}-h${RESET}              Show this help message"
    echo -e "  ${CYAN}-i${RESET}              Launch guided interactive setup"
    echo -e "  ${CYAN}-mode${RESET}           ${DIM}<generate|install|test>${RESET} Generate, install, or test DHCP"
    echo -e "  ${CYAN}-interface${RESET}      ${DIM}<NAME>${RESET}               Interface for test mode"
    echo -e "  ${CYAN}-devices${RESET}        ${DIM}<wifi|dcs-ccs|both>${RESET}  Device type / test client identity (default: both)"
    echo -e "  ${CYAN}-platform${RESET}       ${DIM}<isc|eos|avd>${RESET}        DHCP configuration target (default: isc)"
    echo -e "  ${CYAN}-ipversion${RESET}      ${DIM}<4|6>${RESET}                IP version"
    echo -e "  ${CYAN}-network${RESET}        ${DIM}<CIDR>${RESET}               Subnet (e.g. 192.168.10.0/24)"
    echo -e "  ${CYAN}-nameserver${RESET}     ${DIM}<IP>${RESET}                 DNS server address"
    echo -e "  ${CYAN}-cvcue${RESET}          ${DIM}<IP|cloud>${RESET}           CV-CUE server or ${YELLOW}cloud${RESET} for Arista cloud"
    echo ""
    echo -e "${BOLD}IPv4 OPTIONS${RESET} ${DIM}(auto-derived from CIDR if omitted)${RESET}"
    echo -e "  ${CYAN}-netmask${RESET}        ${DIM}<MASK>${RESET}     ${CYAN}-gateway${RESET}      ${DIM}<IP>${RESET}"
    echo -e "  ${CYAN}-range-begin${RESET}    ${DIM}<IP>${RESET}       ${CYAN}-range-end${RESET}    ${DIM}<IP>${RESET}"
    echo -e "  ${CYAN}-matchstring${RESET}    ${DIM}<PATTERN>${RESET}  ${CYAN}-tftp${RESET}         ${DIM}<IP>${RESET} (optional)"
    echo -e "  ${CYAN}-tftp-path${RESET}      ${DIM}<PATH>${RESET}     ZTP file path (default: ztp.conf)"
    echo -e "  ${CYAN}-config-path${RESET}    ${DIM}<PATH>${RESET}     ISC DHCP config path for install mode"
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
    printf "  ${BOLD}%-18s${RESET} %s\n" "Device Type:" "$DEVICE_TYPE" "DHCP Platform:" "$PLATFORM" "IP Version:" "IPv${IPVERSION}" "Network:" "$NETWORK"
    if [[ "$IPVERSION" == "4" ]]; then
        printf "  ${BOLD}%-18s${RESET} %s\n" "Netmask:" "$NETMASK" "Gateway:" "$GATEWAY" "DHCP Range:" "${RANGESTART} - ${RANGEEND}"
    fi
    printf "  ${BOLD}%-18s${RESET} %s\n" "Nameserver:" "$NAMESERVER" "CV-CUE Server:" "$CVCUE"
    [[ -n "$MATCHSTRING" ]] && printf "  ${BOLD}%-18s${RESET} %s\n" "VCI Match:" "$MATCHSTRING"
    [[ -n "$TFTP" ]] && printf "  ${BOLD}%-18s${RESET} %s\n" "TFTP Server:" "$TFTP"
    [[ -n "$TFTP" ]] && printf "  ${BOLD}%-18s${RESET} %s\n" "TFTP File:" "${TFTP_PATH:-ztp.conf}"
    [[ "$MODE" == "install" ]] && printf "  ${BOLD}%-18s${RESET} %s\n" "Install Target:" "${CONFIG_PATH:-/etc/dhcp/dhcpd.conf}"
    echo ""
    print_equivalent_command
    echo ""
}

build_command() {
    if [[ "$MODE" == "test" ]]; then
        local -a test_args=(-mode test -devices "$DEVICE_TYPE" -ipversion "$IPVERSION" -interface "$INTERFACE")
        local test_arg test_escaped test_command
        [[ -n "$CVCUE" ]] && test_args+=(-cvcue "$CVCUE")
        printf -v test_command '%q' "$0"
        for test_arg in "${test_args[@]}"; do
            printf -v test_escaped '%q' "$test_arg"
            test_command+=" ${test_escaped}"
        done
        printf '%s' "$test_command"
        return
    fi

    local -a args=(
        -devices "$DEVICE_TYPE"
        -platform "$PLATFORM"
        -ipversion "$IPVERSION"
        -network "$NETWORK"
        -nameserver "$NAMESERVER"
    )
    local arg escaped command

    if [[ "$IPVERSION" == "4" ]]; then
        args+=(-netmask "$NETMASK" -gateway "$GATEWAY" -range-begin "$RANGESTART" -range-end "$RANGEEND")
    fi
    if [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]]; then
        args+=(-cvcue "$CVCUE" -matchstring "$MATCHSTRING")
    fi
    if [[ -n "$TFTP" ]]; then
        args+=(-tftp "$TFTP" -tftp-path "${TFTP_PATH:-ztp.conf}")
    fi
    if [[ "$MODE" == "install" ]]; then
        args+=(-mode install -config-path "${CONFIG_PATH:-/etc/dhcp/dhcpd.conf}")
    fi

    printf -v command '%q' "$0"
    for arg in "${args[@]}"; do
        printf -v escaped '%q' "$arg"
        command+=" ${escaped}"
    done
    printf '%s' "$command"
}

print_equivalent_command() {
    printf "  ${BOLD}Equivalent command:${RESET}\n"
    printf "  %s\n" "$(build_command)"
}

interactive_setup() {
    banner

    print_header "Step 1: Operation"
    echo -e "\n  ${GREEN}generate${RESET}  Generate a DHCP configuration"
    echo -e "  ${YELLOW}install${RESET}   Generate, install, and restart ISC DHCP"
    echo -e "  ${CYAN}test${RESET}      Request a DHCP lease and capture the exchange\n"
    prompt_choice "Mode" "generate/install/test" "generate" "MODE"

    print_header "Step 2: IP Version"
    echo ""
    prompt_choice "Which IP version?" "4/6" "4" "IPVERSION"

    if [[ "$MODE" == "test" ]]; then
        print_header "Step 3: Test Device"
        echo -e "\n  ${GREEN}wifi${RESET}     Act as an Arista WiFi access point"
        echo -e "  ${CYAN}dcs-ccs${RESET}  Act as an Arista DCS/CCS switch\n"
        prompt_choice "Test device" "wifi/dcs-ccs" "wifi" "DEVICE_TYPE"

        print_header "Step 4: Test Interface"
        echo ""
        prompt_value "Network interface (e.g. ens18, eth0)" "" "INTERFACE"
        echo ""
        print_equivalent_command
        echo -en "\n  ${BOLD}Run DHCP test?${RESET} ${DIM}[Y/n]${RESET}: "
        read -r confirm
        [[ "$confirm" =~ ^[Nn] ]] && { print_warn "Aborted."; exit 0; }
        return
    fi

    print_header "Step 3: Device Type"
    echo -e "\n  ${GREEN}wifi${RESET}     Arista WiFi access points"
    echo -e "  ${CYAN}dcs-ccs${RESET}  Arista DCS/CCS wired devices"
    echo -e "  ${YELLOW}both${RESET}     WiFi access points and DCS/CCS devices\n"
    prompt_choice "Device type" "wifi/dcs-ccs/both" "both" "DEVICE_TYPE"

    print_header "Step 4: DHCP Platform"
    echo -e "\n  ${GREEN}isc${RESET}  ISC DHCP server configuration"
    echo -e "  ${CYAN}eos${RESET}  Arista EOS DHCP server configuration"
    echo -e "  ${YELLOW}avd${RESET}  YAML variables for arista.avd.eos_cli_config_gen\n"
    prompt_choice "DHCP platform" "isc/eos/avd" "isc" "PLATFORM"

    print_header "Step 5: Network Configuration"
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

    print_header "Step 6: Services"
    echo ""
    local ip_validator="validate_ipv4"; [[ "$IPVERSION" == "6" ]] && ip_validator="validate_ipv6"
    prompt_value "DNS nameserver" "" "NAMESERVER" "$ip_validator"
    if [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]]; then
        echo -e "\n  ${DIM}Tip: Enter ${YELLOW}cloud${DIM} to use Arista's cloud redirector${RESET}"
        prompt_value "CV-CUE server address" "" "CVCUE"
        local default_match="ARISTA-AP*"; [[ "$IPVERSION" == "6" ]] && default_match="ARISTA-AP-C-*"
        prompt_value "VCI match pattern" "$default_match" "MATCHSTRING"
    fi
    [[ "$PLATFORM" == "eos" ]] && print_info "EOS applies the vendor option to the complete subnet; the VCI pattern is included as a configuration comment."
    if [[ "$IPVERSION" == "4" && ( "$DEVICE_TYPE" == "dcs-ccs" || "$DEVICE_TYPE" == "both" ) ]]; then
        print_info "Optional: TFTP server for CCS/DCS device boot (leave empty to skip)"
        prompt_value "TFTP server" "" "TFTP" "" "false"
        [[ -n "$TFTP" ]] && prompt_value "TFTP ZTP file path" "ztp.conf" "TFTP_PATH" "" "false"
    fi

    if [[ "$MODE" == "install" ]]; then
        print_header "Step 7: Install Target"
        echo ""
        command -v dhcpd &>/dev/null || { print_error "ISC DHCP server (dhcpd) is not installed."; exit 1; }
        print_success "ISC DHCP server found"
        prompt_value "ISC DHCP configuration path" "/etc/dhcp/dhcpd.conf" "CONFIG_PATH"
    fi

    [[ "$CVCUE" == "cloud" ]] && export CVCUE="redirector.online.spectraguard.net"
    print_summary

    echo -en "  ${BOLD}Proceed?${RESET} ${DIM}[Y/n]${RESET}: "
    read -r confirm
    [[ "$confirm" =~ ^[Nn] ]] && { print_warn "Aborted."; exit 0; }
    echo ""
}

# =============================================================================
# DHCP Client Test Mode
#
# dhcpcd runs in test mode, so it sends and captures DHCP exchanges without
# applying the offered lease to the selected interface.
# =============================================================================

run_test_mode() {
    [[ -n "$INTERFACE" ]] || { print_error "Test mode requires -interface."; exit 1; }
    [[ "$DEVICE_TYPE" != "both" ]] || DEVICE_TYPE="wifi"
    [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "dcs-ccs" ]] || { print_error "Test device must be wifi or dcs-ccs."; exit 1; }

    print_header "DHCP Connectivity Test"
    print_info "Interface: ${INTERFACE}  |  IPv${IPVERSION}  |  Client: ${DEVICE_TYPE}"
    command -v dhcpcd &>/dev/null || { print_error "dhcpcd required: install dhcpcd"; exit 1; }
    command -v tcpdump &>/dev/null || { print_error "tcpdump required: apt install tcpdump"; exit 1; }
    command -v timeout &>/dev/null || { print_error "timeout command required"; exit 1; }
    print_success "Required DHCP tools found"

    local capture_filter test_dir dhcpcd_config capture_pid dhcp_vci dhcp6_vendor_class
    local -a dhcpcd_request_args=()
    test_dir=$(mktemp -d /tmp/arista-ztp-test.XXXXXX) || { print_error "Could not create a temporary test directory."; exit 1; }
    dhcpcd_config="${test_dir}/dhcpcd.conf"
    trap 'rm -f "$dhcpcd_config"; rmdir "$test_dir" 2>/dev/null || true' EXIT

    if [[ "$IPVERSION" == "4" ]]; then
        if [[ "$DEVICE_TYPE" == "dcs-ccs" ]]; then
            dhcp_vci="Arista"
            dhcpcd_request_args=(-o tftp_server_name -o bootfile_name)
            print_info "Requesting TFTP server (option 66) and bootfile name (option 67)"
        else
            dhcp_vci="ARISTA-AP-430"
        fi
        capture_filter='port 67 or port 68'
        print_info "DHCPv4 vendor class (option 60): ${dhcp_vci}"
        if [[ "$DEVICE_TYPE" == "wifi" ]]; then
            command -v nslookup &>/dev/null || { print_error "nslookup required: apt install dnsutils"; exit 1; }
            print_header "DNS Lookup"
            nslookup "wifi-security-server" || print_warn "DNS lookup failed. Continuing with DHCP test."
        fi
    else
        if [[ "$DEVICE_TYPE" == "dcs-ccs" ]]; then
            dhcp6_vendor_class="Arista"
        else
            dhcp6_vendor_class="ARISTA-AP-C-430"
        fi
        capture_filter='ip6 and udp portrange 546-547'
        printf 'ia_na\nvendclass 16901 "%s"\noption dhcp6_bootfile_url\n' "$dhcp6_vendor_class" > "$dhcpcd_config"
        print_info "DHCPv6 vendor class (option 16): ${dhcp6_vendor_class}"
        print_info "Forcing a DHCPv6 IA_NA request (router advertisement has no DHCPv6 flags)"
    fi

    print_header "DHCP Exchange on ${INTERFACE}"
    timeout 8 tcpdump -c 6 -v -nni "$INTERFACE" $capture_filter &
    capture_pid=$!
    if [[ "$IPVERSION" == "4" ]]; then
        timeout 8 dhcpcd -4 -T -B -i "$dhcp_vci" "${dhcpcd_request_args[@]}" -t 8 "$INTERFACE" || print_warn "dhcpcd exited without a lease."
    else
        timeout 8 dhcpcd -6 -T -B -f "$dhcpcd_config" -t 8 "$INTERFACE" || print_warn "dhcpcd exited without an IPv6 lease."
    fi
    wait "$capture_pid" 2>/dev/null || true

    if [[ "$DEVICE_TYPE" == "wifi" && -n "$CVCUE" ]]; then
        command -v nc &>/dev/null || { print_warn "nc not found; skipping CV-CUE connectivity test."; return; }
        print_header "CV-CUE Connectivity"
        nc -zv "$CVCUE" 3851 || print_warn "Could not reach ${CVCUE}:3851"
    fi
}

# =============================================================================
# ISC DHCP Installation Mode
#
# The generated configuration is validated in the target directory before the
# selected ISC DHCP service is restarted.
# =============================================================================

detect_dhcp_service() {
    local service
    for service in isc-dhcp-server dhcpd; do
        if systemctl cat "$service" &>/dev/null; then
            printf '%s' "$service"
            return 0
        fi
    done
    return 1
}

run_install_mode() {
    [[ "$PLATFORM" == "isc" ]] || { print_error "Install mode supports only the ISC DHCP platform (-platform isc)."; exit 1; }
    [[ $EUID -eq 0 ]] || { print_error "Install mode must be run as root (for example: sudo $0 ...)."; exit 1; }
    command -v dhcpd &>/dev/null || { print_error "ISC DHCP server (dhcpd) is not installed."; exit 1; }
    command -v systemctl &>/dev/null || { print_error "systemctl is required to restart the ISC DHCP server."; exit 1; }

    local service config_dir temp_config dhcpd_args=()
    service=$(detect_dhcp_service) || { print_error "Could not find an ISC DHCP systemd service (isc-dhcp-server or dhcpd)."; exit 1; }
    CONFIG_PATH="${CONFIG_PATH:-/etc/dhcp/dhcpd.conf}"
    config_dir=$(dirname "$CONFIG_PATH")
    [[ -d "$config_dir" ]] || { print_error "Configuration directory does not exist: $config_dir"; exit 1; }
    [[ -w "$config_dir" ]] || { print_error "Configuration directory is not writable: $config_dir"; exit 1; }

    print_header "Install ISC DHCP Configuration"
    print_info "Target: ${CONFIG_PATH}  |  Service: ${service}"
    show_config "$DHCP_CONFIG"
    echo -en "  ${BOLD}Replace ${CONFIG_PATH} and restart ${service}?${RESET} ${DIM}[y/N]${RESET}: "
    read -r confirm
    [[ "$confirm" =~ ^[Yy] ]] || { print_warn "Aborted."; return; }

    temp_config=$(mktemp "${config_dir}/.arista-ztp-dhcpd.XXXXXX") || { print_error "Could not create a temporary configuration file."; exit 1; }
    printf '%s\n' "$DHCP_CONFIG" > "$temp_config"
    [[ "$IPVERSION" == "6" ]] && dhcpd_args=(-6)
    if ! dhcpd -t "${dhcpd_args[@]}" -cf "$temp_config"; then
        rm -f "$temp_config"
        print_error "Generated configuration failed dhcpd validation; existing configuration was not changed."
        exit 1
    fi
    install -m 0644 "$temp_config" "$CONFIG_PATH"
    rm -f "$temp_config"
    systemctl restart "$service"
    print_success "Configuration installed and ${service} restarted."
}

# =============================================================================
# Command-line Parsing and Main Dispatch
#
# Test mode runs after basic argument validation. Generate and install continue
# through shared default derivation and input validation below.
# =============================================================================

MODE="generate"
PLATFORM="isc"
DEVICE_TYPE="both"
INTERACTIVE=false
[[ $# -eq 0 ]] && INTERACTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -mode)          MODE="$2";                shift 2 ;;
        -devices)       DEVICE_TYPE="$2";          shift 2 ;;
        -platform)      PLATFORM="$2";            shift 2 ;;
        -ipversion)     export IPVERSION="$2";     shift 2 ;;
        -network)       export NETWORK="$2";       shift 2 ;;
        -range-begin)   export RANGESTART="$2";    shift 2 ;;
        -range-end)     export RANGEEND="$2";      shift 2 ;;
        -netmask)       export NETMASK="$2";       shift 2 ;;
        -gateway)       export GATEWAY="$2";       shift 2 ;;
        -nameserver)    export NAMESERVER="$2";     shift 2 ;;
        -cvcue)         export CVCUE="$2";         shift 2 ;;
        -matchstring)   export MATCHSTRING="$2";   shift 2 ;;
        -tftp)          export TFTP="$2";          shift 2 ;;
        -tftp-path)     export TFTP_PATH="$2";     shift 2 ;;
        -config-path)   CONFIG_PATH="$2";          shift 2 ;;
        -interface)     INTERFACE="$2";            shift 2 ;;
        -i|--interactive) INTERACTIVE=true;        shift ;;
        -h|--help)      show_help ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

[[ "$INTERACTIVE" == true ]] && interactive_setup
[[ "$CVCUE" == "cloud" ]] && export CVCUE="redirector.online.spectraguard.net"

if [[ "$MODE" != "generate" && "$MODE" != "install" && "$MODE" != "test" ]]; then
    print_error "Mode must be generate, install, or test (-mode generate|install|test)"
    exit 1
fi

if [[ "$PLATFORM" != "isc" && "$PLATFORM" != "eos" && "$PLATFORM" != "avd" ]]; then
    print_error "DHCP platform must be isc, eos, or avd (-platform isc|eos|avd)"
    exit 1
fi
if [[ "$DEVICE_TYPE" != "wifi" && "$DEVICE_TYPE" != "dcs-ccs" && "$DEVICE_TYPE" != "both" ]]; then
    print_error "Device type must be wifi, dcs-ccs, or both (-devices wifi|dcs-ccs|both)"
    exit 1
fi

if [[ -z "$IPVERSION" ]]; then
    print_error "IP version is required (-ipversion 4|6)"
    echo -e "  Run ${CYAN}$0 --help${RESET} or ${CYAN}$0 -i${RESET}"
    exit 1
fi

if [[ "$MODE" == "test" ]]; then
    run_test_mode
    exit 0
fi

# =============================================================================
# Generate / Install Input Completion and Validation
# =============================================================================

if [[ "$IPVERSION" == "4" ]]; then
    if [[ -n "$NETWORK" ]]; then
        local_prefix="${NETWORK##*/}"
        base=$(network_base "$NETWORK")
        [[ -z "$NETMASK" ]]    && export NETMASK=$(cidr_to_netmask "$local_prefix")
        [[ -z "$GATEWAY" ]]    && export GATEWAY="${base}.1"
        [[ -z "$RANGESTART" ]] && export RANGESTART="${base}.100"
        [[ -z "$RANGEEND" ]]   && export RANGEEND="${base}.200"
    fi
    if [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]]; then
        [[ -z "$MATCHSTRING" ]] && export MATCHSTRING="ARISTA-AP*"
    fi

    missing=()
    [[ -z "$NETWORK" ]]    && missing+=("-network")
    [[ -z "$NETMASK" ]]    && missing+=("-netmask")
    [[ -z "$GATEWAY" ]]    && missing+=("-gateway")
    [[ -z "$RANGESTART" ]] && missing+=("-range-begin")
    [[ -z "$RANGEEND" ]]   && missing+=("-range-end")
    [[ -z "$NAMESERVER" ]] && missing+=("-nameserver")
    [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]] && [[ -z "$CVCUE" ]] && missing+=("-cvcue")
    [[ ${#missing[@]} -gt 0 ]] && { print_error "Missing required options: ${missing[*]}"; exit 1; }

    validate_cidr "$NETWORK"     || { print_error "Invalid IPv4 CIDR: $NETWORK"; exit 1; }
    validate_ipv4 "$NAMESERVER"  || { print_error "Invalid nameserver: $NAMESERVER"; exit 1; }
    validate_ipv4 "$GATEWAY"     || { print_error "Invalid gateway: $GATEWAY"; exit 1; }
    validate_ipv4 "$RANGESTART"  || { print_error "Invalid range-begin: $RANGESTART"; exit 1; }
    validate_ipv4 "$RANGEEND"    || { print_error "Invalid range-end: $RANGEEND"; exit 1; }
    validate_netmask "$NETMASK"  || { print_error "Invalid netmask: $NETMASK"; exit 1; }
    [[ "$PLATFORM" == "isc" ]] || print_warn "EOS applies the vendor option to the complete subnet; the VCI pattern is retained as a comment."
else
    if [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]]; then
        [[ -z "$MATCHSTRING" ]] && export MATCHSTRING="ARISTA-AP-C-*"
    fi

    missing=()
    [[ -z "$NETWORK" ]]    && missing+=("-network")
    [[ -z "$NAMESERVER" ]] && missing+=("-nameserver")
    [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]] && [[ -z "$CVCUE" ]] && missing+=("-cvcue")
    [[ ${#missing[@]} -gt 0 ]] && { print_error "Missing required options: ${missing[*]}"; exit 1; }

    if [[ "$DEVICE_TYPE" == "wifi" || "$DEVICE_TYPE" == "both" ]]; then
        export MAGICSTRING
        MAGICSTRING=$(generate_option17 "$CVCUE")
    fi
fi

# =============================================================================
# Rendered Output or Installation
#
# Install mode owns its preview and confirmation. Generate mode prints the
# selected platform's configuration to standard output.
# =============================================================================

show_config() {
    echo -e "${DIM}─────────────────────────────────────────────${RESET}"
    echo "$1"
    echo -e "${DIM}─────────────────────────────────────────────${RESET}"
}

DHCP_CONFIG=$(generate_config)

if [[ "$MODE" == "install" ]]; then
    run_install_mode
    exit 0
fi

if [[ "$PLATFORM" == "isc" ]]; then
    print_header "Generated ISC DHCP Configuration"
elif [[ "$PLATFORM" == "eos" ]]; then
    print_header "Generated Arista EOS DHCP Configuration"
else
    print_header "Generated AVD DHCP Variables"
fi
show_config "$DHCP_CONFIG"
if [[ "$PLATFORM" == "avd" ]]; then
    print_success "Save the YAML above as variables consumed by ${CYAN}arista.avd.eos_cli_config_gen${RESET}."
else
    print_success "Copy the content above into the ${CYAN}${PLATFORM}${RESET} DHCP server configuration."
fi
