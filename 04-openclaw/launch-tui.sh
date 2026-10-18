#!/usr/bin/env bash
# Launch the interactive OpenClaw TUI.
#
# Usage:
#   OPENSHELL_GATEWAY=test-013 WORKSPACE_NAME=openclaw-test ./launch-tui.sh
set -euo pipefail

export OPENSHELL_GATEWAY="${OPENSHELL_GATEWAY:?Set OPENSHELL_GATEWAY}"
export OPENSHELL_WORKSPACE="${WORKSPACE_NAME:?Set WORKSPACE_NAME}"

openshell sandbox exec --tty openclaw-native -- openclaw-start
