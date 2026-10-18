# OpenShell 0.1.3 + Dashboard + OpenClaw — Disconnected Deployment

Deploy OpenShell, the admin dashboard, and OpenClaw (AI coding assistant) on an air-gapped OpenShift cluster. Clone this repo and you have everything: Helm charts, manifests, scripts, and verification steps.

Every phase has **two paths**: run the script, or run the individual commands one by one. If a script fails, use the manual steps.

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

These 9 images must be mirrored to your internal registry. Full details with digests and `podman pull` commands are in `images.txt`.

| # | Image | Purpose |
|---|---|---|
| 1 | `ghcr.io/nvidia/openshell/gateway:0.1.3` | Gateway pod + certgen hook |
| 2 | `ghcr.io/nvidia/openshell/supervisor:0.1.3` | Supervisor injected into every sandbox pod |
| 3 | `ghcr.io/nvidia/openshell/sandbox:0.1.3` | Sandbox runtime (workload-side boundary) |
| 4 | `nvcr.io/nvidia/base/ubuntu:24.04` | Default standalone sandbox base image |
| 5 | `quay.io/opendatahub/odh-openshell-sandbox-openclaw@sha256:b977...` | OpenClaw application |
| 6 | `quay.io/gkrumbach07/openshell-dashboard:0.1.1` | Dashboard BFF + React UI |
| 7 | `quay.io/oauth2-proxy/oauth2-proxy:v7.15.2` | oauth2-proxy sidecar for dashboard |
| 8 | `registry.redhat.io/agent-sandbox/agent-sandbox-rhel9-operator@sha256:5541...` | Agent Sandbox controller |
| 9 | `registry.redhat.io/agent-sandbox/agent-sandbox-router@sha256:d7d7...` | Agent Sandbox router |

---

## Phase 0: Mirror Images

> Run on a **connected** machine. Then transfer images to disconnected registry.

**Script path:**
```bash
export MIRROR_REGISTRY=registry.example.com:5000
./scripts/01-mirror-images.sh
```

**Manual steps (if the script does not work):**

```bash
# Set your mirror registry
export MIRROR=registry.example.com:5000

# Pull each image
podman pull ghcr.io/nvidia/openshell/gateway:0.1.3
podman pull ghcr.io/nvidia/openshell/supervisor:0.1.3
podman pull ghcr.io/nvidia/openshell/sandbox:0.1.3
podman pull nvcr.io/nvidia/base/ubuntu:24.04
podman pull quay.io/opendatahub/odh-openshell-sandbox-openclaw@sha256:b977255e7ee9a8e3cea95bc8ba3ad08a93c5e9ad335984e2db1282b80eb82441
podman pull quay.io/gkrumbach07/openshell-dashboard:0.1.1
podman pull quay.io/oauth2-proxy/oauth2-proxy:v7.15.2
podman pull registry.redhat.io/agent-sandbox/agent-sandbox-rhel9-operator@sha256:554102df4c721bd27be7129c910c206ed1329be14df68906a588959b0e7d9309
podman pull registry.redhat.io/agent-sandbox/agent-sandbox-router@sha256:d7d745b9ad8143282a1356d13a9b351faf6aa1955ee6b02f100fc282dbbd91d3

# Tag and push each to your mirror
podman tag ghcr.io/nvidia/openshell/gateway:0.1.3 $MIRROR/nvidia/openshell/gateway:0.1.3
podman push $MIRROR/nvidia/openshell/gateway:0.1.3

podman tag ghcr.io/nvidia/openshell/supervisor:0.1.3 $MIRROR/nvidia/openshell/supervisor:0.1.3
podman push $MIRROR/nvidia/openshell/supervisor:0.1.3

podman tag ghcr.io/nvidia/openshell/sandbox:0.1.3 $MIRROR/nvidia/openshell/sandbox:0.1.3
podman push $MIRROR/nvidia/openshell/sandbox:0.1.3

podman tag nvcr.io/nvidia/base/ubuntu:24.04 $MIRROR/nvidia/base/ubuntu:24.04
podman push $MIRROR/nvidia/base/ubuntu:24.04

podman tag quay.io/opendatahub/odh-openshell-sandbox-openclaw@sha256:b977255e7ee9a8e3cea95bc8ba3ad08a93c5e9ad335984e2db1282b80eb82441 $MIRROR/opendatahub/odh-openshell-sandbox-openclaw:latest
podman push $MIRROR/opendatahub/odh-openshell-sandbox-openclaw:latest

podman tag quay.io/gkrumbach07/openshell-dashboard:0.1.1 $MIRROR/gkrumbach07/openshell-dashboard:0.1.1
podman push $MIRROR/gkrumbach07/openshell-dashboard:0.1.1

podman tag quay.io/oauth2-proxy/oauth2-proxy:v7.15.2 $MIRROR/oauth2-proxy/oauth2-proxy:v7.15.2
podman push $MIRROR/oauth2-proxy/oauth2-proxy:v7.15.2

# Note: registry.redhat.io images require Red Hat login first: podman login registry.redhat.io
podman tag registry.redhat.io/agent-sandbox/agent-sandbox-rhel9-operator@sha256:554102df4c721bd27be7129c910c206ed1329be14df68906a588959b0e7d9309 $MIRROR/agent-sandbox/agent-sandbox-rhel9-operator:v0.5.0
podman push $MIRROR/agent-sandbox/agent-sandbox-rhel9-operator:v0.5.0

podman tag registry.redhat.io/agent-sandbox/agent-sandbox-router@sha256:d7d745b9ad8143282a1356d13a9b351faf6aa1955ee6b02f100fc282dbbd91d3 $MIRROR/agent-sandbox/agent-sandbox-router:v0.5.0
podman push $MIRROR/agent-sandbox/agent-sandbox-router:v0.5.0
```

