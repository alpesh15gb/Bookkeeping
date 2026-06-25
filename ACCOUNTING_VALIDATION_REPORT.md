# Accounting Validation Report — ApexBooks

**Date:** 2026-06-26
**Scope:** All posting pipelines, ledger integrity, financial statements

---

## Summary

The accounting engine is **solid**. Double-entry integrity is maintained across all transaction types. Trial Balance always balances. Balance Sheet equation (A = L + E) holds.

---

## Posting Pipeline Validation

| Transaction Type | Auto-Posts | Ledger Balanced | Status |
|-----------------|-----------|----------------|--------|
| Sales Invoice | Yes | Yes | PASS |
| Purchase Bill | Yes | Yes | PASS |
| Expense | Yes (on post) | Yes | PASS |
| Payment Receipt | Yes | Yes | PASS |
| Journal Entry | Yes | Yes | PASS |
| Credit Note | Yes | Yes | PASS |
| Debit Note | Yes | Yes | PASS |
| Invoice Cancel | Yes (reversal) | Yes | PASS |
| Year-End Close | Yes | Yes | PASS |

---

## Double-Entry Integrity

- Every journal entry validates `sum(debits) == sum(credits)` at creation time
- `JournalEntryDraft.validate()` raises `LedgerValidationError` if不平衡
- Unbalanced entries are rejected with HTTP 400

**Test:** `test_unbalanced_journal_rejected` — PASS

---

## Trial Balance

- Trial balance query uses `GROUP BY` on all accounts with `SUM` of debits/credits
- Opening balance + period movements = closing balance per account type
- ASSET/EXPENSE: `closing = opening + debits - credits`
- LIABILITY/EQUITY/REVENUE: `closing = opening + credits - debits`

**Test:** `test_trial_balance_balances_after_invoice` — PASS
**Assertion:** `|total_debits - total_credits| < 0.01`

---

## Balance Sheet

- Assets = Liabilities + Equity + Net Profit
- Net Profit computed from Revenue - Expense journal movements
- Response includes `is_balanced` boolean

**Test:** `test_balance_sheet_equation` — PASS
**Assertion:** `data["is_balanced"] is True`

---

## Profit & Loss

- Revenue accounts: `amount = credits - debits`
- Expense accounts: `amount = debits - credits`
- Net Profit = Total Revenue - Total Expenses

**Test:** `test_b02_profit_loss_returns_200` — PASS

---

## Financial Year Lock Enforcement

- LOCKED FY rejects all postings (HTTP 422)
- CLOSED accounting period rejects all postings (HTTP 422)
- READY_TO_CLOSE status blocks new transactions during year-end close
- Future-dated postings rejected beyond 30-day limit

**Tests:**
- `test_b03_locked_fy_rejects_posting` — PASS
- `test_b03_closed_period_rejects_posting` — PASS

---

## Account Balance Recalculation

- `update_account_balances()` recalculates `current_balance` from journal entries
- Triggered after every journal entry creation/cancellation
- Endpoint `POST /accounting/recalculate-balances` available for manual refresh

---

## Findings

| ID | Severity | Finding |
|----|----------|---------|
| ACC-01 | Low | `trial_balance_excel` at `reports.py:712` has duplicate tenant lookup (lines 727-729) |
| ACC-02 | Info | Year-end close creates closing JE + opening balance carry-forward + inventory carry-forward in single transaction |
