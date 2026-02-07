#!/usr/bin/env bash
set -euo pipefail

CERT_DIR="${1:-./certs}"
HOSTNAME="github.proxy"

mkdir -p "$CERT_DIR"

# Generate a positive serial number (high bit cleared) to satisfy Go's x509 library
positive_serial() {
  local serial
  serial="$(openssl rand -hex 8)"
  echo "0$(printf '%x' $(( 0x${serial:0:1} & 0x7 )))${serial:1}"
}

echo "Generating CA key and certificate..."
openssl genrsa -out "$CERT_DIR/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "$CERT_DIR/ca.key" \
  -sha256 -days 825 \
  -set_serial "0x$(positive_serial)" \
  -subj "/CN=clever-computer-ca" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "subjectKeyIdentifier=hash" \
  -out "$CERT_DIR/ca.crt"

echo "Generating server key and CSR..."
openssl genrsa -out "$CERT_DIR/server.key" 4096
openssl req -new \
  -key "$CERT_DIR/server.key" \
  -subj "/CN=$HOSTNAME" \
  -out "$CERT_DIR/server.csr"

echo "Signing server certificate with CA..."
openssl x509 -req \
  -in "$CERT_DIR/server.csr" \
  -CA "$CERT_DIR/ca.crt" \
  -CAkey "$CERT_DIR/ca.key" \
  -set_serial "0x$(positive_serial)" \
  -days 398 \
  -sha256 \
  -extfile <(cat <<EXTEOF
subjectAltName=DNS:$HOSTNAME
basicConstraints=CA:FALSE
authorityKeyIdentifier=keyid,issuer
subjectKeyIdentifier=hash
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EXTEOF
  ) \
  -out "$CERT_DIR/server.crt"

rm -f "$CERT_DIR/server.csr"

echo "Certificates generated in $CERT_DIR/"
echo "  CA:     $CERT_DIR/ca.crt"
echo "  Server: $CERT_DIR/server.crt, $CERT_DIR/server.key"
