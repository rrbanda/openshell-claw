# OpenShell 0.1.3 + Dashboard + OpenClaw — Disconnected Deployment

Deploy OpenShell, the admin dashboard, and OpenClaw (AI coding assistant) on an air-gapped OpenShift cluster. Clone this repo and you have everything: Helm charts, manifests, scripts, and verification steps.

## What You Get

| Component | Version | Description |
|---|---|---|
| OpenShell Gateway | 0.1.3 | Sandbox orchestration with managed workspace mode + mTLS + OIDC |
| OpenShell Dashboard | 0.1.1 | Web admin UI with Keycloak login (oauth2-proxy) |
| OpenClaw | 2026.9.5 | Terminal-based AI coding assistant running inside a sandbox |
| Agent Sandbox | v0.5.0 | Kubernetes CRD controller for sandbox pods |
| Keycloak OIDC | — | Authentication with role-based access control |

## Prerequisites

- OpenShift 4.20+ with cluster-admin access
- `oc`, `helm`, and `openshell` 0.1.3 CLIs installed
- A container registry accessible from the disconnected cluster
- A Keycloak instance accessible from the cluster and user workstations
- An OpenAI-compatible model endpoint accessible from the cluster

## Image Inventory

These 9 images must be mirrored to your internal registry. The full list is in `images.txt`.

| Image | Purpose |
|---|---|
| `ghcr.io/nvidia/openshell/gateway:0.1.3` | Gateway + certgen hook |
| `ghcr.io/nvidia/openshell/supervisor:0.1.3` | Sandbox supervisor (injected by gateway) |
| `ghcr.io/nvidia/openshell/sandbox:0.1.3` | Sandbox runtime |
| `nvcr.io/nvidia/base/ubuntu:24.04` | Default sandbox base image |
| `quay.io/opendatahub/odh-openshell-sandbox-openclaw@sha256:b977...` | OpenClaw application |
| `quay.io/gkrumbach07/openshell-dashboard:0.1.1` | Dashboard UI |
| `quay.io/oauth2-proxy/oauth2-proxy:v7.15.2` | oauth2-proxy for dashboard auth |
| `registry.redhat.io/agent-sandbox/agent-sandbox-rhel9-operator@sha256:5541...` | Agent Sandbox controller |
| `registry.redhat.io/agent-sandbox/agent-sandbox-router@sha256:d7d7...` | Agent Sandbox router |

## Deployment Steps

Follow these in order. **Do not skip verification steps.**

### Phase 0: Mirror Images (on a connected machine)

```bash
export MIRROR_REGISTRY=registry.example.com:5000
./scripts/01-mirror-images.sh
```

Then on the disconnected cluster, verify:
```bash
export MIRROR_REGISTRY=registry.example.com:5000
./scripts/02-verify-mirror.sh
```

### Phase 1: Install Agent Sandbox

```bash
oc apply -f 00-prerequisites/agent-sandbox-manifest.yaml
oc -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=300s
./00-prerequisites/verify-prerequisites.sh
```

### Phase 2: Deploy the Gateway

1. Edit `01-gateway/values.yaml` — replace every `PLACEHOLDER_*` with your values
2. Run the install:
```bash
cd 01-gateway
./install.sh
```

The install script creates the namespace, SCC binding, and runs `helm install` from the local chart. It calls `verify.sh` automatically.

### Phase 3: Configure Keycloak

1. Set environment variables and run the client creation script:
```bash
export KC_HOST=https://sso.example.com
export KC_REALM=openshift
export KC_ADMIN_USER=admin
read -rsp "Keycloak admin password: " KC_ADMIN_PASS; echo; export KC_ADMIN_PASS
export GATEWAY_NAME=013
export DASH_HOST=openshell-dashboard.apps.example.com

cd 02-keycloak
./create-clients.sh
```

