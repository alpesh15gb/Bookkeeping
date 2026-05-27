# PRODUCTION AUDIT & REDESIGN — ApexBooks Accounting ERP
## Classification: FINANCIAL-CRITICAL — Do Not Deploy Before Remediation

---

## 0. EXECUTIVE SUMMARY

Your application has a **modern React + FastAPI + PostgreSQL foundation** with correct `Numeric(15,4)` money storage, tenant isolation, and a working double-entry journal. However, **there are multiple CRITICAL accounting bugs that will cause books to not balance, receivables/payables to drift, and GST returns to mismatch.** The most dangerous issues are in the ledger posting engine (inverted round-off, lost discounts, missing reversal balance updates), mixed transaction patterns, and missing database constraints.

**Verdict:** The system is a **functioning prototype** with early-production candidate UI, but the **accounting engine has arithmetic errors and transaction holes that make it unsafe for real money** without the fixes below.

---

## 1. SYSTEM ARCHITECTURE REDESIGN

### 1.1 Current Data Flow
```
React Frontend (sessionStorage token)
    ↕ axios → /api/v1/*
FastAPI Backend (stateless, JWT RBAC)
    ↕ SQLAlchemy ORM
PostgreSQL (Numeric money, soft-delete, polymorphic journal source_id)
```

### 1.2 Source of Truth per Module
| Layer | Source of Truth | Risk |
|-------|----------------|------|
| **Documents** (Invoice, Bill, Payment) | PostgreSQL header + lines | MEDIUM — document totals and ledger can drift |
| **Journal** | `journal_entries` + `journal_lines` | HIGH — balances cached in `Account.current_balance` are not always recalculated from source |
| **Account Balances** | `Account.current_balance` (cached) | **CRITICAL** — mixed inline-update vs. recalc strategies cause drift |
| **Tax** | Document header tax fields | MEDIUM — proportional tax recalculation on header discounts is approximate |
| **Inventory** | `Product.current_stock` + `StockLedger` | MEDIUM — no DB trigger enforcing `balance_quantity` |

### 1.3 Recommended Architecture
```
┌─────────────────────────────────────────────────────────────┐
│  React Frontend                                             │
│  - React Router (replace view-state routing)                │
│  - React Hook Form + Zod (replace imperative validation)    │
│  - TanStack Query with stale-while-revalidate               │
└─────────────────────────────────────────────────────────────┘
                              ↕ HTTPS / JSON (Decimal-as-string)
┌─────────────────────────────────────────────────────────────┐
│  FastAPI Backend                                            │
│  - Idempotency-Key middleware                               │
│  - Unified Transaction Boundary: every POST/PUT/PATCH       │
│    wraps document mutation + ledger posting in ONE commit   │
│  - Document → Ledger is ALWAYS derived, never manual        │
│  - No inline balance updates; use update_account_balances   │
└─────────────────────────────────────────────────────────────┘
                              ↕ SQLAlchemy (autocommit=False)
┌─────────────────────────────────────────────────────────────┐
│  PostgreSQL                                                 │
│  - Document tables (soft-delete)                            │
│  - Journal tables (immutable, is_locked enforced)           │
│  - DB-level CHECKs: debit=credit trigger, unique numbers    │
│  - Account balances = opening_balance + f(journal_lines)    │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Critical Synchronization Rules (New)
1. **One Transaction Boundary:** Every document state change (create, finalize, cancel, payment) must open a DB transaction, mutate the document, generate journal lines, and commit once. If any step fails, everything rolls back.
2. **No Inline Balance Updates:** Remove all manual `account.current_balance += amount` code. Always call `update_account_balances()` (or a successor) after journal lines are flushed, and never let it call `db.commit()` internally.
3. **Immutable Posted Journals:** Once a journal entry is created, it is locked. Corrections are made via reversal entries, not edits.
4. **Derived Ledger:** The UI never posts manual journals for standard workflows. Operational documents automatically derive journal entries via the `LedgerPostingEngine`.

---

## 2. MODULE-BY-MODULE AUDIT & REDESIGN

### A. SALES MODULE

#### 2.A.1 Invoice Creation & Finalize
**Status:** Functional but contains **CRITICAL ledger bugs**.

**Issues Found:**

| # | Severity | Issue | File:Line |
|---|----------|-------|-----------|
| SAL-1 | **CRITICAL** | Round-off posting logic is **inverted**. Positive round_off debits round_off account and credits customer (reducing receivable). Negative round_off debits customer and credits round_off (increasing receivable). Both are backwards. | `services.py:119-125` |
| SAL-2 | **CRITICAL** | Header discount is **completely lost in the ledger**. `create_invoice_posting` uses `subtotal` for revenue credit and `subtotal + tax_total` for customer debit. It never subtracts `discount_total`. | `services.py:102-106` |
| SAL-3 | **CRITICAL** | Invoice cancellation reverses the invoice journal but **does NOT reverse associated payment journals**. Payments become unallocated dangling credits. | `invoices.py:1237-1241` |
| SAL-4 | **CRITICAL** | Invoice cancellation does **not reverse round-off**, leaving the round-off account permanently out of balance. | `invoices.py:1252-1270` |
| SAL-5 | **HIGH** | `record_invoice_payment` allows `payload.amount` to differ from `allocated_amount`. The bank is debited for the full payment amount, but the invoice only reflects allocated amount. Creates unhandled customer advances. | `invoices.py:1138-1159` |
| SAL-6 | **HIGH** | `record_invoice_payment` does not use `update_account_balances`; it uses inline manual balance updates, mixing strategies. | `invoices.py:1196-1212` |
| SAL-7 | **MEDIUM** | Update line-item key `(product_id, hsn_sac)` is weak. Two lines with same product/HSN but different rates merge incorrectly. | `invoices.py:919` |

**Exact Fixes:**

**SAL-1: Fix inverted round-off logic in `create_invoice_posting`**
```python
# IN services.py, REPLACE lines 119-125 with:
if round_off_amount != 0 and round_off_account_id:
    if round_off_amount > 0:
        # Customer must pay MORE; increase receivable (debit customer)
        lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {invoice_number}"))
        lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {invoice_number}"))
    else:
        # Customer pays LESS; decrease receivable (credit customer)
        lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {invoice_number}"))
        lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {invoice_number}"))
