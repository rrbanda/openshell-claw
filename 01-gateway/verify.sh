#!/usr/bin/env bash
# Verify the OpenShell Gateway deployment.
set -euo pipefail

NAMESPACE="openshell-0-1-3"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ERRORS=$((ERRORS + 1)); }
ERRORS=0

echo "Verifying OpenShell Gateway in $NAMESPACE"
echo "=========================================="

# Gateway pod
POD_STATUS=$(oc -n "$NAMESPACE" get pod -l app.kubernetes.io/name=openshell -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$POD_STATUS" == "Running" ]]; then
  pass "Gateway pod is Running"
else
  fail "Gateway pod status: $POD_STATUS"
fi

# Service
if oc -n "$NAMESPACE" get svc openshell-0-1-3 &>/dev/null; then
  pass "Gateway service exists"
else
  fail "Gateway service not found"
fi

# TLS secrets
for secret in openshell-server-tls openshell-client-tls; do
  if oc -n "$NAMESPACE" get secret "$secret" &>/dev/null; then
    pass "Secret $secret exists"
  else
    fail "Secret $secret not found"
  fi
done

# Config
WORKSPACE_MODE=$(oc -n "$NAMESPACE" get configmap openshell-0-1-3-config -o jsonpath='{.data.gateway\.toml}' 2>/dev/null | grep workspace_mode || echo "")
if [[ "$WORKSPACE_MODE" == *"managed"* ]]; then
  pass "Workspace mode is managed"
else
  fail "Workspace mode not set to managed"
fi

# OIDC
OIDC_ISSUER=$(oc -n "$NAMESPACE" get configmap openshell-0-1-3-config -o jsonpath='{.data.gateway\.toml}' 2>/dev/null | grep 'issuer =' || echo "")
if [[ -n "$OIDC_ISSUER" ]]; then
  pass "OIDC issuer configured: $OIDC_ISSUER"
else
  fail "OIDC issuer not found in gateway config"
fi

echo ""
echo "=========================================="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}$ERRORS check(s) failed. Do NOT proceed.${NC}"
  exit 1
else
  echo -e "${GREEN}Gateway deployment verified. Proceed to Keycloak setup.${NC}"
fi
