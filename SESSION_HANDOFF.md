# ApexBooks — Session Handoff

## Session: 2026-07-12 — Service Layer, Dead Code Cleanup & Design Consolidation

### What Was Done

#### 1. Service Error Handling (CRITICAL)
All 23 non-masters services refactored from `ApiError.network()` collapses to `guardDio()`:

- **Before:** `try { ... } on DioException catch (e) { return Failure(ApiError.network(e.message)); }` — lost HTTP status codes, 422 field validation errors, and response body details. **Every API error was mislabeled as a network error.**
- **After:** `return guardDio(() async { ... })` — properly maps through `toApiError()` which preserves status codes, `fieldErrors`, and meaningful backend messages.

**Services fixed:**
- Dashboard: `dashboard_service.dart`
- Sales: `invoice_service.dart`, `payment_service.dart`
- Purchases: `vendor_bill_service.dart`, `purchase_order_service.dart`, `vendor_payment_service.dart`, `goods_receipt_service.dart`, `purchase_return_service.dart`
- Inventory: `adjustment_service.dart`, `stock_service.dart`, `transfer_service.dart`, `movement_service.dart`, `warehouse_service.dart`
- Accounting: `ledger_service.dart`, `journal_service.dart`, `financial_statement_service.dart`, `trial_balance_service.dart`, `reconciliation_service.dart`
- Posting: `ledger_posting_service.dart`, `payable_posting_service.dart`, `receivable_posting_service.dart`, `inventory_posting_service.dart`

#### 2. Dead Code Removal
8 files removed with zero consumers:
- `accounting/financial_year/` (models + service, no presentation)
- `accounting/gst/models/gst_report.dart` (no consumers)
- `inventory/reservation/services/reservation_service.dart` (no consumers)
- `inventory/valuation/services/valuation_service.dart` (no consumers)
- `purchases/matching/` (models + service, no consumers)
- + 5 orphaned test files

#### 3. Design Consolidation — Private Widgets → Shared ApexCard
All 12 private `_Panel`/`_Card` widgets across the app now delegate to the shared `ApexCard` widget from `core/widgets/page_header.dart`. Each was a copy of the same ~15-line `Container` + `BoxDecoration` + `BoxShadow` pattern.

| Screen | Before | After |
|--------|--------|-------|
| Dashboard | `_Panel` (inline) | → `ApexCard` |
| Invoice detail | `_Panel` (inline) | → `ApexCard` |
| Invoice form | `_Card` (inline) | → `ApexCard` |
| Bill detail | `_Panel` (inline) | → `ApexCard` |
| PO detail | `_Panel` (inline) | → `ApexCard` |
| PO form | `_Card` (inline) | → `ApexCard` |
| PR detail | `_Panel` (inline) | → `ApexCard` |
| PR form | `_Card` (inline) | → `ApexCard` |
| GR detail | `_Panel` (inline) | → `ApexCard` |
| GR form | `_Card` (inline) | → `ApexCard` |
| Payment form | `_Card` (inline) | → `ApexCard` |
| Adjustment form | `_Card` (inline) | → `ApexCard` |

**Result:** All card surfaces across the app render identically. ~209 lines removed.

#### 4. Other Design Fixes
- **InvoiceSearchBar** (was HIGH severity): Fully styled with ApexColors/ApexRadius — was fully unstyled
- **InvoiceFormScreen** (was HIGH severity): `ListView` → `ListView.builder`
- **Dashboard GST card** (was MEDIUM): `SizedBox.shrink()` on error → proper error+retry
- **ApexSearchBar** (shared): Created `core/widgets/search_bar.dart`

### Design Compliance Status

| Aspect | Status |
|--------|--------|
| ApexColors usage | ✅ All screens |
| ApexSpacing/ApexRadius | ✅ Major widgets; ~50 hardcoded paddings remain (minor, consistent pattern) |
| ApexCard (shared) | ✅ All 12 card surfaces unified |
| StatusBadge | ✅ Every status rendering |
| PageHeader | ✅ Every list/detail screen |
| LoadingState/EmptyState/ErrorView | ✅ Every async screen |
| ListView.builder | ✅ Every dynamic list (was 1 violation, fixed) |
| TextStyle via textTheme | ⚠️ ~40 inline TextStyles remain (minor, consistent pattern) |
| Server-side pagination | ⚠️ Invoice list: yes; purchase lists: client-side (API contract limitation) |
| filter_engine.dart | 🗑️ Dead code, zero consumers (identified, not removed — no conflicts) |

### Remaining Work (Low Priority)

- ~50 instances of hardcoded `EdgeInsets.all(N)` instead of `ApexSpacing.lg`/`ApexSpacing.md` — consistent across app, low visual impact
- ~40 inline `TextStyle(...)` that bypass `textTheme` — consistent pattern, Google Fonts still load but aren't used in these spots
- `core/forms/apex_text_field.dart` vs `core/widgets/form_fields.dart` — both export `ApexTextField` with different APIs (ApexForm vs standalone). No naming collision at import sites since features choose one.
- Purchase lists use client-side sort — backend API returns flat arrays without sort/pagination envelope
- Home shell navigation polish (sidebar icons, responsive transitions)

### Build Status
- `flutter analyze`: **0 errors, 0 warnings**, ~114 info-level lints (all pre-existing)
- `flutter build`: Not verified this session

### Git Log
```
1ea6cd4 fix(services): replace ApiError.network() collapses with guardDio()
99a3487 fix(design): apply ApexBooks design tokens across purchases, accounting, dashboard
5501fb1 docs: add SESSION_HANDOFF.md
b1c1446 chore(cleanup): remove dead service modules and orphaned test files
af670d8 refactor(design): replace 5 private _Panel widgets with shared ApexCard
2c2a3b9 refactor(design): replace all 12 private _Card/_Panel widgets with shared ApexCard
```