```

**SAL-2: Post discounted revenue, not pre-discount subtotal**
```python
# IN services.py create_invoice_posting, pass discount_total and adjust:
# Replace:
#   invoice_total = subtotal + tax_total
#   lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "CREDIT", ...))
# With:
net_subtotal = subtotal - discount_total
invoice_total = net_subtotal + tax_total
lines.append(JournalLineDraft(customer_account_id, invoice_total, "DEBIT", f"Receivable: {invoice_number}"))
lines.append(JournalLineDraft(sales_revenue_account_id, net_subtotal, "CREDIT", f"Sales Revenue: {invoice_number}"))
```
Also update `finalize_invoice` to pass `discount_total=invoice.discount_total` to the engine.

**SAL-3: On invoice cancellation, reverse payment journals or block cancellation if payments exist**
```python
# IN cancel_invoice (invoices.py), BEFORE creating reversal entry:
allocations = db.query(PaymentAllocation).filter(PaymentAllocation.invoice_id == id).all()
if allocations:
    # Option A (Recommended): Block cancellation until payments are reversed
    raise HTTPException(status_code=400, detail="Cannot cancel an invoice with applied payments. Reverse payments first.")
    # Option B (Advanced): Auto-reverse each payment journal and unallocate
```
**Real-world impact:** Without this, cancelling a paid invoice deletes allocation records but leaves the cash in the bank and the customer's balance reduced. The customer ledger shows unallocated credits that don't match any open invoice.

**SAL-4: Include round_off in reversal posting**
Add `round_off_amount` parameter to `create_invoice_reversal_posting` and pass `invoice.round_off` from `cancel_invoice`.

---

### B. PURCHASE MODULE (Bills)

#### 2.B.1 Bill Creation & Finalize
**Status:** Mirrors invoices but with its own bugs.

| # | Severity | Issue | File:Line |
|---|----------|-------|-----------|
| PUR-1 | **CRITICAL** | `total` is set to `subtotal + taxes`, but `discount_total` is set to sum of line discounts. The Bill model CHECK constraint requires `total = subtotal + taxes - discount_total`. This causes a **DB constraint violation** on any bill with line discounts. | `bills.py:97-113` |
| PUR-2 | **HIGH** | No round-off handling. `grand_total` is raw sum; `round_off` is never set. | `bills.py:97` |
| PUR-3 | **HIGH** | No bill cancellation endpoint. Bills cannot be reversed. | Entire file |
| PUR-4 | **HIGH** | Inline manual balance updates on finalize (same inconsistency as invoices). | `bills.py:422-439` |
| PUR-5 | **MEDIUM** | `record_bill_payment` has the same `payload.amount` vs `allocated_amount` mismatch as invoices. | `bills.py:445-553` |
| PUR-6 | **MEDIUM** | `update_bill` deletes all lines and recreates them, losing line IDs and audit history. | `bills.py:283` |

**Exact Fixes:**

**PUR-1: Fix total calculation to respect discount_total**
```python
# IN bills.py create_bill, REPLACE line 97-113:
grand_total = bill_subtotal + bill_cgst + bill_sgst + bill_igst + bill_utgst + bill_cess - bill_discount
# Or if discount should not reduce total, remove discount_total from the Bill model CHECK.
# Recommendation: Keep the CHECK and fix the math, because line discounts MUST reduce payable.
```

**PUR-2: Add round-off to bills**
Mirror the invoice round-off logic in `create_bill` and add `round_off` to `create_bill_posting`.

**PUR-3: Implement `POST /bills/{id}/cancel`**
Follow the invoice cancellation pattern but for AP:
- Block if payments exist (or auto-reverse them).
- Post reversal journal: Vendor DR, Purchases CR, Input Tax CR.
- Use `update_account_balances`, not inline updates.

---

### C. SALES ORDER MODULE

**Status:** Non-accounting document (no ledger impact). Safe but operationally weak.

| # | Severity | Issue |
|---|----------|-------|
| SO-1 | **MEDIUM** | `deliver_sales_order` allows `DRAFT` → `DELIVERED` without `CONFIRMED`. Enforce state machine strictly. | `sales_orders.py` |
| SO-2 | **MEDIUM** | No conversion endpoint to Invoice. Users must manually recreate. | Missing |
| SO-3 | **LOW** | `amount_advanced` is dead. Either implement advance tracking or remove. | Model |

**Redesign:**
- Add `POST /sales-orders/{id}/convert-to-invoice`.
- On conversion, copy lines to a new `Invoice` in `DRAFT`, link `so.converted_to_invoice_id`, set `so.status = "CONVERTED"`.
- Sales Orders should **never** post to ledger.

---

### D. PURCHASE ORDER MODULE

**Status:** Mirror of Sales Orders.

| # | Severity | Issue |
|---|----------|-------|
| PO-1 | **MEDIUM** | `receive_purchase_order` allows `DRAFT` → `RECEIVED` without `CONFIRMED`. | `purchase_orders.py` |
| PO-2 | **MEDIUM** | No conversion to Bill. | Missing |

**Redesign:**
- Add `POST /purchase-orders/{id}/convert-to-bill`.
- POs should never affect accounts directly.

---

### E. EXPENSE MODULE

**Status:** Over-simplified; no tax, no bank choice, no reversal.

| # | Severity | Issue |
|---|----------|-------|
| EXP-1 | **HIGH** | `post_expense` hardcodes `assets.cash`. Users cannot record expenses paid by bank transfer, UPI, or card. | `expenses.py` |
| EXP-2 | **HIGH** | No cancellation/reversal. Once posted, an expense cannot be undone without a manual journal. | `expenses.py` |
| EXP-3 | **MEDIUM** | No GST/tax support. Indian businesses need GST on many expenses (RCM, input services). | Schema |
| EXP-4 | **MEDIUM** | Auto-numbering is racy (`func.max` without locking). | `expenses.py` |

**Redesign:**
- Add `payment_mode` and `bank_account_id` to Expense schema.
- Add `POST /expenses/{id}/cancel` that posts a reversal journal.
- Add line-item table (`expense_lines`) with GST support for compliance.

---

### F. PAYMENTS MODULE

**Status:** Allocations are mostly correct, but **cancellations destroy balance integrity**.

| # | Severity | Issue | File:Line |
|---|----------|-------|-----------|
| PAY-1 | **CRITICAL** | `cancel_payment_receipt` and `cancel_vendor_payment` post reversal journal entries but **never call `update_account_balances`**. Account balances remain as if the payment still happened. | `payments.py:219-282`, `465-527` |
| PAY-2 | **HIGH** | Cancellations do not use `with_for_update()` on invoices/bills when reverting allocations. Race condition on concurrent payment recording. | `payments.py:238-246`, `482-491` |
| PAY-3 | **HIGH** | `cancel_payment_receipt` sets `invoice.status = "SENT"` even if the invoice was never sent (edge case). | `payments.py:242-244` |
| PAY-4 | **MEDIUM** | Cross-contact allocation is allowed. A payment for Customer A can pay Customer B's invoice. | `payments.py:89-112` |
| PAY-5 | **MEDIUM** | `list_payment_receipts` excludes cancelled receipts (`deleted_at == None` filter), but `GET /receipts/{id}` also excludes them, making cancellation opaque. | `payments.py:169-201` |

**Exact Fixes:**

**PAY-1: Add balance update to cancellations**
```python
# IN cancel_payment_receipt, AFTER db.add(reversal_entry), BEFORE db.commit:
affected = {line.account_id for line in reversal_lines}
update_account_balances(db, tenant_id, affected)
```
Do the same for `cancel_vendor_payment`.

**PAY-2: Lock invoices/bills during cancellation**
```python
# IN cancel_payment_receipt:
for alloc in payment.allocations:
    invoice = db.query(Invoice).filter(Invoice.id == alloc.invoice_id).with_for_update().first()
    # ... revert amount_paid
