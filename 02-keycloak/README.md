# Keycloak Setup for OpenShell

This directory contains scripts to configure Keycloak for OpenShell OIDC authentication.

## What Gets Created

| Keycloak Object | Purpose |
|---|---|
| Group `users-a` | Regular user group |
| Group `administrators-a` | Platform admin group |
| Client `openshell-api-{name}` | API resource client (audience + roles, non-interactive) |
| Client `openshell-cli-{name}` | CLI public client (PKCE S256, device code grant) |
| Client `openshell-dashboard-{name}` | Dashboard confidential client (oauth2-proxy) |
| Client roles `users-a`, `administrators-a` | On the API client |
| Group-to-role mappings | users-a -> users-a, administrators-a -> administrators-a |
| Audience mapper | Adds API client to `aud` claim |
| Scope mappings | CLI and Dashboard clients can see API client roles |
| `basic` scope assignment | **CRITICAL** -- contains the `sub` mapper; gateway rejects tokens without it |

## Usage

```bash
export KC_HOST=https://sso.example.com
export KC_REALM=openshift
export KC_ADMIN_USER=admin
export KC_ADMIN_PASS=<keycloak-admin-password>
export GATEWAY_NAME=013
export DASH_HOST=openshell-dashboard.apps.example.com

./create-clients.sh
```

## After Running the Script

1. **Create users** in Keycloak Admin Console (or via API)
2. **Assign users to groups**: put regular users in `users-a`, admins in `administrators-a`
3. **Set user profile fields**: firstName, lastName, email (Keycloak 26+ requires these)
4. **Verify tokens**: run `verify-token.sh` to confirm `sub`, `aud`, and `resource_access` are present

```bash
export KC_HOST=https://sso.example.com
export KC_REALM=openshift
export CLI_CLIENT=openshell-cli-013
export API_CLIENT=openshell-api-013
export USERNAME=user1
export PASSWORD=user1pass

./verify-token.sh
```

## Critical Gotcha: The `sub` Claim

The OpenShell gateway **requires** the `sub` claim in access tokens. In Keycloak, `sub` is provided by the `oidc-sub-mapper` in the `basic` client scope. If the `basic` scope is not assigned to your clients, tokens will lack `sub` and the gateway will reject them with:

```
invalid token: JSON error: missing field `sub`
```

The `create-clients.sh` script adds the `basic` scope automatically.
