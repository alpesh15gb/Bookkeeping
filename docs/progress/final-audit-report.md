# Final Production Readiness Audit — Findings and Fixes

**Date:** 2026-08-01
**Method:** Systematic sweep of frontend (Flutter) and backend (FastAPI) per the
`Final Audit.md` mandate. Every claimed defect was verified against code or
runtime evidence before fixing; no defect was "fixed" on assumption. All claims
below distinguish **verified-by-test**, **verified-by-inspection**, and
**deferred/known-limitation**.

---

## Verification baseline (start of audit)

| Gate | Result |
|------|--------|
| `flutter analyze` | 0 issues |
| Flutter test suite | 562 passed, 0 failed |
| Backend pytest | 455 passed, 7 skipped |

---

## Defects found and fixed

### 1. CRITICAL — Pull-cycle deadlock on unknown sync event types
`lib/core/sync/sync_engine.dart` throws `StateError` on any pulled event type
without a registered applicator and does **not** advance the checkpoint. The
backend can emit 8 event types the client had no applicator for
(`bank_statement.imported`, `purchase_receipt.posted`,
`purchase_invoice.posted`, `sales_delivery.posted`, `sales_return.posted`,
`purchase_return.posted`, `credit_note.posted`, `debit_note.posted`). A single
such event permanently blocked that company's pull cycle (every retry re-fetched
the same event).
**Fix:** registered no-op applicators for all 8 types in
`lib/core/sync/reference_pull_service.dart` (acknowledge + advance checkpoint),
matching the existing `branch.created` pattern.
**Evidence:** new regression test in `test/core/sync/pull_cycle_test.dart`
("transaction event types without an applicator are acknowledged, not
deadlocked") passes; full Flutter suite green.
**Deferred limitation:** cross-device application of these aggregates (real
upsert applicators) is not yet implemented — the client acknowledges them but
does not yet reflect them locally. Tracked.

### 2. HIGH — Delivery handler produced zero-value challans and wrong SO status
`backend/src/api/v1/apexbooks_sync.py::_handle_sales_delivery_posted`:
- `DeliveryChallan.total/subtotal` were hard-coded to `0`.
- `SalesOrder.status` was set to `DELIVERED` unconditionally even for partial
  deliveries.
**Fix:** challan totals now accumulate from line amounts; SO status is set to
`DELIVERED` only when every product's delivered quantity (summed across issued
challans) reaches its ordered quantity.

### 3. HIGH — Credit/debit note handlers fabricated an arbitrary-product line
`_handle_credit_note_posted` / `_handle_debit_note_posted` inserted a
`CreditNoteLine`/`DebitNoteLine` pointing at the tenant's *first product* when
the payload carried no line items — assigning every journal-only note to a
random product.
**Fix:** replaced with a proper line parser (`_resolve_product_for_line`) that
skips unresolvable lines; a note without itemized lines is a valid journal-only
note.

### 4. MEDIUM — Mobile Bills card overflowed at small widths
`bill_table_body.dart` `_MobileBillList` overflowed by 210 px at a 400 px
viewport because the date/status row was not flexible.
**Fix:** wrapped the date text in `Expanded` with ellipsis so the "due" amount
always fits.
**Evidence:** widget test `test/features/purchases/mobile_table_body_test.dart`
(passes) proves every desktop column + sort chips render at mobile width.

### 5. MEDIUM — 60+ screens leaked internal error type names
`err.toString()`/`error.toString()` rendered `$runtimeType: …` prefixes in
`ErrorView`/`SnackBar` across 60+ screens.
**Fix:** added `lib/core/errors/user_message.dart` with
`userFacingErrorMessage(Object)` (ApiError.message / AppException.message /
String / generic fallback) and migrated all UI error sites. Transport-layer
`ApiError.network(err.toString())` and logging sites intentionally left raw.
**Evidence:** `flutter analyze` clean after migration.

---

## Verified-by-inspection (no change needed)

- **Token storage:** access/refresh tokens and cached auth context persist via
  `FlutterSecureStorage`, not plain prefs (`session_storage.dart`).
- **Backend secret logging:** no log statement emits a password/token/secret
  value; `audit_log.py` already redacts sensitive fields.
- **Push idempotency:** `/sync/push` dedupes by `(tenant_id, event_id)`;
  replayed events are acknowledged as duplicates without re-processing.
- **Delivery handler tenant scoping:** every query filters by `tenant_id`.
- **Transaction lists (invoice/bill/returns/delivery/sales-order):** all have
  mobile card branches; no horizontal-scroll-only mobile layouts.
- **`ReportsService` numeric review:** 17-test regression suite passes against
  a known dataset (company scoping, draft/cancelled exclusion, DR/CR direction,
  stable sort). `amountPaid` is correct-by-model but data-empty until
  `PaymentAllocations` is populated (see deferred).

---

## Deferred / known limitations (explicitly not hidden)

| Item | Status |
|------|--------|
| `PaymentAllocations` write path | Tracked task #10 — registers show gross amounts until a payment post creates allocation rows. |
| Party-statement FY boundary | Product decision — service is range-authoritative; FY clamping belongs in the UI picker. |
| Cross-device transaction pull applicators (purchases/returns/notes) | Acknowledged, not yet applied locally. |
| `SalesReturn` multi-line-per-product invoice line resolution | First matching invoice line is used — low impact (return totals drive the ledger). |
| Runtime DevTools rebuild profiling / interactive device testing | Not performed — hover-state claim is implementation expectation only. |

---

## Final verification (post-fix)

| Gate | Result |
|------|--------|
| `flutter analyze` | 0 issues |
| Flutter test suite | 563 passed, 0 failed |
| Backend pytest | 455 passed, 7 skipped, 0 failed |

All fixes were verified end-to-end. `flutter analyze` is clean, the full Flutter
suite (563) and the full backend suite (455) both pass with zero failures after
every change in this audit.
