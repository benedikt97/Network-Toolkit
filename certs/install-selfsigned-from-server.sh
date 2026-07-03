#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run this script as root or using sudo."
  exit 1
fi

# Check for required arguments
if [ -z "$1" ]; then
  echo "Usage: $0 <hostname_or_ip> [port]"
  echo "Example: $0 myserver.local 443"
  exit 1
fi

SERVER=$1
PORT=${2:-443} # Default to 443 if no port is provided
CERT_DIR="/etc/pki/ca-trust/source/anchors"
CERT_FILE="${CERT_DIR}/${SERVER}.crt"

echo "Fetching certificate from ${SERVER}:${PORT}..."

# Fetch the certificate using openssl
if echo -n | openssl s_client -connect "${SERVER}:${PORT}" -showcerts 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$CERT_FILE"; then
  
  # Check if the file is empty (meaning no cert was found)
  if [ ! -s "$CERT_FILE" ]; then
    echo "Error: Failed to fetch the certificate. Please check the hostname and port."
    rm -f "$CERT_FILE"
    exit 1
  fi

  echo "Certificate successfully saved to $CERT_FILE"
else
  echo "Error: Failed to connect to ${SERVER}:${PORT}."
  exit 1
fi

echo "Updating system CA trust store..."
update-ca-trust extract

echo "Done! The certificate for ${SERVER} is now trusted on this AlmaLinux system."