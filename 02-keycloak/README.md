# Keycloak Setup for OpenShell

This directory contains scripts to configure Keycloak for OpenShell OIDC authentication.

## Prerequisites

- **Keycloak 26.x or newer** (tested with 26.8). Red Hat build of Keycloak (RHBK) also works.
- **A Keycloak instance accessible from the cluster**. The script will:
  - Create the realm if it doesn't exist (e.g. if you only have `master`)
  - Use the realm if it already exists (e.g. `openshift`, `openshell`)
  - NOT modify or delete anything already in the realm
- **Admin access** to Keycloak (ability to create realms, clients, groups, roles).

## What Gets Created

The script adds the following objects to your **existing** realm. It does not modify or delete anything already there.

| Keycloak Object | Purpose | Naming Pattern |
|---|---|---|
| Group `users-a` | Regular user group | Hardcoded |
| Group `administrators-a` | Platform admin group | Hardcoded |
| Client `openshell-api-{GATEWAY_NAME}` | API resource client (audience + roles, non-interactive) | Unique per gateway |
| Client `openshell-cli-{GATEWAY_NAME}` | CLI public client (PKCE S256, device code grant) | Unique per gateway |
| Client `openshell-dashboard-{GATEWAY_NAME}` | Dashboard confidential client (oauth2-proxy) | Unique per gateway |
| Client roles `users-a`, `administrators-a` | On the API client | Hardcoded |
| Group-to-role mappings | users-a -> users-a, administrators-a -> administrators-a | |
| Audience mapper | Adds API client to `aud` claim | Per client |
| Scope mappings | CLI and Dashboard clients can see API client roles | Per client |
| `basic` scope assignment | **CRITICAL** -- contains the `sub` mapper | Per client |

**Safe to re-run**: If groups or clients already exist, Keycloak returns 409 (Conflict) and the script continues. It will not overwrite existing objects.

## Usage

```bash
export KC_HOST=https://sso.example.com       # Your Keycloak URL
export KC_REALM=openshift                     # Your EXISTING realm name
export KC_ADMIN_USER=admin                    # Realm admin username
export KC_ADMIN_PASS=<keycloak-admin-password>  # Will not be stored
export GATEWAY_NAME=013                       # Suffix for client IDs (makes them unique)
export DASH_HOST=openshell-dashboard.apps.example.com  # Dashboard route hostname

./create-clients.sh
```

### Using an existing realm that already has clients

The script only ADDS objects -- it does not modify existing clients, groups, or roles.
Client IDs are namespaced with `GATEWAY_NAME` (e.g. `openshell-api-013`), so they won't
collide with other applications in the same realm.

The group names `users-a` and `administrators-a` are hardcoded. If your realm already has
groups with these exact names, the script skips creation and reuses them. Make sure the
existing groups don't have conflicting role mappings.

### Using a different Keycloak (Red Hat SSO, RHBK, etc.)

The script uses standard Keycloak Admin REST API. It works with:
- Keycloak 26.x (tested)
- Red Hat build of Keycloak (RHBK) 26.x
- Older Keycloak versions (21+) -- but the `basic` scope may not exist (see below)
- Red Hat SSO 7.x -- API paths are the same, but some features may differ

## After Running the Script

1. **Create users** in Keycloak Admin Console (or via API):
   - Each user must have `firstName`, `lastName`, and `email` set (Keycloak 26+ requires these for login)
   - Example API call is in the README manual steps (Phase 3, Step 9)

2. **Assign users to groups**: put regular users in `users-a`, admins in `administrators-a`

3. **Verify tokens**: run `verify-token.sh` to confirm `sub`, `aud`, and `resource_access` are present

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

The OpenShell gateway **requires** the `sub` claim in access tokens. In Keycloak 26+, `sub` is
provided by the `oidc-sub-mapper` in the `basic` client scope. If the `basic` scope is not
assigned to your clients, tokens will lack `sub` and the gateway will reject them with:

```
invalid token: JSON error: missing field `sub`
```

The `create-clients.sh` script adds the `basic` scope automatically. If your Keycloak does not
have a `basic` client scope (older versions), the script prints a WARNING and you must add a
`sub` mapper manually:

1. Go to your CLI client -> Client scopes -> Dedicated scope -> Add mapper
2. Mapper type: User Attribute
3. Name: `sub`, User attribute: `id`, Token claim name: `sub`, Claim JSON type: String
4. Enable: Add to access token
5. Repeat for the Dashboard client

## Matching Values to Gateway Configuration

The Keycloak objects must match the gateway Helm values exactly:

| Gateway values.yaml key | Must match | Example |
|---|---|---|
| `server.oidc.issuer` | `KC_HOST/realms/KC_REALM` | `https://sso.example.com/realms/openshift` |
| `server.oidc.audience` | API client ID | `openshell-api-013` |
| `server.oidc.rolesClaim` | `resource_access.{API_CLIENT}.roles` | `resource_access.openshell-api-013.roles` |
| `server.oidc.adminRole` | Admin client role name | `administrators-a` |
| `server.oidc.userRole` | User client role name | `users-a` |
