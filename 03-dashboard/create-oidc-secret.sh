#!/usr/bin/env bash
# Create the K8s secret for the dashboard's OIDC authentication.
#
# The dashboard client secret comes from Keycloak (printed by 02-keycloak/create-clients.sh).
# This script reads it interactively so it never appears in shell history.
#
# Usage: ./create-oidc-secret.sh
set -euo pipefail

NAMESPACE="openshell-0-1-3"
SECRET_NAME="openshell-dashboard-oidc"
DASHBOARD_CLIENT="${DASHBOARD_CLIENT:-openshell-dashboard-013}"

echo "Creating OIDC secret for the OpenShell Dashboard."
echo "You need the dashboard client secret from Keycloak."
echo ""

read -rsp "Dashboard client secret (from Keycloak): " CLIENT_SECRET; echo ""

if [[ -z "$CLIENT_SECRET" ]]; then
  echo "ERROR: Client secret cannot be empty."
  exit 1
fi

COOKIE_SECRET=$(openssl rand -hex 16)

oc -n "$NAMESPACE" delete secret "$SECRET_NAME" 2>/dev/null || true
oc -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal=client-id="$DASHBOARD_CLIENT" \
  --from-literal=client-secret="$CLIENT_SECRET" \
  --from-literal=cookie-secret="$COOKIE_SECRET"

echo ""
echo "Secret $SECRET_NAME created in $NAMESPACE."
echo "Proceed with 03-dashboard/install.sh."
