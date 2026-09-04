#!/usr/bin/env bash
# Manage the private CA and EAP-TLS endpoint certificates installed by install.sh.
set -euo pipefail

CERT_DIR=${CERT_DIR:-/etc/freeradius/3.0/certs/$(hostname -s)}
CA_DIR=$CERT_DIR/ca
CA_CONF=$CERT_DIR/openssl-ca.cnf
ENDPOINT_DIR=$CERT_DIR/endpoints
CN_VLAN_FILE=$CERT_DIR/cn-vlan

die() { echo "Error: $*" >&2; exit 1; }
valid_name() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]] || die 'Name must be a hostname-like value.'; }
valid_vlan() { [[ $1 =~ ^[0-9]+$ && $1 -ge 1 && $1 -le 4094 ]] || die 'VLAN must be an integer from 1 through 4094.'; }
need_root() { [[ $EUID -eq 0 ]] || die 'Run with sudo.'; }
need_ca() { [[ -f $CA_DIR/ca.crt && -f $CA_DIR/private/ca.key && -f $CA_CONF ]] || die 'CA is not initialized; run init-ca first.'; }
rehash_ca() { openssl rehash "$CA_DIR" >/dev/null; }

set_vlan() {
  local name=$1 vlan=$2
  [[ -f $CN_VLAN_FILE ]] || die 'CN-to-VLAN authorization file is missing; re-run install.sh.'
  ! awk -v name="$name" '$1 == name { found = 1 } END { exit found ? 0 : 1 }' "$CN_VLAN_FILE" || die "A VLAN assignment already exists for $name"
  {
    printf '%s\n' "$name"
    printf '\tTunnel-Type := VLAN,\n'
    printf '\tTunnel-Medium-Type := IEEE-802,\n'
    printf '\tTunnel-Private-Group-ID := "%s"\n\n' "$vlan"
  } >> "$CN_VLAN_FILE"
}

remove_vlan() {
  local name=$1 temp
  [[ -f $CN_VLAN_FILE ]] || return 0
  temp=$(mktemp "$CERT_DIR/.cn-vlan.XXXXXX")
  awk -v name="$name" '
    $0 == name { skipping = 1; next }
    skipping && /^$/ { skipping = 0; next }
    !skipping { print }
  ' "$CN_VLAN_FILE" > "$temp"
  chown root:freerad "$temp"
  chmod 0640 "$temp"
  mv "$temp" "$CN_VLAN_FILE"
}

init_ca() {
  [[ ! -e $CA_DIR/ca.crt ]] || die "CA already exists at $CA_DIR/ca.crt"
  install -d -m 0700 "$CA_DIR/private" "$CA_DIR/newcerts" "$ENDPOINT_DIR"
  : > "$CA_DIR/index.txt"
  printf '1000\n' > "$CA_DIR/serial"
  printf '1000\n' > "$CA_DIR/crlnumber"
  openssl genrsa -out "$CA_DIR/private/ca.key" 4096
  chmod 0600 "$CA_DIR/private/ca.key"
  openssl req -x509 -new -sha256 -days 3650 -key "$CA_DIR/private/ca.key" \
    -out "$CA_DIR/ca.crt" -subj '/CN=Network Toolkit EAP-TLS CA' \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'
  openssl ca -batch -config "$CA_CONF" -gencrl -out "$CA_DIR/ca.crl"
  chmod 0644 "$CA_DIR/ca.crt" "$CA_DIR/ca.crl"
  rehash_ca
  echo "Created CA certificate: $CA_DIR/ca.crt"
}

issue() {
  local kind=$1 name=$2 vlan=${3:-} key crt csr p12 ext
  valid_name "$name"; need_ca
  if [[ $kind == server ]]; then
    key=$CERT_DIR/server.key; crt=$CERT_DIR/server.crt; csr=$CERT_DIR/server.csr; ext=server_cert
  else
    key=$ENDPOINT_DIR/$name.key; crt=$ENDPOINT_DIR/$name.crt; csr=$ENDPOINT_DIR/$name.csr; ext=client_cert
  fi
  [[ ! -e $crt ]] || die "Certificate already exists: $crt"
  openssl req -new -newkey rsa:3072 -nodes -sha256 -keyout "$key" -out "$csr" \
    -subj "/CN=$name" -addext "subjectAltName=DNS:$name"
  chmod 0600 "$key"
  openssl ca -batch -config "$CA_CONF" -extensions "$ext" -in "$csr" -out "$crt"
  rm -f "$csr"
  openssl ca -batch -config "$CA_CONF" -gencrl -out "$CA_DIR/ca.crl"
  rehash_ca
  if [[ $kind == client ]]; then
    p12=$ENDPOINT_DIR/$name.p12
    openssl pkcs12 -export -out "$p12" -inkey "$key" -in "$crt" -certfile "$CA_DIR/ca.crt" -name "$name"
    chmod 0600 "$p12"
    if [[ -n $vlan ]]; then
      set_vlan "$name" "$vlan"
      systemctl reload freeradius
    fi
    echo "Created $crt, $key and password-protected bundle $p12"
  else
    chown root:freerad "$key" "$crt"
    chmod 0640 "$key" "$crt"
    echo "Created RADIUS server certificate: $crt"
  fi
}

revoke() {
  local name=${1:?usage: revoke NAME}
  need_ca
  [[ -f $ENDPOINT_DIR/$name.crt ]] || die "No endpoint certificate named $name"
  openssl ca -batch -config "$CA_CONF" -revoke "$ENDPOINT_DIR/$name.crt"
  remove_vlan "$name"
  openssl ca -batch -config "$CA_CONF" -gencrl -out "$CA_DIR/ca.crl"
  rehash_ca
  systemctl reload freeradius
  echo "Revoked $name and reloaded FreeRADIUS."
}

case ${1:-} in
  init-ca) need_root; init_ca ;;
  issue) need_root
         case $# in
           2) issue client "$2" ;;
           4) [[ $3 == --vlan ]] || die 'usage: issue ENDPOINT_NAME [--vlan VLAN]'
              valid_vlan "$4"
              issue client "$2" "$4"
              ;;
           *) die 'usage: issue ENDPOINT_NAME [--vlan VLAN]' ;;
         esac
         ;;
  issue-server) need_root; [[ $# -eq 2 ]] || die 'usage: issue-server DNS_NAME'; issue server "$2" ;;
  revoke) need_root; [[ $# -eq 2 ]] || die 'usage: revoke ENDPOINT_NAME'; revoke "$2" ;;
  list) need_ca; cat "$CA_DIR/index.txt" ;;
  *) cat <<'EOF'
Usage: freeradius-certctl {init-ca|issue ENDPOINT [--vlan VLAN]|issue-server DNS_NAME|revoke ENDPOINT|list}
EOF
     exit 2 ;;
esac
