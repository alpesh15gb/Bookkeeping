# Backend Bug Report — Confirmed 500 Errors

**Date**: 2026-06-23  
**Tested Against**: `api.apexbooks.in` (production)  
**Status**: Deployed code has runtime bugs

---

## Executive Summary

The backend **IS deployed** but has **specific code bugs** in 3 endpoints that return HTTP 500 even with valid payloads.

**Not a deployment issue** — other endpoints work perfectly (GSTR2, Balance Sheet, Financial Years, Products, Contacts).

---

## Confirmed 500 Errors (Reproducible)

### 1. GET/PUT /api/v1/settings ❌

```bash
GET /api/v1/settings → 500
PUT /api/v1/settings → 500
GET /api/v1/settings/series → 200 ✅
```

**Pattern**: Settings serialization broken, but numbering series works.

**Suspected Issue**: `display_settings` or `extra_settings` JSON column serialization failure in `TenantSettingResponse` schema.

**File**: `backend/src/api/v1/companies.py` - `get_settings()` / `update_settings()`

---

### 2. GET /api/v1/gst/gstr1 ❌

```bash
GET /gst/gstr1?from_date=2026-04-01&to_date=2026-06-30 → 500
GET /gst/gstr2?from_date=2026-04-01&to_date=2026-06-30 → 200 ✅
GET /gst/gstr3b → 404 (route doesn't exist)
```

**Pattern**: GSTR1 specifically broken, GSTR2 works fine.

**Suspected Issue**: Query logic in `get_gstr1_report()` has unhandled exception (possibly division by zero, None access, or missing invoice data handling).

**File**: `backend/src/api/v1/gst.py` - `get_gstr1_report()`

---

### 3. GET /api/v1/reports/trial-balance/excel ❌
### 4. GET /api/v1/reports/trial-balance/pdf ❌

```bash
GET /reports/trial-balance → 200 ✅ (JSON works)
GET /reports/trial-balance/excel → 500
GET /reports/trial-balance/pdf → 500
```

**Pattern**: JSON response works, Excel/PDF exports crash.

**Suspected Issue**: 
- `openpyxl` or `reportlab` import error
- File I/O issue in export functions
- NoneType access during Excel/PDF generation

**Files**: 
- `backend/src/api/v1/reports.py` - `trial_balance_excel()` / `trial_balance_pdf()`
- `backend/src/domains/printing/invoice_pdf.py` - `generate_trial_balance_pdf()`

---

### 5. POST /api/v1/invoices/preview ❌

```bash
POST /invoices/preview (with valid product_id) → 500
POST /invoices (with valid data) → Works ✅
```

**Pattern**: Invoice creation works, preview calculation crashes.

**Suspected Issue**: Division by zero, tax calculation error, or None access in preview logic.

**File**: `backend/src/api/v1/invoices.py` - preview endpoint

---

### 6. POST /api/v1/expenses ❌

```bash
POST /expenses (with valid category) → 500
GET /masters/expense-categories → 200 ✅
```

**Pattern**: Can read categories, can't create expenses.

**Suspected Issue**: Expense creation service has bug (ledger entry creation? account resolution?)

**File**: `backend/src/api/v1/expenses.py` or `backend/src/domains/accounting/services.py`

---

## What DOES Work (Proof of Partial Deployment)

✅ POST /masters/products — 201  
✅ GET /masters/products — 200  
✅ GET /masters/expense-categories — 200  
✅ GET /financial-years — 200  
✅ POST /financial-years — 201  
✅ GET /invoices — 200  
✅ POST /invoices — 201  
✅ GET /expenses — 200  
✅ GET /gst/gstr2 — 200  
✅ GET /reports/balance-sheet — 200  
✅ GET /reports/trial-balance — 200 (JSON)  
✅ GET /settings/series — 200  

---

## Root Cause

**NOT a deployment failure** — code IS deployed, but has **runtime bugs** in:

1. **JSON serialization** — `TenantSetting` model with `display_settings` / `extra_settings` columns
2. **Export libraries** — `openpyxl`/`reportlab` usage in Excel/PDF generation
3. **Report queries** — GSTR1 specific query logic
4. **Preview calculation** — Invoice preview math/logic
5. **Expense creation** — Service layer bug

---

## Required Fixes

### Priority 1: Settings (Blocks all configuration)
```python
# backend/src/api/v1/companies.py
# Fix: Handle None/null for display_settings and extra_settings
# Check: Pydantic v2 field_validator for JSON columns
```

### Priority 2: Invoice Preview (Blocks invoicing workflow)
```python
# backend/src/api/v1/invoices.py
# Fix: Add try/except around preview calculation
# Add: Logging to capture the actual exception
```

### Priority 3: GSTR1 Report (Blocks GST compliance)
```python
# backend/src/api/v1/gst.py
# Fix: Handle edge cases in GSTR1 query (no invoices, zero tax, etc.)
# Add: Logging for debug
```

### Priority 4: Export Functions (Blocks report downloads)
```python
# backend/src/api/v1/reports.py
# backend/src/domains/printing/invoice_pdf.py
# Fix: Verify openpyxl/reportlab imports and file handling
# Add: Better error handling with specific error messages
```

### Priority 5: Expense Creation
```python
# backend/src/api/v1/expenses.py
# Fix: Account resolution or ledger entry creation logic
```

---

## Test Credentials (for validation)

```
Email: test_user_3@apexbooks.in
Password: Test1234!
Tenant: 6dfced8a-c8a2-405a-9011-9a87a8407bed (auto-created on signup)
```

Or create new tenant:
```bash
curl -X POST https://api.apexbooks.in/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "new@test.com",
    "password": "Test1234!",
    "full_name": "Test",
    "company_legal_name": "Test Co",
    "company_gstin": "27AABCT1234R1Z5"
  }'
```

---

## Verification Steps for Backend Team

1. **Run server in debug mode** with stacktrace logging enabled
2. **Reproduce each 500** and capture full stacktrace
3. **Fix the specific exception** in each endpoint
4. **Deploy and re-test** with the payloads above
5. **Verify error messages return 400/422** instead of 500

---

## Frontend Impact

🔴 **BLOCKED** — Cannot build:
- Settings page (can't read/write settings)
- Invoice preview modal
- Expense creation form
- GSTR1 report view
- Report export buttons (Excel/PDF)

**Frontend development gate: NOT MET**