# Temporal mTLS Proxy for Railway

This repository contains a small mTLS reverse proxy for exposing a self-hosted Temporal Frontend service from Railway through a public Railway TCP Proxy.

It is intended for setups where:

* Temporal is deployed inside Railway.
* Temporal Frontend is available internally as plaintext gRPC.
* An external machine or cloud agent needs to connect to Temporal.
* The external gRPC endpoint must be protected with mTLS client certificates.

## Architecture

```text
External client / Cursor Cloud Agent
  -> Railway TCP Proxy
  -> temporal-mtls-proxy:7233
  -> temporal-frontend.railway.internal:7233
```

The proxy terminates TLS, verifies the client certificate, and then forwards gRPC traffic to the internal Temporal Frontend service.

Temporal itself can remain unchanged and continue accepting plaintext gRPC inside the Railway private network.

## Repository Structure

```text
.
├── Dockerfile
├── Caddyfile
├── entrypoint.sh
├── generate.sh
├── railway.toml
├── .dockerignore
├── .gitignore
└── README.md
```

## How It Works

The proxy uses Caddy as a gRPC-capable reverse proxy.

It listens on:

```text
0.0.0.0:7233
```

with TLS enabled and requires clients to present a certificate signed by your private CA.

Internally, it forwards traffic to:

```text
temporal-frontend.railway.internal:7233
```

using plaintext h2c gRPC.

## Required Railway Variables

Set these variables on the `temporal-mtls-proxy` service in Railway:

```env
PORT=7233
TEMPORAL_UPSTREAM=temporal-frontend.railway.internal:7233

TEMPORAL_TLS_CA_CERT=...
TEMPORAL_TLS_SERVER_CERT=...
TEMPORAL_TLS_SERVER_KEY=...
```

The certificate variables must contain the full PEM contents, including the BEGIN/END lines.

Example:

```text
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
```

Do not commit certificates, private keys, or `.env` files to Git.

## Generate Certificates

The repository includes `generate.sh`.

Use it to generate:

```text
ca.crt
ca.key
server.crt
server.key
client.crt
client.key
```

The server certificate must be generated for the Railway TCP Proxy hostname, without the port.

For example, if Railway gives you this TCP endpoint:

```text
mydeployment.proxy.rlwy.net:21226
```

run:

```bash
./generate.sh mydeployment.proxy.rlwy.net
```

Do not include the port in the certificate hostname.

Correct:

```bash
./generate.sh mydeployment.proxy.rlwy.net
```

Wrong:

```bash
./generate.sh mydeployment.proxy.rlwy.net:21226
```

After generation, verify the server certificate SAN:

```bash
openssl x509 -in temporal-certs/server.crt -noout -text | grep -A1 "Subject Alternative Name"
```

Expected result:

```text
DNS:mydeployment.proxy.rlwy.net
```

## Generated Files

After running `generate.sh`, you should have:

```text
temporal-certs/
  ca.crt
  ca.key
  ca.srl
  server.crt
  server.key
  client.crt
  client.key
```

Use them as follows:

| File         | Where it goes                                                  |
| ------------ | -------------------------------------------------------------- |
| `ca.crt`     | Railway proxy service and external client                      |
| `server.crt` | Railway proxy service only                                     |
| `server.key` | Railway proxy service only                                     |
| `client.crt` | External client only                                           |
| `client.key` | External client only                                           |
| `ca.key`     | Keep locally only; never upload to Railway, Cursor, CI, or Git |

## Railway Setup

### 1. Create the Proxy Service

In Railway:

```text
New Service
-> GitHub Repo
-> Select this repository
```

Railway should detect the `Dockerfile` and build the service.

The service should be named something like:

```text
temporal-mtls-proxy
```

### 2. Add Variables

Go to:

```text
temporal-mtls-proxy
-> Variables
```

Add:

```env
PORT=7233
TEMPORAL_UPSTREAM=temporal-frontend.railway.internal:7233
```

Then add the certificate variables.

Set `TEMPORAL_TLS_CA_CERT` to the contents of:

```text
temporal-certs/ca.crt
```

Set `TEMPORAL_TLS_SERVER_CERT` to the contents of:

```text
temporal-certs/server.crt
```

Set `TEMPORAL_TLS_SERVER_KEY` to the contents of:

```text
temporal-certs/server.key
```

### 3. Deploy the Proxy

Deploy the service.

The service should become online and listen on internal port:

```text
7233
```

### 4. Create Railway TCP Proxy

Go to:

```text
temporal-mtls-proxy
-> Settings
-> Networking
-> TCP Proxy
-> Add TCP Proxy
```

Set the internal port to:

```text
7233
```

