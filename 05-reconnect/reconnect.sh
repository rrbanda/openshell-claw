#!/usr/bin/env bash
# Reconnect to an existing OpenClaw deployment for a later session.
#
# BEFORE USING: Set these variables:
#   OPENSHELL_GATEWAY  -> registered gateway name (e.g. test-013)
#   WORKSPACE_NAME     -> workspace name (e.g. openclaw-test)
#   NAMESPACE          -> gateway namespace (default: openshell-0-1-3)
#   SERVICE            -> gateway service name (default: openshell-0-1-3)
#   LOCAL_PORT         -> local port (default: 18083)
set -euo pipefail

NAMESPACE="${NAMESPACE:-openshell-0-1-3}"
SERVICE="${SERVICE:-openshell-0-1-3}"
LOCAL_PORT="${LOCAL_PORT:-18083}"

export OPENSHELL_GATEWAY="${OPENSHELL_GATEWAY:?Set OPENSHELL_GATEWAY}"
export OPENSHELL_WORKSPACE="${WORKSPACE_NAME:?Set WORKSPACE_NAME}"

echo "Step 1: Start the port-forward in another terminal:"
echo ""
echo "  oc -n $NAMESPACE port-forward svc/$SERVICE $LOCAL_PORT:8080"
echo ""
read -rp "Press Enter once the port-forward is running..."

echo ""
echo "Step 2: Checking gateway connection..."
openshell status

echo ""
echo "Step 3: Checking sandbox..."
openshell sandbox get openclaw-native

echo ""
echo "Step 4: To launch the TUI:"
echo "  openshell sandbox exec --tty openclaw-native -- openclaw-start"
