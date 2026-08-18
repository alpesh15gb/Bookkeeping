# Backup & Restore Drill

The ledger is append-only accounting history. Volume loss destroys it — the
JSON/Excel exports the app offers are reports, not backups. A nightly off-host
`pg_dump` plus a practiced restore is the minimum viable protection.

## 1. Enable the nightly backup

1. Add to `/opt/bookkeeping/.env` (or export in the shell):

   ```bash
   BACKUP_DIR=/opt/backups/bookkeeping
   RCLONE_DEST=gdrive:ApexBooks/backups   # off-host destination — REQUIRED for real protection
   ```

2. Install the cron job on the host:

   ```bash
   chmod +x /opt/bookkeeping/scripts/backup.sh
   crontab -e
   ```

   ```cron
   15 1 * * * /opt/bookkeeping/scripts/backup.sh >> /var/log/bookkeeping-backup.log 2>&1
   ```

3. First run by hand to prove it works:

   ```bash
   /opt/bookkeeping/scripts/backup.sh
   ls -lh /opt/backups/bookkeeping/
   ```

   Expect a `bookkeeping_YYYYMMDDTHHMMSSZ.dump` of a few MB to tens of MB,
   and (if `RCLONE_DEST` is set) a matching object in the off-host bucket.

## 2. Restore drill (quarterly, and before the first live FY)

The point of a drill is to prove the backup is restorable, not just present.
Run it against a scratch database first:

```bash
# 1. Snapshot the current state for comparison
docker compose exec -T db psql -U postgres -d bookkeeping -c \
  "SELECT count(*) AS journal_entries FROM journal_entries;"
docker compose exec -T db psql -U postgres -d bookkeeping -c \
  "SELECT count(*) AS invoices FROM invoices;"

# 2. Restore from the latest backup
./scripts/restore.sh /opt/backups/bookkeeping/bookkeeping_*.dump
# ... type 'restore' when prompted ...

# 3. Verify: row counts match the snapshot above, and the health gate passes
docker compose exec -T db psql -U postgres -d bookkeeping -c \
  "SELECT count(*) AS journal_entries FROM journal_entries;"
curl -s http://127.0.0.1:8000/health   # expect {"status":"healthy", ... "schema":"ok"}
```

Additional checks worth scripting:

- Pick a recent invoice and confirm its lines, totals, and GST breakdown
  match what the app shows.
- Confirm an old journal entry still cannot be deleted (append-only guards
  survive restore — they are schema objects inside the dump).
- Confirm RLS is still enforced: a salesperson token cannot see another
  tenant's ledger.

## 3. Failure modes the drill must cover

| Failure | Detection | Recovery |
|---|---|---|
| Volume loss (the real one) | Host re-provision; db container empty | Restore latest dump; journal entries survive |
| Corrupt backup | `pg_restore --exit-on-error` fails during drill | Alert on cron failure; keep 14 days of history |
| Migration mismatch | `/health` shows `schema` != `ok` | Restore + `alembic upgrade head` (runs on container start) |
| Off-host copy missing | `rclone.log` errors or empty bucket | Fix `RCLONE_DEST`; treat local-only backups as no backup |

## 4. Retention

`backup.sh` prunes to the newest `KEEP_DAYS` (default 14) backups. A GST
dispute can span quarters, so if disk allows, keep at least 93 days (one
quarter + grace) on the off-host side.

## 5. Security note

The dump contains the full ledger — treat it as production data. Keep the
off-host bucket private, encrypt at rest, and restrict access to the ops
account that runs `rclone`.
