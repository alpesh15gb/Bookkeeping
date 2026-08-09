# Accounting Direct-Posting Redesign — Architecture Proposal & Migration Plan

**Status:** PROPOSAL — for review. No schema changes have been made.
**Date:** 2026-08-08
**Author:** Buffy (AI engineering agent), on request of the project owner.

---

## 1. Executive Summary

The request: remove the persistent **Draft → Posted** workflow for accounting
transactions and move to a **direct-posting** model where a valid submission is
posted to the ledger immediately, becomes immutable accounting history, and can
only be corrected through an accounting-safe reversal/correction flow with a
full audit trail.

**The single most important finding of the audit:** the system is already
*halfway there*. Invoices, bills, credit notes, debit notes, sales returns and
purchase returns already have an auto-posting engine
(`backend/src/domains/accounting/auto_post.py`) and a migration
(`20260531_0001_add_cancel_columns_and_migrate_drafts.py`) that bulk-promoted
old DRAFT rows to POSTED. Journal entries are already immutable at the DB layer
(`is_locked` + `before_update` guard + unique source constraint).

What remains is a **mixed architecture**:

| Document | Today | Backend default | Frontend sends |
|---|---|---|---|
| Manual Journal | Direct-posting via API (`POST /journals`) | n/a (no draft exists server-side) | Draft→Post two-step in form (client-local only) |
| Invoice | DRAFT → `POST /{id}/finalize` | `post_on_create: true` | **`post_on_create: false`** → creates DRAFT |
| Bill | DRAFT → `POST /{id}/finalize` | `post_on_create: true` | **`post_on_create: false`** → creates DRAFT |
| Expense | DRAFT → `POST /{id}/post` | **no auto-post by design** | Draft flow |
| Credit/Debit Note | DRAFT → `POST /{id}/finalize` | draft on create | Finalize step in detail screen |
| Sales/Purchase Return | **Auto-posted** on create | n/a | n/a |
| Payments (receipt/payout) | **Posted immediately** | n/a | n/a |

And one **critical integrity violation** exists today: editing a **posted bill**
(`PUT /bills/{id}`, `backend/src/api/v1/bills.py:713`) **silently deletes its
journal entry, journal lines and stock-ledger rows and re-posts** — exactly what
the new architecture must forbid.

This document proposes the target architecture, the field mapping, the risks,
the migration strategy, and the disposition of existing drafts. **No destructive
schema change is made until you approve.**

---

## 2. Scope of the Audit (what was inspected)

**Backend (FastAPI + SQLAlchemy + Alembic):**
- Models: `backend/src/infrastructure/database/models.py` — `JournalEntry`,
  `JournalLine`, `Invoice`, `Bill`, `Expense`, `CreditNote`, `DebitNote`,
  `SalesReturn`, `PurchaseReturn`, `Payment`, `BillPayment`, `StockLedger`,
  `AuditLog`, `FinancialYear`, status CHECK constraints on all ledger docs.
- Services: `domains/accounting/services.py` (`LedgerPostingEngine`,
  `JournalEntryDraft`, `commit_ledger_draft`, `update_account_balances`,
  `AccountResolver`), `domains/accounting/auto_post.py` (auto-post + cancel +
  reversal engine), `domains/accounting/period_lock.py`.
- API: `api/v1/accounting.py` (manual journals, contra, reversal, reports,
  year-end), `invoices.py`, `bills.py`, `expenses.py`, `payments.py`,
  `returns.py`, `recurring_invoices.py`, `financial_years.py`, `dashboard.py`,
  `goods_receipts.py`, `delivery_challans.py`, `inventory_adjustments.py`,
  `apexbooks_sync.py` (offline sync event processor), `vyapar_import.py`.
- Audit: `common/audit_log.py` (contextvars actor identity, `before_flush`
  capture, atomic with the business transaction).
- Schemas: `schemas/accounting_schemas.py`, `schemas/document.py`,
  `schemas/bill_schemas.py`.
- Workers: `workers/tasks.py` (recurring auto-post, status filters).
- Tests: 20+ test files asserting DRAFT creation / finalize / post behavior.