2. **Save the dashboard client secret** printed at the end (you'll need it in Phase 4).

3. Create users in Keycloak, assign them to `users-a` or `administrators-a` groups, and set their firstName/lastName/email.

4. Verify tokens:
```bash
export CLI_CLIENT=openshell-cli-013
export API_CLIENT=openshell-api-013
export USERNAME=user1
export PASSWORD=user1pass
./verify-token.sh
```

Expected output must show `sub`, `aud`, and `resource_access` all passing.

### Phase 4: Deploy the Dashboard

1. Create the OIDC secret (reads the client secret interactively):
```bash
cd 03-dashboard
./create-oidc-secret.sh
```

2. Edit `03-dashboard/values.yaml` — replace every `PLACEHOLDER_*`

3. Install:
```bash
./install.sh
```

4. Open the dashboard URL and log in with a Keycloak user.

### Phase 5: Deploy OpenClaw

1. Start the port-forward and register the gateway:
```bash
oc -n openshell-0-1-3 port-forward svc/openshell-0-1-3 18083:8080 &

# For mTLS access:
openshell gateway add https://127.0.0.1:18083 --local --name my-gateway

# Extract mTLS certs (see "mTLS Setup" below)
```

2. Edit `04-openclaw/model-provider-profile.yaml` — replace `PLACEHOLDER_MODEL_HOST`

3. Create workspace and provider:
```bash
export OPENSHELL_GATEWAY=my-gateway
export WORKSPACE_NAME=openclaw-test
cd 04-openclaw
./create-workspace.sh
```

4. Create the sandbox:
```bash
export MODEL_BASE_URL=https://api.example.com/v1
export MODEL_ID=your-model-id
export OPENCLAW_IMAGE=MIRROR_REGISTRY/opendatahub/odh-openshell-sandbox-openclaw@sha256:b977...
./create-sandbox.sh
```

5. Verify:
```bash
./verify-model.sh
```

6. Launch the interactive TUI:
```bash
./launch-tui.sh
```

## mTLS Setup

After the gateway is running, extract client certificates for CLI access:

```bash
NAMESPACE=openshell-0-1-3
GATEWAY_NAME=my-gateway
TLS_DIR="$HOME/.config/openshell/gateways/$GATEWAY_NAME/mtls"

mkdir -p "$TLS_DIR"
chmod 700 "$TLS_DIR"

WORK_DIR=$(mktemp -d)
oc -n "$NAMESPACE" get secret openshell-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "$WORK_DIR/ca.crt"
oc -n "$NAMESPACE" get secret openshell-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > "$WORK_DIR/tls.crt"
oc -n "$NAMESPACE" get secret openshell-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d > "$WORK_DIR/tls.key"

openssl verify -CAfile "$WORK_DIR/ca.crt" "$WORK_DIR/tls.crt"

install -m 600 "$WORK_DIR/ca.crt" "$TLS_DIR/ca.crt"
install -m 600 "$WORK_DIR/tls.crt" "$TLS_DIR/tls.crt"
install -m 600 "$WORK_DIR/tls.key" "$TLS_DIR/tls.key"
rm -rf "$WORK_DIR"
```

Note: on macOS, use `base64 -D` instead of `base64 -d`.

## Reconnecting Later

```bash
# Terminal 1: port-forward
oc -n openshell-0-1-3 port-forward svc/openshell-0-1-3 18083:8080

# Terminal 2
export OPENSHELL_GATEWAY=my-gateway
export WORKSPACE_NAME=openclaw-test
./05-reconnect/reconnect.sh
```

## Critical Gotchas

| Gotcha | Fix |
|---|---|
| CLI version must be exactly 0.1.3 | `openshell --version` before proceeding |
| macOS uses `base64 -D`, Linux uses `base64 -d` | Check your OS |
| mTLS directory must exist before cert extraction | `mkdir -p` first |
| Keycloak tokens missing `sub` claim | Assign the `basic` client scope to all clients |
| Dashboard flashing / 401 errors | Check that gateway `adminRole`/`userRole` match Keycloak roles exactly |
| `fullScopeAllowed` hides roles from tokens | Keep it `false` and add explicit scope mappings instead |
| Dashboard shows "role required" error | Ensure Keycloak user is in the correct group with the matching client role |
| Port-forward dies between commands | Run it in a separate terminal with `&` or `nohup` |

## Repo Structure

```
charts/                     Extracted Helm charts (install directly, no internet)
  openshell-gateway/        OpenShell Gateway v0.1.3
  openshell-dashboard/      Dashboard v0.1.1
scripts/                    Image mirroring and verification
00-prerequisites/           Agent Sandbox manifest + preflight checks
01-gateway/                 Gateway namespace, RBAC, Helm values, install/verify
02-keycloak/                Keycloak client creation, token verification
03-dashboard/               Dashboard OIDC secret, Helm values, install/verify
04-openclaw/                Provider profile, workspace/sandbox creation, model test
05-reconnect/               Reconnection script for later sessions
```

## Versions Tested

| Component | Version |
|---|---|
| OpenShift | 4.20.33 |
| OpenShell Gateway | 0.1.3 |
| OpenShell CLI | 0.1.3 |
| OpenShell Dashboard | 0.1.1 |
| Agent Sandbox | v0.5.0 (Red Hat operator) |
| OpenClaw | 2026.9.5 |
| Keycloak | 26.x |
| oauth2-proxy | v7.15.2 |

## License

Apache License 2.0
