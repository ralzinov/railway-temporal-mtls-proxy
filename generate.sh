#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1}"
OUT_DIR="${2:-certs}"

CA_DAYS="${CA_DAYS:-3650}"
CERT_DAYS="${CERT_DAYS:-825}"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "Generating Temporal mTLS certificates for: $DOMAIN"
echo "Output dir: $(pwd)"
echo

# 1. CA
openssl genrsa -out ca.key 4096

openssl req -x509 -new -nodes \
  -key ca.key \
  -sha256 \
  -days "$CA_DAYS" \
  -out ca.crt \
  -subj "/CN=temporal-private-ca"

# 2. Server certificate config with SAN
cat > server.cnf <<EOF
[req]
default_bits = 4096
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[dn]
CN = ${DOMAIN}

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
EOF

# 3. Server cert/key
openssl genrsa -out server.key 4096

openssl req -new \
  -key server.key \
  -out server.csr \
  -config server.cnf

openssl x509 -req \
  -in server.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out server.crt \
  -days "$CERT_DAYS" \
  -sha256 \
  -extensions req_ext \
  -extfile server.cnf

# 4. Client cert/key
openssl genrsa -out client.key 4096

openssl req -new \
  -key client.key \
  -out client.csr \
  -subj "/CN=cursor-cloud-agent"

openssl x509 -req \
  -in client.csr \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -out client.crt \
  -days "$CERT_DAYS" \
  -sha256

# 5. Cleanup CSR files
rm -f server.csr client.csr

# 6. Verify server SAN
echo
echo "Server certificate SAN:"
openssl x509 -in server.crt -noout -text | grep -A1 "Subject Alternative Name" || true

echo
echo "Generated files:"
ls -la

echo
echo "Railway Temporal Frontend variables:"
echo "-----------------------------------"
echo "TEMPORAL_TLS_CA_CERT:"
cat ca.crt
echo
echo "TEMPORAL_TLS_SERVER_CERT:"
cat server.crt
echo
echo "TEMPORAL_TLS_SERVER_KEY:"
cat server.key

echo
echo "Cursor Cloud Agent secrets:"
echo "---------------------------"
echo "TEMPORAL_ADDRESS=${DOMAIN}:28514"
echo
echo "TEMPORAL_TLS_CA_CERT:"
cat ca.crt
echo
echo "TEMPORAL_TLS_CERT:"
cat client.crt
echo
echo "TEMPORAL_TLS_KEY:"
cat client.key

echo
echo "Test later with:"
echo "grpcurl \\"
echo "  -cacert ca.crt \\"
echo "  -cert client.crt \\"
echo "  -key client.key \\"
echo "  -authority ${DOMAIN} \\"
echo "  ${DOMAIN}:28514 \\"
echo "  list"