```

---

### G. CREDIT NOTE / DEBIT NOTE MODULE

**Status:** GST logic is now correct (origin state resolved properly), but ledger integration is incomplete.

| # | Severity | Issue |
|---|----------|-------|
| CDN-1 | **HIGH** | `create_credit_note_posting` and `create_debit_note_posting` do **not accept `round_off_amount`**. CN/DN round-off is lost in the ledger. | `services.py:278`, `326` |
| CDN-2 | **MEDIUM** | No cancellation endpoints for CN/DN. | Missing |
| CDN-3 | **MEDIUM** | `credit_note_number` uses `uuid.uuid4().hex[:6]` with **no duplicate check**. | `invoices.py:361` |
| CDN-4 | **LOW** | `float()` used in `get_credit_note_pdf_payload`. | `invoices.py:535-542` |

**Exact Fix for CDN-1:**
Add `round_off_amount` and `round_off_account_id` parameters to both posting methods and pass them from finalize endpoints.

---

### H. JOURNAL MODULE

**Status:** Core double-entry validation works, but period controls are missing.

| # | Severity | Issue |
|---|----------|-------|
| JNL-1 | **HIGH** | `is_locked` on `JournalEntry` defaults to `True` but is **never enforced**. Any code can theoretically mutate posted lines. | `models.py` |
| JNL-2 | **HIGH** | No period locking. Users can backdate or post into closed fiscal years. | Missing |
| JNL-3 | **MEDIUM** | Manual journal duplicate reference check has no row lock. Race condition possible. | `accounting.py:101-109` |
| JNL-4 | **MEDIUM** | `recalculate_all_account_balances` calls `db.commit()` internally, breaking outer transactions. | `services.py:625` |

**Redesign:**
- Enforce `is_locked`: Add a DB trigger or SQLAlchemy event that raises on UPDATE/DELETE of `journal_lines` where `entry.is_locked = True`.
- Add `AccountingPeriod` table with `is_closed` flag. Block all journal creation before `period_end` if closed.
- Remove `db.commit()` from `recalculate_all_account_balances`; let callers commit.

---

### I. INVENTORY-LINKED FLOWS

**Status:** Basic stock ledger exists but is not tightly coupled to accounting.

| # | Severity | Issue |
|---|----------|-------|
| INV-1 | **MEDIUM** | `stock_ledger.balance_quantity` is a stored value with no DB constraint ensuring it equals the running sum of `quantity`. | `models.py` |
| INV-2 | **MEDIUM** | Inventory adjustments do not post to ledger (no COGS/Inventory account movement). | `inventory_adjustments.py` |
| INV-3 | **LOW** | Negative stock is not prevented at the DB level. | `models.py` |

**Redesign:**
- Every stock receipt (GRN) should generate: `Inventory DR / Vendor CR` (or `Inventory DR / GRN Clearing CR` if bill not yet received).
- Every stock issue (delivery) should generate: `COGS DR / Inventory CR`.
- Tie `delivery_challans` to stock issue and optionally to invoice.

---

## 3. DOCUMENT LIFECYCLE DESIGN (Unified)

### 3.1 States per Document Type

| State | Editable? | Ledger Impact | Reversible? | Deletable? |
|-------|-----------|---------------|-------------|------------|
| **DRAFT** | Yes | None | N/A | Hard delete allowed |
| **CONFIRMED / SENT / ISSUED / POSTED / UNPAID** | No | Yes — entry created | Via cancellation/reversal | No — use cancel |
| **PARTIALLY_PAID** | No | Yes + payment entries | Reverse payments first | No |
| **PAID** | No | Yes + payment entries | Reverse payments first | No |
| **CANCELLED** | No | Reversal entry created | No | No |
| **CONVERTED** (SO→Inv, PO→Bill) | No | None yet on order | N/A | No |

### 3.2 Rules
1. **Posted documents are immutable.** Edit is forbidden. Correct via Credit Note, Debit Note, or Reversal Journal.
2. **Cancellations always create a reversal journal** and update balances atomically.
3. **Hard delete is ONLY allowed for DRAFT.** All other states must use cancellation/soft-delete.
4. **Audit trail:** Every state change writes an `audit_log` row with `entity_type`, `entity_id`, `actor_id`, `old_state`, `new_state`.

---

## 4. AUTOMATIC ACCOUNTING ENGINE DESIGN

### 4.1 Core Principle
> **Operational documents are the source transaction. Ledger entries are derived automatically and atomically.**

### 4.2 Posting Matrix (Corrected)

| Document | Debit | Credit | Notes |
|----------|-------|--------|-------|
| **Sales Invoice** | Customer AR (net_subtotal + tax + round_off) | Sales Revenue (net_subtotal), Tax Outputs (tax), Round-off (round_off) | Round-off fixed per SAL-1 |
| **Invoice Payment** | Bank/Cash | Customer AR | For exact allocated amount |
| **Invoice Cancellation** | Sales Revenue, Tax Outputs | Customer AR | Exact mirror of original, including round_off |
| **Purchase Bill** | Purchases/Inventory (subtotal - disc), Input Tax | Vendor AP (total) | Fix discount per PUR-1 |
| **Bill Payment** | Vendor AP | Bank/Cash | |
| **Credit Note** | Sales Revenue, Tax Outputs | Customer AR | |
| **Debit Note** | Customer AR | Sales Revenue, Tax Outputs | |
| **Expense** | Expense Category Account | Bank/Cash (chosen account) | Remove hardcoded cash |

### 4.3 Engine Refactor
1. **Remove inline balance updates** from ALL routers. Every router that posts a journal must call `update_account_balances(db, tenant_id, affected_account_ids)` and then let the endpoint call `db.commit()`.
2. **Fix `update_account_balances`**: Remove its internal `db.commit()` and `db.flush()`. It should only compute and set balances.
3. **Add `db.commit()` only in routers**, never in services.
4. **Discount handling:** Pass `discount_total` into posting engines. Revenue/purchases credit/debit must be **net of discount**.
5. **Round-off handling:** All engines (invoice, bill, credit note, debit note) must accept and post round_off correctly.

---

## 5. FRONTEND REACT AUDIT

### 5.1 Critical Issues

| # | Severity | Issue | Impact |
|---|----------|-------|--------|
| FE-1 | **CRITICAL** | **Refresh token is lost on page reload.** `refreshTokenMemory` is never restored from storage. After access token expiry, users are force-logged out. | `lib/api.ts` |
| FE-2 | **HIGH** | **BillForm computes taxes client-side.** Preview totals may mismatch backend saved totals. | `BillForm.tsx` |
| FE-3 | **HIGH** | **Dashboard computes `netProfit` incorrectly** (`sales - expenses`), omitting purchases/bills. | `SalesDashboard.tsx` |
| FE-4 | **HIGH** | **No unsaved-changes guard for in-app navigation.** `beforeunload` only protects tab close; sidebar clicks silently destroy forms. | All forms |
| FE-5 | **MEDIUM** | **Auth fragile on reload:** Access token restored from `sessionStorage`, refresh token not. | `App.tsx`, `lib/api.ts` |
| FE-6 | **MEDIUM** | **Lists have inconsistent pagination.** `BillList`, `ExpenseList`, `CreditNoteList` load all records client-side. Will crash at scale. | Multiple |
| FE-7 | **MEDIUM** | **Currency formatting inconsistent.** Lists hide paise (`maximumFractionDigits: 0`), detail shows paise. Confuses users. | `InvoiceList.tsx` vs `InvoiceDetail.tsx` |
| FE-8 | **MEDIUM** | **EstimateForm silently fails validation.** `handleSubmit` returns without setting `formError`. | `EstimateForm.tsx` |
| FE-9 | **LOW** | **TrialBalance uses strict equality `===` on floats** for debit/credit check. Unsafe. | `TrialBalance.tsx` |

### 5.2 Exact Fixes

**FE-1 & FE-5: Fix refresh token persistence**
```typescript
// IN lib/api.ts:
// Store refresh token in httpOnly cookie (backend must set it).
// OR as a fallback, store in localStorage with clear XSS warnings.
// The backend currently returns refresh_token in JSON. Change backend
// /auth/login and /auth/refresh to set it as httpOnly cookie.
// Frontend then removes all refreshTokenMemory logic and relies on cookie.
```
**Backend change required:** Set `Set-Cookie: refresh_token=...; HttpOnly; Secure; SameSite=Strict` on login/refresh. Read it server-side.

**FE-2: Move BillForm tax computation to backend preview endpoint**
Create `POST /bills/preview` that mirrors `POST /invoices/preview`. BillForm should call this instead of local `calculateTotals()`.

**FE-3: Fix Dashboard net profit**
Remove frontend profit calculation. Query a new lightweight `GET /reports/summary` endpoint that returns backend-computed KPIs.

**FE-4: Add in-app navigation guard**
```typescript
// Use a global PendingChangesContext or Zustand store.
// In App.tsx navigation handlers:
if (hasUnsavedChanges && !window.confirm("You have unsaved changes. Leave anyway?")) return;
```

**FE-6: Unify pagination**
Add server-side pagination to `/bills`, `/expenses`, `/credit-notes`, `/debit-notes`, `/sales-orders`, `/purchase-orders`. Frontend sends `?page=&limit=`.

---

## 6. UI/UX CONSISTENCY AUDIT

### 6.1 Issues
| # | Severity | Issue |
|---|----------|-------|
| UX-1 | **HIGH** | Dashboard flashes zeros before data loads (no skeleton/loading state). |
| UX-2 | **HIGH** | Dashboard has no error state — API failure shows blank zeros. |
| UX-3 | **MEDIUM** | Mobile live preview uses `text-[9px]` and `text-[10px]`, nearly illegible. |
| UX-4 | **MEDIUM** | `InvoiceForm` uses browser `prompt()` and `alert()` for GST verification — extremely jarring. |
| UX-5 | **MEDIUM** | Print flows generate raw HTML strings in `useEffect` — brittle. |
| UX-6 | **LOW** | Sidebar footer has WCAG contrast failure. |
| UX-7 | **LOW** | Missing `aria-label` on many icon buttons. |

### 6.2 Fixes
- Add `isLoading` skeletons to all dashboard cards.
- Add `isError` banner with retry button to dashboard.
- Replace `prompt()/alert()` with modal dialogs.
- Use a print-specific React component or `window.print()` with a print media query instead of `window.open("", "_blank")`.
- Run a Tailwind contrast audit on all `text-zinc-*` combinations.

---

## 7. BACKEND API AUDIT

### 7.1 Security & Safety

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| API-1 | **CRITICAL** | `JWT_SECRET_KEY` and `SECRET_KEY` have hardcoded fallback strings in `config.py`. | Remove defaults; fail startup if env vars missing. |
| API-2 | **CRITICAL** | `update_account_balances()` commits internally, breaking transaction boundaries. | Remove `db.commit()` and `db.flush()` from the function. |
| API-3 | **HIGH** | `recalculate_all_account_balances` also commits internally. | Same fix. |
| API-4 | **HIGH** | No idempotency keys. Retried POSTs create duplicates. | Add `Idempotency-Key` header middleware with Redis TTL. |
| API-5 | **HIGH** | Access token stored in `sessionStorage` (XSS risk). | Move to `httpOnly` cookie or memory-only + refresh cookie. |
| API-6 | **HIGH** | `logout` endpoint is unauthenticated. Anyone with a stolen refresh token can revoke it. | Require valid access token to call logout. |
| API-7 | **MEDIUM** | Rate limiting can be disabled via config flag in production. | Remove kill-switch for rate limiting; make it mandatory. |
| API-8 | **MEDIUM** | `sales.py` analytics bypasses RBAC (`get_active_tenant` instead of `enforce_permission`). | Replace with `enforce_permission`. |
| API-9 | **MEDIUM** | No request ID tracing. | Add `X-Request-ID` middleware propagated to logs. |
| API-10 | **LOW** | `password_reset_tokens` keeps orphaned valid tokens if multiple resets requested. | Mark all previous tokens for that user as used on reset. |

### 7.2 Transaction Boundaries
**Current:** Most endpoints rely on SQLAlchemy implicit rollback on exception. This is okay for simple cases but bad for user experience (raw 500s on constraint violations).

**Required:**
```python
# Pattern for every state-changing endpoint:
try:
    # ... validate ...
    # ... mutate document ...
    # ... generate journal draft ...
    # ... add journal entry ...
    # ... update_account_balances(db, tenant_id, affected) ...
    db.commit()
