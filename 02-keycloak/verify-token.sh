#!/usr/bin/env bash
# Verify that a Keycloak token has the required claims for the OpenShell gateway.
#
# Usage:
#   KC_HOST=https://sso.example.com KC_REALM=openshift \
#   CLI_CLIENT=openshell-cli-013 API_CLIENT=openshell-api-013 \
#   USERNAME=user1 PASSWORD=user1pass \
#   ./verify-token.sh
set -euo pipefail

for var in KC_HOST KC_REALM CLI_CLIENT API_CLIENT USERNAME PASSWORD; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set."
    exit 1
  fi
done

echo "Requesting token for $USERNAME via $CLI_CLIENT..."

RESULT=$(curl -sk -X POST "$KC_HOST/realms/$KC_REALM/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=$CLI_CLIENT&username=$USERNAME&password=$PASSWORD")

echo "$RESULT" | python3 -c "
import json, base64, sys

d = json.load(sys.stdin)
if 'error' in d:
    print(f'ERROR: {d[\"error\"]}: {d.get(\"error_description\",\"\")}')
    sys.exit(1)

t = d['access_token']
p = t.split('.')[1] + '=='
c = json.loads(base64.urlsafe_b64decode(p))

errors = []

sub = c.get('sub')
if sub:
    print(f'[PASS] sub: {sub}')
else:
    print('[FAIL] sub claim is MISSING')
    errors.append('sub')

aud = c.get('aud')
if isinstance(aud, list):
    aud_str = ', '.join(aud)
elif aud:
    aud_str = aud
else:
    aud_str = None

if aud_str and '$API_CLIENT' in str(aud):
    print(f'[PASS] aud: {aud_str}')
else:
    print(f'[FAIL] aud does not contain $API_CLIENT (got: {aud_str})')
    errors.append('aud')

ra = c.get('resource_access', {})
api_roles = ra.get('$API_CLIENT', {}).get('roles', [])
if api_roles:
    print(f'[PASS] resource_access.$API_CLIENT.roles: {api_roles}')
else:
    print(f'[FAIL] resource_access.$API_CLIENT.roles is empty')
    errors.append('resource_access')

print(f'[INFO] preferred_username: {c.get(\"preferred_username\")}')
print(f'[INFO] iss: {c.get(\"iss\")}')

if errors:
    print(f'\\nFAILED: {errors}')
    print('Fix Keycloak scopes/mappers before proceeding.')
    sys.exit(1)
else:
    print('\\nAll token claims verified. Safe to proceed.')
"
