#!/usr/bin/env bash
# restore.sh — restore a bookkeeping pg_dump backup into the db container.
#
# RESTORE DRILL (run at least quarterly, and before the first live FY):
#
#   DANGER: this REPLACES the current database contents. Run it against a
#   throwaway copy first (fresh `docker compose up -d db` with a scratch
#   volume), and never while the backend is serving traffic.
#
# Usage:
#   ./scripts/restore.sh /path/to/bookkeeping_20260818T030000Z.dump
#
# Verification after restore:
#   docker compose exec -T db psql -U postgres -d bookkeeping -c \
#     "SELECT count(*) FROM journal_entries;"
#   curl -s http://127.0.0.1:8000/health   # schema: ok
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/bookkeeping}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-bookkeeping}"

if [ $# -ne 1 ]; then
  echo "usage: $0 /path/to/backup.dump" >&2
  exit 2
fi
DUMP="$1"
if [ ! -f "$DUMP" ]; then
  echo "backup file not found: $DUMP" >&2
  exit 2
fi

cd "$COMPOSE_DIR"

read -r -p "This will DROP and recreate the '$POSTGRES_DB' database. Type 'restore' to continue: " CONFIRM
if [ "$CONFIRM" != "restore" ]; then
  echo "aborted." >&2
  exit 1
fi

# Stop writers first so the restore is not racing live traffic.
docker compose stop backend worker beat

set -a
# shellcheck disable=SC1091
[ -f .env ] && . ./.env
set +a

echo "[$(date -u +%FT%TZ)] Dropping and recreating $POSTGRES_DB"
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c \
  "DROP DATABASE IF EXISTS $POSTGRES_DB WITH (FORCE);"
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c \
  "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"

echo "[$(date -u +%FT%TZ)] Restoring $DUMP"
docker compose cp "$DUMP" db:/tmp/restore.dump
docker compose exec -T db pg_restore \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --no-owner \
  --no-privileges \
  --exit-on-error \
  /tmp/restore.dump
docker compose exec -T db rm -f /tmp/restore.dump

echo "[$(date -u +%FT%TZ)] Restarting services"
docker compose start db
docker compose up -d backend worker beat

# Wait for the health gate (it checks the alembic schema revision).
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1; then
    echo "[$(date -u +%FT%TZ)] Backend healthy after restore."
    exit 0
  fi
  sleep 2
done
echo "backend did not become healthy within 60s — inspect: docker compose logs backend" >&2
exit 1
