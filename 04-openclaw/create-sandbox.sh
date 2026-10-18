#!/usr/bin/env bash
# Create the OpenClaw sandbox from the pinned reference image.
#
# BEFORE USING: Set these variables:
#   OPENSHELL_GATEWAY   -> registered gateway name
#   WORKSPACE_NAME      -> workspace name (must exist)
#   MODEL_BASE_URL      -> model API base URL (e.g. https://api.example.com/v1)
#   MODEL_ID            -> model identifier (e.g. gemini-2.5-flash)
#   OPENCLAW_IMAGE      -> OpenClaw image (use the mirror registry path)
#
# Usage: ./create-sandbox.sh
set -euo pipefail

for var in OPENSHELL_GATEWAY WORKSPACE_NAME MODEL_BASE_URL MODEL_ID OPENCLAW_IMAGE; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set."
    exit 1
  fi
done

export OPENSHELL_GATEWAY
export OPENSHELL_WORKSPACE="$WORKSPACE_NAME"
SANDBOX_NAME="openclaw-native"

echo "=== Creating OpenClaw sandbox ==="
echo "  Image:     $OPENCLAW_IMAGE"
echo "  Model URL: $MODEL_BASE_URL"
echo "  Model ID:  $MODEL_ID"
echo ""

openshell sandbox create \
  --name "$SANDBOX_NAME" \
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

echo ""
echo "Waiting for sandbox to be ready..."
sleep 10

echo ""
echo "=== Sandbox status ==="
openshell sandbox get "$SANDBOX_NAME"

echo ""
echo "Sandbox created. Run verify-model.sh to test the model connection."