**Frontend (Flutter, offline-first):**
- `features/accounting/journal/presentation/journal_form_screen.dart`,
  `journal_form_notifier.dart`, `journal_list_screen.dart`
  (Save draft / Post / Edit draft / lifecycle chips).
- `features/journals/data/repositories/journal_repository_impl.dart`
  (SQLite `lifecycleStatus: draft/posted/reversed`, outbox, sync events
  `journal.created/updated/posted/reversed`).
- `features/sales/presentation/invoice_form_screen.dart`,
  `invoice_form_notifier.dart` (sends `post_on_create: false`,
  "Save as Draft" button), `invoice_detail_screen.dart` (edit/cancel/delete
  gated on status), `invoice_list_screen.dart`, status chips, timeline.
- `features/purchases/vendor_bills/...` (`post_on_create: false`),
  `features/expenses/...`.
- Non-ledger flows that also use DRAFT: sales orders, proformas, delivery
  challans, goods receipts, inventory adjustments (see §6 scope decision).

---

## 3. Current Architecture (how it works today)

### 3.1 Ledger layer
- `LedgerPostingEngine` builds a validated, balanced `JournalEntryDraft`
  (in-memory only — despite the name, **not** a persistent draft).
- `commit_ledger_draft(db, tenant, draft)` inserts one `JournalEntry` + its
  `JournalLine`s and recomputes `Account.current_balance` for affected accounts.
  It runs inside the caller's DB session, so document creation + posting are
  one transaction whenever the endpoint commits once at the end.
- `JournalEntry` is immutable-by-guard: `is_locked=True` default, a
  `before_update` event raises `IntegrityError`, unique
  `(tenant_id, source_type, source_id)` and `(tenant_id, reference_number)`.
  **Note:** the guard blocks UPDATE but *not* DELETE — bills.py deletes rows
  directly.
- `_check_no_existing_posting()` uses `SELECT FOR UPDATE` to block duplicate
  postings of the same document (idempotency at the posting level).

### 3.2 Document statuses
- Ledger documents use `status` with CHECK constraints that include `DRAFT`:
  Invoice `('DRAFT','POSTED','SENT','PARTIALLY_PAID','PAID','CANCELLED')`,
  Bill `('DRAFT','POSTED','UNPAID','PARTIALLY_PAID','PAID','CANCELLED')`,
  Expense `('DRAFT','POSTED','CANCELLED')`, CN/DN `('DRAFT','POSTED','ISSUED','CANCELLED')`.
- Workflows: Invoice/Bill/CN/DN support `post_on_create` (backend default
  **true**) or explicit `/finalize`; Expenses require explicit `/post`;
  Returns and Payments post immediately.
- Cancellation creates a reversing `JournalEntry` (+ stock reversal), sets
  `CANCELLED`, records `cancelled_at`/`cancelled_by`.

### 3.3 Manual journals
- `POST /journals` validates balance + accounts + period and posts immediately
  (there is **no server-side journal draft**).
- `POST /journals/{id}/reverse` creates a `JOURNAL_REVERSAL` entry with flipped
  lines and `source_id = original.id`; 409 if already reversed. The original is
  left untouched. There is no link *back* from the original to its reversal,
  and no replacement/correction flow.

### 3.4 Offline sync (ApexBooks)
- Client writes to SQLite with `lifecycleStatus` draft/posted/reversed and an
  outbox of sync operations carrying `idempotency_key`.
- Server: `journal.created` / `journal.updated` → `_handle_journal_draft`
  (validates but **never touches the ledger**; the event stream is the durable
  record of the draft). `journal.posted` / `journal.reversed` →
  `_handle_journal_posted` (commits to ledger, dedups on
  `(source_type, source_id)`). Sync events are stored idempotently by
  `event_id`.

### 3.5 Audit
- `set_audit_context()` captures `actor_id`/`actor_email`/`ip`/`user_agent`
  from the authenticated request (never client-supplied). `before_flush`
  listeners record created/updated/deleted with before/after state, inserted in
  the same transaction (`after_flush_postexec`). Action naming special-cases
  `DRAFT → POSTED` transitions ("invoice.finalized") — these mappings become
  obsolete under direct posting.

