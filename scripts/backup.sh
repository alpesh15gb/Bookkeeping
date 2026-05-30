#!/bin/bash
# =============================================================================
# Database Backup Script for ApexBooks
# Run daily via cron: 0 2 * * * /path/to/backup.sh
# =============================================================================

set -euo pipefail

BACKUP_DIR="/backups/postgres"
DATE=$(date +%Y%m%d_%H%M%S)
KEEP_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Full backup
echo "[$(date)] Starting database backup..."
docker compose exec -T db pg_dump -U postgres -d bookkeeping --format=custom --compress=9 > "$BACKUP_DIR/bookkeeping_${DATE}.dump"

# Schema-only backup
docker compose exec -T db pg_dump -U postgres -d bookkeeping --schema-only > "$BACKUP_DIR/schema_${DATE}.sql"

# Cleanup old backups
find "$BACKUP_DIR" -name "*.dump" -mtime +$KEEP_DAYS -delete
find "$BACKUP_DIR" -name "*.sql" -mtime +$KEEP_DAYS -delete

echo "[$(date)] Backup completed: bookkeeping_${DATE}.dump"
echo "[$(date)] Backups older than $KEEP_DAYS days deleted."
