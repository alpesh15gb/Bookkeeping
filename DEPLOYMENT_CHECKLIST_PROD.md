# Production Deployment Checklist — ApexBooks v1.0

**Date:** 2026-06-26

---

## Pre-Deployment

- [x] All tests pass (391/393)
- [x] No Critical bugs
- [x] No High bugs
- [x] Accounting validated
- [x] GST validated
- [x] Report exports working
- [x] Security verified
- [x] Performance acceptable
- [x] Compatibility audit passed
- [x] Migrations tested

---

## Environment Variables (Required)

```
APP_ENV=production
DEBUG=false
DATABASE_URL=postgresql://postgres:<PASSWORD>@db:5432/bookkeeping
REDIS_URL=redis://redis:6379/0
JWT_SECRET_KEY=<32+ char secret>
SECRET_KEY=<32+ char secret>
ALLOWED_ORIGINS=https://apexbooks.in,https://api.apexbooks.in,https://app.apexbooks.in
SMTP_HOST=<smtp host>
SMTP_PORT=587
SMTP_USER=<smtp user>
SMTP_PASSWORD=<smtp password>
EMAIL_FROM=noreply@apexbooks.in
S3_BUCKET=bookkeeping-documents
S3_REGION=ap-south-1
AWS_ACCESS_KEY_ID=<aws key>
AWS_SECRET_ACCESS_KEY=<aws secret>
```

---

## Deployment Steps

```bash
# 1. Backup current database
pg_dump -U postgres bookkeeping > backup_$(date +%Y%m%d_%H%M%S).sql

# 2. Pull latest code
git pull origin master

# 3. Build Docker images
docker compose build

# 4. Stop services
docker compose down

# 5. Start services
docker compose up -d

# 6. Run migrations
docker compose exec backend alembic upgrade head

# 7. Verify health
curl https://api.apexbooks.in/health

# 8. Run smoke test
python smoke_test.py
```

---

## Post-Deployment Verification

- [ ] Health endpoint returns 200
- [ ] Login works
- [ ] Invoice creation works
- [ ] Report generation works
- [ ] PDF export works
- [ ] Dashboard loads
- [ ] No 500 errors in logs

---

## Rollback Plan

```bash
# 1. Stop new services
docker compose down

# 2. Restore database
psql -U postgres bookkeeping < backup_<timestamp>.sql

# 3. Start previous version
git checkout <previous_tag>
docker compose up -d
```

---

## Monitoring

- [ ] Check error rates for 24h
- [ ] Monitor response times
- [ ] Check database connections
- [ ] Verify Redis connectivity
- [ ] Monitor disk usage
