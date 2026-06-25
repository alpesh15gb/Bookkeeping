# Balance Sheet PDF Validation Report

**Date:** 2026-06-26

---

## Test Results

| Check | Status |
|-------|--------|
| Assets section renders | PASS |
| Liabilities section renders | PASS |
| Equity section renders | PASS |
| Opening balances correct | PASS |
| Current year balances correct | PASS |
| Closing balances correct | PASS |
| Totals match API response | PASS |
| Formatting correct | PASS |
| Empty accounts handled | PASS |
| Zero balances handled | PASS |
| Negative balances handled | PASS |

---

## Data Integrity

PDF values match:
- Balance Sheet API response (`/reports/balance-sheet`)
- Database journal entries
- Trial Balance report

---

## Export Formats Verified

| Format | Status |
|--------|--------|
| Balance Sheet PDF | PASS |
| Balance Sheet Excel | PASS |
| GSTR-1 Excel | PASS |
| GSTR-1 PDF | Previously verified |
| GSTR-2 PDF | Previously verified |
