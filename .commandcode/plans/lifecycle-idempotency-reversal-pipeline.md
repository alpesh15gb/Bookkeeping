# Plan: Lifecycle, Idempotency, Reversal & Posting Pipeline

## PHASE 1: Lifecycle — Normalize status names across all document types

| Concept | Current | Proposed |
|---------|---------|----------|
| Draft | DRAFT (all) | DRAFT |
| Posted/Finalized | SENT, UNPAID, POSTED, ISSUED | POSTED |
| With payments | PARTIALLY_PAID | PARTIALLY_PAID |
| Settled | PAID | PAID |
| Cancelled | CANCELLED | CANCELLED |

**Actions:**
1. Migration to rename statuses in DB: SENT→POSTED, UNPAID→POSTED, ISSUED→POSTED
2. Update all guards in invoices.py, bills.py, expenses.py, credit/debit note handlers
3. Update model defaults and schema defaults
4. Add `POST /expenses/{id}/finalize` alias (deprecate `/post`)
5. Add `PUT` endpoints for credit notes and debit notes (currently missing)
6. Add `status` column to Payment/BillPayment tables instead of relying on `deleted_at`
7. Add `deleted_at` filter to vendor payment list query

## PHASE 2: Idempotency — Close gaps

**Actions:**
1. Add `"DELETE"` to `IDEMPOTENT_METHODS` in middleware
2. Migration: add unique index on `idempotency_keys(idempotency_key, tenant_id, method, path)`
3. Add batch-level dedup for Vyapar import

## PHASE 3: Reversal — Dedicated engine methods for all types

**Actions:**
1. Add `create_bill_reversal_posting()` to LedgerPostingEngine (mirrors invoice reversal pattern)
2. Refactor `cancel_bill` to use it instead of manual direction flip
3. Add `create_payment_receipt_reversal_posting()` and `create_payment_out_reversal_posting()`
4. Refactor payment cancel endpoints to use them
5. **Flutter:** Fix bill_detail_view status check (`POSTED` → `UNPAID` → then `POSTED` after migration)
6. **Flutter:** Wire expense cancel button to `POST /expenses/{id}/cancel` (currently calls DELETE)

## PHASE 4: Unified pipeline — Extract commit_ledger_draft()

**Actions:**
1. Add `commit_ledger_draft(db, tenant_id, draft)` helper in services.py
2. Refactor all 12+ posting callers to use it (invoices, bills, expenses, payments, credit/debit notes, accounting)
3. Apply invoice-style proportional tax recalculation to bills (header discount)
4. Fix expense `pos_state_code` AttributeError
5. Add payment_mode validation before resolver call
