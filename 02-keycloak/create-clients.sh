#!/usr/bin/env bash
# Create Keycloak clients, users, groups, roles, and mappers for OpenShell.
#
# BEFORE USING: Set these environment variables:
#
#   KC_HOST        -> Keycloak base URL (e.g. https://sso.example.com)
#   KC_REALM       -> Realm name (e.g. openshift)
#   KC_ADMIN_USER  -> Keycloak admin username
#   KC_ADMIN_PASS  -> Keycloak admin password (will not be stored)
#   GATEWAY_NAME   -> Unique suffix for client IDs (e.g. 013)
#   DASH_HOST      -> Dashboard route hostname (e.g. dashboard.example.com)
#
# Usage: ./create-clients.sh
set -euo pipefail

for var in KC_HOST KC_REALM KC_ADMIN_USER KC_ADMIN_PASS GATEWAY_NAME DASH_HOST; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set."
    exit 1
  fi
done

API_CLIENT="openshell-api-${GATEWAY_NAME}"
CLI_CLIENT="openshell-cli-${GATEWAY_NAME}"
DASH_CLIENT="openshell-dashboard-${GATEWAY_NAME}"

echo "Keycloak: $KC_HOST realm=$KC_REALM"
echo "Clients:  $API_CLIENT, $CLI_CLIENT, $DASH_CLIENT"
echo ""

