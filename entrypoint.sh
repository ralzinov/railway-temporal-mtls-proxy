#!/usr/bin/env sh
set -eu

mkdir -p /etc/caddy/certs

if [ -z "${TEMPORAL_TLS_CA_CERT:-}" ]; then
  echo "TEMPORAL_TLS_CA_CERT is required"
  exit 1
fi

if [ -z "${TEMPORAL_TLS_SERVER_CERT:-}" ]; then
  echo "TEMPORAL_TLS_SERVER_CERT is required"
  exit 1
fi

if [ -z "${TEMPORAL_TLS_SERVER_KEY:-}" ]; then
  echo "TEMPORAL_TLS_SERVER_KEY is required"
  exit 1
fi

printf '%s\n' "$TEMPORAL_TLS_CA_CERT" > /etc/caddy/certs/ca.crt
printf '%s\n' "$TEMPORAL_TLS_SERVER_CERT" > /etc/caddy/certs/server.crt
printf '%s\n' "$TEMPORAL_TLS_SERVER_KEY" > /etc/caddy/certs/server.key

chmod 600 /etc/caddy/certs/server.key
chmod 644 /etc/caddy/certs/ca.crt /etc/caddy/certs/server.crt

echo "Starting mTLS proxy on port ${PORT:-7233}"
echo "Upstream: ${TEMPORAL_UPSTREAM:-temporal-frontend.railway.internal:7233}"

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile