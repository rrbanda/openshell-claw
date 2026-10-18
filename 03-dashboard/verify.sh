#!/usr/bin/env bash
# Verify the OpenShell Dashboard deployment.
set -euo pipefail

NAMESPACE="openshell-0-1-3"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ERRORS=$((ERRORS + 1)); }
ERRORS=0

echo "Verifying Dashboard in $NAMESPACE"
echo "==================================="

# Pod with 2 containers
READY=$(oc -n "$NAMESPACE" get pod -l app.kubernetes.io/name=openshell-dashboard -o jsonpath='{.items[0].status.containerStatuses}' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for c in d if c['ready']))" 2>/dev/null || echo "0")
TOTAL=$(oc -n "$NAMESPACE" get pod -l app.kubernetes.io/name=openshell-dashboard -o jsonpath='{.items[0].status.containerStatuses}' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "0")
if [[ "$READY" == "2" && "$TOTAL" == "2" ]]; then
  pass "Dashboard pod: 2/2 containers ready (dashboard + oauth2-proxy)"
else
  fail "Dashboard pod: $READY/$TOTAL containers ready (expected 2/2)"
fi

# Route
ROUTE_HOST=$(oc -n "$NAMESPACE" get route -l app.kubernetes.io/name=openshell-dashboard -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "")
if [[ -n "$ROUTE_HOST" ]]; then
  pass "Route: https://$ROUTE_HOST"
else
  fail "Dashboard route not found"
fi

# Dashboard BFF logs -- check gateway connection
if oc -n "$NAMESPACE" logs deployment/openshell-dashboard -c dashboard --tail=5 2>/dev/null | grep -q 'gateway error'; then
  fail "Dashboard BFF reports gateway errors (check logs)"
else
  pass "No gateway errors in recent logs"
fi

echo ""
echo "==================================="
if [[ $ERRORS -gt 0 ]]; then
  echo -e "${RED}$ERRORS check(s) failed. Do NOT proceed.${NC}"
  exit 1
else
  echo -e "${GREEN}Dashboard verified. Open https://$ROUTE_HOST and log in.${NC}"
fi