Railway will generate an external TCP endpoint like:

```text
mydeployment.proxy.rlwy.net:21226
```

This becomes your external Temporal address:

```env
TEMPORAL_ADDRESS=mydeployment.proxy.rlwy.net:21226
```

### 5. Remove Direct Public Access to Temporal Frontend

Make sure the original Temporal Frontend service is not directly exposed.

Remove or disable:

```text
Temporal Frontend -> TCP Proxy -> 7233
```

Also remove any public HTTP domain pointing to Temporal Frontend port `7233`.

The only public external path to Temporal gRPC should be:

```text
Railway TCP Proxy
-> temporal-mtls-proxy
-> internal Temporal Frontend
```

## External Client Configuration

For an external client, Cursor Cloud Agent, Temporal CLI, or Temporal SDK, use:

```env
TEMPORAL_ADDRESS=mydeployment.proxy.rlwy.net:21226
TEMPORAL_TLS_SERVER_NAME=mydeployment.proxy.rlwy.net
TEMPORAL_TLS_CA_CERT=<contents of ca.crt>
TEMPORAL_TLS_CERT=<contents of client.crt>
TEMPORAL_TLS_KEY=<contents of client.key>
```

If your client expects file paths instead of PEM values, write these environment variables into files at startup.

## Testing with grpcurl

### Test 1: Without CA

This should fail because the server certificate is signed by your private CA:

```bash
grpcurl mydeployment.proxy.rlwy.net:21226 list
```

Expected error:

```text
certificate signed by unknown authority
```

### Test 2: With CA but Without Client Certificate

This should fail because the proxy requires a valid client certificate:

```bash
grpcurl \
  -cacert temporal-certs/ca.crt \
  -authority mydeployment.proxy.rlwy.net \
  mydeployment.proxy.rlwy.net:21226 \
  list
```

A timeout or TLS handshake failure is expected.

### Test 3: With CA and Client Certificate

This should succeed:

```bash
grpcurl \
  -cacert temporal-certs/ca.crt \
  -cert temporal-certs/client.crt \
  -key temporal-certs/client.key \
  -authority mydeployment.proxy.rlwy.net \
  mydeployment.proxy.rlwy.net:21226 \
  list
```

Expected output should include Temporal services:

```text
grpc.health.v1.Health
grpc.reflection.v1.ServerReflection
grpc.reflection.v1alpha.ServerReflection
temporal.api.operatorservice.v1.OperatorService
temporal.api.workflowservice.v1.WorkflowService
temporal.server.api.adminservice.v1.AdminService
```

## Testing with Temporal CLI

Example:

```bash
temporal \
  --address mydeployment.proxy.rlwy.net:21226 \
  --tls \
  --tls-ca-path temporal-certs/ca.crt \
  --tls-cert-path temporal-certs/client.crt \
  --tls-key-path temporal-certs/client.key \
  namespace list
```

If your Temporal CLI supports server name override, set it to:

```text
mydeployment.proxy.rlwy.net
```

## Security Notes

Never commit these files:

```text
ca.key
server.key
client.key
*.crt
*.csr
*.srl
*.pem
.env
```

The most sensitive file is:

```text
ca.key
```

Keep it offline or in a secure secret manager. Anyone with `ca.key` can issue new client certificates that will be trusted by the proxy.

If a client certificate leaks, rotate it:

1. Generate a new client certificate.
2. Update the external client secrets.
3. Optionally rotate the CA if you want to invalidate all previously issued client certificates.

## Troubleshooting

### `certificate signed by unknown authority`

The client does not trust your private CA.

Use:

```bash
-cacert temporal-certs/ca.crt
```

### `certificate is valid for host:port, not host`

The server certificate was generated with the port included in the SAN.

Regenerate it using only the hostname:

```bash
./generate.sh mydeployment.proxy.rlwy.net
```

Not:

```bash
./generate.sh mydeployment.proxy.rlwy.net:21226
```

### `context deadline exceeded` without client cert

This is expected when the client trusts the CA but does not provide a client certificate.

### `connection refused` or timeout

Check:

1. The Railway TCP Proxy is attached to the `temporal-mtls-proxy` service, not directly to Temporal Frontend.
2. The TCP Proxy internal port is `7233`.
3. The proxy service is online.
4. `PORT=7233` is set.
5. `TEMPORAL_UPSTREAM=temporal-frontend.railway.internal:7233` points to the correct internal Temporal Frontend service name.

### Temporal UI still works but external gRPC does not

Temporal UI and Temporal gRPC are different services.

Temporal UI is normal HTTP, usually on port `8080`.

Temporal Frontend is gRPC, usually on port `7233`.

This proxy only handles Temporal gRPC.