### 3.6 Reports / queries / workers
- Dashboard, GST, e-invoice, e-way bill, bank reconciliation, workers and
  year-end readiness all filter on `status NOT IN ('DRAFT',...)` or count
  "unposted documents". Under direct posting these guards become no-ops.

---

## 4. Gap Analysis — what violates the target today

1. **Frontend still creates drafts by default** for invoices and bills
   (`post_on_create: false` in both form layers) and expenses have no
   auto-post at all. This is the persistent draft workflow the request removes.
2. **Silent rewrite of posted bills** (`bills.py` update path) — deletes JE +
   lines + stock ledger rows, mutates `Product.current_stock`, re-posts.
   Violates "posted transactions must not be silently edited or deleted".
3. **`JournalEntry` lacks actor/source/reversal metadata**: no `created_by`,
   `posted_by`, `posted_at`, channel, or reversal-link columns. The who/when is
   only in `AuditLog` (fine for audit, but not queryable on the ledger record).
4. **The `is_locked` guard does not prevent DELETE** — deletion of journal rows
   is possible (as bills.py does).
5. **No idempotency at the document level** for double-click/retry on create
   endpoints (only the journal-level `(source_type, source_id)` unique + sync
   outbox keys). A double-submitted invoice can create two DRAFTs today.
6. **Reversal chain is one-directional and manual-journal-only** — no
   replacement/corrected transaction flow, no link from original to reversal.
7. **Obsolete Draft machinery remains**: `post_on_create` flag, `/finalize` and
   `/post` endpoints, status filters, "Edit draft" UI, tests asserting DRAFT.

---

## 5. Target Architecture — Direct Posting

### 5.1 Transaction lifecycle

```
User submits transaction
  → validate (balance, accounts, period open, permissions, stock)
  → post atomically in ONE DB transaction:
      insert document (status = business state, e.g. POSTED/SENT/UNPAID)
      build balanced JournalEntryDraft via LedgerPostingEngine
      commit_ledger_draft → JournalEntry + JournalLines + account balances
      update stock ledger (if goods)
      record audit (actor, timestamp, before/after) — same transaction
  → transaction becomes immutable accounting history
```

- There is **no DRAFT state** for ledger-touching documents.
- The `status` column stays for *business* states (SENT/UNPAID/PARTIALLY_PAID/
  PAID/CANCELLED) but `DRAFT` is removed from ledger-document CHECK constraints.
- **Corrections** (replacing the current cancel/reversal flows, which already
  exist for most documents, plus manual journals):

```
Original posted transaction
  → reversal transaction (reversing JE, linked via source_id + reversal fields)
  → optional corrected/replacement transaction (new document or journal)
  → all records linked; who/when recorded on each; original never modified
```

### 5.2 Schema changes (field mapping — reuse before adding)

Per the instruction "do not blindly add fields if equivalents exist", the plan
reuses: `source_type`/`source_id` (already the canonical document→journal link
and reversal link), `cancelled_by`/`cancelled_at` (already on Invoice/Bill/
Expense/CN/DN), `created_at`/`updated_at` (already everywhere), and the
`AuditLog` actor trail.

**Additions to `journal_entries`** (the ledger record — minimal, high-value):

| Column | Type | Purpose |
|---|---|---|
| `created_by` | UUID (FK users) | actor who created the entry — set server-side from audit context, never client input |
| `posted_by` | UUID (FK users) | same as created_by for direct-posting entries; populated for legacy rows from audit log where possible |
| `posted_at` | timestamptz | posting timestamp (defaults to created_at for legacy rows) |
| `source_channel` | varchar | `UI` / `API` / `IMPORT` / `RECURRING` / `SYNC` — request-derived (imports/recurring/sync set it explicitly) |
| `reversed_by` | UUID (FK users) | actor who reversed this entry |
| `reversed_at` | timestamptz | when reversed |
| `reversal_transaction_id` | UUID self-FK | set on the **original** → points at its reversal entry |
| `reverses_transaction_id` | UUID self-FK | set on the **reversal** → points at the original |
| `replacement_transaction_id` | UUID self-FK | set on the **original** → points at the corrected/replacement entry |
| `original_transaction_id` | UUID self-FK | set on a **replacement** → points at the original it replaces |

