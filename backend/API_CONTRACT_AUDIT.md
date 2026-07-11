# API Contract Audit

**Date**: 2026-06-24  
**Auditor**: Backend Team  
**Status**: All 276 tests passing (20 new + 256 existing)

---

## 1. Breaking Changes Found & Fixed

### P0-1: Financial Year Lock Not Enforced (CRITICAL)

**File**: `backend/src/domains/accounting/period_lock.py`

**Bug**: `validate_period_open()` checked for `READY_TO_CLOSE` and `AccountingPeriod.is_closed` but did NOT check `FinancialYear.status == "LOCKED"` or `"ARCHIVED"`. The FY lock was only indirectly enforced via `AccountingPeriod.is_closed`, which is created during the close operation. If the AccountingPeriod record was missing or not synced, locked FYs could accept new postings.

**Fix**: Added explicit check for `FinancialYear.status in ("LOCKED", "ARCHIVED")` that blocks ALL posting operations (invoices, bills, expenses, journal entries) when the entry_date falls within a locked/archived FY period.

**Impact**: All posting entry points (`create_invoice`, `create_bill`, `create_expense`, `create_journal_entry`, `create_credit_note`, `create_debit_note`) are now protected.

### P0-2: Pydantic v1 Deprecation — `.dict()` → `.model_dump()`

**Files**:
- `backend/src/api/v1/masters.py:67-68` — `ContactCreate.billing_address.dict()`
- `backend/src/api/v1/companies.py:257` — `BranchCreate.address.dict()`

**Bug**: Using deprecated Pydantic v1 `.dict()` method. Will break when Pydantic v3 removes it.

**Fix**: Replaced with `.model_dump()` (Pydantic v2).

### P0-3: Pydantic v1 `@validator` → `@field_validator`

**File**: `backend/src/api/v1/expenses.py:6,39-43`

**Bug**: `BulkDeleteRequest` used deprecated `@validator` (Pydantic v1 style).

**Fix**: Changed to `@field_validator` with `@classmethod` decorator and updated import from `validator` to `field_validator`.

### P0-4: Duplicate Exception Handler in Expense Creation

**File**: `backend/src/api/v1/expenses.py:206-211`

**Bug**: Two identical `except Exception as e:` blocks stacked — the second was dead code.

**Fix**: Removed the duplicate.

---

## 2. Schema Validation (Confirmed Correct — No Changes Needed)

### Contact Creation (`ContactCreate` in `master_schemas.py`)

Required fields:
| Field | Type | Validation |
|-------|------|-----------|
| `name` | str | max_length=150 |
| `contact_type` | str | `CUSTOMER\|VENDOR\|BOTH` |
| `registration_type` | str | `REGULAR\|COMPOSITION\|SEZ\|UNREGISTERED\|CONSUMER` |
| `billing_address` | AddressSchema | `{street, city, state, state_code, pincode, country?}` |
| `state_code` | str | 2-digit state code |

Optional: `email`, `phone`, `gstin`, `pan`, `shipping_address`

**Result**: Schema correctly validates with test payloads. HTTP 422 only returned for invalid data (as expected).

### Product Creation (`ProductCreate` in `master_schemas.py`)

Required fields: `name`, `sku`, `hsn_sac`, `product_type`, `uom`, `sales_price`, `purchase_price`, `gst_rate`

Optional: `min_stock`, `reorder_level`

**Result**: Schema is correct and consistent with tests.

---

## 3. Account Type Mapping

The API uses 5 standard account types: `ASSET`, `LIABILITY`, `EQUITY`, `REVENUE`, `EXPENSE`

| Category | Standard Types | Account Groups |
|----------|---------------|----------------|
| GST Input Tax | ASSET | Input Tax Credit (codes 1401-1405) |
| GST Output Tax | LIABILITY | GST Output (codes 3001-3005) |
| Cash & Bank | ASSET | Cash & Bank (codes 1001-1005) |
| Revenue | REVENUE | Sales, Other Income |
| Expenses | EXPENSE | COGS, Direct, Admin, Selling, Financial |

**Note**: The old validation scripts expected `BANK`, `CASH`, `GST_OUTPUT`, `GST_INPUT` as account types. The API has always used `ASSET`/`LIABILITY` with `account_group` for finer classification. Validation scripts must use the correct types.

---

## 4. Failed Endpoint List (Pre-Fix → Post-Fix)

| Endpoint | Pre-Fix Status | Post-Fix Status | Root Cause |
|----------|---------------|-----------------|------------|
| `POST /api/v1/accounting/journals` (locked FY) | **200 OK** (BUG: allowed) | **422 Blocked** | Missing LOCKED status check |
| `POST /api/v1/invoices` (locked FY) | **201 Created** (BUG) | **422 Blocked** | Missing LOCKED status check |
| `POST /api/v1/bills` (locked FY) | **201 Created** (BUG) | **422 Blocked** | Missing LOCKED status check |
| `POST /api/v1/expenses` (locked FY) | **201 Created** (BUG) | **422 Blocked** | Missing LOCKED status check |
| `POST /api/v1/masters/contacts` | **201 OK** ✓ | 201 OK | No issue |
| `POST /api/v1/masters/products` | **201 OK** ✓ | 201 OK | No issue |
| `DELETE /api/v1/masters/contacts/{id}` | **204 OK** ✓ | 204 OK | No issue |
| `GET /api/v1/accounting/trial-balance` | **200 OK** ✓ | 200 OK | Schema has `total_debits`, `total_credits` |
| `GET /api/v1/reports/trial-balance` | **200 OK** ✓ | 200 OK | Schema has `total_debits`, `total_credits` |

---

## 5. Trial Balance Response Contract

### `/api/v1/accounting/trial-balance` (accounting_schemas.py)

```json
{
  "lines": [...],
  "total_opening_debits": "0.00",
  "total_opening_credits": "0.00",
  "total_debits": "0.00",
  "total_credits": "0.00",
  "total_closing_debits": "0.00",
  "total_closing_credits": "0.00"
}
```

### `/api/v1/reports/trial-balance` (report_schemas.py)

```json
{
  "as_of_date": "2026-03-31",
  "lines": [...],
  "total_debits": "0.00",
  "total_credits": "0.00",
  "is_balanced": true
}
```

Both endpoints guarantee `total_debits` and `total_credits` in every response.

---

## 6. Delete Endpoint Contract

All delete endpoints return:
- **HTTP 204 No Content** with empty body
- **No JSON payload** — clients MUST NOT call `.json()` on 204 responses

Verified endpoints:
- `DELETE /api/v1/masters/contacts/{id}`
- `DELETE /api/v1/masters/products/{id}`
- `DELETE /api/v1/masters/accounts/{id}`
- `DELETE /api/v1/masters/banking-profiles/{id}`
- `DELETE /api/v1/masters/expense-categories/{id}`

---

## 7. Validation Results

```
pytest: 276 passed, 77 warnings in 253.85s (0:04:13)
```

New tests added: 20 (in `tests/test_api_contract_validation.py`)
- 4 contact schema tests
- 3 product schema tests
- 2 FY lock enforcement tests
- 4 CRUD delete tests
- 3 trial balance contract tests
- 2 journal posting consistency tests
- 2 account type mapping tests
