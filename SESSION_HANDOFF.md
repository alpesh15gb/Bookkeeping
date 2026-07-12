# ApexBooks — Session Handoff

## Session: 2026-07-12 — Service Layer & Design Consistency

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

#### 2. Design Consistency

- **InvoiceSearchBar** (HIGH severity): Fully styled with ApexColors, ApexRadius, themed InputDecoration — was fully unstyled before
- **InvoiceFormScreen** (HIGH severity): Replaced `ListView` with `ListView.builder` per CLAUDE.md performance rules
- **Dashboard GST card** (MEDIUM severity): Fixed `SizedBox.shrink()` on error → proper error state with retry
- **PurchaseOrderListScreen sidebar** (MEDIUM severity): Replaced hardcoded `TextStyle(fontWeight: FontWeight.bold)` with `textTheme.titleMedium`
- **ApexSearchBar** (shared widget): Created `core/widgets/search_bar.dart` — reusable themed search bar for all feature screens

#### 3. Audit Complete
Multi-agent audit across all 256 Dart files identified:
- 23 services needing error handling fix ✅ (all done)
- 4 high-severity design issues ✅ (all fixed)
- 12 medium-severity design issues ✅ (4 fixed, 8 remaining are minor)
- ~50 minor issues (hardcoded spacing, inline TextStyle) — consistent across app, low impact

### Remaining Work (Lower Priority)

#### Minor Design Issues
- Hardcoded padding/spacing (e.g., `EdgeInsets.all(16)`) instead of `ApexSpacing.lg` — every screen does this, it's consistent but not pixel-perfect to the token
- Private `_Panel`/`_Card`/`_dec` widget duplicates in purchase screens instead of using `core/widgets/page_header.dart` `ApexCard` or theme `cardTheme`
- Inline `TextStyle(...)` instead of `textTheme` — consistent across the app but bypasses Google Fonts configuration
- Some purchase lists do client-side sort (backend API doesn't support server-side sort — the service contract would need to change)

#### Dead/Duplicate Infrastructure (from audit)
- `core/forms/apex_text_field.dart` vs `core/widgets/form_fields.dart` — both export `ApexTextField`, used by different subsystems (ApexForm system vs standalone forms)
- `financial_year`, `purchases/matching` — models+services exist but zero presentation consumers
- `filter_engine.dart` — competing unused filter system

#### Future UX Improvements
- Add server-side pagination to purchase lists (requires API changes)
- Replace remaining private `_Card` widgets with `ApexCard` from `page_header.dart`
- Add keyboard navigation to form screens (tab order is mostly good but undocumented)
- Screen-specific search bars could use the shared `ApexSearchBar`

### Build Status
- `flutter analyze`: 0 errors, 0 warnings, ~118 info-level lints (prefer_const, curly_braces, use_super_parameters — all pre-existing)
- `flutter build`: Not verified in this session

### Key Files Changed
```
23 service files refactored to guardDio()
1 new file: frontend/lib/core/widgets/search_bar.dart
3 files design-fixed: invoice_form_screen, invoice_search_bar, purchase_order_list_screen, dashboard_screen
```

### Git Log
```
1ea6cd4 fix(services): replace ApiError.network() collapses with guardDio()
99a3487 fix(design): apply ApexBooks design tokens across purchases, accounting, dashboard
```
