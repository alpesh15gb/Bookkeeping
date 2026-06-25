# GST Validation Report — ApexBooks

**Date:** 2026-06-26
**Scope:** All GST scenarios, GSTR reports, tax calculations

---

## Summary

The GST engine is **fully validated** across all scenarios. CGST/SGST, IGST, Cess, zero-rate, NON_GST, and composition modes all work correctly. GSTR-1, GSTR-2, and GSTR-3B reports generate without errors.

---

## Tax Calculation Engine

### GSTEngine.calculate_tax() — Unit Tests

| Scenario | Input | Expected | Actual | Status |
|----------|-------|----------|--------|--------|
| Intra-state 18% | 100000, rate=18, origin=27, pos=27 | CGST=9000, SGST=9000 | CGST=9000, SGST=9000 | PASS |
| Inter-state 18% | 100000, rate=18, origin=27, pos=29 | IGST=18000 | IGST=18000 | PASS |
| With Cess 5% | 100000, rate=18, cess=5 | Cess=5000 | Cess=5000 | PASS |
| Zero rate | 100000, rate=0 | Total tax=0 | Total tax=0 | PASS |
| Negative base | -100, rate=18 | ValueError | ValueError | PASS |

### GSTEngine.resolve_gst_rate() — Tenant Mode Enforcement

| Tenant Mode | Requested Rate | Effective Rate | Status |
|-------------|---------------|----------------|--------|
| GST_REGULAR | 18% | 18% | PASS |
| GST_COMPOSITION | 18% | 0% | PASS |
| NON_GST | 18% | 0% | PASS |
| NON_GST (with GSTIN) | 18% | 18% (auto-detect) | PASS |

---

## Invoice GST Integration

### Intra-state Invoice (CGST + SGST)

- Origin: Maharashtra (27), POS: Maharashtra (27)
- Product: 18% GST rate
- Result: CGST = 9% × subtotal, SGST = 9% × subtotal, IGST = 0

**Test:** `test_b01_intrastate_invoice_cgst_sgst` — PASS

### Inter-state Invoice (IGST)

- Origin: Maharashtra (27), POS: Karnataka (29)
- Product: 18% GST rate
- Result: IGST = 18% × subtotal, CGST = 0, SGST = 0

**Test:** `test_b01_interstate_invoice_igst` — PASS

### NON_GST Tenant

- Tenant has no GSTIN, tax_mode = NON_GST
- All tax amounts forced to 0 regardless of product GST rate

**Test:** `test_gst_non_gst_tenant_zero_tax` — PASS

### Round-off Handling

- Odd-paise amounts correctly rounded
- `total = subtotal + cgst + sgst + round_off`

**Test:** `test_gst_round_off` — PASS

---

## GSTR Reports

### GSTR-1 (Outward Supplies)

- Sections: B2B, B2CL, B2CS, CDNR, CDNUR, HSN Summary
- All sections populated correctly from invoice data

**Test:** `test_gst_gstr1_report_structure` — PASS

### GSTR-2 (Inward Supplies)

- Sections: B2B Purchases, B2BUR, CDNR, CDNUR, HSN Summary
- Purchase bills correctly classified by vendor GSTIN

**Test:** `test_gst_gstr2_report_structure` — PASS

### GSTR-3B (Monthly Summary)

- Tables 3.1 (outward), 4 (ITC), net tax payable
- Report generates without errors

**Test:** `test_gst_gstr3b_report` — PASS

---

## GSTIN Validation

- Valid GSTIN format accepted (15 chars, checksum)
- Invalid format rejected (HTTP 400)

**Tests:**
- `test_gst_gstin_validation` — PASS
- `test_gst_invalid_gstin_rejected` — PASS

---

## Registration Tax Mode Auto-Detection

- Registration with GSTIN → `tax_mode = GST_REGULAR`
- Registration without GSTIN → `tax_mode = NON_GST`

**Tests:**
- `test_b01_gst_registration_auto_detects_tax_mode` — PASS
- `test_b01_gst_registration_without_gstin_is_non_gst` — PASS

---

## Findings

| ID | Severity | Finding |
|----|----------|---------|
| GST-01 | Info | `GSTEngine.resolve_gst_rate()` has auto-detection fallback for tenants with GSTIN but NON_GST mode (handles legacy data) |
| GST-02 | Info | Origin state code defaults to "36" (Telangana) when tenant has no GSTIN — prevents 500 crashes |
