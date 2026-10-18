#!/usr/bin/env bash
# Verify that the OpenClaw sandbox can reach the model endpoint.
# Runs a non-interactive prompt and checks the response.
#
# Usage:
#   OPENSHELL_GATEWAY=test-013 WORKSPACE_NAME=openclaw-test ./verify-model.sh
set -euo pipefail

export OPENSHELL_GATEWAY="${OPENSHELL_GATEWAY:?Set OPENSHELL_GATEWAY}"
export OPENSHELL_WORKSPACE="${WORKSPACE_NAME:?Set WORKSPACE_NAME}"
SANDBOX_NAME="openclaw-native"

echo "=== Running non-interactive model turn ==="
OUTPUT=$(openshell sandbox exec "$SANDBOX_NAME" -- \
  openclaw-start agent exec 'Reply with exactly: native-image-ok' 2>&1)

echo "$OUTPUT"
echo ""

if echo "$OUTPUT" | grep -q 'native-image-ok'; then
  echo "[PASS] Model round-trip verified."
else
  echo "[FAIL] Expected 'native-image-ok' in output."
  exit 1
fi
