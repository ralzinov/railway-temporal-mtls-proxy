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

## Generate Certificates

The repository includes `generate.sh`.

Use it to generate certificates:
```bash
sh ./generate.sh mydeployment.proxy.rlwy.net
```

After generation, verify the server certificate SAN:

```bash
openssl x509 -in certs/server.crt -noout -text | grep -A1 "Subject Alternative Name"
```

Expected result:

```text
DNS:mydeployment.proxy.rlwy.net
```

## Generated Files

After running `generate.sh`, in ./certs you will have:

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

### 2. Add Variables

```env
PORT=7233
TEMPORAL_UPSTREAM=temporal-frontend.railway.internal:7233
TEMPORAL_TLS_CA_CERT=<contents of ca.crt>
TEMPORAL_TLS_SERVER_CERT=<contents of server.crt>
TEMPORAL_TLS_SERVER_KEY=<contents of server.key>
```
 
### 3. Create Railway TCP Proxy

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

## External Client Configuration

For an external client, Cursor Cloud Agent, Temporal CLI, or Temporal SDK, use:

```env
TEMPORAL_ADDRESS=mydeployment.proxy.rlwy.net:21226
TEMPORAL_TLS_SERVER_NAME=mydeployment.proxy.rlwy.net
TEMPORAL_TLS_CA_CERT=<contents of ca.crt>
TEMPORAL_TLS_CERT=<contents of client.crt>
TEMPORAL_TLS_KEY=<contents of client.key>
```

## Testing with grpcurl

### Test 1: With CA but Without Client Certificate

This should fail because the proxy requires a valid client certificate:

```bash
grpcurl \
  -cacert temporal-certs/ca.crt \
  -authority mydeployment.proxy.rlwy.net \
  mydeployment.proxy.rlwy.net:21226 \
  list
```

A timeout or TLS handshake failure is expected.

### Test 2: With CA and Client Certificate

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
export TEMPORAL_ADDRESS="switchback.proxy.rlwy.net:21226"
export TEMPORAL_TLS="true"
export TEMPORAL_TLS_SERVER_NAME="switchback.proxy.rlwy.net"
export TEMPORAL_TLS_SERVER_CA_CERT_PATH="$PWD/ca.crt"
export TEMPORAL_TLS_CLIENT_CERT_PATH="$PWD/client.crt"
export TEMPORAL_TLS_CLIENT_KEY_PATH="$PWD/client.key"

temporal operator namespace list
```
