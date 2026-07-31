#!/bin/bash
# Generates a local CA and a TLS server certificate for openrouter.ai.
# The envoy proxy terminates TLS with the server cert; the omp-sandbox image
# bakes the CA cert into its trust store so the sandbox can talk to
# https://openrouter.ai while the connection really goes to the proxy.
#
# Idempotent: existing certs are reused. Delete certs/ to regenerate.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p certs

if [[ -f certs/ca.pem && -f certs/server.pem && -f certs/server.key ]]; then
    echo "certs/ already populated, nothing to do"
    exit 0
fi

extfile=$(mktemp)
trap 'rm -f "$extfile"' EXIT

# Local certificate authority.
if [[ ! -f certs/ca.pem ]]; then
    openssl req -new -newkey rsa:4096 -nodes \
        -keyout certs/ca.key -out certs/ca.csr \
        -subj "/CN=omp-sandbox local CA"
    printf 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' \
        > "$extfile"
    openssl x509 -req -in certs/ca.csr -signkey certs/ca.key \
        -days 3650 -sha256 -extfile "$extfile" \
        -out certs/ca.pem
    rm -f certs/ca.csr
fi

# Server certificate for openrouter.ai, signed by the CA.
openssl req -new -newkey rsa:2048 -nodes \
    -keyout certs/server.key -out certs/server.csr \
    -subj "/CN=openrouter.ai"
printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:openrouter.ai\n' \
    > "$extfile"
openssl x509 -req -in certs/server.csr -CA certs/ca.pem -CAkey certs/ca.key \
    -CAcreateserial -days 825 -sha256 -extfile "$extfile" \
    -out certs/server.pem
rm -f certs/server.csr

chmod 0600 certs/ca.key certs/server.key
chmod 0644 certs/ca.pem certs/server.pem

echo "Generated:"
echo "  certs/ca.pem      (public, baked into the sandbox image)"
echo "  certs/server.pem  (public, mounted into the proxy)"
echo "  certs/server.key  (secret, mounted into the proxy)"
echo "  certs/ca.key      (secret, stays on this host for re-signing)"