except LedgerValidationError as e:
    db.rollback()
    raise HTTPException(422, detail=str(e))
except IntegrityError as e:
    db.rollback()
    raise HTTPException(409, detail="Duplicate or invalid data.")
```

---

## 8. POSTGRESQL DATABASE AUDIT

### 8.1 Critical Schema Fixes

| # | Severity | Issue | Exact Fix |
|---|----------|-------|-----------|
| DB-1 | **CRITICAL** | `invoices` model missing `ck_invoices_total_balance` and `ck_invoices_amount_paid` that exist in migration. Causes model/migration drift. | Add constraints to `models.py` to match migration. |
| DB-2 | **CRITICAL** | `journal_lines` has no DB-level enforcement that `SUM(debits) == SUM(credits)` per entry. | Add trigger `trg_enforce_journal_balance` (see below). |
| DB-3 | **HIGH** | No per-tenant UNIQUE on document numbers for `invoices`, `bills`, `payments`, `credit_notes`, `debit_notes`, `expenses`. | Add `UniqueConstraint(tenant_id, number)` to each. |
| DB-4 | **HIGH** | `payment_allocations` and `bill_payment_allocations` allow over-allocation (no CHECK vs parent amount). | Add application validation + ideally a DB trigger. |
| DB-5 | **HIGH** | Soft-deleted tables lack index on `deleted_at`. Queries filter `deleted_at IS NULL` constantly. | Add composite indexes: `(tenant_id, deleted_at)`. |
| DB-6 | **MEDIUM** | `eway_bills` allows both `invoice_id` and `bill_id` NULL simultaneously. | Add CHECK: `(invoice_id IS NOT NULL) != (bill_id IS NOT NULL)` or similar. |
| DB-7 | **MEDIUM** | `bank_reconciliations` allows both `payment_id` and `bill_payment_id` NULL. | Add CHECK ensuring exactly one is set. |
| DB-8 | **MEDIUM** | `accounts.parent_id` has no explicit `ON DELETE`. | Set `ondelete="SET NULL"` or `"RESTRICT"` explicitly. |
| DB-9 | **LOW** | `credit_note_lines.hsn_sac` and `debit_note_lines.hsn_sac` are `String(20)`; all others `String(8)`. | Standardize to `String(8)`. |

### 8.2 Trigger for Journal Balance (DB-2)
```sql
CREATE OR REPLACE FUNCTION fn_check_journal_balance()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM journal_entries je
        WHERE je.id = NEW.entry_id
        GROUP BY je.id
        HAVING COALESCE(SUM(CASE WHEN direction='DEBIT' THEN amount ELSE 0 END), 0)
            != COALESCE(SUM(CASE WHEN direction='CREDIT' THEN amount ELSE 0 END), 0)
    ) THEN
        RAISE EXCEPTION 'Journal entry debits do not equal credits';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_journal_balance
