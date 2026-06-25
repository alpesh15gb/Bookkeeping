# Security Report — ApexBooks

**Date:** 2026-06-26
**Scope:** Authentication, authorization, tenant isolation, input validation

---

## Summary

The security posture is **strong**. JWT authentication, RBAC authorization, and multi-tenant isolation are all properly implemented and verified.

---

## Authentication

### JWT Token Validation

| Test | Result |
|------|--------|
| Invalid token rejected (401) | PASS |
| Expired token rejected (401) | PASS |
| Refresh token rejected as access token (401) | PASS |
| Missing token rejected (401) | PASS |

### Token Structure

- Access token: 15-minute expiry, contains `sub` (user_id), `type` (access), `scopes`
- Refresh token: 7-day expiry, contains `sub`, `type` (refresh)
- Algorithm: HS256 (configurable via `JWT_ALGORITHM`)
- Secret key: 32+ characters (enforced in production)

### Password Security

- Bcrypt hashing with automatic salt generation
- Minimum 8 characters, uppercase, lowercase, digit, special character
- Account lockout after failed attempts (configurable)

**Test:** `test_password_strength_enforced` — PASS

---

## Authorization (RBAC)

### Role Permissions

| Role | Create Invoice | View Ledger | Manage Accounts | Create Payment |
|------|---------------|-------------|-----------------|----------------|
| owner | Yes | Yes | Yes | Yes |
| accountant | No | Yes | Yes | Yes |
| salesperson | Yes | No | No | Yes |
| auditor | No | Yes | No | No |

### Verified Scenarios

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| Auditor cannot create invoice | 403 | 403 | PASS |
| Salesperson cannot access ledger | 403 | 403 | PASS |
| Owner can do everything | 200/201 | 200/201 | PASS |

---

## Multi-Tenant Isolation

### Mechanism

1. `X-Tenant-ID` header required on all tenant-scoped endpoints
2. `enforce_permission()` dependency verifies user has active membership in target tenant
3. All database queries filter by `tenant_id`
4. PostgreSQL RLS policies enforce at database level (production)

### Verified Scenarios

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| Cross-tenant GET denied | 403 | 403 | PASS |
| Cross-tenant PUT denied | 403 | 403 | PASS |
| Cross-tenant DELETE denied | 403 | 403 | PASS |
| Cross-tenant LIST returns empty | 200 (empty) | 200 (empty) | PASS |
| Tenant data isolated in queries | No leakage | No leakage | PASS |

**Test:** `test_tenant_isolation_enforced` — PASS

---

## Input Validation

- All request bodies validated by Pydantic schemas
- UUID fields validated for format
- Date fields validated for format and range
- Numeric fields validated for range (gt, ge, le)
- String fields validated for pattern (regex)
- SQL injection prevented by SQLAlchemy parameterized queries

---

## Rate Limiting

- Login endpoint: rate-limited (configurable)
- Registration endpoint: rate-limited
- Default API endpoints: rate-limited
- Implementation: slowapi with Redis backend

**Note:** Rate limiting disabled in test environment.

---

## Audit Logging

- All significant actions logged to `audit_logs` table
- Fields: action, entity_type, entity_id, before_state, after_state, actor_id, ip_address
- Audit trail preserved even for soft-deleted records

**Test:** `test_audit_log_model_works` — PASS

---

## Recommendations

| Priority | Recommendation |
|----------|---------------|
| High | Add Sentry error tracking (SENTRY_DSN configured but not wired) |
| Medium | Add comprehensive rate limiting per tenant |
| Medium | Add file upload validation for document uploads |
| Low | Add CSP headers hardening |
| Low | Add API request signing for mobile clients |
