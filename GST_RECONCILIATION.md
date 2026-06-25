# GST Reconciliation Report — ApexBooks v1.0

**Date:** 2026-06-26

---

## GSTR-1 (Outward Supplies)

- **Status:** Generates correctly
- **Sections verified:** B2B, B2CL, B2CS, CDNR, CDNUR, HSN Summary
- **Test:** `test_200_gstr1_generates` — PASS
- **Test:** `test_201_gstr1_b2b_section` — PASS
- **Test:** `test_203_gstr1_export` — PASS

---

## GSTR-3B (Monthly Summary)

- **Status:** Generates correctly
- **Tables verified:** 3.1 (Outward), 4 (ITC), Net Tax Payable
- **Test:** `test_202_gstr3b_generates` — PASS

---

## GSTR-2 (Inward Supplies)

- **Status:** Generates correctly
- **Sections verified:** B2B Purchases, B2BUR, HSN Summary
- **Test:** `test_407_gstr2_report` — PASS

---

## Tax Calculation Engine

| Scenario | Status |
|----------|--------|
| Intra-state (CGST + SGST) | PASS |
| Inter-state (IGST) | PASS |
| Cess | PASS |
| Zero rate (NON_GST) | PASS |
| Composition mode | PASS |
| GST-inclusive extraction | PASS |
| Round-off handling | PASS |

---

## GSTIN Validation

- Valid GSTIN format accepted
- Invalid format rejected (400)
- Checksum validation working

---

## Findings

| ID | Finding | Severity |
|----|---------|----------|
| GR-01 | No GST calculation discrepancies found | — |
| GR-02 | Tax totals match invoice amounts | — |
