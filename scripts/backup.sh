#!/usr/bin/env bash
# backup.sh — nightly PostgreSQL backup for ApexBooks (bookkeeping).
#
# Dumps the live database with pg_dump (custom format), keeps N daily
# backups, and (optionally) syncs them off-host. Run from the host where
# docker compose lives, e.g. via cron:
#
#   15 1 * * * /opt/bookkeeping/scripts/backup.sh >> /var/log/bookkeeping-backup.log 2>&1
#
# Restore drill: see docs/backup-restore-drill.md and restore.sh.
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/bookkeeping}"
BACKUP_DIR="${BACKUP_DIR:-/opt/backups/bookkeeping}"
KEEP_DAYS="${KEEP_DAYS:-14}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-bookkeeping}"
# Optional: off-host destination reachable by rclone, e.g. "gdrive:ApexBooks/backups"
RCLONE_DEST="${RCLONE_DEST:-}"

mkdir -p "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/bookkeeping_${STAMP}.dump"

cd "$COMPOSE_DIR"

echo "[$(date -u +%FT%TZ)] Starting backup -> $OUT"

# .env holds DB_PASSWORD; load it so pg_dump can authenticate. The db
# container is not port-published, so dump through `docker compose exec`.
set -a
# shellcheck disable=SC1091
[ -f .env ] && . ./.env
set +a

docker compose exec -T db pg_dump \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --compress=9 \
  -f /tmp/bookkeeping_latest.dump

# Copy out of the container, then clean up inside it.
docker compose cp db:/tmp/bookkeeping_latest.dump "$OUT"
docker compose exec -T db rm -f /tmp/bookkeeping_latest.dump

SIZE="$(du -h "$OUT" | cut -f1)"
echo "[$(date -u +%FT%TZ)] Backup complete ($SIZE) -> $OUT"

# Retention: keep KEEP_DAYS most recent backups.
ls -1t "$BACKUP_DIR"/bookkeeping_*.dump 2>/dev/null | tail -n +$((KEEP_DAYS + 1)) | while read -r old; do
  echo "[$(date -u +%FT%TZ)] Pruning $old"
  rm -f "$old"
done

# Optional off-host copy. Off-host is REQUIRED for the restore drill to be
# meaningful: local disk loss (the failure mode pg_dump alone cannot survive)
# is exactly what volume loss destroys.
if [ -n "$RCLONE_DEST" ]; then
  echo "[$(date -u +%FT%TZ)] Syncing to $RCLONE_DEST"
  rclone copy "$OUT" "$RCLONE_DEST" --log-file="$BACKUP_DIR/rclone.log" --log-level=ERROR
fi

echo "[$(date -u +%FT%TZ)] Done."
