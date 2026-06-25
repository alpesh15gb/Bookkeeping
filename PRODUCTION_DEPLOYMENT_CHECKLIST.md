# Production Deployment Checklist — ApexBooks v1.0

**Date:** 2026-06-26

---

## Pre-Deployment

- [x] All 283 existing tests pass
- [x] 46 UAT tests pass (44/46)
- [x] 64 integration sprint tests pass (62/64)
- [x] No Critical bugs
- [ ] Fix 2 HIGH bugs (report exports)
- [x] GST engine validated
- [x] Accounting engine validated
- [x] Multi-tenant isolation verified
- [x] RBAC permissions verified

---

## Environment Variables

- [ ] `DATABASE_URL` — PostgreSQL connection string
- [ ] `REDIS_URL` — Redis connection string
- [ ] `JWT_SECRET_KEY` — 32+ character secret
- [ ] `SECRET_KEY` — 32+ character secret
- [ ] `ALLOWED_ORIGINS` — CORS origins
- [ ] `SMTP_HOST/PORT/USER/PASSWORD` — Email config
- [ ] `S3_BUCKET/REGION/AWS_*` — File storage
- [ ] `IRP_*` — e-Invoice config

---

## Docker Deployment

- [ ] `docker compose build` succeeds
- [ ] `docker compose up -d` starts all services
- [ ] `alembic upgrade head` runs migrations
- [ ] Health check returns 200
- [ ] API endpoints accessible

---

## SSL/TLS

- [ ] SSL certificate configured
- [ ] HSTS header enabled
- [ ] HTTP → HTTPS redirect

---

## Database

- [ ] PostgreSQL 15+ running
- [ ] Connection pooling configured
- [ ] Backup schedule configured
- [ ] Restore procedure tested

---

## Monitoring

- [ ] Sentry DSN configured
- [ ] Error tracking active
- [ ] Log aggregation configured
- [ ] Health check endpoint monitored

---

## Post-Deployment

- [ ] Run smoke test: `python smoke_test.py`
- [ ] Verify registration flow
- [ ] Verify invoice creation
- [ ] Verify GST reports
- [ ] Verify PDF/Excel exports
- [ ] Monitor error rates for 24h
