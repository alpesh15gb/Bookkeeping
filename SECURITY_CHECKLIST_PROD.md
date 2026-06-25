# Security Checklist — ApexBooks v1.0 Production

**Date:** 2026-06-26

---

## Authentication

| Check | Status |
|-------|--------|
| JWT tokens with expiry (15min access, 7d refresh) | PASS |
| bcrypt password hashing | PASS |
| Password strength enforcement (8+ chars, upper/lower/digit/special) | PASS |
| Account lockout on failed attempts | PASS |
| Token refresh mechanism | PASS |
| Token revocation on logout (Redis blacklist) | PASS |
| 2FA support (TOTP) | PASS |

---

## Authorization (RBAC)

| Role | Permissions Verified |
|------|---------------------|
| Owner | Full access to all endpoints | PASS |
| Accountant | Reports, ledger, invoices (no delete) | PASS |
| Salesperson | Contacts, invoices, payments (no ledger) | PASS |
| Auditor | Read-only access to all views | PASS |

---

## Multi-Tenant Isolation

| Check | Status |
|-------|--------|
| X-Tenant-ID header required | PASS |
| Membership verification on every request | PASS |
| All queries filter by tenant_id | PASS |
| PostgreSQL RLS policies on all tables | PASS |
| Cross-tenant access returns 403 | PASS |

---

## Input Validation

| Check | Status |
|-------|--------|
| Pydantic schema validation on all inputs | PASS |
| UUID format validation | PASS |
| Date format validation | PASS |
| Numeric range validation | PASS |
| String pattern validation (regex) | PASS |
| SQL injection prevention (SQLAlchemy ORM) | PASS |

---

## Rate Limiting

| Endpoint | Limit | Status |
|----------|-------|--------|
| Login | 10/minute | PASS |
| Register | 5/minute | PASS |
| Reports | 60/minute | PASS |
| Default | 200/minute | PASS |

---

## Transport Security

| Check | Status |
|-------|--------|
| TLS 1.2/1.3 | PASS |
| HSTS enabled (max-age=63072000) | PASS |
| X-Frame-Options: DENY | PASS |
| X-Content-Type-Options: nosniff | PASS |
| HTTP → HTTPS redirect | PASS |

---

## Secrets Management

| Secret | Storage | Status |
|--------|---------|--------|
| JWT_SECRET_KEY | Environment variable | PASS |
| SECRET_KEY | Environment variable | PASS |
| DB_PASSWORD | Environment variable | PASS |
| AWS_SECRET_ACCESS_KEY | Environment variable | PASS |
| IRP_PASSWORD | Environment variable | PASS |
| SMTP_PASSWORD | Environment variable | PASS |

**Note:** No secrets hardcoded in source code.

---

## Audit Logging

| Check | Status |
|-------|--------|
| All mutations logged | PASS |
| before_state/after_state captured | PASS |
| Actor ID recorded | PASS |
| IP address recorded | PASS |
| Soft-delete preserves records | PASS |
