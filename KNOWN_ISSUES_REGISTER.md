# Known Issues Register — ApexBooks v1.0

**Date:** 2026-06-26
**Total Issues:** 6 (0 Critical, 2 High, 2 Medium, 2 Low)

---

## Critical: None

---

## High

### KI-001: Balance Sheet Excel Export — NameError

**File:** `backend/src/api/v1/reports.py:517`
**Error:** `NameError: name 'BytesIO' is not defined`
**Impact:** Balance sheet Excel export returns 500
**Fix:** Add `from io import BytesIO` to top-level imports
**Status:** FIXED in this sprint

### KI-002: Balance Sheet PDF Export — AttributeError

**File:** `backend/src/api/v1/reports.py:594`
**Error:** `AttributeError: 'str' object has no attribute 'get'`
**Impact:** Balance sheet PDF export returns 500
**Root Cause:** PDF generator expects dict but receives string from model_dump()
**Status:** Needs fix

---

## Medium

### KI-003: `/api/v1/search` Endpoint Not Registered

**Impact:** Global search feature unavailable
**Workaround:** Use individual module list endpoints
**Status:** Documented

### KI-004: `GET /financial-years/{fy_id}` Endpoint Missing

**Impact:** Cannot fetch single FY by ID
**Workaround:** Use `/financial-years/current` or `/financial-years/{fy_id}/dashboard`
**Status:** Documented

---

## Low

### KI-005: Pydantic Deprecation Warnings

**Impact:** 64 warnings in test suite
**Details:** `min_items` deprecated, should use `min_length`
**Status:** Cosmetic

### KI-006: `datetime.utcnow()` Deprecated

**Impact:** 2 test files use deprecated function
**Details:** Should use `datetime.now(timezone.utc)`
**Status:** Cosmetic