**Verify (on disconnected cluster):**
```bash
# For each image, check it exists in the mirror
skopeo inspect docker://registry.example.com:5000/nvidia/openshell/gateway:0.1.3
# Repeat for all 9 images. Or run: ./scripts/02-verify-mirror.sh
```

---

## Phase 1: Install Agent Sandbox

**Script path:**
```bash
./00-prerequisites/verify-prerequisites.sh
```

**Manual steps:**

```bash
# Step 1: Check CLIs are installed
oc version
helm version --short
openshell --version    # Must report 0.1.3

# Step 2: Check cluster access
oc whoami
oc whoami --show-server

# Step 3: Apply the Agent Sandbox manifest (vendored in this repo)
oc apply -f 00-prerequisites/agent-sandbox-manifest.yaml

# Step 4: Wait for the controller to be ready
oc -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=300s

# Step 5: Verify the CRD exists
oc get crd sandboxes.agents.x-k8s.io
# Expected: sandboxes.agents.x-k8s.io

# Step 6: Verify the controller pod is running
oc -n agent-sandbox-system get pods
# Expected: agent-sandbox-controller pod in Running state
```

**Do not proceed until the CRD exists and the controller is Running.**

---

## Phase 2: Deploy the Gateway

**Script path:**
```bash
# Edit values first, then:
cd 01-gateway
./install.sh
```

**Manual steps:**

```bash
# Step 1: Create the namespace
oc apply -f 01-gateway/namespace.yaml

# Step 2: Verify namespace exists
oc get namespace openshell-0-1-3
# Expected: Active

# Step 3: Bind privileged SCC to the sandbox service account
oc apply -f 01-gateway/scc-rbac.yaml

# Step 4: Verify SCC binding
oc auth can-i use scc/privileged --as=system:serviceaccount:openshell-0-1-3:openshell-0-1-3-sandbox
# Expected: yes

# Step 5: Edit 01-gateway/values.yaml
# Replace ALL of these PLACEHOLDERs:
#   PLACEHOLDER_REGISTRY      -> your mirror registry (e.g. registry.example.com:5000)
#   PLACEHOLDER_KC_ISSUER     -> Keycloak issuer URL (e.g. https://sso.example.com/realms/openshell)
#   PLACEHOLDER_KC_AUDIENCE   -> Keycloak API client ID (e.g. openshell-api-013)
#   PLACEHOLDER_KC_ROLESCLAIM -> Roles claim path (e.g. resource_access.openshell-api-013.roles)
#   PLACEHOLDER_ADMIN_ROLE    -> Admin role name (e.g. administrators-a)
#   PLACEHOLDER_USER_ROLE     -> User role name (e.g. users-a)

# Step 6: Install the gateway from the local chart
helm upgrade --install openshell-0-1-3 ./charts/openshell-gateway/ \
  --namespace openshell-0-1-3 \
  --values 01-gateway/values.yaml \
  --wait --timeout 5m
# Expected: STATUS: deployed

# Step 7: Verify the gateway pod is running
oc -n openshell-0-1-3 get pods
# Expected: openshell-0-1-3-0 pod in Running state (1/1)

# Step 8: Verify TLS secrets were created
oc -n openshell-0-1-3 get secret openshell-server-tls openshell-client-tls
# Expected: both secrets exist

# Step 9: Verify the gateway config has managed workspace mode
oc -n openshell-0-1-3 get configmap openshell-0-1-3-config -o jsonpath='{.data.gateway\.toml}' | grep workspace_mode
# Expected: workspace_mode = "managed"

# Step 10: Verify OIDC is configured
oc -n openshell-0-1-3 get configmap openshell-0-1-3-config -o jsonpath='{.data.gateway\.toml}' | grep issuer
# Expected: your Keycloak issuer URL
```