**Additions to ledger documents** (Invoice, Bill, Expense, CreditNote,
DebitNote — one migration):

| Column | Purpose |
|---|---|
| `created_by` | actor who created/posted the document (server-derived) |
| `reversed_by`, `reversed_at` | mirror of the cancel fields (reuses `cancelled_by`/`cancelled_at` semantics — we keep both and treat CANCELLED as the reversal terminal state) |
| `replacement_id` | new corrected document that replaces this one |
| `replaces_id` | this document replaces `replaces_id` |

**Delete guard:** extend the `JournalEntry` event to block `before_delete` as
well as `before_update` — the ledger becomes delete-proof at the ORM/database
layer. (Optionally a Postgres trigger for defense in depth.)

**Draft disposition (see §8):** existing DRAFT ledger documents are handled by
an explicit review workflow; `DRAFT` is removed from ledger-doc CHECK
constraints only after the data migration confirms zero remain. Non-ledger
documents (sales orders, proformas, delivery challans, goods receipts,
inventory adjustments) keep `DRAFT` — they are business work items, not
accounting transactions (see §6 decision).

### 5.3 Idempotency (double-click / retry safety)

- **Journal level (exists):** unique `(tenant_id, source_type, source_id)` +
  `_check_no_existing_posting` (SELECT FOR UPDATE) + sync outbox keys.
- **Document level (new):** each ledger document gets a
  `client_transaction_id UUID` column with a unique `(tenant_id,
  client_transaction_id)` constraint. The frontend generates one UUID per form
  submission (reusing its existing `IdempotencyKey`-style outbox key) and sends
  it on create/post. On conflict the endpoint returns the **existing** document
  (200) instead of creating a duplicate (or 409 with a clear message).
- Submit buttons become single-flight (disabled while in flight) on top of this.
- Reversal endpoints already 409 on double-reverse; this stays.

### 5.4 Audit logging (extends the existing mechanism — no rework needed)

- `set_audit_context` already derives the actor from the authenticated request.
- New explicit action strings: `journal.posted`, `journal.reversed`,
  `journal.corrected`, `{entity}.posted`, `{entity}.reversed`.
- The obsolete `DRAFT → POSTED` special-casing in `_action_name` is removed.
- Correction flows log: who reversed, when, reversal reference, replacement
  reference (already have before/after state capture for free).

### 5.5 Permissions

- Keep `ledger:view` / `ledger:manual_post` and per-document
  `{entity}:create/update/cancel`.
- Under direct posting, **create implies post** — no separate "post" permission
  is needed for UI flows.
- Corrections: reversing a document stays under the existing `{entity}:cancel`;
  manual-journal reversal stays under `ledger:manual_post`. A new
  `transaction:correct` permission is **optional** and not added unless you want
  a distinct role boundary.

### 5.6 Reports / ledger queries

- Ledger reports (trial balance, P&L, balance sheet, ledger card) already read
  only `journal_lines` — they are inherently "posted-only". No change beyond
  the new reversal-link columns being exposed.
- Dashboard / GST / e-invoice / e-way bill / reconciliation / worker status
  filters (`NOT IN ('DRAFT',...)`) become no-ops; they are left in place as
  defensive filters during the transition, then cleaned up.
- Year-end readiness: the "unposted documents" block is replaced by a check
  that no ledger document is in a non-final state (should always pass under
  direct posting) and that there are no open payment allocations.

### 5.7 Frontend changes

- **Journal form:** replace "Save draft" + "Post" with a single
  "Post journal" action (writes locally as *posted*, syncs `journal.posted`).
  Remove "Edit draft" from the journal list; posted journals get "Reverse"
  only. Local `lifecycleStatus` becomes internal bookkeeping (per requirement 8
  — UI state, never a server-side draft transaction).
