#!/bin/sh
set -e

echo "Waiting for database..."

# Extract host and port from DATABASE_URL
# DATABASE_URL is postgresql://user:pass@host:port/db
DB_HOST=$(echo "$DATABASE_URL" | sed -E 's|.*@([^:]+):([0-9]+)/.*|\1|')
DB_PORT=$(echo "$DATABASE_URL" | sed -E 's|.*@([^:]+):([0-9]+)/.*|\2|')

until nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; do echo "Database not ready, retrying in 2s..."; sleep 2; done

echo "Database is ready."

echo "Running migrations..."
npx prisma migrate deploy

echo "Seeding database..."
npx prisma db seed

echo "Starting server..."
exec node server.js
