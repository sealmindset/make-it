# FastAPI + Next.js Scaffold

## What This Is

This is the infrastructure scaffold used by `/make-it` when building a web application with a FastAPI backend and Next.js frontend. It contains proven, battle-tested patterns extracted from real builds.

The scaffold provides the foundational infrastructure that every app needs -- authentication, database, Docker orchestration, and mock services for local development. Claude copies these files into the new project during the Build phase and replaces placeholders with app-specific values.

## How Claude Uses This During /make-it

1. **Design phase** determines the app slug, ports, users, and integrations
2. **Build phase** copies scaffold files into the project directory
3. Placeholders are replaced with values from `app-context.json`
4. App-specific code (frontend, backend, migrations) is generated on top of this foundation
5. `seed-mock-services.sh` is customized with the app's users and any extra mock services

## Files

| File | Copied As-Is? | Notes |
|------|---------------|-------|
| `mock-services/mock-oidc/` | Yes | Complete mock OIDC provider. Ships unchanged with every app. |
| `docker-compose.yml` | Customized | Placeholders replaced; additional services added per app |
| `scripts/seed-mock-services.sh` | Customized | User list and extra mock seeding filled in per app |
| `.env.example` | Customized | Additional service URLs added per app |
| `.gitignore` | Yes | Standard Python + Node.js + Docker gitignore |

## Placeholders

All placeholders use the `[PLACEHOLDER_NAME]` format and are replaced during the Build phase.

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `[APP_NAME]` | Human-readable app name | DeliverIt |
| `[APP_SLUG]` | Kebab-case identifier (used for DB, containers) | deliver-it |
| `[FRONTEND_PORT]` | Host port mapped to frontend container port 3000 | 3100 |
| `[BACKEND_PORT]` | Host port mapped to backend container port 8000 | 8100 |
| `[DB_PORT]` | Host port mapped to PostgreSQL container port 5432 | 5500 |
| `[MOCK_OIDC_PORT]` | Host port mapped to mock-oidc container port 10090 | 10090 |
| `[SEED_USERS]` | JSON array of `{sub, email, name}` for seed script | See below |
| `[ADDITIONAL_SERVICE_ENVS]` | Extra env vars in backend service | `JIRA_BASE_URL=...` |
| `[ADDITIONAL_MOCK_SERVICES]` | Extra service definitions in docker-compose | mock-jira service block |
| `[ADDITIONAL_MOCK_SEED]` | Extra seeding logic in seed script | Jira project creation |
| `[ADDITIONAL_SERVICE_URLS]` | Extra env var docs in .env.example | `JIRA_BASE_URL=...` |

### SEED_USERS Example

```bash
SEED_USERS='[
  {"sub": "mock-admin", "email": "admin@deliver-it.local", "name": "Admin User"},
  {"sub": "mock-manager", "email": "manager@deliver-it.local", "name": "Manager User"},
  {"sub": "mock-user", "email": "user@deliver-it.local", "name": "Regular User"},
  {"sub": "mock-viewer", "email": "viewer@deliver-it.local", "name": "Viewer User"}
]'
```

The `sub` values must exactly match the `oidc_subject` column in the database seed migration. This alignment is what connects "the person who logs in" to "the user row with the correct role."

## Architecture

### Authentication Flow

```
Browser                Frontend (Next.js)         Backend (FastAPI)        mock-oidc
  |                         |                          |                      |
  |-- click "Sign In" ----->|                          |                      |
  |                         |-- redirect to /authorize ---------------------->|
  |<-- login page (user list) ------------------------------------------------|
  |-- select user ---------------------------------------------------------->|
  |<-- redirect with ?code= ----------------------------                      |
  |-- /api/auth/callback -->|                          |                      |
  |                         |-- POST /token (code) ----|--------------------->|
  |                         |<-- access_token + id_token ----------------------|
  |                         |-- GET /userinfo ----------|--------------------->|
  |                         |<-- {sub, email, name} ---|----------------------|
  |                         |-- POST /auth/callback --->|                      |
  |                         |                          |-- lookup user by sub  |
  |                         |                          |-- get role + perms    |
  |                         |                          |-- create session JWT  |
  |                         |<-- set cookie + redirect-|                      |
  |<-- authenticated -------|                          |                      |
```

Key points:
- The frontend proxies auth requests to the backend (Next.js API routes)
- The backend exchanges the code for tokens server-to-server (never exposed to browser)
- User roles come from the application database, NOT from the OIDC provider
- The mock-oidc provider only supplies identity (sub, email, name)

### Internal/External URL Split

mock-oidc natively handles the Docker networking split:
- `MOCK_OIDC_EXTERNAL_BASE_URL` (e.g., `http://localhost:10090`) -- used for the `authorization_endpoint` in the discovery document, since the browser navigates to it directly
- `MOCK_OIDC_INTERNAL_BASE_URL` (e.g., `http://mock-oidc:10090`) -- used for `token_endpoint`, `userinfo_endpoint`, and `jwks_uri`, since the backend calls these server-to-server inside the Docker network

This eliminates the need for `OIDC_INTERNAL_URL` environment variables or URL rewriting logic in the application.

### RBAC

The database has four tables for role-based access control:
- `roles` -- system roles (Super Admin, Admin, Manager, User) plus custom roles
- `permissions` -- page-level CRUD permissions (e.g., `forecasts.view`, `users.create`)
- `role_permissions` -- junction table mapping roles to permissions
- `users` -- has a `role_id` foreign key and `oidc_subject` for OIDC identity mapping

Every route handler uses `require_permission(resource, action)` middleware. The app never checks role strings directly.

### Health Checks

All health checks use `127.0.0.1` (not `localhost`) to avoid IPv6 resolution issues in Alpine containers:
- **Frontend**: `wget --spider -q http://127.0.0.1:3000` (Alpine has wget)
- **Backend**: `python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"` (slim image, no wget/curl)
- **mock-oidc**: `python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:10090/health')"` (slim image)
- **PostgreSQL**: `pg_isready -U [APP_SLUG]`

### Port Selection

Default ports (3000, 5432, 8000) are almost always taken on developer machines running multiple Docker projects. During the Design phase, `/make-it` checks `lsof -i :PORT` and selects available ports. The scaffold placeholders make this remapping seamless.
