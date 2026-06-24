# POST-DEPLOYMENT VERIFICATION
## Commit: c658ae9

**Date:** 2026-06-25
**Target:** https://api.apexbooks.in
**Status:** CI/CD PENDING — old code still deployed

---

## CI/CD Status

| Item | Status |
|------|--------|
| Commit pushed | `c658ae9` → master |
| CI/CD pipeline | **PENDING** — old code still running |
| Fix deployed | **NO** — `tax_mode` still defaults to `NON_GST` for new GSTIN registrations |

**Evidence:** Smoke test registers a new tenant with GSTIN `27AAAAA0967A1Z1`. Company endpoint returns `tax_mode = NON_GST`. This is the old behavior — the fix auto-detects `GST_REGULAR` from GSTIN.

---

## Production Smoke Test Results

**Total: 27/28 PASS, 1 FAIL**

### Test 1: Register WITHOUT GSTIN
| Check | Result |
|-------|--------|
| Registration succeeds | PASS |
| tax_mode = NON_GST | PASS |
| gstin = None | PASS |

### Test 2: Register WITH GSTIN
| Check | Result |
|-------|--------|
| Registration succeeds | PASS |
| tax_mode = GST_REGULAR | **FAIL** (got NON_GST — old code) |
| gstin matches input | PASS |

### Test 3: Create Product
| Check | Result |
|-------|--------|
| Product created | PASS |

### Test 4: Create Contacts
| Check | Result |
|-------|--------|
| Intrastate contact (MH) | PASS |
| Interstate contact (KA) | PASS |

### Test 5: Intrastate Invoice (POS=27, origin=27)
| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| CGST rate | 9% | 9% | PASS |
| CGST amount | ₹900 | ₹900 | PASS |
| SGST rate | 9% | 9% | PASS |
| SGST amount | ₹900 | ₹900 | PASS |
| IGST | ₹0 | ₹0 | PASS |
| Total | ₹11,800 | ₹11,800 | PASS |

### Test 6: Interstate Invoice (POS=29, origin=27)
| Check | Expected | Actual | Result |
|-------|----------|--------|--------|
| CGST | ₹0 | ₹0 | PASS |
| SGST | ₹0 | ₹0 | PASS |
| IGST rate | 18% | 18% | PASS |
| IGST amount | ₹1,800 | ₹1,800 | PASS |
| Total | ₹11,800 | ₹11,800 | PASS |

### Test 7: Financial Reports
| Check | Result |
|-------|--------|
| Trial Balance | PASS |
| Profit & Loss | PASS |
| Balance Sheet | PASS |

### Test 8: GSTR-1
| Check | Result |
|-------|--------|
| GSTR-1 returns 200 | PASS |
| B2B has entries | PASS |
| HSN summary has entries | PASS |

---

## Analysis

### Why GST calculations are correct despite old code

The `GSTEngine.resolve_gst_rate()` at `services.py:61-73` has auto-detection:

```python
if effective_mode == "NON_GST" and tenant.gstin and len(tenant.gstin) == 15:
    effective_mode = "GST_REGULAR"
```

This means even with the old code, tenants with a valid GSTIN get correct GST calculations. The fix ensures:
1. `tax_mode` is set correctly at registration (affects company endpoint response)
2. `TenantSetting` is created with `origin_state_code` and `gst_enabled`
3. No confusion between displayed tax_mode and actual GST behavior

### Regression Impact

No regressions found. All existing functionality works correctly.

---

## Pending Actions

1. **Wait for CI/CD to complete** — verify deployment on GitHub Actions
2. **Re-run smoke test after deployment** — confirm `tax_mode = GST_REGULAR` for new GSTIN registrations
3. **Clean up smoke test tenants** — delete test data created by smoke test

---

**Verification Date:** 2026-06-25
**Smoke Test Script:** `smoke_test.py`
**Deployment Version:** c658ae9 (pending)