**Do not proceed until the gateway pod is Running and both TLS secrets exist.**

---

## Phase 3: Configure Keycloak

**Script path:**
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

**Manual steps (if the script does not work):**

See `02-keycloak/README.md` for full details. The key operations are:

```bash
# Get a Keycloak admin token
TOKEN=$(curl -sk -X POST "$KC_HOST/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=$KC_ADMIN_USER&password=$KC_ADMIN_PASS" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
AUTH="Authorization: Bearer $TOKEN"

# Step 1: Create groups
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/groups" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name":"users-a"}'
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/groups" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name":"administrators-a"}'

# Step 2: Create API resource client (non-interactive, defines audience)
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"clientId":"openshell-api-013","enabled":true,"publicClient":false,"bearerOnly":true,"standardFlowEnabled":false,"directAccessGrantsEnabled":false}'

# Step 3: Create CLI public client (PKCE + device code)
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"clientId":"openshell-cli-013","enabled":true,"publicClient":true,"standardFlowEnabled":true,"directAccessGrantsEnabled":true,"attributes":{"oauth2.device.authorization.grant.enabled":"true","pkce.code.challenge.method":"S256"},"redirectUris":["http://127.0.0.1/*"],"fullScopeAllowed":false,"defaultClientScopes":["openid","profile","email","roles"]}'

# Step 4: Create Dashboard confidential client
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"clientId\":\"openshell-dashboard-013\",\"enabled\":true,\"publicClient\":false,\"standardFlowEnabled\":true,\"attributes\":{\"pkce.code.challenge.method\":\"S256\"},\"redirectUris\":[\"https://$DASH_HOST/oauth2/callback\"],\"webOrigins\":[\"https://$DASH_HOST\"],\"fullScopeAllowed\":false,\"defaultClientScopes\":[\"openid\",\"profile\",\"email\",\"roles\"]}"

# Step 5: Get API client UUID
API_UUID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients?clientId=openshell-api-013" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

# Step 6: Create client roles on the API client
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles" \
  -H "$AUTH" -H "Content-Type: application/json" -d '{"name":"users-a"}'
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles" \
  -H "$AUTH" -H "Content-Type: application/json" -d '{"name":"administrators-a"}'

# Step 7: Map groups to client roles
USERS_A_GROUP=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/groups?search=users-a&exact=true" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
ROLE_JSON=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles/users-a")
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/groups/$USERS_A_GROUP/role-mappings/clients/$API_UUID" \
  -H "$AUTH" -H "Content-Type: application/json" -d "[$ROLE_JSON]"

ADMINS_A_GROUP=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/groups?search=administrators-a&exact=true" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
ROLE_JSON=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles/administrators-a")
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/groups/$ADMINS_A_GROUP/role-mappings/clients/$API_UUID" \
  -H "$AUTH" -H "Content-Type: application/json" -d "[$ROLE_JSON]"

# Step 8: For EACH of openshell-cli-013 and openshell-dashboard-013:
#   a) Add audience mapper
#   b) Add scope mappings (API client roles)
#   c) Add 'basic' scope (CRITICAL -- contains the 'sub' mapper)
for CLIENT_NAME in openshell-cli-013 openshell-dashboard-013; do
  CLIENT_UUID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients?clientId=$CLIENT_NAME" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

  # Audience mapper
  curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$CLIENT_UUID/protocol-mappers/models" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d '{"name":"openshell-api-audience","protocol":"openid-connect","protocolMapper":"oidc-audience-mapper","config":{"included.client.audience":"openshell-api-013","id.token.claim":"false","access.token.claim":"true"}}'

  # Scope mappings
  ROLES=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles")
  curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$CLIENT_UUID/scope-mappings/clients/$API_UUID" \
    -H "$AUTH" -H "Content-Type: application/json" -d "$ROLES"

  # CRITICAL: Add 'basic' scope (where the 'sub' claim lives)
  BASIC_ID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/client-scopes" | python3 -c "import sys,json; [print(s['id']) for s in json.load(sys.stdin) if s['name']=='basic']")
  curl -sk -X PUT "$KC_HOST/admin/realms/$KC_REALM/clients/$CLIENT_UUID/default-client-scopes/$BASIC_ID" -H "$AUTH"
done

# Step 9: Create users (example)
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/users" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"username":"admin1","firstName":"Admin","lastName":"User","email":"admin1@example.com","enabled":true,"emailVerified":true,"credentials":[{"type":"password","value":"CHANGE_ME","temporary":false}]}'

# Step 10: Add user to group
ADMIN1_ID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/users?username=admin1&exact=true" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
curl -sk -X PUT "$KC_HOST/admin/realms/$KC_REALM/users/$ADMIN1_ID/groups/$ADMINS_A_GROUP" -H "$AUTH"
```