# Get admin token
TOKEN=$(curl -sk -X POST "$KC_HOST/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=$KC_ADMIN_USER&password=$KC_ADMIN_PASS" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
AUTH="Authorization: Bearer $TOKEN"

# 0. Create realm if it doesn't exist
echo "=== Checking realm: $KC_REALM ==="
REALM_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" "$KC_HOST/realms/$KC_REALM")
if [[ "$REALM_STATUS" == "200" ]]; then
  echo "  Realm '$KC_REALM' already exists. Using it."
else
  echo "  Realm '$KC_REALM' not found. Creating it..."
  CREATE_CODE=$(curl -sk -X POST "$KC_HOST/admin/realms" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"realm\":\"$KC_REALM\",\"enabled\":true,\"sslRequired\":\"external\"}" \
    -o /dev/null -w "%{http_code}")
  if [[ "$CREATE_CODE" == "201" ]]; then
    echo "  Realm '$KC_REALM' created."
  else
    echo "  ERROR: Failed to create realm (HTTP $CREATE_CODE)."
    echo "  Create the realm manually in the Keycloak Admin Console, then re-run this script."
    exit 1
  fi
fi

# 1. Create groups
echo "=== Creating groups ==="
for g in users-a administrators-a; do
  CODE=$(curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/groups" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\":\"$g\"}" -o /dev/null -w "%{http_code}")
  echo "  $g: $([[ "$CODE" == "201" ]] && echo "created" || echo "exists or error ($CODE)")"
done

# 2. Create API resource client
echo ""
echo "=== Creating API resource client: $API_CLIENT ==="
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"clientId\":\"$API_CLIENT\",\"enabled\":true,\"publicClient\":false,\"bearerOnly\":true,\"standardFlowEnabled\":false,\"directAccessGrantsEnabled\":false,\"implicitFlowEnabled\":false,\"serviceAccountsEnabled\":false}" \
  -o /dev/null -w "  HTTP %{http_code}\n"

# 3. Create CLI public client
echo ""
echo "=== Creating CLI client: $CLI_CLIENT ==="
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"clientId\":\"$CLI_CLIENT\",\"enabled\":true,\"publicClient\":true,\"standardFlowEnabled\":true,\"directAccessGrantsEnabled\":true,\"attributes\":{\"oauth2.device.authorization.grant.enabled\":\"true\",\"pkce.code.challenge.method\":\"S256\"},\"redirectUris\":[\"http://127.0.0.1/*\"],\"webOrigins\":[],\"fullScopeAllowed\":false,\"defaultClientScopes\":[\"openid\",\"profile\",\"email\",\"roles\"]}" \
  -o /dev/null -w "  HTTP %{http_code}\n"

# 4. Create Dashboard confidential client
echo ""
echo "=== Creating Dashboard client: $DASH_CLIENT ==="
curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients" \
  -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"clientId\":\"$DASH_CLIENT\",\"enabled\":true,\"publicClient\":false,\"standardFlowEnabled\":true,\"directAccessGrantsEnabled\":false,\"attributes\":{\"pkce.code.challenge.method\":\"S256\"},\"redirectUris\":[\"https://$DASH_HOST/oauth2/callback\"],\"webOrigins\":[\"https://$DASH_HOST\"],\"fullScopeAllowed\":false,\"defaultClientScopes\":[\"openid\",\"profile\",\"email\",\"roles\"]}" \
  -o /dev/null -w "  HTTP %{http_code}\n"

# 5. Get API client UUID and create roles
API_UUID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients?clientId=$API_CLIENT" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
echo ""
echo "=== Creating client roles on $API_CLIENT ==="
for role in users-a administrators-a; do
  curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\":\"$role\"}" -o /dev/null -w "  $role: %{http_code}\n"
done

# 6. Map groups -> client roles
echo ""
echo "=== Mapping groups to roles ==="
for mapping in "users-a:users-a" "administrators-a:administrators-a"; do
  GROUP_NAME="${mapping%%:*}"
  ROLE_NAME="${mapping##*:}"
  GROUP_ID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/groups?search=$GROUP_NAME&exact=true" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
  ROLE_JSON=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles/$ROLE_NAME")
  curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/groups/$GROUP_ID/role-mappings/clients/$API_UUID" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "[$ROLE_JSON]" -o /dev/null -w "  $GROUP_NAME -> $ROLE_NAME: %{http_code}\n"
done

# 7. Add audience mapper + basic scope to CLI and Dashboard clients
echo ""
echo "=== Adding audience mapper and basic scope ==="
BASIC_SCOPE_ID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/client-scopes" | \
  python3 -c "import sys,json; [print(s['id']) for s in json.load(sys.stdin) if s['name']=='basic']")

for CLIENT_NAME in "$CLI_CLIENT" "$DASH_CLIENT"; do
  CLIENT_UUID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients?clientId=$CLIENT_NAME" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")

  # Add audience mapper
  curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$CLIENT_UUID/protocol-mappers/models" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"name\":\"openshell-api-audience\",\"protocol\":\"openid-connect\",\"protocolMapper\":\"oidc-audience-mapper\",\"config\":{\"included.client.audience\":\"$API_CLIENT\",\"id.token.claim\":\"false\",\"access.token.claim\":\"true\"}}" \
    -o /dev/null -w "  $CLIENT_NAME audience mapper: %{http_code}\n"

  # Add scope mappings (API client roles)
  ROLES=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$API_UUID/roles")
  curl -sk -X POST "$KC_HOST/admin/realms/$KC_REALM/clients/$CLIENT_UUID/scope-mappings/clients/$API_UUID" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "$ROLES" -o /dev/null -w "  $CLIENT_NAME scope: %{http_code}\n"

  # Add basic scope (contains the 'sub' mapper -- CRITICAL)
  if [[ -n "$BASIC_SCOPE_ID" ]]; then
    curl -sk -X PUT "$KC_HOST/admin/realms/$KC_REALM/clients/$CLIENT_UUID/default-client-scopes/$BASIC_SCOPE_ID" \
      -H "$AUTH" -o /dev/null -w "  $CLIENT_NAME basic scope: %{http_code}\n"
  else
    echo "  WARNING: 'basic' client scope not found. Tokens may lack 'sub' claim."
  fi
done

# 8. Print dashboard client secret (do NOT store in git)
DASH_UUID=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients?clientId=$DASH_CLIENT" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
DASH_SECRET=$(curl -sk -H "$AUTH" "$KC_HOST/admin/realms/$KC_REALM/clients/$DASH_UUID/client-secret" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['value'])")

echo ""
echo "=========================================="
echo "Keycloak clients created successfully."
echo ""
echo "Dashboard client secret (store securely, DO NOT commit to git):"
echo "  $DASH_SECRET"
echo ""
echo "Next: Create users in Keycloak, assign to groups, then run verify-token.sh"
echo "=========================================="
