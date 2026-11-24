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
# On a cluster the practice sign-in's admin API answers only itself (403 here): its own start-up hook loads
# the people from scripts/seed-mock-services.sh, so this stops at once and the app starts.
OIDC_URL="${OIDC_ISSUER_URL:-http://mock-oidc:10090}"
echo "Seeding mock-oidc test users..."
SEED=yes
for i in 1 2 3 4 5; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${OIDC_URL}/api/users" 2>/dev/null || true)
    if [ "$STATUS" = "200" ]; then break; fi
    if [ "$STATUS" = "403" ]; then SEED=no; echo "mock-oidc loads its own users here; skipping."; break; fi
    echo "mock-oidc not ready, retrying in 2s..."
    sleep 2
done

[ "$SEED" = yes ] && curl -sf --max-time 3 -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-superadmin","email":"superadmin@example.com","name":"Sarah SuperAdmin"}' >/dev/null 2>&1 || true
[ "$SEED" = yes ] && curl -sf --max-time 3 -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-admin","email":"admin@example.com","name":"Alex Admin"}' >/dev/null 2>&1 || true
[ "$SEED" = yes ] && curl -sf --max-time 3 -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-analyst","email":"analyst@example.com","name":"Ana Analyst"}' >/dev/null 2>&1 || true
[ "$SEED" = yes ] && curl -sf --max-time 3 -X POST "${OIDC_URL}/api/users" -H "Content-Type: application/json" \
    -d '{"sub":"mock-viewer","email":"viewer@example.com","name":"Victor Viewer"}' >/dev/null 2>&1 || true
echo "Mock-oidc users seeded."

echo "Starting server..."
# --no-proxy-headers: X-Forwarded-For is read by the app, only from the proxies in TRUSTED_PROXIES
# (app/middleware/trusted_proxies.py); uvicorn would otherwise also believe it from 127.0.0.1.
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-proxy-headers