**Verify the token:**
```bash
# Get a token and decode it
curl -sk -X POST "$KC_HOST/realms/$KC_REALM/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=openshell-cli-013&username=admin1&password=CHANGE_ME" | \
  python3 -c "
import sys,json,base64
d=json.load(sys.stdin)
if 'error' in d: print(f'ERROR: {d[\"error\"]}: {d.get(\"error_description\",\"\")}'); exit(1)
t=d['access_token']; p=t.split('.')[1]+'=='
c=json.loads(base64.urlsafe_b64decode(p))
print(f'sub: {c.get(\"sub\",\"MISSING\")}')
print(f'aud: {c.get(\"aud\")}')
print(f'resource_access: {json.dumps(c.get(\"resource_access\",{}))}')
"
# Expected: sub has a UUID, aud contains openshell-api-013, resource_access has the role
```

**Do not proceed until `sub`, `aud`, and `resource_access` are all present in the token.**

---

## Phase 4: Deploy the Dashboard

**Script path:**
```bash
cd 03-dashboard
./create-oidc-secret.sh
# Edit values.yaml with your PLACEHOLDERs
./install.sh
```

**Manual steps:**

```bash
# Step 1: Get the dashboard client secret from Keycloak
# (This was printed by create-clients.sh in Phase 3, or get it from Keycloak console)
DASH_UUID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients?clientId=openshell-dashboard-013" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$DASH_UUID/client-secret" | python3 -c "import sys,json; print(json.load(sys.stdin)['value'])"
# Save this value -- you need it below

# Step 2: Create the OIDC secret in Kubernetes
COOKIE_SECRET=$(openssl rand -hex 16)
oc -n openshell-0-1-3 create secret generic openshell-dashboard-oidc \
  --from-literal=client-id=openshell-dashboard-013 \
  --from-literal=client-secret=YOUR_CLIENT_SECRET_HERE \
  --from-literal=cookie-secret=$COOKIE_SECRET

# Step 3: Verify the secret exists
oc -n openshell-0-1-3 get secret openshell-dashboard-oidc
# Expected: secret exists with 3 data keys

# Step 4: Edit 03-dashboard/values.yaml
# Replace ALL PLACEHOLDERs:
#   PLACEHOLDER_REGISTRY    -> your mirror registry
#   PLACEHOLDER_DASH_HOST   -> dashboard route hostname
#   PLACEHOLDER_KC_ISSUER   -> Keycloak issuer URL
#   PLACEHOLDER_KC_AUDIENCE -> openshell-api-013
#   PLACEHOLDER_DASH_CLIENT -> openshell-dashboard-013
#   PLACEHOLDER_API_CLIENT  -> openshell-api-013

# Step 5: Install the dashboard from the local chart
helm upgrade --install openshell-dashboard ./charts/openshell-dashboard/ \
  --namespace openshell-0-1-3 \
  --values 03-dashboard/values.yaml \
  --wait --timeout 5m
# Expected: STATUS: deployed

# Step 6: Verify the pod has 2/2 containers (dashboard + oauth2-proxy)
oc -n openshell-0-1-3 get pods -l app.kubernetes.io/name=openshell-dashboard
# Expected: 2/2 Running

# Step 7: Verify the route exists
oc -n openshell-0-1-3 get route -l app.kubernetes.io/name=openshell-dashboard
# Expected: route with your dashboard hostname

# Step 8: Check the dashboard logs for errors
oc -n openshell-0-1-3 logs deployment/openshell-dashboard -c dashboard --tail=10
# Expected: no "gateway error" lines

# Step 9: Open the dashboard URL in a browser
# Expected: Keycloak login page (NOT "Authentication is disabled" warning)
# Log in with admin1 / your password
```

