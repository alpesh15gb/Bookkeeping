# API Health Report — ApexBooks

**Date:** 2026-06-26
**Scope:** All API endpoints, request validation, response schemas

---

## Summary

The API layer is **healthy**. All tested endpoints return consistent JSON. Request validation works correctly. Error responses use appropriate HTTP status codes.

---

## Endpoint Inventory

### Auth (`/api/v1/auth`) — 13 endpoints

| Endpoint | Method | Status | Notes |
|----------|--------|--------|-------|
| /register | POST | PASS | Auto-detects tax_mode from GSTIN |
| /login | POST | PASS | Returns JWT access + refresh tokens |
| /refresh | POST | PASS | Token refresh working |
| /logout | POST | PASS | Revokes refresh token |
| /me | GET | PASS | Returns current user |
| /memberships | GET | PASS | Lists tenant memberships |
| /change-password | POST | PASS | Password strength enforced |
| /forgot-password | POST | PASS | Sends reset token |
| /reset-password | POST | PASS | Token-based reset |
| /verify-email | POST | PASS | Email verification |
| /2fa/enable | POST | PASS | TOTP setup |
| /2fa/verify | POST | PASS | TOTP verification |
| /2fa/disable | POST | PASS | 2FA removal |

### Masters (`/api/v1/masters`) — 12 endpoints

| Endpoint | Method | Status |
|----------|--------|--------|
| /contacts | POST | PASS |
| /contacts | GET | PASS |
| /contacts/{id} | GET | PASS |
| /contacts/{id} | PUT | PASS |
| /contacts/{id} | DELETE | PASS |
| /products | POST | PASS |
| /products | GET | PASS |
| /products/{id} | GET | PASS |
| /products/{id} | PUT | PASS |
| /products/{id} | DELETE | PASS |
| /accounts | GET | PASS |
| /banking-profiles | GET | PASS |

### Invoices (`/api/v1/invoices`) — 18 endpoints

All CRUD operations, payment recording, cancellation, PDF generation, e-Invoice, credit/debit notes verified.

### Reports (`/api/v1/reports`) — 20+ endpoints

Trial balance, balance sheet, P&L, cash flow, aging, outstanding, GST reports, party statements — all verified.

### Financial Years (`/api/v1/financial-years`) — 8 endpoints

Create, list, switch, current, close, reopen, dashboard, audit trail — all verified.

---

## Response Schema Consistency

| Response Type | Schema | Consistent |
|--------------|--------|-----------|
| Invoice | InvoiceResponse | Yes |
| Contact | ContactResponse | Yes |
| Product | ProductResponse | Yes |
| Expense | ExpenseResponse | Yes |
| Journal Entry | JournalEntryResponse | Yes |
| Trial Balance | TrialBalanceResponse | Yes |
| Balance Sheet | BalanceSheetResponse | Yes |
| GSTR-1 | GSTR1Response | Yes |
| GSTR-2 | GSTR2Response | Yes |

---

## Pagination

- Invoice list supports `page` and `limit` parameters
- Default: page=1, limit=50
- Max limit: 100

**Test:** `test_invoice_pagination` — PASS

---

## Missing Endpoints

| Endpoint | Status |
|----------|--------|
| GET /api/v1/search | NOT REGISTERED (documented but missing) |
| GET /api/v1/financial-years/{fy_id} | NOT REGISTERED (list and current exist) |

---

## Error Response Format

All errors return consistent JSON:
```json
{
  "detail": "Human-readable error message"
}
```

Status codes used correctly:
- 400: Business logic errors (duplicate number, unbalanced journal)
- 401: Authentication failures
- 403: Authorization failures
- 404: Resource not found
- 422: Validation errors (Pydantic, period lock)
- 500: Internal server errors (should not occur in production)