- **Invoice / Bill forms:** drop `post_on_create: false` (send `true` or remove
  the flag), rename "Save as Draft" → "Save & Post", remove the `/finalize`
  step and the draft-only edit affordances on detail screens. Edits of posted
  documents are removed; corrections happen via Cancel (+ optional re-issue
  with `replaces_id`).
- **Expense form:** create → auto-post directly; remove the manual `/post`
  step. Draft-only edit/delete affordances removed.
- **CN/DN:** create → auto-post; remove finalize step.
- Status chips/timelines for ledger docs stop showing "Draft".

---

## 6. Decisions Required From You (before implementation)

1. **Scope — non-ledger documents.** Sales Orders, Proformas, Delivery
   Challans, Goods Receipts and Inventory Adjustments use DRAFT/ISSUED/
   CONFIRMED workflows but are **not accounting transactions** (requirement 8
   explicitly allows separate non-ledger work items). Recommendation: leave
   their workflows unchanged. Confirm?
2. **Disposition of existing drafts** — see §8. Recommendation: post-or-delete
   review list per tenant; default = leave as archived work items, never
   auto-post.
3. **`status` column:** keep business states (SENT/UNPAID/PAID/CANCELLED) and
   drop only `DRAFT` from ledger-document constraints — or remove the column
   entirely and derive state? Recommendation: keep the column (payments,
   e-invoice and display logic depend on it).
4. **`source_channel` values:** propose `UI | API | IMPORT | RECURRING | SYNC`.
   OK?
5. **Optional `transaction:correct` permission** — add or reuse existing?

---

## 7. Accounting & Data-Integrity Risks (current → mitigated)

| # | Risk (today) | Mitigation (target) |
|---|---|---|
| 1 | Posted bill edit deletes JE/stock rows and re-posts (silent rewrite, audit log still shows "updated") | Block all updates to posted ledger documents at the API layer; enforce with the extended delete-proof guard; corrections only via reversal + replacement with linkage |
| 2 | Drafts are un-balanced/un-validated work in progress that can linger in "unposted" counts and block year-end | No drafts for ledger docs; year-end check replaced |
| 3 | Duplicate submission (double-click) can create duplicate documents / postings | `client_transaction_id` unique per tenant + single-flight submit buttons + existing `(source_type, source_id)` uniqueness |
| 4 | Partial posting on validation failure (if an endpoint ever committed before posting) | Enforced single-transaction posting; new tests assert rollback leaves no partial JE/lines/balance changes |
| 5 | `is_locked` guard bypassable via DELETE | `before_delete` guard (+ optional trigger); delete endpoints restricted to never-posted legacy drafts |
| 6 | Actor identity could be spoofed if a client passed `created_by` | All actor fields set server-side from audit context; client-supplied actor fields rejected |
| 7 | Reversals don't link back to the original; no replacement flow | Reversal/replacement linkage columns + correction endpoints |
| 8 | Reports might include draft data if filters regress | Reports read only `journal_entries` (all posted by construction); integration tests assert drafts never reach the ledger |

---

## 8. Migration Strategy & Disposition of Existing Drafts

**Guiding rule (requirement 6): existing drafts are NEVER auto-posted without
human review.**

### Phase 0 — Non-destructive preparation (safe to run at any time)
1. Add the new columns (§5.2) with nullable defaults — no data rewrite.
2. Add the `before_delete` guard on `JournalEntry`.
3. Add `client_transaction_id` support to ledger-doc create/post endpoints
   (idempotency) — additive.
4. Add `created_by`/`posted_by`/`posted_at`/`source_channel` population in
   `commit_ledger_draft` from the audit context — additive.
5. Ship a **Draft Review Report** (`scripts/review_ledger_drafts.py`): lists
   every DRAFT Invoice/Bill/Expense/CN/DN per tenant with number, date, amount,
   age, and the creating actor (from `AuditLog`), plus a summary count.

### Phase 1 — Data review (human-in-the-loop, per tenant)
The script supports three explicit dispositions per draft (no bulk auto-post):
- `--post <document_id>` — post through the *normal* validated path
  (auto_post + journal + balances + stock + audit), recording
  `source_channel = 'IMPORT'`/`MIGRATION` and the reviewing admin as actor.
