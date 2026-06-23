# Backend Deployment Required - P0/P1/P2 Blockers

## Problem Status
**ALL P0/P1/P2 BLOCKERS STILL ACTIVE** - Production backend returning 500 errors on critical endpoints.

## Root Cause
The backend code fixes (commit `e41ac15` from June 23, 14:28) have **NOT been deployed** to production at `api.apexbooks.in`.

The production server is running an outdated version of the code that still contains all the original bugs.

## Evidence

### Code Fixed Locally (Commit: e41ac15)
Commit message: "fix backend bugs: deps early context set, product delete, current fy logic, settings and preview schema validation"

Files changed:
- `backend/alembic/versions/20260622_0001_fix_rls_nullable_tenant.py`
- `backend/src/api/deps.py`
- `backend/src/api/v1/auth.py`
- `backend/src/api/v1/companies.py` (settings endpoints)
- `backend/src/api/v1/financial_years.py`
- `backend/src/api/v1/invoices.py` (preview endpoint)
- `backend/src/api/v1/masters.py`
- `backend/src/schemas/company_schemas.py`
- `backend/src/schemas/document.py`

### Production Still Broken (Tested 2026-06-23 19:00 UTC)
All critical endpoints return HTTP 500:

```
✅ GET  /health                              → 200 OK (server is running)
✅ POST /api/v1/auth/register                → 201 OK (auth works)
✅ POST /api/v1/auth/login                   → 200 OK (auth works)
❌ GET  /api/v1/settings                      → 500 INTERNAL_SERVER_ERROR
❌ PUT  /api/v1/settings                      → 500 INTERNAL_SERVER_ERROR
❌ POST /api/v1/invoices/preview              → 500 INTERNAL_SERVER_ERROR
❌ GET  /api/v1/gst/gstr1                     → 500 INTERNAL_SERVER_ERROR
❌ GET  /api/v1/reports/trial-balance/excel   → 500 INTERNAL_SERVER_ERROR
❌ GET  /api/v1/reports/trial-balance/pdf     → 500 INTERNAL_SERVER_ERROR
```

**Note**: Some endpoints like `/invoices` and `/expenses` return 422 (validation errors) instead of 500, which means they're working but rejecting empty payloads. This is expected behavior.

## Deployment Checklist

### 1. Pre-Deployment
- [ ] Verify current production commit hash
- [ ] Backup production database
- [ ] Confirm migration status

### 2. Deploy Backend Code
```bash
# On production server
cd /path/to/Bookkeeping
git fetch origin
git checkout e41ac15  # Or pull latest master if it's the same

# Install dependencies
cd backend
pip install -r requirements.txt

# Run migrations
alembic upgrade head

# Restart backend service
# (depends on deployment: systemd, docker, etc.)
systemctl restart apexbooks-backend
# OR
docker-compose restart backend
```

### 3. Post-Deployment Verification
Test all previously failing endpoints:

```bash
# Get auth token
TOKEN=$(curl -s -X POST https://api.apexbooks.in/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"<test-user>","password":"<password>"}' | jq -r '.access_token')

TENANT="<tenant-uuid>"

# Test all P0/P1/P2 endpoints
curl -s https://api.apexbooks.in/api/v1/settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT"

curl -s -X PUT https://api.apexbooks.in/api/v1/settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT" \
  -H "Content-Type: application/json" \
  -d '{"currency":"INR"}'

curl -s -X POST https://api.apexbooks.in/api/v1/invoices/preview \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT" \
  -H "Content-Type: application/json" \
  -d '{"pos_state_code":"27","line_items":[]}'

curl -s "https://api.apexbooks.in/api/v1/gst/gstr1?from_date=2026-04-01&to_date=2026-06-30" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT"

curl -s "https://api.apexbooks.in/api/v1/reports/trial-balance/excel?financial_year_id=2026" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Tenant-ID: $TENANT"
```

Expected: All should return 200 OK (or appropriate success codes)

### 4. Rollback Plan
If deployment fails:
```bash
git checkout <previous-commit>
systemctl restart apexbooks-backend
```

## Impact
- **Frontend development is BLOCKED** until these endpoints work
- **All P0 (5 endpoints), P1 (3 endpoints), and P2 (14 endpoints) remain unresolved**
- Investment烈士陵园
- Backend team needs to deploy ASAP

## Contact
Backend deployment responsibility: [Assign to backend team member]