**Do not proceed until you can log in to the dashboard and see the gateway status.**

---

## Phase 5: Deploy OpenClaw

**Script path:**
```bash
cd 04-openclaw
export OPENSHELL_GATEWAY=my-gateway
export WORKSPACE_NAME=openclaw-test
./create-workspace.sh
./create-sandbox.sh
./verify-model.sh
./launch-tui.sh
```

**Manual steps:**

```bash
# Step 1: Start port-forward (keep this running in a separate terminal)
oc -n openshell-0-1-3 port-forward svc/openshell-0-1-3 18083:8080

# Step 2: Extract mTLS certificates
NAMESPACE=openshell-0-1-3
GATEWAY_NAME=my-gateway
TLS_DIR="$HOME/.config/openshell/gateways/$GATEWAY_NAME/mtls"

mkdir -p "$TLS_DIR"
chmod 700 "$TLS_DIR"

WORK_DIR=$(mktemp -d)

# Note: on macOS use base64 -D, on Linux use base64 -d
oc -n "$NAMESPACE" get secret openshell-client-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > "$WORK_DIR/ca.crt"
oc -n "$NAMESPACE" get secret openshell-client-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > "$WORK_DIR/tls.crt"
oc -n "$NAMESPACE" get secret openshell-client-tls -o jsonpath='{.data.tls\.key}' | base64 -d > "$WORK_DIR/tls.key"

# Step 3: Verify the certificate chain
openssl verify -CAfile "$WORK_DIR/ca.crt" "$WORK_DIR/tls.crt"
# Expected: tls.crt: OK

# Step 4: Install certs to the config directory
install -m 600 "$WORK_DIR/ca.crt" "$TLS_DIR/ca.crt"
install -m 600 "$WORK_DIR/tls.crt" "$TLS_DIR/tls.crt"
install -m 600 "$WORK_DIR/tls.key" "$TLS_DIR/tls.key"
rm -rf "$WORK_DIR"

# Step 5: Register the gateway
openshell gateway add https://127.0.0.1:18083 --local --name "$GATEWAY_NAME"

# Step 6: Verify connection
export OPENSHELL_GATEWAY=$GATEWAY_NAME
openshell status
# Expected: Status: Connected, Authentication: Authenticated (mTLS transport), Version: 0.1.3

# Step 7: Create the workspace
export OPENSHELL_WORKSPACE=openclaw-test
OPENSHELL_WORKSPACE=default openshell workspace create --name openclaw-test

# Step 8: Verify workspace
openshell workspace list
# Expected: openclaw-test is listed and Active

# Step 9: Edit 04-openclaw/model-provider-profile.yaml
# Replace PLACEHOLDER_MODEL_HOST with your model API hostname

# Step 10: Import the provider profile
openshell profile lint -f 04-openclaw/model-provider-profile.yaml
openshell profile import -f 04-openclaw/model-provider-profile.yaml --global

# Step 11: Create the model provider (reads API key interactively)
read -rsp "Model API key: " CUSTOM_API_KEY; echo
export CUSTOM_API_KEY
openshell provider create --name model --type model-provider --global-profile --credential CUSTOM_API_KEY
unset CUSTOM_API_KEY

# Step 12: Verify provider
openshell provider list
# Expected: model provider listed

# Step 13: Create the OpenClaw sandbox
# Set OPENCLAW_IMAGE to your mirror registry path for the OpenClaw image
export OPENCLAW_IMAGE=YOUR_MIRROR/opendatahub/odh-openshell-sandbox-openclaw:latest
export MODEL_BASE_URL=https://your-model-api.example.com/v1
export MODEL_ID=your-model-id

openshell sandbox create \
  --name openclaw-native \
  --from "$OPENCLAW_IMAGE" \
  --provider model \
  --no-auto-providers \
  --env "MODEL_BASE_URL=$MODEL_BASE_URL" \
  --env "MODEL_ID=$MODEL_ID" \
  --env MODEL_CONTEXT_WINDOW=128000 \
  --env MODEL_MAX_TOKENS=4096 \
  --env MODEL_REASONING=false \
  --detach \
  --restart-policy never \
  -- bash -lc 'openclaw-start --version && exec sleep infinity'

# Step 14: Wait and verify sandbox is ready
sleep 10
openshell sandbox get openclaw-native
# Expected: Phase: Ready, Conditions: Ready: True

# Step 15: Test the model connection (non-interactive)
openshell sandbox exec openclaw-native -- \
  openclaw-start agent exec 'Reply with exactly: native-image-ok'
# Expected: output contains "native-image-ok"

# Step 16: Launch the interactive TUI
openshell sandbox exec --tty openclaw-native -- openclaw-start
# This opens the OpenClaw coding assistant. Type 'exit' or Ctrl+C to leave.
# The sandbox stays running after you exit.
```