- `--delete <document_id>` — soft-delete with audit (drafts only).
- `--archive` — move the draft row into a new **`pending_documents`** table
  (a non-ledger work item per requirement 8) so the ledger tables contain no
  drafts while the data is not lost.

Preflight gate: the destructive migration refuses to run while any DRAFT
ledger document remains.

### Phase 2 — Destructive schema migration (only after Phase 1 gate passes)
1. Remove `DRAFT` from the status CHECK constraints of Invoice, Bill, Expense,
   CreditNote, DebitNote (non-ledger docs keep theirs).
2. Make the new actor/reversal columns `NOT NULL` where sensible (backfill
   `posted_by`/`posted_at` for existing POSTED rows from `AuditLog` first; where
   unknown, use a `system` sentinel recorded in a migration audit note).
3. Drop the `post_on_create` flag from request schemas (or force `true`).

### Phase 3 — Code removal (only after nothing depends on it)
- Remove `/finalize` (bills, invoices, CN/DN) and `/post` (expenses) endpoints
  once the frontend no longer calls them; keep them as idempotent no-ops during
  the transition window if old app versions are live.
- Remove `post_on_create` handling, draft status filters, draft-only edit/
  delete affordances, "Edit draft" UI, obsolete tests.
- Replace bills.py update-on-posted path with a **reject** (posted bills cannot
  be edited) + cancel/re-issue flow.
- Remove obsolete audit action special-casing.

### Rollback
All migrations are reversible via Alembic `downgrade`; Phase 0 changes are
purely additive; Phase 2 is gated by the draft-free preflight and is the only
step that alters CHECK constraints.

---

## 9. Implementation Plan (once approved) — mapped to your checklist

1. ✅ **Affected inventory** — this document (§2) plus a grep-audit annex.
2. ✅ **Current architecture explained** — §3.
3. ✅ **Target architecture** — §5.
4. ✅ **Risks** — §7.
5. ✅ **Migration strategy** — §8.
6. ✅ **Draft disposition** — §8 Phase 1.
7. **Schema** — Alembic migrations: journal actor/reversal/link columns +
   delete guard; document `created_by`/replacement columns +
   `client_transaction_id`; `pending_documents` table; CHECK constraint changes
   (Phase 2).
8. **Backend services/APIs** — `commit_ledger_draft` actor/channel population;
   auto-post for expenses; enforce `post_on_create=true`; block updates to
   posted ledger docs (bills.py); new correction endpoints (reverse +
   optional replacement with linkage); idempotency-key handling on create/post;
   year-end readiness rework.
9. **Frontend flows** — journal single-action post; invoice/bill/expense/CN/DN
   save-and-post; remove Draft controls/chips/finalize steps; single-flight
   submit buttons sending `client_transaction_id`.
10. **Reversal/correction** — manual-journal replacement flow; document cancel
    keeps existing reversal engine and gains linkage columns; frontend
    "Reverse"/"Cancel & re-issue" actions.
11. **Permissions & audit** — actor fields from context; new audit action
    strings; remove obsolete DRAFT→POSTED special-casing; optional
    `transaction:correct`.
12. **Reports/queries** — expose reversal links; tidy year-end unposted check;
    defensive filters retained then cleaned.
13. **Tests updated** — every test asserting DRAFT creation/finalize/post
    (≈33 test functions across 15+ files) moves to direct-posting assertions.
14. **New tests** — atomic posting (mid-failure rollback), balanced journals,
    permissions, reversals (409 double-reverse, linkage), audit history (actor,
    before/after), duplicate submissions (idempotency), failed postings
    (locked period, invalid account, negative stock).
15. **Dead-code removal** — only after Phase 2/3 gates and a full
    grep confirmation that nothing references the removed symbols.

---

## 10. Open Questions to Approve

1. Proceed with implementation of Phase 0 + Phase 1 tooling first (non-
   destructive), pausing before Phase 2 destructive migration? 
2. Confirm the §6 decisions (non-ledger docs unchanged; draft disposition
   policy; keep `status` column; channel values).
3. Do you want the Draft Review Report + script built now so you can run it
   against production data before any code change?
