#!/usr/bin/env bash
# Create the OpenClaw workspace, import the model provider profile, and create the provider.
#
# BEFORE USING: Set these variables:
#   OPENSHELL_GATEWAY   -> registered gateway name (e.g. test-013)
#   WORKSPACE_NAME      -> workspace name (e.g. openclaw-test)
#
# The model-provider-profile.yaml must have PLACEHOLDERs replaced.
# The API key is read interactively (never in shell history).
#
# Usage: ./create-workspace.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_FILE="$SCRIPT_DIR/model-provider-profile.yaml"

for var in OPENSHELL_GATEWAY WORKSPACE_NAME; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set."
    exit 1
  fi
done

if grep -q 'PLACEHOLDER' "$PROFILE_FILE"; then
  echo "ERROR: model-provider-profile.yaml still contains PLACEHOLDERs."
  grep 'PLACEHOLDER' "$PROFILE_FILE"
  exit 1
fi

export OPENSHELL_GATEWAY
export OPENSHELL_WORKSPACE="$WORKSPACE_NAME"

echo "=== Creating workspace: $WORKSPACE_NAME ==="
OPENSHELL_WORKSPACE=default openshell workspace create --name "$WORKSPACE_NAME" 2>&1 || true

# In managed workspace mode, the gateway creates a new namespace for the workspace.
# The sandbox SA in that namespace needs the privileged SCC on OpenShift.
GATEWAY_RELEASE="${GATEWAY_RELEASE:-openshell-0-1-3}"
MANAGED_NS="openshell-${GATEWAY_RELEASE}-${WORKSPACE_NAME}"
echo ""
echo "=== Binding privileged SCC in managed namespace: $MANAGED_NS ==="
echo "  (waiting for namespace to be created by the gateway...)"
for i in $(seq 1 30); do
  if oc get namespace "$MANAGED_NS" &>/dev/null; then
    echo "  Namespace $MANAGED_NS found."
    break
  fi
  sleep 2
done
if oc get namespace "$MANAGED_NS" &>/dev/null; then
  oc adm policy add-scc-to-user privileged \
    -z "${GATEWAY_RELEASE}-sandbox" -n "$MANAGED_NS" 2>&1
  echo "  SCC binding created."
else
  echo "  WARNING: Namespace $MANAGED_NS not found after 60s."
  echo "  You may need to manually bind SCC after the namespace appears:"
  echo "    oc adm policy add-scc-to-user privileged -z ${GATEWAY_RELEASE}-sandbox -n $MANAGED_NS"
fi

echo ""
echo "=== Importing model provider profile ==="
openshell profile lint -f "$PROFILE_FILE"
openshell profile import -f "$PROFILE_FILE" --global

echo ""
echo "=== Creating model provider ==="
echo "Enter the model API key (will not be displayed):"
read -rsp "API key: " CUSTOM_API_KEY; echo ""
export CUSTOM_API_KEY

openshell provider create \
  --name model \
  --type model-provider \
  --global-profile \
  --credential CUSTOM_API_KEY

unset CUSTOM_API_KEY

echo ""
echo "=== Verify ==="
openshell workspace list
openshell provider list
echo ""
echo "Workspace and provider ready. Proceed with create-sandbox.sh."
