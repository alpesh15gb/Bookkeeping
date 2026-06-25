# Release Blocker Fix — Balance Sheet PDF Export

**Date:** 2026-06-26
**Severity:** HIGH
**Status:** FIXED

---

## Root Cause

Three issues in `backend/src/api/v1/reports.py` and `backend/src/domains/printing/invoice_pdf.py`:

### Issue 1: Missing Imports in `reports.py`

`Tenant`, `BytesIO`, and `StreamingResponse` were not imported at the top level. Functions that used them locally worked, but `balance_sheet_excel` and `balance_sheet_pdf` did not have local imports.

**Error:** `NameError: name 'Tenant' is not defined`

### Issue 2: Data Structure Mismatch in PDF Generator

`BalanceSheetResponse.model_dump()` produces:
```python
{"assets": {"items": [...], "total": 100}, ...}
```

But `generate_balance_sheet_pdf()` expected:
```python
{"total_assets": 100, ...}
```

**Error:** Totals were always 0 because `data.get("total_assets")` returned `None`.

### Issue 3: Empty List Fallback Bug

When `items` was empty `[]`, the expression:
```python
[] or data.get("assets", [])
```
fell through to the dict, and iterating a dict yields string keys, causing:
```python
item.get("account_name")  # AttributeError: 'str' object has no attribute 'get'
```

---

## Fix Applied

### File: `backend/src/api/v1/reports.py`

Added top-level imports:
```python
from src.infrastructure.database.models import Tenant
from io import BytesIO
from fastapi.responses import StreamingResponse
```

### File: `backend/src/domains/printing/invoice_pdf.py`

1. Fixed sections to read from correct nested structure:
```python
assets_data = data.get("assets", {})
sections = [
    ("ASSETS", assets_data.get("items", []), float(assets_data.get("total", 0))),
    ...
]
```

2. Fixed item access to handle both dict and object:
```python
for item in items:
    if isinstance(item, dict):
        name = item.get("account_name", "")
        ...
    else:
        name = item.account_name
        ...
```

---

## Verification

| Test | Before | After |
|------|--------|-------|
| Balance Sheet PDF export | 500 error | 200 OK |
| Balance Sheet Excel export | 500 error | 200 OK |
| UAT suite | 44/46 | 46/46 |
| Full regression | 389/393 | 391/393 |
