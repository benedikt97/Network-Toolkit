#!/usr/bin/env bash
# Install an EAP-TLS-only FreeRADIUS configuration on Ubuntu.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh --nas-ip ADDRESS --nas-secret SECRET [--server-name DNS_NAME] [--radsec]

--nas-ip       IP address of the switch/authenticator that will send RADIUS.
--nas-secret   Shared RADIUS secret (use a long, random value).
--server-name  DNS name placed in the RADIUS server certificate (default: hostname -f).
--radsec       Enable mutual-TLS RadSec on TCP port 2083.
EOF
}

NAS_IP=""
NAS_SECRET=""
SERVER_NAME="$(hostname -f 2>/dev/null || hostname)"
RADSEC=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nas-ip) NAS_IP=${2:?missing value}; shift 2 ;;
    --nas-secret) NAS_SECRET=${2:?missing value}; shift 2 ;;
    --server-name) SERVER_NAME=${2:?missing value}; shift 2 ;;
    --radsec) RADSEC=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo 'Run this installer with sudo.' >&2; exit 1; }
[[ -n $NAS_IP && -n $NAS_SECRET ]] || { usage >&2; exit 2; }
[[ $NAS_SECRET != 'change-me' ]] || { echo 'Choose a real --nas-secret.' >&2; exit 2; }
command -v apt-get >/dev/null || { echo 'This installer supports Ubuntu/Debian apt systems only.' >&2; exit 1; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RADIUS_DIR=/etc/freeradius/3.0
HOSTNAME_DIR=$(hostname -s)
CERT_DIR=$RADIUS_DIR/certs/$HOSTNAME_DIR
STAMP=$(date +%Y%m%d%H%M%S)
export CERT_DIR NAS_IP NAS_SECRET

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y freeradius freeradius-utils openssl gettext-base
[[ -d $RADIUS_DIR ]] || { echo "Expected FreeRADIUS 3 configuration at $RADIUS_DIR." >&2; exit 1; }

install -d -m 0750 "$CERT_DIR" "$CERT_DIR/ca" "$CERT_DIR/endpoints"
install -d -m 0755 "$RADIUS_DIR/clients.d"
install -m 0700 "$SCRIPT_DIR/certctl.sh" /usr/local/sbin/freeradius-certctl
envsubst '${CERT_DIR}' < "$SCRIPT_DIR/config/openssl-ca.cnf" > "$CERT_DIR/openssl-ca.cnf"
chmod 0640 "$CERT_DIR/openssl-ca.cnf"

backup="$RADIUS_DIR/.eap-tls-backup-$STAMP"
install -d -m 0700 "$backup"
for file in "$RADIUS_DIR/mods-enabled/eap" "$RADIUS_DIR/clients.conf" "$RADIUS_DIR/sites-enabled/radsec"; do
  [[ -e $file || -L $file ]] && cp -a "$file" "$backup/"
done

envsubst '${CERT_DIR}' < "$SCRIPT_DIR/config/mods-enabled/eap" > "$RADIUS_DIR/mods-enabled/eap"
chown root:freerad "$RADIUS_DIR/mods-enabled/eap"
chmod 0640 "$RADIUS_DIR/mods-enabled/eap"
envsubst '${NAS_IP} ${NAS_SECRET}' < "$SCRIPT_DIR/config/clients.d/network-toolkit.conf" > "$RADIUS_DIR/clients.d/eap-tls.conf"
chown root:freerad "$RADIUS_DIR/clients.d/eap-tls.conf"
chmod 0640 "$RADIUS_DIR/clients.d/eap-tls.conf"
if ! grep -Eq '^\$INCLUDE[[:space:]]+clients\.d/' "$RADIUS_DIR/clients.conf"; then
  printf '\n$INCLUDE clients.d/\n' >> "$RADIUS_DIR/clients.conf"
fi
if [[ $RADSEC == true ]]; then
  envsubst '${CERT_DIR}' < "$SCRIPT_DIR/config/sites-enabled/radsec" > "$RADIUS_DIR/sites-enabled/radsec"
  chown root:freerad "$RADIUS_DIR/sites-enabled/radsec"
  chmod 0640 "$RADIUS_DIR/sites-enabled/radsec"
fi

if [[ ! -f $CERT_DIR/ca/ca.crt ]]; then
  freeradius-certctl init-ca
fi
if [[ ! -f $CERT_DIR/server.crt ]]; then
  freeradius-certctl issue-server "$SERVER_NAME"
fi
chown root:freerad "$CERT_DIR" "$CERT_DIR/ca" "$CERT_DIR/server.key" "$CERT_DIR/server.crt"
chmod 0750 "$CERT_DIR" "$CERT_DIR/ca"
chmod 0640 "$CERT_DIR/server.key" "$CERT_DIR/server.crt"

freeradius -XC
systemctl enable --now freeradius
systemctl restart freeradius

echo "Installed successfully. Original files (if present): $backup"
echo "Create an Arista endpoint bundle: sudo freeradius-certctl issue arista-eos-01"
[[ $RADSEC == true ]] && echo 'RadSec is enabled on TCP/2083; issue and install a client certificate for each RadSec switch.'
