#!/usr/bin/env bash
# Install the OpenShell Dashboard from the local chart.
#
# Prerequisites:
#   1. Gateway is deployed and verified (01-gateway/verify.sh passes)
#   2. Keycloak clients created (02-keycloak/create-clients.sh)
#   3. OIDC secret created (03-dashboard/create-oidc-secret.sh)
#   4. values.yaml PLACEHOLDERs replaced
#
# Usage: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../charts/openshell-dashboard"
VALUES_FILE="$SCRIPT_DIR/values.yaml"
NAMESPACE="openshell-0-1-3"
RELEASE_NAME="openshell-dashboard"

if grep -q 'PLACEHOLDER' "$VALUES_FILE"; then
  echo "ERROR: values.yaml still contains PLACEHOLDER values."
  grep 'PLACEHOLDER' "$VALUES_FILE"
  exit 1
fi

if ! oc -n "$NAMESPACE" get secret openshell-dashboard-oidc &>/dev/null; then
  echo "ERROR: OIDC secret not found. Run create-oidc-secret.sh first."
  exit 1
fi

echo "Installing OpenShell Dashboard from local chart..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --wait --timeout 5m

echo ""
echo "Verifying deployment..."
"$SCRIPT_DIR/verify.sh"