AFTER INSERT OR UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balance();
```
*Note: This is expensive. An alternative is an application-level check + periodic reconciliation job.*

### 8.3 Money Storage
✅ **Excellent:** All money uses `Numeric(15,4)` or `Numeric(5,2)`. No floats in schema.

---

## 9. ACCOUNTING CORRECTNESS AUDIT

### 9.1 Double-Entry Validation
✅ `JournalEntryDraft.validate()` enforces `debit == credit`.
⚠️ **Gap:** API endpoints do not explicitly call `validate()` after building drafts, but the draft `__init__` does call it. **Safe for now**, but add an explicit call in routers for defense in depth.

### 9.2 Sales Postings (Confirmed Bugs)
- **Round-off inverted:** See SAL-1. **This means every invoice with non-zero round_off has incorrect AR and incorrect round-off account balance.**
- **Discount lost:** See SAL-2. **Revenue is overstated and AR is overstated by exactly the discount amount.**
- **Cancellation incomplete:** See SAL-3, SAL-4.

### 9.3 Purchase Postings
- **Discount bug:** See PUR-1. Bills with line discounts will fail to save due to CHECK constraint violation, or if the constraint is removed, the discount is lost from the payable.
- **No reversal:** Bills cannot be cancelled.

### 9.4 Payment Postings
- **Cancellation leaves balances wrong:** See PAY-1. After cancelling a receipt, the bank account balance and customer balance are both wrong.

### 9.5 Tax Postings
- ✅ GST engine correctly splits CGST/SGST/IGST/UTGST/Cess.
- ✅ RCM invoices skip tax credits for seller.
- ⚠️ Credit/Debit notes do not post round_off tax effect (minor).

### 9.6 Opening / Closing Balances
- ✅ Trial Balance correctly includes `opening_balance`.
- ❌ **Balance Sheet ignores `opening_balance`.** It uses `a.current_balance` directly, which is net movement only. Any account with non-zero opening balance is misstated.
- **Fix:** Change `get_balance_sheet` to compute balance from `opening_balance + SUM(journal_lines)` up to the cutoff date, or ensure `current_balance` is always `opening + movement`.

### 9.7 Outstanding Calculations
- ✅ `amount_paid` is maintained on invoices and bills.
- ⚠️ Race conditions exist on payment cancellation (no row locks).

### 9.8 Partial Settlement & Advances
- ⚠️ Unallocated overpayments are possible in invoice-level payment endpoint (`/{id}/payment`).
- ✅ Bulk payment endpoint (`/payments/receipts`) validates exact allocation.

### 9.9 Financial Period Locking
- **Completely missing.** There is no way to lock a month or year.
- **Fix:** Add `accounting_periods` table and check it before any journal creation.

---

## 10. RELIABILITY, SECURITY, AND PRODUCTION SAFETY

### 10.1 Top Security Risks
| # | Severity | Risk | Fix |
|---|----------|------|-----|
| SEC-1 | **CRITICAL** | Hardcoded JWT secret fallback. | Crash on startup if env var unset. |
| SEC-2 | **HIGH** | XSS can steal `sessionStorage` access token. | Move to `httpOnly` cookie. |
| SEC-3 | **HIGH** | `logout` unauthenticated. | Require auth. |
| SEC-4 | **HIGH** | No auth event audit trail. | Write `audit_logs` on login success/failure/password change. |
| SEC-5 | **MEDIUM** | `SECRET_KEY` used for password reset tokens is same as app secret. | Use a separate `PASSWORD_RESET_SECRET`. |
| SEC-6 | **MEDIUM** | CORS allows `api.apexbooks.in` origin. | Review if this is intentional; usually APIs don't allow other API origins. |
| SEC-7 | **LOW** | `refresh_token` accepted via query param (reported in QA). | Ensure it is only accepted via cookie or body. |

### 10.2 Production Hardening Checklist
- [ ] Add `Idempotency-Key` middleware.
- [ ] Add `X-Request-ID` middleware.
- [ ] Enforce rate limits unconditionally in production.
- [ ] Add structured JSON logging (not just basicConfig).
- [ ] Add DB connection pool monitoring.
- [ ] Run migrations via Alembic in CI/CD, not `Base.metadata.create_all()`.
- [ ] Back up `journal_entries` and `journal_lines` with WAL archiving; these are immutable financial records.

---

## 11. MIGRATION STRATEGY: CURRENT → PRODUCTION-GRADE

### Phase 1: Fix Critical Accounting Bugs (Week 1)
**Goal:** Prevent financial data corruption.
1. Fix `create_invoice_posting` round-off logic (SAL-1).
2. Fix `create_invoice_posting` discount handling (SAL-2).
3. Fix `create_bill` total calculation (PUR-1).
4. Add `update_account_balances` to payment cancellations (PAY-1).
5. Remove all inline manual balance updates; unify on `update_account_balances`.
6. Remove `db.commit()` from `update_account_balances` and `recalculate_all_account_balances`.
7. Fix Balance Sheet to include opening balances.

### Phase 2: Close Transaction & Reversal Gaps (Week 2)
1. Block invoice cancellation if payments exist (or auto-reverse payments).
2. Implement `POST /bills/{id}/cancel`.
3. Implement `POST /expenses/{id}/cancel`.
4. Implement `POST /invoices/credit-notes/{id}/cancel` and `/debit-notes/{id}/cancel`.
5. Add round-off support to CN/DN posting engines.
6. Add `POST /bills/preview` endpoint.

### Phase 3: Schema Hardening (Week 3)
1. Add missing per-tenant UNIQUE constraints on document numbers.
2. Add composite indexes on `(tenant_id, deleted_at)`.
3. Add CHECK constraints for `eway_bills` and `bank_reconciliations` orphan prevention.
4. Add DB trigger for journal balance (or strengthen app validation).
5. Add `accounting_periods` table and locking logic.

### Phase 4: Frontend & Auth Hardening (Week 4)
1. Move refresh token to `httpOnly` cookie.
2. Fix refresh token loss on reload.
3. Add in-app unsaved-changes navigation guard.
4. Unify pagination on all list endpoints.
5. Replace BillForm client-side tax with `/bills/preview`.
6. Add dashboard skeletons, error banners, and refetch intervals.

### Phase 5: Inventory & Advanced Features (Month 2)
1. Link delivery challans to stock ledger.
2. Add COGS/Inventory auto-posting on delivery.
3. Add SO→Invoice and PO→Bill conversion endpoints.
4. Add aging reports and cash flow statement.

---

## APPENDIX A: RISK REGISTER (Quick Reference)

| ID | Severity | Module | Issue | Accounting Impact |
|----|----------|--------|-------|-------------------|
| SAL-1 | CRITICAL | Sales | Round-off inverted | AR and round-off account permanently wrong |
| SAL-2 | CRITICAL | Sales | Discount lost in ledger | Revenue overstated; AR overstated |
| SAL-3 | CRITICAL | Sales | Cancel doesn't reverse payments | Unallocated dangling credits; customer balance wrong |
| PAY-1 | CRITICAL | Payments | Cancel doesn't update balances | Bank and AR/AP balances permanently wrong |
| PUR-1 | CRITICAL | Bills | Total violates CHECK / discount lost | DB error OR payable overstated |
| API-1 | CRITICAL | Auth | Hardcoded JWT secret | Complete authentication bypass possible |
| DB-2 | CRITICAL | DB | No journal balance trigger | Unbalanced journals possible if app bug introduced |
| BAL-1 | HIGH | Reports | Balance Sheet ignores opening balance | Balance sheet materially misstated |
| FE-1 | HIGH | Frontend | Refresh token lost | Users forced out; poor UX; token refresh broken |
| EXP-1 | HIGH | Expenses | Hardcoded cash account | Wrong cash/bank balance on all expenses |
| CDN-1 | HIGH | CN/DN | Round-off ignored in ledger | CN/DN round-off not recorded |
| JNL-1 | HIGH | Journal | `is_locked` never enforced | Posted journals could be silently edited |

---

*End of Audit Report. This document should be treated as a blocking checklist before any production deployment involving real financial data.*
