#!/bin/bash
set -e

echo "Waiting for database..."

# Strip asyncpg dialect for raw connection check
# DATABASE_URL is postgresql+asyncpg://user:pass@host:port/db
DB_HOST=$(echo "$DATABASE_URL" | sed -E 's|.*@([^:]+):([0-9]+)/.*|\1|')
DB_PORT=$(echo "$DATABASE_URL" | sed -E 's|.*@([^:]+):([0-9]+)/.*|\2|')

until python3 -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); s.connect(('${DB_HOST}', ${DB_PORT})); s.close()" 2>/dev/null; do
    echo "Database not ready, retrying in 2s..."
    sleep 2
done

echo "Database is ready."

echo "Running migrations..."
alembic upgrade head

# ---------------------------------------------------------------------------
# Seed mock-oidc test users (local dev only)
# In production OIDC_ISSUER_URL points to a real IdP and this is a harmless no-op.
# ---------------------------------------------------------------------------
OIDC_URL="${OIDC_ISSUER_URL:-http://mock-oidc:10090}"
echo "Seeding mock-oidc test users..."
for i in 1 2 3 4 5; do
    curl -sf "${OIDC_URL}/api/users" >/dev/null 2>&1 && break
    echo "mock-oidc not ready, retrying in 2s..."
    sleep 2
done

curl -sf -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-superadmin","email":"superadmin@example.com","name":"Sarah SuperAdmin"}' >/dev/null 2>&1 || true
curl -sf -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-admin","email":"admin@example.com","name":"Alex Admin"}' >/dev/null 2>&1 || true
curl -sf -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-analyst","email":"analyst@example.com","name":"Ana Analyst"}' >/dev/null 2>&1 || true
curl -sf -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-viewer","email":"viewer@example.com","name":"Victor Viewer"}' >/dev/null 2>&1 || true
echo "Mock-oidc users seeded."

echo "Starting server..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
