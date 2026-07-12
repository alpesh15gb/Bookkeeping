# ApexBooks UI Redesign — Pickup Document

## Current State (2026-07-07)

### Project Context
- Production Flutter ERP with live API at https://api.apexbooks.in
- Uses GoRouter for navigation, Riverpod for state management
- Architecture: core/ (repositories, services, models, API contracts) is stable and must NOT be modified
- Only presentation layer should be changed

### Analyzer Status: ✅ 0 errors, 0 warnings
Full project dart analyze passes cleanly.

---

## Batch Completion Status

### ✅ Batch 1 — App Shell + Navigation
**Goal**: Enterprise sidebar + header with GoRouter-based navigation.

**Completed**:
- home_shell.dart refactored to use Scaffold with collapsible NavigationRail
- home_shell_widgets.dart updated for sidebar + header components
- AppDrawer → NavigationRail migration (sidebar)
- Header bar with breadcrumb, global search trigger, profile
- GoRouter preserved as sole navigation system — no MaterialPageRoute introduced
- Responsive layout: sidebar collapses to NavigationRail.minimized on narrower screens
- GoRouterState breadcrumb parsing

**Architecture**: Clean — no core/ touched, no duplicate routing.

---

### ✅ Batch 2 — Dashboard KPI Refactor

**Completed**:
- dashboard_screen.dart — all FABs removed; KPI layout changed from 4 wide cards to a responsive grid using KpiCardGrid widget
- kpi_card_grid.dart — new reusable widget with SliverGrid layout
- BaseCrudController integration for DashboardController
- DashboardProvider wired to existing DashboardService (no new API calls)
- Overdue alerts section added (data already fetched, just wasn't displayed)

**Architecture**: Clean — only presentation/state wiring changed.

---

### ✅ Batch 2.5 — Stabilization

**Completed**:
- dart analyze brought to 0 errors, 0 warnings
- Removed stale/duplicate widget circular_icon_button.dart
- Removed unused eedback_barrel.dart
- Removed duplicate sales_barrel.dart
- Removed unused import in invoice_detail_screen.dart
- Verified GoRouter is the single navigation standard
### ✅ Batch 3 — Invoice List (Table, Search, Split View)

**Completed**:
- **invoice_search_bar.dart** (new) — debounced search bar, reusable with any ApexTableController
- **invoice_table_body.dart** (new) — lightweight table with:
  - Sticky header (surfaceMuted background)
  - 5 columns: Code, Customer, Date, Total (right-aligned), Status
  - Sortable headers with arrow indicators
  - Status badges (draft/posted/sent/partial/paid/cancelled)
  - Row selection highlighting
  - Horizontal scroll for overflow
- **invoice_list_screen.dart** — cleaned up:
  - Removed duplicate _InvoiceSearchBar class (moved to separate file)
  - Removed unused imports (dart:async, pp_constants, invoice_status.dart)
  - Added dio_extensions.dart import for Paged<T>
  - Split-view layout: list (flex: 3) + detail inspector (380px) right panel
  - MaterialPageRoute still used for 'New Invoice' (preserved existing)
  - Pagination via ApexPaginationControls
  - Empty/loading/error states from states.dart

---

## Workspace Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Navigation | GoRouter (single) | Prevents dual-navigation drift |
| Table widget | Custom InvoiceTableBody (not ApexDataTable) | InvoiceListItem doesn't extend BaseModel; forcing model change prohibited |
| State mgmt | Riverpod (existing) | No new providers unless gap proven |
| Invoice detail | Right-panel inspector (380px) | Preserves list context; Esc/dismiss pattern |
| Invoice form | Full-screen (preserved) | Complex multi-section form needs full width |
| Search | Debounced, driven by ApexTableController | Reusable across CRUD screens |
---

## Remaining Issues / Known Gaps

1. **MaterialPageRoute** in invoice_list_screen.dart — 'New Invoice' still uses Navigator.of(context).push(MaterialPageRoute(...)). Should be migrated to GoRouter when a named route is added.

2. **Paged vs BaseCrudController pattern mismatch** — InvoiceListProvider returns InvoiceListResponse, not Paged<T>. The Paged<InvoiceListItem> is created in build as a bridge for ApexPaginationControls.

3. **Custom table vs ApexDataTable** — Invoice module diverges because InvoiceListItem doesn't extend BaseModel. If refactored in future, replace with ApexDataTable<InvoiceListItem>.

---

## Screens Already Transformed

| Screen | Status | Batch |
|--------|--------|-------|
| home_shell.dart | ✅ | 1 |
| home_shell_widgets.dart | ✅ | 1 |
| dashboard_screen.dart | ✅ | 2 |
| kpi_card_grid.dart | ✅ (new) | 2 |
| invoice_list_screen.dart | ✅ | 3 |
| invoice_search_bar.dart | ✅ (new) | 3 |
| invoice_table_body.dart | ✅ (new) | 3 |

## Screens Pending

| Screen | Priority | Batch | Dependencies |
|--------|----------|-------|-------------|
| invoice_detail_screen.dart | Medium | 3.5 | Batch 3 foundation |
| invoice_form_screen.dart | High | 4 | GoRouter integration |
| contact_list_screen.dart | Medium | 4 | Contacts module |
| product_list_screen.dart | Medium | 4 | Products module |
| Banking screens | Medium | 5 | Banking module |
| Accounting screens | High | 6 | Accounting module |
| Settings screens | Low | 7 | Settings module |
---

## Architecture Rules (Non-Negotiable)

1. **GoRouter** is the single navigation source. Do not introduce Navigator.push / MaterialPageRoute.
2. **No new models, services, repositories, or providers** unless proven necessary.
3. **Never modify core/** — no changes to core/ infrastructure, API contracts, business logic.
4. **Reuse before create** — search the codebase before creating any new widget.
5. **Never delete** infrastructure until proven unused across the entire project.
6. **Surgical edits only** — never rewrite a file; edit only the smallest fragment.
7. **After every change**: run dart analyze and achieve 0 errors, 0 warnings before continuing.

---

## Quick Reference: Key Files

| File | Purpose |
|------|---------|
| lib/core/routing/app_router.dart | GoRouter definition |
| lib/core/tables/table_controller.dart | ApexTableController, ApexTableState |
| lib/core/tables/table_column.dart | ApexColumn<T>, TableSort |
| lib/core/api/base_model.dart | BaseModel, SortDirection |
| lib/core/network/dio_extensions.dart | Paged<T>, parsePaged() |
| lib/core/crud/base_crud.dart | BaseCrudController, BaseCrudState |
| lib/core/theme/app_colors.dart | ApexColors |
| lib/core/formatting/number_formatting.dart | NumberFormatter |
| lib/core/widgets/page_header.dart | PageHeader |
| lib/core/widgets/states.dart | LoadingSpinner, ErrorView, EmptyState |
| lib/features/sales/presentation/invoice_list_screen.dart | Invoice list with split-view |
| lib/features/sales/presentation/invoice_search_bar.dart | Reusable debounced search |
| lib/features/sales/presentation/invoice_table_body.dart | Custom table body for invoices |
| lib/features/sales/presentation/invoice_list_provider.dart | Riverpod provider for invoice list |
| lib/features/sales/presentation/invoice_detail_screen.dart | Invoice detail (right panel) |
| lib/features/sales/presentation/invoice_form_screen.dart | Invoice creation/editing |

---

## Next Immediate Step
**Batch 3.5**: Clean up remaining MaterialPageRoute usage, then proceed to Invoice Form or Contacts transformation.

*Last updated: 2026-07-07*