---

## Reconnecting Later

```bash
# Terminal 1: restart the port-forward
oc -n openshell-0-1-3 port-forward svc/openshell-0-1-3 18083:8080

# Terminal 2: set vars and check
export OPENSHELL_GATEWAY=my-gateway
export OPENSHELL_WORKSPACE=openclaw-test

openshell status                          # Check gateway connection
openshell sandbox get openclaw-native     # Check sandbox is still running
openshell sandbox exec --tty openclaw-native -- openclaw-start   # Launch TUI
```

---

## Critical Gotchas

| # | Gotcha | Fix |
|---|---|---|
| 1 | CLI version must be exactly 0.1.3 | `openshell --version` before proceeding |
| 2 | macOS uses `base64 -D`, Linux uses `base64 -d` | Check your OS |
| 3 | mTLS directory must exist before cert extraction | `mkdir -p "$TLS_DIR"` first |
| 4 | Keycloak tokens missing `sub` claim | Assign the `basic` client scope to all clients (Step 8c in Phase 3) |
| 5 | Dashboard flashing / 401 errors | Gateway `adminRole`/`userRole` must match Keycloak role names exactly |
| 6 | `fullScopeAllowed` hides roles from tokens | Keep `false` and add explicit scope mappings instead |
| 7 | Dashboard shows "role required" error | User must be in the correct group with the matching client role |
| 8 | Port-forward dies between commands | Run it in a separate dedicated terminal |
| 9 | "Account is not fully set up" on token request | Set firstName, lastName, email on the Keycloak user |
| 10 | Agent Sandbox images need Red Hat login | `podman login registry.redhat.io` before pulling |

---

## Repo Structure

```
charts/                     Extracted Helm charts (install directly, no internet)
  openshell-gateway/        OpenShell Gateway v0.1.3 chart (Chart.yaml, templates/, values.yaml)
  openshell-dashboard/      Dashboard v0.1.1 chart (Chart.yaml, templates/, values.yaml)
scripts/                    Image mirroring and verification
00-prerequisites/           Agent Sandbox v0.5.0 manifest + preflight checks
01-gateway/                 Gateway namespace, RBAC, Helm values, install/verify
02-keycloak/                Keycloak client creation scripts, token verification
03-dashboard/               Dashboard OIDC secret, Helm values, install/verify
04-openclaw/                Provider profile, workspace/sandbox creation, model test
05-reconnect/               Reconnection script for later sessions
images.txt                  All 9 images with digests and podman pull commands
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
