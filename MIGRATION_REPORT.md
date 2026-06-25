# Migration Report — ApexBooks v1.0

**Date:** 2026-06-26

---

## Migration History

| Revision | Date | Description |
|----------|------|-------------|
| 20260524_0001 | 2026-05-24 | Phase 0 integrity updates |
| 20260524_0002 | 2026-05-24 | Phase 1 DB constraints |
| 20260527_0001 | 2026-05-27 | Bill round_off and constraints |
| 20260528_0001 | 2026-05-28 | Expense bank_account_id |
| 20260528_0002 | 2026-05-28 | Idempotency keys table |
| 20260528_0003 | 2026-05-28 | Accounting periods table |
| 20260528_0004 | 2026-05-28 | Expense GST columns |
| 20260528_0005 | 2026-05-28 | Idempotency unique constraint |
| 20260528_0006 | 2026-05-28 | Normalize status names |
| 20260528_0007 | 2026-05-28 | Backfill expense category linked account |
| 20260528_0008 | 2026-05-28 | Add is_locked to journal entries |
| 20260530_0001 | 2026-05-30 | Security and feature columns |
| 20260531_0001 | 2026-05-31 | Cancel columns and migrate drafts |
| 20260601_0001 | 2026-06-01 | Document fields |
| 20260601_0002 | 2026-06-01 | Bills TDS columns |
| 20260602_0001 | 2026-06-02 | Expense category deleted_at |
| 20260606_0001 | 2026-06-06 | Financial years table |
| 20260606_0002 | 2026-06-06 | Roll-forward tables |
| 20260606_0003 | 2026-06-06 | Tax mode to tenants |
| 20260608_0001 | 2026-06-08 | Missing invoice/bill columns |
| 20260609_0001 | 2026-06-09 | Row-level security policies |
| 20260609_0002 | 2026-06-09 | Contact credit balance |
| 20260615_0001 | 2026-06-15 | Multicurrency, recurring, terms templates |
| 20260622_0001 | 2026-06-22 | Fix RLS nullable tenant |

**Total: 24 migrations**

---

## Migration Safety

| Check | Status |
|-------|--------|
| All migrations have upgrade() | PASS |
| All migrations have downgrade() | PASS |
| PostgreSQL-only guards present | PASS |
| No data loss migrations | PASS |
| RLS policies included | PASS |
| Constraints added incrementally | PASS |

---

## Deployment Procedure

```bash
# 1. Backup database
pg_dump -U postgres bookkeeping > backup_$(date +%Y%m%d_%H%M%S).sql

# 2. Run migrations
docker compose exec backend alembic upgrade head

# 3. Verify
docker compose exec backend alembic current
```

---

## Rollback Procedure

```bash
# Rollback one migration
docker compose exec backend alembic downgrade -1

# Rollback to specific version
docker compose exec backend alembic downgrade 20260615_0001
```

---

## Indexes and Constraints

| Type | Count | Status |
|------|-------|--------|
| Primary keys | All tables | PASS |
| Foreign keys | All relationships | PASS |
| Unique constraints | tenant_id + document_number | PASS |
| Check constraints | amount > 0, direction IN | PASS |
| RLS policies | All tenant-scoped tables | PASS |
| Indexes | Hot query paths | PASS |
