# Performance Benchmark — ApexBooks v1.0

**Date:** 2026-06-26
**Environment:** Local test (SQLite, no Redis)

---

## Benchmark Results

| Endpoint | Response Time | Threshold | Status |
|----------|--------------|-----------|--------|
| POST /auth/login | < 1s | 5s | PASS |
| GET /dashboard/metrics | ~8s | 15s | PASS |
| POST /invoices | < 1s | 5s | PASS |
| GET /reports/trial-balance | < 1s | 5s | PASS |
| GET /reports/balance-sheet | < 1s | 5s | PASS |
| GET /invoices (paginated) | < 1s | 5s | PASS |
| POST /invoices (50 bulk) | < 120s | 120s | PASS |

---

## Production Optimization Notes

1. **Dashboard** is the slowest endpoint due to multiple aggregation queries. Redis caching will improve this significantly in production.

2. **Report generation** uses complex SQL with JOINs and GROUP BY. PostgreSQL query planner will optimize these better than SQLite.

3. **Invoice creation** includes GST calculation + ledger posting in a single transaction. Performance is acceptable.

---

## Recommendations

| Priority | Recommendation |
|----------|---------------|
| High | Enable Redis caching for dashboard metrics |
| Medium | Add database connection pooling (pgbouncer) |
| Medium | Monitor slow queries in production |
| Low | Add query result caching for static reports |
