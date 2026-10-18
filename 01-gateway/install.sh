#!/usr/bin/env bash
# Install the OpenShell Gateway from the local chart.
#
# Prerequisites:
#   1. 00-prerequisites/verify-prerequisites.sh passes
#   2. namespace.yaml and scc-rbac.yaml applied
#   3. values.yaml PLACEHOLDERs replaced with actual values
#
# Usage: ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../charts/openshell-gateway"
VALUES_FILE="$SCRIPT_DIR/values.yaml"
NAMESPACE="openshell-0-1-3"
RELEASE_NAME="openshell-0-1-3"

# Safety check: PLACEHOLDERs must be replaced (ignore comments)
if grep -v '^\s*#' "$VALUES_FILE" | grep -q 'PLACEHOLDER'; then
  echo "ERROR: values.yaml still contains PLACEHOLDER values."
  echo "       Replace all PLACEHOLDER_* entries before running this script."
  grep -v '^\s*#' "$VALUES_FILE" | grep 'PLACEHOLDER'
  exit 1
fi

echo "Creating namespace and SCC binding..."
oc apply -f "$SCRIPT_DIR/namespace.yaml"
oc apply -f "$SCRIPT_DIR/scc-rbac.yaml"

echo ""
echo "Installing OpenShell Gateway from local chart..."
helm upgrade --install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --wait --timeout 5m

echo ""
echo "Verifying deployment..."
"$SCRIPT_DIR/verify.sh"
