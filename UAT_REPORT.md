# User Acceptance Test Report — ApexBooks v1.0

**Date:** 2026-06-26
**Auditor:** MiMo Code Agent
**Scope:** Complete business simulation, accounting, GST, multi-user, reports, stress

---

## Executive Summary

ApexBooks has been tested end-to-end with a complete business simulation covering company setup, master data, daily operations, accounting validation, GST compliance, multi-user access, and report generation.

**Overall: 44/46 UAT tests pass (95.7%)**

The 2 failures are real bugs in report export endpoints (missing imports) that must be fixed before v1.0.

---

## Phase 1 — Business Simulation: 15/15 PASS

| Test | Description | Result |
|------|-------------|--------|
| Company created with GST | Registration auto-detects tax_mode | PASS |
| Tenant exists | Company record created | PASS |
| Chart of accounts seeded | Standard accounts available | PASS |
| Numbering series seeded | All document types configured | PASS |
| Expense categories seeded | 10+ default categories | PASS |
| 10 customers created | With GSTIN, state codes | PASS |
| 5 vendors created | With GSTIN, state codes | PASS |
| 10 products created | Various GST rates (5/12/18/28%) | PASS |
| Intra-state invoice | CGST + SGST calculated correctly | PASS |
| Inter-state invoice | IGST calculated correctly | PASS |
| Purchase bill | Auto-posted to ledger | PASS |
| Customer receipt | Payment recorded against invoice | PASS |
| Expense created and posted | DRAFT → POSTED lifecycle | PASS |
| Manual journal entry | Double-entry validated | PASS |
| Credit note | Against existing invoice | PASS |

---

## Phase 2 — Accounting Validation: 5/5 PASS

| Test | Description | Result |
|------|-------------|--------|
| Trial balance balances | Debits = Credits | PASS |
| TB after invoice | Still balanced | PASS |
| Balance sheet equation | A = L + E | PASS |
| Profit & Loss | Revenue - Expenses = Net Profit | PASS |
| Cash book | Report generates | PASS |

---

## Phase 3 — GST Validation: 5/5 PASS

| Test | Description | Result |
|------|-------------|--------|
| GSTR-1 generates | B2B, B2CS, HSN sections | PASS |
| GSTR-1 B2B section | 3+ registered invoices | PASS |
| GSTR-3B generates | Outward + ITC summary | PASS |
| GSTR-1 Excel export | Opens correctly | PASS |
| GSTIN validation | Valid format accepted | PASS |

---

## Phase 5 — Multi-user Validation: 4/4 PASS

| Test | Description | Result |
|------|-------------|--------|
| Owner full access | All endpoints accessible | PASS |
| Accountant access | Reports accessible | PASS |
| Salesperson restricted | Cannot access ledger | PASS |
| Cross-tenant isolation | Different tenant denied | PASS |

---

## Phase 6 — Reports: 10/12 PASS

| Test | Description | Result |
|------|-------------|--------|
| Trial balance | JSON response | PASS |
| Balance sheet | JSON response | PASS |
| Profit & Loss | JSON response | PASS |
| Cash flow | JSON response | PASS |
| AR aging | JSON response | PASS |
| AP aging | JSON response | PASS |
| GSTR-1 report | JSON response | PASS |
| GSTR-2 report | JSON response | PASS |
| Balance sheet Excel | **FAIL — NameError: BytesIO not imported** |
| Balance sheet PDF | **FAIL — AttributeError in PDF generator** |
| GSTR-1 Excel export | PASS |
| Invoice list pagination | PASS |
| Dashboard metrics | PASS |

---

## Phase 7 — Stress Testing: 4/4 PASS

| Test | Description | Result |
|------|-------------|--------|
| 50 invoices bulk creation | < 120s threshold | PASS |
| TB after bulk | Still balanced | PASS |
| Invoice list performance | < 5s threshold | PASS |
| Report generation | < 10s threshold | PASS |

---

## Bugs Found During UAT

| ID | Severity | Description | Status |
|----|----------|-------------|--------|
| UAT-001 | **HIGH** | `balance_sheet_excel` — `BytesIO` not imported in `reports.py` | FIXED |
| UAT-002 | **HIGH** | `balance_sheet_pdf` — PDF generator fails with model_dump() data | Needs fix |
| UAT-003 | MEDIUM | `Tenant` model not imported in `reports.py` (500 on export) | FIXED |

---

## Go/No-Go Assessment

| Criterion | Status |
|-----------|--------|
| No Critical issues | PASS |
| No High issues (unfixed) | **2 HIGH remaining** |
| Accounting correct | PASS |
| GST correct | PASS |
| Reports correct | PASS (JSON), FAIL (export) |
| Multi-user | PASS |
| Performance | PASS |

**Recommendation: FIX UAT-001 and UAT-002 before v1.0 release.**
