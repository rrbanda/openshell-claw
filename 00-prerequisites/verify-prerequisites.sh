#!/usr/bin/env bash
# Verify prerequisites before deploying OpenShell.
#
# Checks: oc, helm, openshell CLI, Agent Sandbox CRD, cluster access.
# Run from the 00-prerequisites/ directory.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ERRORS=$((ERRORS + 1)); }

ERRORS=0

echo "Checking prerequisites..."
echo "========================="

# oc CLI
if command -v oc &>/dev/null; then
  pass "oc CLI found: $(oc version --client 2>/dev/null | head -1)"
else
  fail "oc CLI not found"
fi

# helm CLI
if command -v helm &>/dev/null; then
  pass "helm CLI found: $(helm version --short 2>/dev/null)"
else
  fail "helm CLI not found"
fi

# openshell CLI
if command -v openshell &>/dev/null; then
  VERSION=$(openshell --version 2>/dev/null)
  if [[ "$VERSION" == *"0.1.3"* ]]; then
    pass "openshell CLI: $VERSION"
  else
    fail "openshell CLI version mismatch: $VERSION (expected 0.1.3)"
  fi
else
  fail "openshell CLI not found"
fi

# Cluster access
if oc whoami &>/dev/null; then
  pass "Cluster access: $(oc whoami) on $(oc whoami --show-server 2>/dev/null)"
else
  fail "Not logged in to a cluster"
fi

# Agent Sandbox CRD
if oc get crd sandboxes.agents.x-k8s.io &>/dev/null; then
  pass "Agent Sandbox CRD exists"
else
  echo -e "${RED}[FAIL]${NC} Agent Sandbox CRD not found. Install it:"
  echo "       oc apply -f 00-prerequisites/agent-sandbox-manifest.yaml"
  ERRORS=$((ERRORS + 1))
fi

# Agent Sandbox controller
if oc -n agent-sandbox-system get deployment agent-sandbox-controller &>/dev/null; then
  READY=$(oc -n agent-sandbox-system get deployment agent-sandbox-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [[ "$READY" == "1" ]]; then
    pass "Agent Sandbox controller is running"
  else
    fail "Agent Sandbox controller not ready (readyReplicas=$READY)"
  fi
else
  fail "Agent Sandbox controller deployment not found"
fi

echo ""
echo "========================="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}$ERRORS check(s) failed. Fix them before proceeding.${NC}"
  exit 1
else
  echo -e "${GREEN}All prerequisites met.${NC}"
fi
