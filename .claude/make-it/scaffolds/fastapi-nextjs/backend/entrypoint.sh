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

echo "Starting server..."
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
