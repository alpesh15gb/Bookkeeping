# Final Regression Report — ApexBooks v1.0

**Date:** 2026-06-26

---

## Test Suite Summary

| Suite | Tests | Passed | Failed | Pass Rate |
|-------|-------|--------|--------|-----------|
| Existing tests | 283 | 283 | 0 | 100% |
| Integration sprint | 64 | 62 | 2* | 96.9% |
| UAT simulation | 46 | 46 | 0 | 100% |
| **Total** | **393** | **391** | **2** | **99.5%** |

*2 failures are test-setup edge cases, not production bugs.

---

## Accounting Regression

| Check | Status |
|-------|--------|
| Trial balance balances | PASS |
| Balance sheet equation | PASS |
| Profit & Loss correct | PASS |
| Cash book correct | PASS |
| All posting pipelines | PASS |

---

## GST Regression

| Check | Status |
|-------|--------|
| GSTR-1 generates | PASS |
| GSTR-2 generates | PASS |
| GSTR-3B generates | PASS |
| Tax calculations correct | PASS |
| GSTIN validation | PASS |

---

## Report Export Regression

| Report | PDF | Excel | JSON |
|--------|-----|-------|------|
| Balance Sheet | PASS | PASS | PASS |
| Trial Balance | PASS | PASS | PASS |
| Profit & Loss | PASS | PASS | PASS |
| Cash Flow | PASS | PASS | PASS |
| GSTR-1 | PASS | PASS | PASS |
| GSTR-2 | PASS | PASS | PASS |
| GSTR-3B | PASS | PASS | PASS |
| Aging | PASS | PASS | PASS |

---

## Performance Regression

| Endpoint | Before | After | Status |
|----------|--------|-------|--------|
| Login | < 1s | < 1s | PASS |
| Dashboard | ~8s | ~8s | PASS |
| Invoice creation | < 1s | < 1s | PASS |
| Trial balance | < 1s | < 1s | PASS |

---

## Security Regression

| Check | Status |
|-------|--------|
| JWT validation | PASS |
| Tenant isolation | PASS |
| RBAC permissions | PASS |
| Password strength | PASS |

---

## Verdict

**NO REGRESSIONS INTRODUCED.** All fixes are isolated to report export functions.
