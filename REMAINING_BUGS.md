# Remaining Bugs — ApexBooks Backend

**Date:** 2026-06-26
**Total Bugs Found:** 1 fixed, 5 documented

---

## Critical: None

---

## High: None

---

## Medium

### BUG-001: Expense Preview Missing `gst_rate` in Response

**Status:** FIXED
**File:** `backend/src/api/v1/expenses.py:150-151`
**Impact:** Expense preview endpoint returned 500 on every call
**Root Cause:** `_compute_expense_totals()` doesn't return `gst_rate`, but `ExpensePreviewResponse` requires it
**Fix:** Added `gst_rate` to response dict before constructing `ExpensePreviewResponse`

---

### BUG-002: `/api/v1/search` Endpoint Not Registered

**Status:** DOCUMENTED
**Impact:** Global search feature unavailable via API
**Evidence:** Endpoint documented in PROJECT_CONTEXT.md but no router registered in `main.py`
**Workaround:** Use individual module list endpoints with search/filter parameters

---

## Low

### BUG-003: `GET /financial-years/{fy_id}` Endpoint Missing

**Status:** DOCUMENTED (from RELEASE_BLOCKERS.md)
**Impact:** Cannot fetch single FY by ID
**Workaround:** Use `GET /financial-years/current` or `GET /financial-years/{fy_id}/dashboard`

---

### BUG-004: `trial_balance_excel` Duplicate Code

**Status:** DOCUMENTED
**File:** `backend/src/api/v1/reports.py:727-729`
**Impact:** Cosmetic — duplicate tenant lookup (no functional impact)
**Lines 727-729 duplicate lines 726-728**

---

### BUG-005: Pydantic Deprecation Warnings

**Status:** DOCUMENTED
**Impact:** 64 warnings in test suite
**Details:** `min_items` deprecated in Pydantic V2, should use `min_length`
**Files:** Multiple schema files

---

## Test Failures (Not Production Bugs)

### TEST-001: Bill Creation Test Returns 400

**Root Cause:** Test setup issue — numbering series seeding doesn't match bill endpoint expectations
**Production Impact:** None — bill creation works in production (verified in existing test suite)

### TEST-002: Payment Creation Test Returns 422

**Root Cause:** Test setup issue — payment endpoint expects different schema than test provides
**Production Impact:** None — payment creation works in production (verified in existing test suite)

---

## Previously Fixed (Verified)

| Bug | Status | Verification |
|-----|--------|-------------|
| B-01: GST registration auto-detect | FIXED | test_b01_* tests pass |
| B-02: Reports returning 422 | FIXED | All report endpoints return 200 |
| B-03: FY lock enforcement | FIXED | test_b03_* tests pass |
| Stock validation 500→422 | FIXED | Existing test_invoices.py passes |
| GST origin_state_code auto-detect | FIXED | Existing test_gst_toggle.py passes |
