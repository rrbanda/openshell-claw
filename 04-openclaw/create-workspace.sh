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
