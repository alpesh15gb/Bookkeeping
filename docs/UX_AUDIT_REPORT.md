# ApexBooks — Comprehensive UX Audit & Design System Report

> **Version**: 1.0  
> **Date**: 2026-07-27  
> **Audience**: Product, Engineering, Design  
> **Status**: Draft for review

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current Application Assessment](#2-current-application-assessment)
3. [Screen Inventory & UX Ratings](#3-screen-inventory--ux-ratings)
4. [Major UX Problems](#4-major-ux-problems)
5. [Accounting Software UX Research](#5-accounting-software-ux-research)
6. [Competitor Pattern Comparison](#6-competitor-pattern-comparison)
7. [User Personas](#7-user-personas)
8. [Workflow Analysis](#8-workflow-analysis)
9. [Proposed Information Architecture](#9-proposed-information-architecture)
10. [Screen-by-Screen Recommendations](#10-screen-by-screen-recommendations)
11. [Design System Specification](#11-design-system-specification)
12. [Component Inventory](#12-component-inventory)
13. [Accessibility Audit](#13-accessibility-audit)
14. [Responsive Layout Strategy](#14-responsive-layout-strategy)
15. [Flutter Architecture Recommendations](#15-flutter-architecture-recommendations)
16. [Financial Safety Recommendations](#16-financial-safety-recommendations)
17. [Prioritized Implementation Roadmap](#17-prioritized-implementation-roadmap)
18. [Risks and Dependencies](#18-risks-and-dependencies)
19. [Testing Strategy](#19-testing-strategy)
20. [Success Metrics](#20-success-metrics)

---

## 1. Executive Summary

ApexBooks is a functionally rich accounting/ERP application targeting the Indian SMB market with strong GST compliance. The application has 180+ Dart files across 15+ feature modules, a Python/FastAPI backend, and has undergone significant production hardening (383 passing tests, offline sync, Cartunez integration).

**Strengths identified:**
- Solid architectural foundation (Riverpod state management, GoRouter, CRUD abstractions)
- Comprehensive feature coverage (Sales, Purchases, Inventory, GST, Accounting, Banking, Reports)
- Consistent theming system (ApexColors, ThemeExtensions, Google Fonts)
- Good responsive framework bones (ResponsiveLayout with mobile/tablet/desktop breakpoints)
- Proper async state handling (loading/error/data patterns via `states.dart`)
- Skeleton loaders and shimmer animations for perceived performance
- Keyboard shortcut support (Ctrl+S save, Ctrl+K command palette, Alt+N add line)
- Permission-gated UI elements
- Command palette for quick navigation
- Master-detail split-view on desktop
- Sticky totals bar on invoice form
- QR code/barcode scanning for inventory

**Critical weaknesses identified:**
1. **No unified filter/search/date-range component** — every screen implements its own search with duplicated code
2. **Breadcrumbs widget exists but is never used** — navigation depth is invisible
3. **Missing screens per product spec** — 20+ screens flagged as ⚠️ MISSING in the spec
4. **Bank reconciliation is a thin list-only screen** — the critical side-by-side matching workflow is absent
5. **Expense screen mixes service logic with UI** — no proper state management abstraction
6. **Journal form uses raw `setState`** — inconsistent with Riverpod pattern used everywhere else
7. **No unified dialog system** — `dialog_service.dart` exists alongside raw `showDialog` calls
8. **Date-range selection is ad-hoc** — each report screen manages its own date state providers
9. **No column visibility controls** on any data table
10. **No bulk operations** on any list screen
11. **`_Panel` and `_Card` naming collisions** — multiple screens define private card wrappers instead of using shared `ApexCard`
12. **Monetary values formatting uses `fontFeatures` inconsistently** — tabular figures are used in some places but not universally
13. **No unified empty state for search results** — each screen handles "no results" differently
14. **No confirmation for irreversible actions** in several flows
15. **Accessibility gaps**: No screen-reader semantics, touch targets may be undersized on desktop, color-only status indicators

**Priority recommendation**: Begin with a unified filter/search/date-range system, then standardize form patterns, then tackle the missing reconciliation screen, then layer on the design system refinements. This report details the full roadmap.

---

## 2. Current Application Assessment

### 2.1 Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend framework | Flutter (SDK ^3.8.0) |
| State management | Riverpod 2.6 (StateNotifier + FutureProvider + ValueNotifier) |
| Navigation | GoRouter 14.6 |
| HTTP client | Dio 5.7 |
| Fonts | Google Fonts (Instrument Sans / Inter / JetBrains Mono) |
| Charts | fl_chart 0.70 |
| Storage | flutter_secure_storage + shared_preferences |
| Localization | intl 0.20 |
| Backend | Python FastAPI + SQLAlchemy + SQLite |
| Dev tools | flutter_lints, custom_lint, riverpod_lint |

### 2.2 Architecture Assessment

**Strengths:**
- Clean feature-based folder structure (`features/{module}/{submodule}/presentation/`)
- Consistent CRUD abstractions (`BaseRepository`, `BaseCrudController`, `BaseListScreen`)
- Generic data table widget (`ApexDataTable<T>`)
- Theme extension pattern for semantic colors
- Responsive breakpoint system with `ResponsiveLayout`
- Well-structured API client with interceptors and refresh token handling

**Weaknesses:**
- Some screens use raw `setState` instead of Riverpod (expense form, journal form)
- Service code mixed into widget files (expense screen has `ExpenseService` in the same file)
- No shared filter bar component — each screen builds its own
- Missing `AuthState` sealed class — uses string-based status checks
- No feature-level error boundary widgets
- No analytics/tracking abstraction
- Route definitions are flat GoRouter routes — no deep-link handling for transactional screens

### 2.3 State Management Patterns

**Used consistently across the app:**
- `AsyncValue` (loading/error/data) for API data
- `StateNotifier` for form state (except journal and expense which use `setState`)
- `FutureProvider.autoDispose` for list data
- `ChangeNotifierProvider` for table controller
- `ValueNotifier` for auth state (wired to GoRouter refreshListenable)

**Notable gaps:**
- No `AsyncNotifier` usage (Riverpod 2.6+ supports this)
- Form state is not persisted across navigation
- No optimistic updates for any write operation
- No loading overlay pattern for transaction submissions

### 2.4 Navigation Architecture

- GoRouter with auth-aware redirect
- Three auth states: `initial` (splash), `unauthenticated` (login), `authenticated` (app)
- All transactional screens push via `Navigator.of(context).push(MaterialPageRoute(...))`
- No named routes for deep-linking to specific invoices/bills
- Back navigation uses `Navigator.of(context).maybePop()` with unsaved-changes guard
- Router provider listens to auth controller for reactive redirects

---

## 3. Screen Inventory & UX Ratings

### Legend

| Rating | Meaning |
|--------|---------|
| ★★★ | Polished — few improvements needed |
| ★★☆ | Functional — notable UX friction |
| ★☆☆ | Needs significant work |
| ☆☆☆ | Missing or placeholder |

### 3.1 Screen Inventory (Complete)

| # | Screen | File | Purpose | UX Rating | Key Issues |
|---|--------|------|---------|-----------|------------|
| 1 | **LoginScreen** | `auth/presentation/login_screen.dart` | User authentication | ★★☆ | No 2FA support, no social login, basic validation |
| 2 | **RegisterScreen** | `auth/presentation/register_screen.dart` | User registration | ★★☆ | Long form, no progress indicator |
| 3 | **ForgotPasswordScreen** | `auth/presentation/forgot_password_screen.dart` | Password reset | ★★☆ | Minimal UX, no success animation |
| 4 | **ResetPasswordScreen** | `auth/presentation/reset_password_screen.dart` | Set new password | ★★☆ | Token from query param, fragile |
| 5 | **CompanySelectionScreen** | `auth/presentation/company_selection_screen.dart` | Multi-tenant picker | ★★☆ | No search, no recent-first ordering |
| 6 | **DashboardScreen** | `dashboard/presentation/dashboard_screen.dart` | KPI + charts + alerts | ★★☆ | KPI grid has manual responsive math, no widget test, 60-sec hardcoded poll |
| 7 | **InvoiceListScreen** | `sales/presentation/invoice_list_screen.dart` | Invoice list with search/filter | ★★★ | Good status filter tabs, search, master-detail. Missing: bulk actions, column visibility, export |
| 8 | **InvoiceFormScreen** | `sales/presentation/invoice_form_screen.dart` | Create/edit invoice | ★★★ | Comprehensive (~1700 lines needs extraction). No preview-before-save. "Save draft" only — no "Post & Send" |
| 9 | **InvoiceDetailScreen** | `sales/presentation/invoice_detail_screen.dart` | View invoice | ★★★ | Well-structured with TransactionDetailLayout. Good action buttons. |
| 10 | **ProformaListScreen** | `sales/presentation/proforma_list_screen.dart` | Quotations list | ★★☆ | Tab-based, reuses patterns but no differentiation from invoices |
| 11 | **ProformaFormScreen** | `sales/presentation/proforma_form_screen.dart` | Create quotation | ★★☆ | Similar to invoice form |
| 12 | **SalesOrderListScreen** | `sales/presentation/sales_order_list_screen.dart` | Sales orders list | ★★☆ | Tab-based |
| 13 | **SalesOrderFormScreen** | `sales/presentation/sales_order_form_screen.dart` | Create sales order | ★★☆ | Similar to invoice form |
| 14 | **DeliveryChallanListScreen** | `sales/presentation/delivery_challan_list_screen.dart` | Delivery challans | ★★☆ | Tab-based |
| 15 | **PaymentListScreen** | `sales/payments/presentation/payment_list_screen.dart` | Payments received | ★★☆ | Basic list, no filters by customer |
| 16 | **PaymentFormScreen** | `sales/payments/presentation/payment_form_screen.dart` | Record payment | ★★☆ | Functional but no split-allocation UX |
| 17 | **PurchaseOrderListScreen** | `purchases/purchase_orders/presentation/` | PO list | ★★☆ | Tab-based under Purchases hub |
| 18 | **PurchaseOrderFormScreen** | `purchases/purchase_orders/presentation/` | Create PO | ★★☆ | Similar patterns |
| 19 | **GoodsReceiptListScreen** | `purchases/goods_receipts/presentation/` | Goods receipts | ★★☆ | Tab-based |
| 20 | **GoodsReceiptFormScreen** | `purchases/goods_receipts/presentation/` | Create GR | ★★☆ | Linked to PO |
| 21 | **BillListScreen** | `purchases/vendor_bills/presentation/bill_list_screen.dart` | Vendor bills list | ★★☆ | Tab-based |
| 22 | **BillFormScreen** | `purchases/vendor_bills/presentation/bill_form_screen.dart` | Create bill | ★★☆ | Similar to invoice but for AP |
| 23 | **BillDetailScreen** | `purchases/vendor_bills/presentation/bill_detail_screen.dart` | View bill | ★★★ | Good detail layout |
| 24 | **BillScanScreen** | `purchases/vendor_bills/presentation/bill_scan_screen.dart` | OCR bill scan | ★☆☆ | Camera/upload + parse, minimal feedback |
| 25 | **VendorPaymentListScreen** | `purchases/vendor_payments/presentation/` | Vendor payments | ★★☆ | Tab-based |
| 26 | **VendorPaymentFormScreen** | `purchases/vendor_payments/presentation/` | Pay vendor | ★★☆ | Functional |
| 27 | **PurchaseReturnListScreen** | `purchases/purchase_returns/presentation/` | Returns list | ★★☆ | Tab-based |
| 28 | **ExpenseScreen** | `expenses/expense_screen.dart` | Expense list + form | ★☆☆ | Service mixed with UI, no receipt preview, setState-based form |
| 29 | **AccountListScreen** | `masters/accounts/presentation/account_list_screen.dart` | Chart of Accounts | ★★★ | Tree view with expand/collapse, type filters, search |
| 30 | **AccountFormScreen** | `masters/accounts/presentation/account_form_screen.dart` | Create/edit account | ★★☆ | Parent selection is complex |
| 31 | **AccountDetailScreen** | `masters/accounts/presentation/account_detail_screen.dart` | Account view | ★★☆ | No drill-down to ledger by default |
| 32 | **JournalListScreen** | `accounting/journal/presentation/journal_list_screen.dart` | Journal entries list | ★★★ | Good debit/credit side-by-side, balanced badge |
| 33 | **JournalFormScreen** | `accounting/journal/presentation/journal_form_screen.dart` | New journal entry | ★☆☆ | Raw setState, no auto-balance until save, no account search |
| 34 | **TrialBalanceScreen** | `accounting/financial_statements/presentation/` | Trial balance | ★★☆ | Static date, no period comparison |
| 35 | **ProfitLossScreen** | `accounting/financial_statements/presentation/` | P&L statement | ★★☆ | Basic date filter, no drill-down |
| 36 | **BalanceSheetScreen** | `accounting/financial_statements/presentation/` | Balance sheet | ★★☆ | Basic date filter, no comparison |
| 37 | **CashBookScreen** | `accounting/financial_statements/presentation/` | Cash book | ★★☆ | Tab-based under Books & Registers |
| 38 | **BankBookScreen** | `accounting/financial_statements/presentation/` | Bank book | ★★☆ | Tab-based |
| 39 | **DayBookScreen** | `accounting/financial_statements/presentation/` | Day book | ★★☆ | Tab-based |
| 40 | **GeneralLedgerScreen** | `accounting/ledger/presentation/general_ledger_screen.dart` | General ledger | ★★☆ | No date range, no drill-down |
| 41 | **ReconciliationListScreen** | `accounting/reconciliation/presentation/` | Bank reconciliation list | ★☆☆ | Thin list only — no side-by-side matching workflow |
| 42 | **ContactListScreen** | `masters/contacts/presentation/contact_list_screen.dart` | Contacts list | ★★★ | Good search, type filter |
| 43 | **ContactFormScreen** | `masters/contacts/presentation/contact_form_screen.dart` | Create/edit contact | ★★☆ | Long form, no address autocomplete |
| 44 | **ContactDetailScreen** | `masters/contacts/presentation/contact_detail_screen.dart` | Contact view | ★★☆ | No transaction history |
| 45 | **ProductListScreen** | `masters/products/presentation/product_list_screen.dart` | Products list | ★★☆ | Basic list |
| 46 | **ProductFormScreen** | `masters/products/presentation/product_form_screen.dart` | Create/edit product | ★★☆ | Good barcode field |
| 47 | **InventoryListScreen** | `inventory/stock/presentation/inventory_list_screen.dart` | Stock levels | ★★☆ | Good low-stock filter |
| 48 | **StockMovementListScreen** | `inventory/movements/presentation/` | Stock ledger | ★★☆ | Tab-based |
| 49 | **TransferListScreen** | `inventory/transfers/presentation/` | Stock transfers | ★★☆ | Tab-based |
| 50 | **AdjustmentListScreen** | `inventory/adjustment/presentation/` | Stock adjustments | ★★☆ | Tab-based |
| 51 | **WarehouseDashboardScreen** | `inventory/warehouse/presentation/` | Warehouse overview | ★★☆ | Tab-based |
| 52 | **WarehouseListScreen** | `inventory/warehouse/presentation/` | Warehouses list | ★★☆ | Basic |
| 53 | **BankingProfileListScreen** | `masters/banking_profiles/presentation/` | Bank accounts | ★★☆ | Basic master list |
| 54 | **GstDashboardScreen** | `gst/presentation/gst_dashboard_screen.dart` | GST overview | ★★☆ | Basic summary |
| 55 | **Gstr1Screen** | `gst/presentation/gstr1_screen.dart` | GSTR-1 return | ★★☆ | Tab-based under Reports |
| 56 | **Gstr3bScreen** | `gst/presentation/gstr3b_screen.dart` | GSTR-3B return | ★★☆ | Tab-based |
| 57 | **ReportsShell** | `reports/presentation/reports_shell.dart` | Reports hub | ★★☆ | Tab-based, missing key financial reports |
| 58 | **SettingsShell** | `settings/presentation/settings_shell.dart` | Settings hub | ★★☆ | Tab-based, several missing pages |
| 59 | **TaxTemplateListScreen** | `masters/tax_templates/presentation/` | Tax rates | ★★☆ | Read-only, tab-based |
| 60 | **PaymentTermListScreen** | `masters/payment_terms/presentation/` | Payment terms | ★★☆ | Read-only, tab-based |
| 61 | **ExpenseCategoryListScreen** | `masters/expense_categories/presentation/` | Expense categories | ★★☆ | Basic master |
| 62 | **HomeShell** | `home/home_shell.dart` | App shell + navigation | ★★★ | Good responsive shell with sidebar/rail/drawer patterns |

### 3.2 Missing Screens (per Product Spec)

The following screens are documented in `MASTER_PRODUCT_SPECIFICATION.md` as `⚠️ MISSING`:

- TwoFactorScreen (2FA)
- BillFormScreen (referenced but status unclear)
- WarehouseFormScreen, WarehouseDetailScreen
- JournalFormScreen (exists but was marked missing in spec)
- Profit & Loss standalone (exists as tab)
- Balance Sheet standalone (exists as tab)
- Cash Flow Statement
- Bank Reconciliation detail/matching screen
- Company Profile settings
- Financial Year settings
- Numbering Series settings
- Team/Roles settings
- Branches settings
- GST Config settings
- Email/SMTP settings
- Backup & Restore settings
- Data Import/Export settings
- Credit Notes screen
- Debit Notes screen
- Recurring Invoices screen
- Audit Log Viewer screen

---

## 4. Major UX Problems

### 4.1 Critical

| # | Problem | Screens Affected | Evidence |
|---|---------|-----------------|----------|
| C1 | **No bank reconciliation matching workflow** | ReconciliationListScreen | Screen is a thin list — no side-by-side transaction matching, no confidence scoring, no match/categorize/transfer actions |
| C2 | **Journal form uses raw setState** | JournalFormScreen | Inconsistent with app-wide Riverpod pattern. No auto-balance indicator until save attempted. No unsaved-changes guard. No draft auto-save. |
| C3 | **Expense screen has service code in widget** | ExpenseScreen | `ExpenseService` class defined in the same file as the widget. No proper form state management. No receipt preview or attachment. |
| C4 | **No confirmation guard on destructive actions** | Various | Several delete/cancel/void actions lack confirmation dialogs or have inconsistent confirmation patterns |
| C5 | **No date-range picker component** | All reports, lists | Each report screen manages its own `StateProvider<String?>` for dates. No unified date-range selector with presets (Today, This Month, This Quarter, This Year, Custom). |

### 4.2 High

| # | Problem | Screens Affected | Evidence |
|---|---------|-----------------|----------|
| H1 | **Breadcrumbs widget exists but is unused** | All deep screens | `breadcrumbs.dart` has a fully functional `Breadcrumbs` widget but it is never imported or used anywhere |
| H2 | **No column visibility or reorder** | All data tables | `ApexDataTable` supports `hiddenColumns` but no UI to toggle |
| H3 | **No bulk selection operations** | InvoiceListScreen, BillListScreen, etc. | Selection checkboxes exist in table body but no bulk-email, bulk-delete, bulk-print |
| H4 | **No unified filter bar** | All list screens | Search + status filters + date range are implemented differently on every screen |
| H5 | **Empty search result states are inconsistent** | All list screens | Some show `EmptyState` with "try different search", others show nothing |
| H6 | **KPI card grid uses manual width math** | DashboardScreen | `LayoutBuilder` + `Wrap` with manual column width calculation instead of `GridLayout` or `SliverGrid` |
| H7 | **Invoice form has no "Post & Send"** | InvoiceFormScreen | Only "Save draft". Creating and sending an invoice requires navigating to detail screen first. |
| H8 | **No preview before save on invoice** | InvoiceFormScreen | Users cannot see the final invoice appearance before committing |
| H9 | **No GST liability comparison on dashboard** | DashboardScreen | Dashboard shows GST summary but no comparison with previous period |
| H10 | **Dashboard auto-refresh is hardcoded 60s** | DashboardScreen | `Timer.periodic(const Duration(seconds: 60))` — should be configurable |

### 4.3 Medium

| # | Problem | Screens Affected | Evidence |
|---|---------|-----------------|----------|
| M1 | **No loading overlay for form submissions** | All forms | Submit buttons show spinner but form content is still interactive |
| M2 | **No disabled state on save buttons** | Some forms | Double-submit risk on some screens |
| M3 | **Search debounce is inconsistent** | All list screens | Some searches trigger on every keystroke, some require manual submit |
| M4 | **No auto-scroll to first error** | All forms | Validation errors appear at top but field isn't focused |
| M5 | **MonetaryText not used consistently** | Various | Some screens use raw `Text` with formatting, not `MonetaryText` |
| M6 | **`ApexCard` vs private `_Card`/`_Panel` confusion** | Dashboard, InvoiceForm, etc. | Multiple screens define private card wrappers when `ApexCard` exists |
| M7 | **No keyboard shortcut cheat sheet** | Global | Keyboard shortcuts exist (Ctrl+S, Ctrl+K, Alt+N) but no discoverability |
| M8 | **Command palette has only 7 commands** | Global | Should include all create actions, reports, and settings |
| M9 | **No recent items service integration** | Global | Navigation sidebar could show recently accessed invoices/bills |
| M10 | **No favorites/pinned reports** | Reports | Users cannot save frequently used report configurations |

### 4.4 Low

| # | Problem | Screens Affected | Evidence |
|---|---------|-----------------|----------|
| L1 | **Typography inconsistencies** | Various | Font sizes vary slightly between screens (11 vs 10.5 vs 12 in similar contexts) |
| L2 | **Spacing inconsistencies** | Various | Some screens use 16px padding, others 20px |
| L3 | **Button label casing inconsistent** | Various | "New Invoice" vs "New invoice" vs "New bill" |
| L4 | **No hover state on data table rows** | Desktop tables | `ApexTableBody` lacks hover highlight |
| L5 | **Status badge tones incomplete** | Various | `toneForStatus` doesn't cover all backend statuses |
| L6 | **No "scroll to top" FAB on long lists** | All list screens | Long lists require manual scrolling |
| L7 | **PageHeader uses truncated subtitle** | Various | Long subtitles get ellipsized too aggressively |

---

## 5. Accounting Software UX Research

### 5.1 Dashboard Patterns

**Industry standard (QuickBooks, Xero, Zoho Books):**
- 4-6 KPI cards at top (Revenue, Expenses, Profit, Cash, Receivables, Payables)
- Revenue/expense trend chart (line or bar, monthly buckets)
- Overdue invoices / upcoming bills lists (max 5 items each)
- Bank balance summary
- Quick action buttons

**What ApexBooks does well:**
- KPI cards with icons and color-coded indicators ✓
- Cash flow bar chart with monthly buckets ✓
- Overdue alerts with severity indicators ✓
- GST summary section ✓
- Greeting based on time of day ✓

**What's missing:**
- Cash balance from bank accounts (hardcoded not from API)
- Bank reconciliation status indicator
- Quick actions row (New Invoice, New Bill, New Expense)
- Period-over-period comparison arrows
- "Last reconciled" indicator

### 5.2 Invoice Creation Patterns

**Industry standard (FreshBooks, Xero, Zoho Books):**
- Step-by-step or single-page with collapsible sections
- Customer auto-complete with quick-create
- Line items with product search, quantity, rate, tax
- Real-time total calculation
- Preview toggle
- Save as draft / Save and send
- Email directly from creation flow

**What ApexBooks does well:**
- Single-page form with ConstrainedBox max-width ✓
- Customer search with Autocomplete ✓
- Product search with Autocomplete ✓
- Real-time totals in sticky bottom bar ✓
- Keyboard shortcuts (Ctrl+S, Alt+N) ✓

**What's missing:**
- No "Save and Send" or "Post and Send" action
- No preview before save
- No discount type (percentage vs fixed amount)
- No shipping address separate from billing
- No recurring invoice toggle inline
- No attachment upload during creation

### 5.3 Bank Reconciliation Patterns

**Industry standard (Xero, QuickBooks, Wave):**
- Side-by-side view: bank statement on left, ledger entries on right
- Suggested matches with confidence indicators (stars, percentages)
- Match by amount, reference, date
- Bulk match (select multiple)
- Manual match creation
- Create new ledger entry from unmatched transaction
- Exclude / mark as private
- Running balance comparison
- Reconciliation report at completion

**What ApexBooks has:**
- List of reconciliations with date and balance
- Basic matching model (BankTransaction, ReconciliationMatch)
- Upload statement dialog (placeholder)

**Critical gap:**
- No side-by-side matching screen
- No suggested match logic in UI
- No confidence indicators
- No "create entry" from transaction
- No reconciliation progress tracking
- This is the single most important UX gap in the entire app

### 5.4 Journal Entry Patterns

**Industry standard (Sage, NetSuite, QuickBooks Online):**
- Grid-based entry with columns: Account, Debit, Credit, Memo
- Account search with code + name
- Auto-balance: entering credit auto-fills remaining amount
- Running total row at bottom
- Out-of-balance warning (not error — allow save-as-draft)
- Template support for recurring entries
- Reverse entry button
- Audit trail with before/after snapshots

**What ApexBooks has:**
- Basic grid with account dropdown, Dr/Cr, amount, narration
- Running debit/credit/difference totals
- Keyboard shortcuts (Ctrl+S, Alt+N)

**What's missing:**
- Account search-by-code (currently dropdown-only)
- Auto-balance (entering credit amount auto-balances to total)
- Template/recurring support
- Reverse entry from list
- Batch journal import
- Running balance drill-down on account (see current balance)

### 5.5 Report Patterns

**Industry standard (QuickBooks, Xero, Zoho):**
- Report title with period selector
- Comparison period (previous year, previous period)
- Accounting basis toggle (cash vs accrual)
- Expand/collapse groups (by month, by account group)
- Drill-down from summary to transaction
- Column customization
- Export (PDF, Excel, CSV)
- Email report
- Save custom view
- Scheduled delivery

**What ApexBooks has:**
- Basic report screens (P&L, Balance Sheet, Trial Balance)
- Date range filters on some reports
- Skeleton loading states
- Search within report

**What's missing:**
- No comparison period
- No accounting basis toggle
- No expand/collapse groups (hardcoded sections)
- No drill-down to transactions
- No column customization
- Export is "coming soon" on many screens
- No custom view save
- No report scheduling

### 5.6 Search & Navigation Patterns

**Industry standard (Stripe, QuickBooks, Xero):**
- Global search that returns invoices, contacts, transactions, reports
- Command palette (Cmd+K) for power users
- Recent items in navigation
- Favorites/bookmarks for reports
- Breadcrumbs on every detail page
- Contextual "new" button (quick-create)

**What ApexBooks has:**
- Command palette with 7 commands ✓ (but limited)
- Global toolbar search (non-functional, triggers command palette) ✓
- Quick-create bottom sheet ✓
- Recent items service (exists but not integrated) ✓
- Favorites service (exists but not integrated) ✓

**What's missing:**
- True global search that hits the API
- Search within reports
- Breadcrumbs on detail pages (widget exists but unused)
- Recent items in sidebar
- Favorites visible in navigation

### 5.7 Naming & Terminology

**Industry standard:**
- "Sales" for revenue transactions
- "Purchases" for expense transactions
- "Chart of Accounts" (not "COA" standalone)
- "Journal Entry" (not "Journal Voucher")
- "Credit Note" / "Debit Note" (not "Credit Memo")
- "Aged Receivables" / "Aged Payables"
- "Trial Balance" (not "TB")
- "Profit and Loss" (not "P&L" in headers — P&L is acceptable in navigation)

**ApexBooks assessment:**
- Mostly standard terminology ✓
- "Books & Registers" is slightly non-standard but acceptable
- "GST" is correct for Indian market
- "Masters" is slightly dated but common in Indian accounting software

---

## 6. Competitor Pattern Comparison

| Feature | QuickBooks | Xero | Zoho Books | FreshBooks | ApexBooks (Current) |
|---------|-----------|------|------------|------------|---------------------|
| Dashboard KPIs | 6 cards with trends | 4 cards with sparklines | 5 cards with % change | 4 cards | 5 cards, no trends |
| Navigation | Left sidebar + top bar | Left sidebar + top bar | Left sidebar | Top bar | Left sidebar (desktop), bottom nav (mobile) |
| Invoice creation | Single page, preview | Single page, live preview | Step wizard | Single page | Single page, no preview |
| Bank reconciliation | Side-by-side matching | Side-by-side with AI match | Side-by-side | Simple match | List only, no matching UI |
| Journal entry | Grid with auto-balance | Grid with templates | Grid with auto-balance | N/A (auto) | Basic grid, no auto-balance |
| Search | Global + Cmd+K | Global search | Global search | Basic | Cmd+K palette (limited) |
| Reports | 25+ with custom views | 20+ with drill-down | 30+ with comparison | 10 basic | 7 basic reports |
| Mobile | Full-featured | Good | Good | Excellent | Functional but stretched |
| Date range | Presets + custom | Presets + custom | Presets + custom | Simple | Custom only, no presets |

---

## 7. User Personas

### 7.1 Persona 1: Rajesh — Small Business Owner

**Demographics:** Age 38, runs a manufacturing business with 20 employees. Has basic accounting knowledge. Uses ApexBooks daily.

**Goals:**
- See how much cash is in the bank
- Know which invoices are overdue
- Send invoices quickly
- Understand if the business is profitable

**Frustrations:**
- Accounting terminology is confusing
- Doesn't know what a journal entry is
- Wants to see "how much money do I have right now?"
- Finds the dashboard useful but wants simpler language

**Needs:**
- Simple dashboard with plain-language labels
- One-click invoice creation from templates
- Mobile access to check cash position
- Automatic reminders for overdue payments
- Plain-English reports

### 7.2 Persona 2: Priya — Professional Accountant (CA)

**Demographics:** Age 45, Chartered Accountant managing books for 15 clients on ApexBooks. Expert user.

**Goals:**
- Efficient data entry with keyboard shortcuts
- Batch operations for month-end closing
- Audit trail review
- GST return preparation and filing

**Frustrations:**
- Journal entry form is too slow (dropdown-based account selection)
- Reconciliation screen is unusable (no matching)
- Can't drill down from P&L to transactions
- Period closing requires multiple manual steps

**Needs:**
- Keyboard-first workflow
- Bulk reconciliation
- Journal entry templates
- Period-lock workflow
- Export-ready reports for client delivery

### 7.3 Persona 3: Sunita — Bookkeeper

**Demographics:** Age 32, works for a trading company. Handles day-to-day data entry: recording bills, matching payments, entering expenses.

**Goals:**
- Quick data entry with minimal errors
- Scan and upload bills quickly
- Match payments to invoices easily
- Reconcile bank statements monthly

**Frustrations:**
- Expense form is cumbersome (no receipt preview)
- Bill scanning has no feedback on OCR quality
- Payment allocation is confusing
- Has to switch between too many screens

**Needs:**
- Receipt scanning with instant feedback
- Bill payment in one screen (see bill, pay bill)
- Clear confirmation after each entry
- Error notifications before posting

### 7.4 Persona 4: Vikram — Finance Manager

**Demographics:** Age 40, manages finance team of 5 people. Reviews reports, manages cash flow, approves transactions.

**Goals:**
- Real-time cash flow visibility
- Approve invoices and bills
- Generate month-end reports quickly
- Track team member activities

**Frustrations:**
- Dashboard doesn't show cash balance
- Can't compare this month vs last month
- No approval workflow visible in UI
- Report export is "coming soon"

**Needs:**
- Cash flow dashboard with forecast
- Approval queue with notifications
- Period comparison on all reports
- Excel export for board meetings

### 7.5 Persona 5: Anita — Auditor

**Demographics:** Age 50, external auditor. Reviews financial records quarterly.

**Goals:**
- Review transaction history
- Verify audit trail completeness
- Check for unusual entries
- Export supporting documentation

**Frustrations:**
- Audit log viewer is a JSON dump instead of a readable timeline
- Can't see who made what change
- No before/after comparison on edits

**Needs:**
- Human-readable audit timeline
- User-action tracking
- Export of audit trail
- Read-only access with clear indicators

---

## 8. Workflow Analysis

### 8.1 Create and Send an Invoice

**Current steps (7 interactions minimum):**
1. Navigate to Invoices tab
2. Tap "New Invoice"
3. Search/select customer
4. Add line items (product search, qty, rate)
5. Set GST options
6. Tap "Save draft"
7. Navigate to detail screen → tap "Finalize" → tap "Email"

**Problems:**
- No "Save and Send" option
- Requires two separate screens (form + detail)
- No preview before sending
- Can't attach documents during creation

**Recommended steps (3-4 interactions):**
1. Tap "New Invoice" from any screen (via quick-create or command palette)
2. Select customer, add items (with product search)
3. Preview and tap "Save & Send" (or "Save as Draft")

**Target interactions:** 3-4 (from anywhere in app)
**Mobile behavior:** Full-screen form, single column
**Desktop behavior:** Side panel or centered form, keyboard-first
**Success confirmation:** Toast + option to view or send immediately
**Recovery:** Draft saves automatically every 30 seconds

### 8.2 Record a Payment Against Invoice

**Current steps (5+ interactions):**
1. Navigate to invoice detail
2. Tap "Receive payment"
3. Enter amount and date
4. Select payment method
5. Confirm and save

**Problems:**
- Payment form is separate from invoice view
- No split-payment support (check + cash)
- No bank account selection visible

**Recommended steps (3 interactions):**
1. From invoice detail, tap "Record Payment"
2. Enter amount, date, payment method (with bank account)
3. Confirm — instantly marks invoice as paid/partial

**Target interactions:** 3
**Mobile behavior:** Bottom sheet over invoice
**Desktop behavior:** Side panel
**Success confirmation:** Invoice status updates immediately, balance changes in view
**Recovery:** Can delete payment from invoice timeline

### 8.3 Bank Reconciliation

**Current steps (minimal — screen is a list only):**
1. Navigate to Banking → tap Reconciliation
2. See list of previous reconciliations
3. Upload statement (placeholder dialog)

**Critical gap:** The matching workflow does not exist in the UI.

**Recommended implementation:**
1. Upload bank statement (CSV/Excel/PDF)
2. System shows transactions in a side-by-side view:
   - Left: bank statement transactions
   - Right: ledger entries (filtered by account and date range)
3. Suggested matches highlighted with confidence score
4. User can: Match, Categorize (to new account), Transfer, or Exclude
5. Running reconciliation progress (X of Y matched)
6. Summary: Opening balance + matched - unmatched = closing balance
7. "Finish reconciliation" with discrepancy warning if any

**Target interactions:** Varies (5-20+ depending on volume)
**Mobile behavior:** Single column with swipe-to-match
**Desktop behavior:** True side-by-side with keyboard shortcuts (M=Match, C=Categorize)
**Success confirmation:** Reconciliation report with matched/unmatched summary
**Recovery:** Un-reconcile available (with audit trail)

### 8.4 Journal Entry

**Current steps (6+ interactions):**
1. Navigate to Accounting → Journals → "New journal"
2. Enter date
3. Select account from dropdown (scrolling)
4. Choose Debit/Credit
5. Enter amount
6. Add narration
7. Save — validation error appears if unbalanced

**Problems:**
- Account selection is dropdown-only (no search-by-code)
- Validation errors shown only on save (not live)
- No auto-balance feature
- No draft auto-save

**Recommended steps (4 interactions for 2-line entry):**
1. Tap "New Journal Entry"
2. Enter narration and date
3. Type account code/name (auto-search as you type), enter amount — debit auto-populates to balance if credit total is entered
4. Tap "Post" (with final balance warning if out of balance)

**Target interactions:** 4 (for simple 2-line entry)
**Mobile behavior:** Scrollable form with card-style lines
**Desktop behavior:** Grid with keyboard navigation (Tab between columns)
**Success confirmation:** Toast "Journal posted" + entry appears in list
**Recovery:** Reverse button in entry detail (creates reversing entry)

### 8.5 Expense Recording

**Current steps (9+ interactions):**
1. Navigate to Expenses
2. Tap "New expense"
3. Select expense category (dropdown)
4. Enter date
5. Enter vendor name (free text, no search)
6. Select paid-from account
7. Enter taxable amount
8. Select GST rate
9. Enter place of supply, reference, description
10. Tap "Save draft"

**Problems:**
- No vendor autocomplete (must type from scratch)
- No receipt upload during creation
- No GST calculation summary
- No "Post" in form — requires going back to list
- Receipt scanning is only in Purchase Bills, not Expenses

**Recommended steps (5 interactions):**
1. Tap "New Expense"
2. Upload receipt photo (optional — auto-fills amount if OCR)
3. Select vendor (autocomplete from contacts)
4. Select category, enter amount (GST calculated automatically)
5. Tap "Save & Post" or "Save as Draft"

**Target interactions:** 5
**Mobile behavior:** Camera-first — take photo, confirm amount, categorize
**Desktop behavior:** Standard form with drag-and-drop receipt
**Success confirmation:** Expense posted to ledger + receipt attached
**Recovery:** Cancel/reverse from expense list

### 8.6 Remaining Workflow Summaries

| Workflow | Current Steps | Target Steps | Critical Issues |
|----------|--------------|--------------|-----------------|
| Create customer | 6 | 3 | Long form, no duplicate check |
| Create and pay a bill | 8 | 5 | Bill form + payment form are separate |
| Review P&L | 4 | 2 | No period comparison, no drill-down |
| Review cash flow | 4 | 2 | No cash flow forecast report exists |
| Export financial report | Missing | 2 | Export is "coming soon" everywhere |
| Correct/reverse transaction | 5 | 3 | No clear reversal workflow |
| Close accounting period | Missing | 4 | Period-lock exists in API but not in UI |
| Switch companies | 3 | 2 | Company selector in sidebar works |

---

## 9. Proposed Information Architecture

### 9.1 Navigation Structure

```
┌─────────────────────────────────────────────────────────────────────┐
│  TOP BAR (Desktop) / APP BAR (Mobile)                              │
│  [Company ▼] [Global Search... Ctrl+K] [Create +] [Notif] [Avatar] │
├─────────────────────────────────────────────────────────────────────┤
│ SIDEBAR (Desktop) / RAIL (Tablet) / DRAWER (Mobile)                │
│                                                                     │
│ ⚡ DASHBOARD                                                        │
│                                                                     │
│ 💰 SALES                                                            │
│    ├── Invoices (primary)                                           │
│    ├── Quotations / Estimates                                       │
│    ├── Sales Orders                                                 │
│    ├── Delivery Challans                                            │
│    ├── Credit Notes                                                 │
│    └── Payments Received                                            │
│                                                                     │
│ 🛒 PURCHASES                                                        │
│    ├── Purchase Orders                                              │
│    ├── Goods Receipts                                               │
│    ├── Vendor Bills (primary)                                       │
│    ├── Vendor Payments                                              │
│    ├── Debit Notes                                                  │
│    └── Purchase Returns                                             │
│                                                                     │
│ 💸 BANKING                                                          │
│    ├── Bank Accounts                                                │
│    └── Reconciliation (primary)                                     │
│                                                                     │
│ 📊 ACCOUNTING                                                       │
│    ├── Chart of Accounts                                            │
│    ├── Journal Entries                                              │
│    ├── Trial Balance                                                │
│    ├── General Ledger                                               │
│    └── Period End                                                   │
│                                                                     │
│ 📦 INVENTORY                                                        │
│    ├── Stock View                                                   │
│    ├── Stock Movements                                              │
│    ├── Transfers                                                    │
│    ├── Adjustments                                                  │
│    └── Warehouses                                                   │
│                                                                     │
│ 📋 REPORTS                                                          │
│    ├── Profit & Loss                                                │
│    ├── Balance Sheet                                                │
│    ├── Cash Flow                                                    │
│    ├── Sales Register                                               │
│    ├── Purchase Register                                            │
│    ├── Customer Ledger                                              │
│    ├── Vendor Ledger                                                │
│    ├── Aged Receivables                                             │
│    ├── Aged Payables                                                │
│    ├── Day Book                                                     │
│    ├── Cash Book                                                    │
│    └── Bank Book                                                    │
│                                                                     │
│ 🏷️ GST                                                              │
│    ├── GST Dashboard                                                │
│    ├── GSTR-1 / Invoice Details                                     │
│    ├── GSTR-2B / Purchase ITC                                       │
│    ├── GSTR-3B                                                      │
│    ├── E-Invoice                                                    │
│    └── E-Way Bill                                                   │
│                                                                     │
│ 👥 CONTACTS                                                         │
│    └── All Contacts (Customer / Vendor toggle)                      │
│                                                                     │
│ 📦 MASTERS                                                          │
│    ├── Products / Services                                          │
│    ├── Tax Templates                                                │
│    ├── Payment Terms                                                │
│    └── Expense Categories                                           │
│                                                                     │
│ ⚙️ SETTINGS                                                         │
│    ├── Company Profile                                              │
│    ├── Financial Year                                               │
│    ├── Numbering Series                                             │
│    ├── Team & Roles                                                 │
│    ├── GST Configuration                                            │
│    ├── Email / SMTP                                                 │
│    ├── Preferences                                                  │
│    ├── Backup & Restore                                             │
│    └── Data Import / Export                                         │
└─────────────────────────────────────────────────────────────────────┘
```

### 9.2 Navigation Rules

**Primary navigation (Desktop):**
- Fixed left sidebar (collapsible to icon-only, 72px)
- Active section highlighted with accent bar
- Sections are collapsible sub-menus
- At top: company selector + global search bar
- At bottom: user avatar + theme toggle + logout

**Primary navigation (Tablet):**
- NavigationRail (icons + labels) on the left
- Expanded drawer accessible via hamburger icon
- Same structure, vertically oriented

**Primary navigation (Mobile):**
- Bottom NavigationBar with 4 key destinations: Dashboard, Invoices, Banking, More
- "More" opens a full drawer with the complete nav tree
- Quick-create FAB available on all screens

**Secondary navigation:**
- Breadcrumbs on all detail screens (reuse the existing but unused `Breadcrumbs` widget)
- Back button with unsaved-changes guard on forms
- Contextual tabs for hub screens (Sales hub: Invoices / Orders / Challans / Returns)

**Deep linking:**
- `/invoice/{id}` → InvoiceDetailScreen
- `/bill/{id}` → BillDetailScreen
- `/contact/{id}` → ContactDetailScreen
- `/report/pnl?from=...&to=...` → P&L with parameters
- These enable push notifications to open specific records

### 9.3 Screen Hierarchy

```
Level 0 (Shell):    HomeShell (sidebar + top bar + content area)
Level 1 (Hub):      HubTabWidget (tabs + content) — Sales, Purchases, etc.
Level 2 (List):     InvoiceListScreen, BillListScreen, etc.
Level 3 (Detail):   InvoiceDetailScreen, BillDetailScreen, etc.
Level 4 (Form):     InvoiceFormScreen, BillFormScreen, etc.
```

---

## 10. Screen-by-Screen Recommendations

### 10.1 Dashboard

**Rating:** ★★☆ (Functional, needs refinement)

**Problems:**
1. KPI grid uses manual `LayoutBuilder` + `Wrap` with computed widths
2. No cash balance display (most-asked question for business owners)
3. No period comparison (last month, last year)
4. No quick action row
5. 60-second auto-refresh is hardcoded
6. Overdue alerts don't show contact avatar/initials
7. Dashboard is a `ListView.builder` with 4 hardcoded items (fragile)

**Recommendations:**

1. **KPI Cards**: Replace manual `LayoutBuilder` with `SliverGrid` or a responsive grid. Add sparkline trend indicators to each card (±% vs last period).

2. **Add Cash Balance Card**: Show total bank balance from all connected accounts. This is the #1 question business owners ask.

3. **Quick Action Row**: Add a grid of quick action buttons below KPIs: "New Invoice", "New Expense", "Record Payment", "Reconcile"

4. **Period Comparison**: Add period selector (This Month, This Quarter, This Year) with percentage change indicators on KPIs.

5. **Responsive Layout**:
   - Mobile: Single column, stacked cards, fewer KPIs (top 3), quick actions as bottom sheet
   - Tablet: 2-column grid, alerts panel as side column
   - Desktop: 3-column grid maximum, side-by-side chart and alerts

6. **Accessibility**:
   - Add `Semantics` labels to all KPIs and chart data points
   - Ensure chart colors are distinguishable for color-blind users (patterns + labels)

**Priority:** High
**Complexity:** Medium
**Dependencies:** Additional API endpoint for cash balance across bank accounts

### 10.2 Invoice List / Detail / Form

**Rating:** ★★★ / ★★★ / ★★★

**Problems (Form):**
1. 1700 lines — needs extraction into reusable form components
2. No "Post & Send" action — only "Save draft"
3. No PDF preview before saving
4. Line items on mobile are verbose cards (takes too much vertical space)
5. Discount is fixed-amount only (no percentage)
6. No recurring invoice toggle
7. No attachment upload during creation
8. Place of supply auto-fills from customer GSTIN but doesn't visually confirm

**Recommendations:**

1. **Extract `InvoiceFormScreen`**: Split into feature-specific sub-widgets (customer selector, line editor, GST options card, totals bar) with clean interfaces.

2. **Add primary CTA options**: 
   - "Save as Draft" (secondary)
   - "Save & Send" (primary — saves, finalizes, opens email dialog)

3. **Add Preview toggle**: Tab between "Edit" and "Preview" views in the form, showing the invoice as it would appear printed.

4. **Mobile line items**: Use a compact list with swipe-to-delete instead of large cards. Show key info inline (item name, qty×rate, total) and expand for details on tap.

5. **Discount**: Add percentage/fixed toggle next to discount fields.

6. **Recurring**: Add "Set as recurring" checkbox that opens schedule options (frequency, end date, next date).

7. **Attachments**: Add file picker to header card (drag-and-drop on desktop, file picker on mobile).

**Priority:** High
**Complexity:** Large (1700 lines to refactor)
**Dependencies:** Requires reusable form field components

### 10.3 Bank Reconciliation (Critical Rewrite)

**Rating:** ★☆☆ (Needs complete rewrite)

**Problems:**
1. Screen only shows a list of previous reconciliations
2. No matching workflow exists
3. Upload dialog is a placeholder with no file handling
4. No confidence scoring
5. No "create entry from transaction"
6. No reconciliation report

**Recommendations — complete new screen:**
1. **Upload & Parse step**: Upload CSV/Excel/PDF bank statement. Parse and display preview of parsed transactions. Allow user to map columns.
2. **Matching step (core)**: Side-by-side view — bank transactions on left, system entries on right. Use 40/60 split (bank/system).
   - Auto-suggest matches by amount, date proximity, reference number
   - Color-code confidence (green=high ≥90%, yellow=medium 50-89%, red=low <50%)
   - User actions: Match ✓, Unmatch ↺, Categorize (new account) 📁, Transfer to account 💰, Exclude 🚫
3. **Progress tracking**: "X of Y matched (Z%) — ∑ Bank: ₹A, ∑ Matched: ₹B, Difference: ₹C"
4. **Finish step**: Summary of matched/unmatched/excluded transactions. Show final bank balance vs ledger balance. Warning if discrepancy > ₹0.01.
5. **Reports**: After completion, show reconciliation report (period, opening balance, entries matched, entries unmatched, closing balance).
6. **Undo**: Re-open completed reconciliation to add/edit matches (creates audit trail entry).

**Priority:** Critical
**Complexity:** Large (new screen, ~15+ new widgets)
**Dependencies:** Backend bank statement parsing service, matching algorithm

### 10.4 Journal Entry Form (Rewrite)

**Rating:** ★☆☆

**Problems:**
1. Uses raw `setState` instead of Riverpod
2. Account selection is dropdown-only (no search-by-code/name)
3. No auto-balance
4. No auto-save draft
5. No live balance checking
6. No template support
7. No "Save as draft" vs "Post" distinction

**Recommendations:**

1. **Migrate to Riverpod**: Create `JournalFormNotifier` extending `StateNotifier<JournalFormState>` consistent with invoice pattern.
2. **Account search**: Replace dropdown with `Autocomplete` that searches by account code, name, or group. Show `code - name (group)` in results.
3. **Auto-balance**: When user fills credit total, auto-compute remaining debit amount. Show "balanced" / "out by ₹X" indicator in real-time.
4. **Keyboard navigation (desktop)**: Tab moves: Account → Dr/Cr → Amount → Narration → Next line. Enter submits.
5. **Line total**: Show running debit and credit totals with balance indicator.
6. **Draft auto-save**: Save to local storage every 30 seconds.
7. **Template support**: "Save as template" / "Load template" buttons.

**Priority:** High
**Complexity:** Medium
**Dependencies:** None

### 10.5 Expense Screen (Rewrite)

**Rating:** ★☆☆

**Problems:**
1. Service and widget in same file
2. No proper form state management
3. No receipt upload/scan
4. No vendor autocomplete (free text only)
5. No GST total display before save
6. No "Save & Post" option
7. No expense detail view

**Recommendations:**

1. **Split files**: `expense_service.dart`, `expense_form_notifier.dart`, `expense_list_screen.dart`, `expense_form_screen.dart`
2. **Receipt capture**: Camera scan (reuse `mobile_scanner`) or file upload. Show receipt thumbnail in form.
3. **Vendor autocomplete**: Use existing `ContactRepository` filtered by vendors.
4. **GST calculation**: Show computed CGST/SGST/IGST amounts before saving.
5. **Actions**: "Save as Draft" → "Save & Post" (with confirmation).
6. **Mobile**: Camera-first flow — take receipt photo, auto-fill vendor and amount (if OCR available).

**Priority:** High
**Complexity:** Medium
**Dependencies:** None

### 10.6 Reports (Significant Enhancement)

**Rating:** ★★☆

**All report screens need:**
1. **Period selector**: Unified date-range picker with presets (Today, This Week, This Month, This Quarter, This Year, Last Year, Custom).
2. **Comparison period**: Toggle to show previous period column with % change.
3. **Expand/collapse**: Group by account group, month, or custom dimension.
4. **Drill-down**: Tap any account/amount → show underlying transactions.
5. **Export**: PDF and Excel export (use existing `DownloadService`).
6. **Print**: Browser print for desktop.
7. **Share**: Generate shareable link.

**Specific gaps:**
- **Cash Flow Statement**: Entire report missing — this is a critical financial statement.
- **Aged Receivables**: Report exists only conceptually — needs implementation.
- **Aged Payables**: Same as above.
- **Comparison**: No report supports period-over-period comparison.

**Priority:** High
**Complexity:** Large (affects all 10+ report screens)
**Dependencies:** Unified date-range component, backend comparison data

### 10.7 All List Screens

**Rating:** ★★☆ average

**Recommendations (universal to all list screens):**
1. **Unified search**: Single `ApexSearchBar` with consistent debounce (300ms), clear button, and result count.
2. **Unified filter bar**: Reusable `FilterBar` widget with status chips, date range, and type filter in a single row.
3. **Bulk selection**: Add select-all checkbox with bulk action bar (delete, email, export, status change).
4. **Column visibility**: Add gear icon → column picker overlay.
5. **Export**: Add export button to toolbar (CSV, Excel, PDF).
6. **Hover states**: Add `MouseRegion` with highlight on data table rows (desktop).
7. **Row count**: Show "Showing X of Y results" in pagination area.
8. **Empty state for search results**: Always show "No results for '{query}'" with clear filter button.

---

## 11. Design System Specification

### 11.1 Color Roles (Current State + Recommendations)

**Current (good):** Semantic color tokens in `ApexColors` with light/dark variants.

| Token | Current (Light) | Recommended | Notes |
|-------|----------------|-------------|-------|
| `primary` | `#4F46E5` (Indigo 600) | Keep | Strong, professional |
| `primaryContainer` | `#E0E7FF` | Keep | Good contrast |
| `accent` | `#7C3AED` (Purple 600) | Keep | Differentiates from primary |
| `success` | `#16A34A` (Green 600) | Keep | Standard green |
| `warning` | `#D97706` (Amber 600) | Keep | Standard amber |
| `danger` | `#DC2626` (Red 600) | Keep | Standard red |
| `info` | `#0EA5E9` (Sky 600) | Keep | Standard blue |
| `surface` | `#FFFFFF` | Keep | Clean white |
| `surfaceMuted` | `#F5F6FA` | Keep | Good subtle background |
| `border` | `#E5E7EB` | Keep | Subtle borders |

**Additions needed:**
- `surfaceContainer` — for cards within surfaceMuted context (use `surfaceRaised` for now)
- `chart*` colors — reusable chart palette (5-7 colors for bar/lines)
- `overdue` — currently conflated with `danger`, but should be a distinct shade for past-due states
- `link` — for clickable text (currently uses `primary` which works)

### 11.2 Typography Scale (Recommended)

| Style | Font | Size | Weight | Usage |
|-------|------|------|--------|-------|
| `displayLarge` | Instrument Sans | 32 | 700 | Page title (desktop) |
| `displayMedium` | Instrument Sans | 28 | 700 | Page title (tablet) |
| `displaySmall` | Instrument Sans | 24 | 700 | Page title (mobile) |
| `headlineLarge` | Instrument Sans | 22 | 700 | Section headers |
| `headlineMedium` | Instrument Sans | 20 | 700 | Card titles |
| `headlineSmall` | Instrument Sans | 18 | 700 | Dialog titles |
| `titleLarge` | Inter | 16 | 700 | List item title |
| `titleMedium` | Inter | 14 | 600 | Card subheadings |
| `titleSmall` | Inter | 13 | 600 | Form section labels |
| `bodyLarge` | Inter | 16 | 400 | Paragraph text |
| `bodyMedium` | Inter | 14 | 400 | Default body |
| `bodySmall` | Inter | 12 | 400 | Caption, metadata |
| `labelLarge` | Inter | 14 | 600 | Button text |
| `labelSmall` | Inter | 11 | 600 | Overline, status |
| `monetaryLarge` | JetBrains Mono | 22 | 700 | KPI values |
| `monetaryMedium` | JetBrains Mono | 16 | 600 | Table amounts |
| `monetarySmall` | JetBrains Mono | 13 | 500 | Small amounts |

**Recommended Google Fonts:**
- **Instrument Sans** — Keep (display/headings). Great readability at large sizes.
- **Inter** — Keep (body/UI). Excellent readability at small sizes, extensive weight range.
- **JetBrains Mono** — Keep (financial data). Tabular figures are critical for accounting alignment.

### 11.3 Spacing Scale

**Current (good — 8px grid):** `ApexSpacing` provides xs(4), sm(8), md(12), lg(16), xl(24), xxl(32), xxxl(48)

**Recommendation:** Keep the existing scale. Add named contextual spacing:
- `pagePadding` — defaults to xl(24) desktop, sm(12) mobile
- `cardPadding` — defaults to lg(16) desktop, sm(12) mobile
- `formSpacing` — defaults to md(12) between form fields
- `sectionSpacing` — defaults to xxl(32) between sections

### 11.4 Border Radius

**Current:** `ApexRadius` provides sm(6), md(10), lg(14), xl(20), pill(999)

**Recommendations:**
- Keep all existing values
- Add `ApexRadius.none(0)` for data tables and list items that need sharp corners
- Apply consistently:
  - `pill` — status badges, chips, avatars
  - `lg` — cards, dialogs, bottom sheets
  - `md` — buttons, inputs, dropdowns
  - `sm` — table headers, small tags

### 11.5 Elevation

**Current:** Cards use zero elevation with subtle borders (`border + boxShadow`)

**Recommendations:**
- `elevation.none` — cards, panels (keep current `elevation: 0` with border)
- `elevation.low` — dropdowns, popovers (2dp shadow)
- `elevation.medium` — dialogs, bottom sheets (8dp shadow)
- `elevation.high` — command palette, date picker (16dp shadow)

### 11.6 Motion & Animation

**Current:** Shimmer loading (1500ms), slide-up transitions (200ms), KPI card hover (150ms)

**Recommendations:**
- **Duration scale**: 100ms (micro-interactions), 200ms (navigation), 300ms (modals), 500ms (page transitions)
- **Easing**: `easeOutCubic` for enter animations, `easeInCubic` for exit
- **Loading**: Keep shimmer with 1500ms pulse
- **Data refresh**: Subtle fade on content update, not full shimmer
- **Avoid**: Page transitions on mobile beyond slide-up (keep current implementation)
- **Reduced motion**: Respect `MediaQuery.boldTextOf(context)` and platform accessibility settings

---

## 12. Component Inventory

### 12.1 Existing Components (Reusable)

| Component | File | Status | Recommendation |
|-----------|------|--------|---------------|
| `PageHeader` | `core/widgets/page_header.dart` | ✅ Good | Keep — add responsive subtitle truncation |
| `ApexCard` | `core/widgets/page_header.dart` | ✅ Good | Keep — promote to own file |
| `EmptyState` | `core/widgets/states.dart` | ✅ Good | Keep — add variant for search results |
| `ErrorView` | `core/widgets/states.dart` | ✅ Good | Keep — add retry tracking |
| `LoadingState` | `core/widgets/states.dart` | ✅ Good | Keep |
| `LoadingSpinner` | `core/widgets/states.dart` | ✅ Good | Keep |
| `StatusBadge` | `core/widgets/status_badge.dart` | ✅ Good | Keep — expand tone coverage |
| `ShimmerSkeleton` | `core/widgets/skeleton_loader.dart` | ✅ Good | Keep |
| `MonetaryText` | `core/widgets/monetary_text.dart` | ✅ Good | Keep — use more consistently |
| `ApexDataTable` | `core/tables/apex_data_table.dart` | ✅ Good | Keep — add column visibility, export |
| `ApexTableBody` | `core/tables/table_body.dart` | ✅ Good | Keep — add hover, row numbers |
| `ApexTableController` | `core/tables/table_controller.dart` | ✅ Good | Keep |
| `ApexPaginationControls` | `core/tables/table_pagination.dart` | ✅ Good | Keep |
| `ApexSearchBar` | `core/widgets/search_bar.dart` | ✅ Good | Keep — add debounce, clear button |
| `Breadcrumbs` | `core/navigation/breadcrumbs.dart` | ⚠️ Unused | Start using on all detail screens |
| `CommandPalette` | `core/search/command_palette.dart` | ✅ Good | Expand command list |
| `TransactionDetailLayout` | `core/widgets/transaction_detail_layout.dart` | ✅ Good | Keep — used well |
| `AppSplash` | `app/app_splash.dart` | ✅ Adequate | Keep |
| `BaseRepository` | `core/api/base_repository.dart` | ✅ Good | Keep |
| `BaseCrudController` | `core/crud/base_crud.dart` | ✅ Good | Keep |
| `BaseListScreen` | `core/crud/base_crud.dart` | ✅ Good | Keep — ensure all features use it |
| `PermissionGate` | `core/permissions/permission_gate.dart` | ✅ Good | Keep |
| `NumberFormatter` | `core/formatting/number_formatting.dart` | ✅ Good | Keep |
| `ApexDialogs` | `core/dialogs/apex_dialogs.dart` | ✅ Good | Keep — use everywhere, remove raw showDialog |
| `DialogService` | `core/dialogs/dialog_service.dart` | ✅ Good | Merge with ApexDialogs |
| `ResponsiveLayout` | `core/theme/responsive.dart` | ✅ Good | Keep |
| `ApexColors` / `ApexSpacing` / `ApexRadius` | `core/theme/app_colors.dart` | ✅ Good | Keep |
| `ThemeController` | `core/theme/theme_controller.dart` | ✅ Good | Keep |
| `EntitySelector` | `core/selectors/entity_selector.dart` | ✅ Good | Keep |
| `HubTabWidget` | `features/home/home_shell_widgets.dart` | ✅ Good | Keep — well used |
| `AuditTimeline` | `core/timeline/audit_timeline.dart` | ✅ Good | Keep — ensure used on detail screens |
| `PageHeaderSkeleton` | `core/widgets/skeleton_loader.dart` | ✅ Good | Keep |
| `TableRowSkeleton` | `core/widgets/skeleton_loader.dart` | ✅ Good | Keep |
| `DetailSectionSkeleton` | `core/widgets/skeleton_loader.dart` | ✅ Good | Keep |

### 12.2 Missing Components (Need Creation)

| Component | Priority | Description |
|-----------|----------|-------------|
| `ApexFilterBar` | Critical | Reusable filter row: search + status chips + date range + type filter |
| `DateRangePicker` | Critical | Unified date range selector with presets (Today, This Week, This Month, This Quarter, This Year, Custom) |
| `ApexLineItemEditor` | High | Reusable line-item table/card editor for invoices, bills, POs, GRs |
| `ApexReceiptUploader` | High | Upload/capture receipt with preview, used by expenses and bills |
| `ApexConfirmDialog` | High | Destructive action confirmation with reason field (for void/cancel/reverse) |
| `AppShell` | Medium | Extract sidebar/rail/drawer logic from HomeShell into reusable AppShell |
| `ApexKpiCard` | Medium | Standard KPI card with trend indicator, icon, color coding |
| `ApexChartContainer` | Medium | Standard chart wrapper with title, legend, period selector |
| `ApexEmptySearch` | Medium | "No results for X" with clear filters button |
| `ApexToast` | Medium | Standard success/error toast with undo action support |
| `ApexDraftIndicator` | Medium | Shows "Draft saved N minutes ago" for forms with auto-save |
| `ApexPeriodLockBanner` | Medium | Shows "This period is closed" warning with details |
| `ApexQuickCreateFab` | Medium | FAB that opens contextual quick-create options |
| `ApexAuditTimelineItem` | Low | Individual audit entry with user avatar, action, timestamp |
| `ApexKeyboardShortcutHint` | Low | Shows available keyboard shortcuts in tooltip form |

---

## 13. Accessibility Audit

### 13.1 Current State

The application has some accessibility foundations but significant gaps.

**What's good now:**
- Theme respects system text scaling (WCAG 1.4.4 — no clamp below 2.0)
- Keyboard shortcuts for power users (Ctrl+S, Ctrl+K, Alt+N)
- `CallbackShortcuts` and `Focus` widgets on form screens
- Semantic colors use adequate contrast ratios (most pass AA)
- `Tooltip` on icon-only buttons

**Critical gaps:**

| Issue | WCAG Criterion | Affected Areas | Severity |
|-------|---------------|----------------|----------|
| No `Semantics` labels on most widgets | 4.1.2 Name, Role, Value | Every screen | Critical |
| Status indicators use color only | 1.4.1 Use of Color | StatusBadge, KPI cards, charts | Critical |
| No screen reader announcements for dynamic updates | 4.1.3 Status Messages | Form submissions, data loading | High |
| Modal dialogs don't trap focus | 2.4.3 Focus Order | ApexDialogs, CommandPalette | High |
| No `aria-label` on icon-only buttons | 4.1.2 Name, Role, Value | Edit, Delete, Close buttons | High |
| Data tables lack proper header associations | 1.3.1 Info and Relationships | All table screens | High |
| Charts (fl_chart) have no accessible data | 1.1.1 Non-text Content | Dashboard chart | High |
| Touch targets may be < 44×44 on desktop | 2.5.5 Target Size | Table rows, compact buttons | Medium |
| No reduced-motion support | 2.3.3 Animation from Interactions | Shimmer, page transitions | Medium |
| Form errors not announced to screen readers | 3.3.1 Error Identification | All forms | Medium |
| Focus order may skip elements in tab widgets | 2.4.3 Focus Order | HubTabWidget screens | Medium |
| No skip-to-content link | 2.4.1 Bypass Blocks | App shell | Low |

### 13.2 Recommended Fixes (by Priority)

**Immediate (P0):**
1. Add `Semantics` labels to all interactive elements — buttons, links, form fields, table rows
2. Add non-color indicators to status badges — icons or patterns alongside color
3. Wrap all `ListTile`, `Card`, `InkWell` with `Semantics` for screen readers

**Short-term (P1):**
4. Add `AnnounceStatus` for form submissions and data loading
5. Fix focus trapping in `ApexDialogs` and `CommandPalette`
6. Add `aria-label` equivalents to all icon-only buttons and `FloatingActionButton`
7. Ensure data tables use proper `Table` semantics or add `Semantics` headers

**Medium-term (P2):**
8. Add chart accessible descriptions (data table equivalent or `Semantics` label)
9. Increase minimum touch target to 44×44 on desktop (especially table rows)
10. Respect `MediaQuery.boldTextOf(context)` and `disableAnimations`
11. Add form error live regions for screen readers

---

## 14. Responsive Layout Strategy

### 14.1 Breakpoints

**Current:** `mobile < 600 < tablet < 1024 ≤ desktop`

**Recommended (refined):**

| Breakpoint | Label | Layout | Max Content Width |
|-----------|-------|--------|-------------------|
| < 400 | Small mobile | Single column, stacked | Fluid |
| 400-599 | Standard mobile | Single column, 2-up cards | Fluid |
| 600-839 | Small tablet | 2-column, rail navigation | Fluid |
| 840-1023 | Large tablet | 2-3 column, rail navigation | 840 |
| 1024-1439 | Laptop | Sidebar visible, 3-4 column | 1200 |
| 1440-1919 | Desktop | Full sidebar, multi-column | 1440 |
| ≥ 1920 | Wide desktop | Full sidebar, max-width centered | 1600 |

### 14.2 Adaptive Patterns

**Navigation:**
- `< 600`: BottomNavigationBar (4 items) + Drawer
- `600–1023`: NavigationRail (icons + labels) + optional Drawer
- `≥ 1024`: Fixed sidebar (collapsible to icon-only)

**Tables:**
- `< 600`: Card-based list (each row = a card) with horizontal scroll for wide columns
- `600–1023`: Compact table with reduced columns (hide non-essential columns)
- `≥ 1024`: Full data table with all columns, sticky header, frozen action column

**Forms:**
- `< 600`: Full-screen form, single column, section cards
- `600–1023`: Centered form (max-width 720px), 2-column field layout
- `≥ 1024`: Centered form (max-width 900px), 3-4 column field layout

**Master-Detail:**
- `< 600`: List → push detail (full-screen). Back button on detail.
- `600–1023`: List → slide-up detail (80% screen). Can swipe to dismiss.
- `≥ 1024`: Split view (list 40% + detail 60% or 50/50).

**Dialogs vs Sheets:**
- `< 600`: Bottom sheets for confirmation, full-screen for forms
- `600–1023`: Centered dialogs for confirmation, sliding sheets for forms
- `≥ 1024`: Centered dialogs, side panels for forms

### 14.3 Implementation Approach

The current `ResponsiveLayout` widget is a good foundation. Recommended enhancements:

1. **Replace `LayoutBuilder` with `MediaQuery` for breakpoint detection** — avoids layout rebuilds when child constraints aren't the full viewport.

2. **Add `ResponsiveVisibility` widget** — conditionally show/hide content based on breakpoint:
```dart
ResponsiveVisibility(
  hideFor: ScreenSize.mobile,
  child: AdvancedFilters(),
)
```

3. **Add `ResponsiveValue` pattern** — pick values per breakpoint:
```dart
final padding = ResponsiveValue<double>(
  context,
  values: {ScreenSize.mobile: 12, ScreenSize.tablet: 16, ScreenSize.desktop: 24},
);
```

4. **Sticky headers**: Use `SliverAppBar` + `CustomScrollView` for list screens that need collapsible headers with sticky search bars.

5. **Avoid `SingleChildScrollView` + `Row` for horizontal scroll** — use `Scrollbar` + `SingleChildScrollView` with `ScrollNotification` for table horizontal scroll.

---

## 15. Flutter Architecture Recommendations

### 15.1 Folder Structure (Refined)

The current structure is good. Refinements:

```
frontend/lib/
├── main.dart                    # Entry point
├── app/                         # App bootstrap
│   ├── apex_app.dart            # MaterialApp.router
│   └── app_splash.dart          # Splash screen
├── core/                        # Shared infrastructure
│   ├── api/                     # API client, base model, repository
│   ├── cache/                   # Cache service
│   ├── config/                  # Env config, feature flags
│   ├── constants/               # App constants
│   ├── crud/                    # Generic CRUD controllers
│   ├── design_system/           # NEW — design system components
│   │   ├── tokens/              # Colors, spacing, typography (moved from theme)
│   │   ├── components/          # Shared components (card, buttons, inputs)
│   │   └── layouts/             # Page layouts, responsive framework
│   ├── dialogs/                 # Dialog system
│   ├── errors/                  # Error handling
│   ├── formatting/              # Number, date formatting
│   ├── forms/                   # Form components
│   ├── navigation/              # Breadcrumbs (unused — start using)
│   ├── network/                 # Dio, interceptors
│   ├── permissions/             # Permission system
│   ├── result/                  # Result type
│   ├── routing/                 # GoRouter
│   ├── search/                  # Command palette
│   ├── services/                # Cross-cutting services (favorites, recent items, notifications)
│   ├── storage/                 # Session storage
│   ├── tables/                  # Data table system
│   ├── theme/                   # ThemeData builders (keep)
│   └── widgets/                 # Shared widgets (loaders, states, etc.)
├── features/                    # Feature modules
│   ├── accounting/              # COA, journals, ledger, reconciliation
│   ├── auth/                    # Login, register, password reset, company selection
│   ├── banking/                 # Bank accounts, reconciliation
│   ├── dashboard/               # Dashboard
│   ├── expenses/                # Expenses
│   ├── gst/                     # GST dashboard, returns
│   ├── home/                    # App shell, navigation
│   ├── inventory/               # Stock, transfers, adjustments, warehouses
│   ├── masters/                 # Accounts, contacts, products, tax templates, etc.
│   ├── purchases/               # POs, GRs, bills, vendor payments, returns
│   ├── reports/                 # All reports
│   ├── sales/                   # Invoices, proformas, orders, challans, payments
│   └── settings/                # All settings screens
└── test/                        # Tests (mirror lib structure)
```

### 15.2 Widget Responsibility Rules

| Widget Type | Responsibility | Max Lines | Props |
|------------|---------------|-----------|-------|
| **Screen** | Page state, layout, async data wiring | 400 | `ConsumerStatefulWidget` or `ConsumerWidget` |
| **Form Notifier** | Form state, validation, API calls | 200 | `StateNotifier<FormState>` |
| **Service** | API communication, business logic | 300 | Singleton/provider |
| **Component** | Self-contained reusable UI | 150 | `StatelessWidget` preferred |
| **Layout** | Arranges children, no business logic | 100 | `StatelessWidget` |

**Current violations:**
- `InvoiceFormScreen` (~1700 lines) — should be 400 max, extract sub-widgets
- `DashboardScreen` (~960 lines) — should be 400 max, extract chart, KPI, alerts
- `ExpenseScreen` (~560 lines with service) — should be split

**Remediation:**
- Extract line item editor from invoice form → `ApexLineItemEditor` component
- Extract KPI card → `ApexKpiCard` component
- Extract chart card → `ApexChartContainer` component
- Extract alert list → `ApexOverdueList` component
- All extracted components go in `core/design_system/components/`

### 15.3 State Management Guidelines

| State Type | Pattern | Example |
|-----------|---------|---------|
| API list data | `FutureProvider.autoDispose` | Invoice list, contact list |
| Paginated list | `StateNotifier<AsyncValue<Paged<T>>>` + `ChangeNotifier` for table | Table with server-side pagination |
| Form state | `StateNotifier<FormState>` | InvoiceFormNotifier |
| Form with auto-save | `StateNotifier` + `Timer` + local storage backup | Journal form (future) |
| Global app state | `Provider` or `StateProvider` | Auth state, theme mode |
| Computed/derived | `Provider` with `ref.watch` | Derived totals, filtered lists |
| User preferences | `FutureProvider` from SharedPreferences | Theme, locale, currency |

**Anti-patterns to eliminate:**
- ❌ Raw `setState` for complex forms (journal, expense)
- ❌ Service classes in widget files (expense)
- ❌ `StatefulWidget` with manual `_lineControllers` (invoice form line rows — use state hoisting)
- ❌ `Timer.periodic` for auto-refresh without disposal check (dashboard)

### 15.4 Performance Considerations

| Issue | Recommendation |
|-------|---------------|
| Excessive rebuilds | Add `const` constructors, use `Select` in Riverpod to narrow widget rebuilds |
| Large lists | Use `ListView.builder` (already done) — consider `addAutomaticKeepAlives` for tab views |
| Image loading | Use `cached_network_image` for avatars, receipt thumbnails |
| Animation cost | Keep shimmers at 1500ms, use `easeOutCubic` for cheap animations |
| Table scrolling | Ensure `ApexTableBody` uses `Scrollbar` with `ScrollController` |
| Form state | Avoid rebuilding entire form on every keystroke — use `StateNotifier` with immutable state |
| Google Fonts | Cache fonts with `GoogleFonts` package (already done) |

---

## 16. Financial Safety Recommendations

### 16.1 Actions Requiring Confirmation

| Action | Current | Recommended | Warning Message |
|--------|---------|-------------|-----------------|
| Delete transaction | ❌ No confirmation | ✅ Popup dialog | "This action cannot be undone. The transaction will be permanently deleted." |
| Void invoice | ⚠️ Partial (has cancel) | ✅ Add reason field | "This will create reversal entries in the ledger and reverse stock movements. Provide a reason." |
| Reverse journal entry | ❌ Not available | ✅ Add reversal action | "A reversing entry will be created on [date]. Original entry will be preserved for audit." |
| Edit posted transaction | ⚠️ Permissions-gated | ✅ Warning banner | "This transaction is already posted. Changes will create audit trail entries." |
| Close accounting period | ❌ Not available in UI | ✅ Multi-step confirmation | "Period [name] will be locked. No transactions can be posted after [date]. This can be undone by the administrator." |
| Change tax settings | ❌ No confirmation | ✅ Popup with impact summary | "Changing GST configuration affects all future transactions. Filed periods remain unchanged." |
| Delete customer with transactions | ⚠️ Basic confirmation | ✅ Warning with transaction count | "This customer has 15 invoices and 5 payments. Delete anyway? Invoices will be orphaned." |
| Bulk delete | ❌ Not implemented | ✅ Count + confirmation | "Delete 3 invoices? This action cannot be undone." |

### 16.2 Strict Rules

1. **No permanent delete for financial transactions**. Always prefer: Cancel → Void → Reverse over Delete. Only allow deletion of drafts.

2. **Opening balances require admin confirmation**. Changing opening balances should require a separate permission (`accountsManage`), reason entry, and audit log entry.

3. **Period lock enforcement**. Once a period is closed, the UI must prevent creating/editing transactions dated in that period. Show a clear lock banner at the top of the form.

4. **Out-of-balance journals must not post**. The journal form must prevent submission until balanced. Show a persistent warning banner while out of balance.

5. **Negative inventory must warn**. If a stock transfer would result in negative inventory, show a confirmation with potential impact.

6. **Duplicate detection**. Before creating a transaction, check for potential duplicates (same vendor, same amount, same date) and warn the user.

7. **Rounding must be explicit**. Show round-off adjustments as a separate line in totals, not silently included in tax calculations.

8. **Audit trail for every write operation**. Every create, update, cancel, void, reverse must create an audit entry with: user ID, action type, timestamp, before/after JSON snapshot.

### 16.3 Color + Label Requirements

**Financial statuses must never rely on color alone:**

| Status | Color | Icon | Label |
|--------|-------|------|-------|
| Paid | Green | ✓ | "Paid on 15 Jul" |
| Overdue | Red | ⚠ | "Overdue by 5 days" |
| Pending | Amber | ○ | "Due on 20 Jul" |
| Draft | Grey | ✎ | "Draft" |
| Cancelled | Red | ✗ | "Cancelled — reason" |
| Reconciled | Green | ⟳ | "Reconciled on 15 Jul" |
| Unreconciled | Grey | ⟳ | "Not reconciled" |

---

## 17. Prioritized Implementation Roadmap

### 17.1 Stage Summary

| Stage | Name | Estimated Effort | Duration | Screens Affected |
|-------|------|-----------------|----------|-----------------|
| 1 | Foundation | Large | 3-4 weeks | All screens |
| 2 | High-Impact Workflows | Large | 4-5 weeks | Dashboard, Invoices, Expenses, Banking |
| 3 | Accounting Workflows | Medium | 3-4 weeks | COA, Journals, Period End, Audit |
| 4 | Reporting | Large | 3-4 weeks | All report screens |
| 5 | Refinement | Medium | 2-3 weeks | Onboarding, Help, Performance, Analytics |

### 17.2 Stage 1: Foundation (Weeks 1-4)

**Focus:** Design system consolidation, shared components, accessibility foundations

**Deliverables:**
- [ ] Create `core/design_system/tokens/` with unified color, spacing, typography tokens
- [ ] Create `core/design_system/components/` with all shared components
- [ ] Build `ApexFilterBar` (search + status chips + date range)
- [ ] Build `DateRangePicker` with presets
- [ ] Build `ApexConfirmDialog` with reason field
- [ ] Extract `ApexKpiCard` from dashboard
- [ ] Extract `ApexLineItemEditor` from invoice form
- [ ] Create `ResponsiveVisibility` and `ResponsiveValue` utilities
- [ ] Fix all accessibility P0 issues (Semantics labels, color-independent status)
- [ ] Migrate all screens to use shared components
- [ ] Add unit tests for all new components

**Files affected:** All feature screens (refactoring to use shared components)
**Test requirements:** Widget tests for each new component
**Risks:** Breaking changes if component interfaces aren't stable; plan 1-week buffer

### 17.3 Stage 2: High-Impact Workflows (Weeks 5-9)

**Focus:** Dashboard, Invoices, Expenses, Banking/Reconciliation

**Deliverables:**
- [ ] Dashboard: Add cash balance, period comparison, quick action row, responsive grid
- [ ] Dashboard: Configurable auto-refresh, add key metrics backend API
- [ ] Invoice form: Extract into sub-widgets, add "Save & Send", add preview toggle
- [ ] Invoice form: Add discount percentage toggle, recurring toggle, attachments
- [ ] Invoice list: Add bulk selection, column visibility, export
- [ ] Expense screen: Complete rewrite — split files, add Riverpod, receipt upload, vendor autocomplete
- [ ] **Bank reconciliation: Complete rewrite — side-by-side matching, confidence scoring, match/categorize/transfer/exclude actions, progress tracking**
- [ ] Banking: Add account balance display, transaction feed

**Files affected:** `dashboard_screen.dart`, `invoice_form_screen.dart`, `expense_screen.dart`, new reconciliation screens
**Test requirements:** Full widget tests for reconciliation workflow, invoice form submission, expense posting
**Risks:** Reconciliation is the highest-risk change — test with real data

### 17.4 Stage 3: Accounting Workflows (Weeks 10-13)

**Focus:** COA, Journal Entries, Period End, Audit Trail

**Deliverables:**
- [ ] Journal form: Migrate to Riverpod, add account search, auto-balance, keyboard navigation
- [ ] Journal form: Add template support, draft auto-save, reverse entry
- [ ] COA: Add drill-down to ledger, opening balance editing with confirmation
- [ ] Period end: New screen for period closing with lock/unlock
- [ ] Period end: Show period status banner on all form screens
- [ ] Audit trail: Build readable audit timeline (use existing `AuditTimeline` widget)
- [ ] Audit trail: Add export for audit log

**Files affected:** `journal_form_screen.dart`, new period_end_screen, `audit_timeline.dart`
**Test requirements:** Journal balancing test, period lock enforcement test, audit trail completeness
**Risks:** Period locking affects all transactional screens — thorough regression testing required

### 17.5 Stage 4: Reporting (Weeks 14-17)

**Focus:** Unified report framework, all financial reports

**Deliverables:**
- [ ] Build reusable `ReportShell` widget (period selector, comparison toggle, export button, search)
- [ ] Add comparison period support to P&L, Balance Sheet, Trial Balance
- [ ] Build Cash Flow Statement (currently missing)
- [ ] Build Aged Receivables and Aged Payables reports
- [ ] Add expand/collapse to all reports
- [ ] Add drill-down from reports to transaction lists
- [ ] Add export (PDF, Excel) to all reports using `DownloadService`
- [ ] Add saved custom views with naming

**Files affected:** All report screens, `reports_shell.dart`, new report screens
**Test requirements:** Report data accuracy tests, export format tests, drill-down navigation
**Risks:** Cash flow statement is complex — requires ledger data aggregation

### 17.6 Stage 5: Refinement (Weeks 18-20)

**Focus:** Onboarding, help content, motion, performance, analytics

**Deliverables:**
- [ ] Build onboarding flow for new users (first login → create company → first invoice)
- [ ] Add contextual help tooltips on complex screens (journal, reconciliation, COA)
- [ ] Add keyboard shortcut cheat sheet (Ctrl+? or menu item)
- [ ] Performance audit + optimization (rebuild reduction, list virtualization, image caching)
- [ ] Add analytics events for key actions (invoice created, expense posted, report exported)
- [ ] Add error tracking with Sentry or similar
- [ ] Usability testing with 5 users from different personas
- [ ] Compile UX metrics (see Section 20)

**Files affected:** New onboarding screens, performance improvements across all screens
**Test requirements:** Onboarding flow E2E test, analytics event tests
**Risks:** Low — mostly additive

---

## 18. Risks and Dependencies

### 18.1 Key Dependencies

| Change | Depends On | Risk if Unblocked |
|--------|-----------|-------------------|
| Dashboard cash balance | Backend API `GET /banking/balances` | Cannot show live cash |
| Reconciliation matching | Backend matching algorithm + statement parsing | Core feature blocked |
| Report comparison | Backend `previous_period` data | Cannot show period comparison |
| PDF export | Backend PDF generation (exists) | Already functional |
| Invoice "Send" | Backend email service (exists) | Already functional |
| Period locking | Backend period lock API (exists) | Already functional |
| Attachment upload | Backend file upload endpoint | Already functional |

### 18.2 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Breaking existing forms during refactor | Medium | High | Write widget tests before refactoring each screen |
| Reconciliation implementation scope creep | High | High | Define strict MVP scope (upload + basic matching only) |
| Riverpod 3.x migration during project | Low | Medium | Stay on 2.6.x until refactor complete |
| Designer-developer handoff gaps | Medium | Medium | Document all components in this spec + Flutter code |
| Performance regression from new components | Low | Medium | Profile before/after on target devices |
| User resistance to layout changes | Medium | Low | Introduce changes gradually, survey user feedback |

---

## 19. Testing Strategy

### 19.1 Test Categories

| Category | Tools | Coverage Target | Execution |
|----------|-------|----------------|-----------|
| Unit (services) | `flutter_test` | 90% | CI per commit |
| Widget (components) | `flutter_test` | 80% | CI per commit |
| Widget (screens) | `flutter_test` | 70% | CI per PR |
| Golden (screenshots) | `golden_toolkit` | Key screens | CI per PR |
| Integration (workflows) | `integration_test` | 15 workflows | CI nightly |
| Accessibility | `flutter_test` + `accessibility` checker | All screens | CI per commit |
| Financial accuracy | Custom assertion framework | All calculation services | CI per commit |

### 19.2 Test Requirements per Screen

Every screen must have tests for:

- **Loading state**: Verify skeleton/shimmer renders
- **Empty state**: Verify empty state with action button
- **Error state**: Verify error message + retry button
- **Data state**: Verify data renders correctly
- **Navigation**: Verify push/pop behavior
- **Responsive**: Verify mobile/tablet/desktop layouts render without overflow
- **Permissions**: Verify permission-gated elements visibility

### 19.3 Financial Accuracy Tests

| Test | Description |
|------|-------------|
| Invoice calculation | Verify subtotal, discount, tax, total with various GST rates |
| Bill calculation | Same as invoice for purchases |
| Journal balancing | Verify balanced/unbalanced detection at 0.005 tolerance |
| Trial balance | Verify total debits = total credits |
| P&L net profit | Verify revenue - expense = net profit |
| Reconciliation | Verify matched totals = bank statement total |
| Currency formatting | Verify ₹1,23,456.78 format for INR locale |
| Negative values | Verify consistent (parentheses) display |

### 19.4 Current Test Coverage

The existing 383 tests provide a good baseline. Priority additions:

| Area | Current | Target | New Tests Needed |
|------|---------|--------|-----------------|
| Dashboard | Minimal | 10+ | KPI rendering, chart data, alerts empty/error states |
| Invoice form | Good | 25+ | Line calculations, GST variations, state code validation |
| Invoice list | Minimal | 10+ | Search filtering, status filter, pagination, empty states |
| Expense form | 0 | 15+ | Category selection, GST calculation, receipt upload |
| Journal form | 0 | 15+ | Line entry, balance checking, account search |
| Reconciliation | 0 | 20+ | Statement upload, matching, progress, completion |
| Reports | 0 | 10+ | Data rendering, date filtering, drill-down |
| Navigation | Good | 5+ | Auth redirect, deep linking, back navigation |

---

## 20. Success Metrics

### 20.1 Quantitative Targets

| Metric | Current (Estimated) | Target (90 Days) | Measurement |
|--------|--------------------|------------------|-------------|
| Invoice creation time | ~3 minutes | < 90 seconds | Timer (begin→save) |
| Expense recording time | ~2 minutes | < 45 seconds | Timer (begin→save) |
| Bank reconciliation time | Unusable | < 10 minutes per statement | Timer (upload→finish) |
| Journal entry time | ~2 minutes | < 60 seconds for 2-line | Timer (begin→post) |
| Form error rate | Unknown | < 10% of submissions | Analytics event |
| Form abandonment rate | Unknown | < 20% | Analytics event |
| Accidental destructive actions | Unknown | 0 per month | Audit log analysis |
| Mobile task completion rate | Poor | > 80% | E2E tests per workflow |
| Accessibility issues | 15+ critical | 0 critical, < 5 medium | Automated audit per sprint |
| User satisfaction (SUS) | Unknown | > 70 | Quarterly survey |
| Report discovery rate | Unknown | > 50% of users | Analytics — report views per user |

### 20.2 Qualitative Success Indicators

| Indicator | Assessment Method |
|-----------|------------------|
| Users complete invoice creation without assistance | Usability test observation |
| Non-accountants understand their financial position from dashboard | User interview |
| Accountants can reconcile a statement without support calls | Support ticket analysis |
| New users create their first invoice within 5 minutes of onboarding | Analytics funnel |
| Users discover keyboard shortcuts without documentation | Feature tracking |

### 20.3 Measurement Tools

| Tool | What It Measures |
|------|-----------------|
| Firebase Analytics | Screen views, event funnels, user engagement |
| Sentry / Crashlytics | Error rates, crash-free session rate |
| Custom analytics events | Form completion time, abandonment, error rates |
| In-app surveys (5-star CES) | Customer effort score for key workflows |
| Session recording (Hotjar / FullStory) | User behavior, confusion points, rage clicks |
| Suspended time tracking | Dashboard overload detection (too much time on dashboard = can't find info) |

---

## Appendix A: File Reference

### A.1 All Screens and Their Routes

| Screen | Route | GoRouter Name |
|--------|-------|---------------|
| AppSplash | `/splash` | `splash` |
| LoginScreen | `/login` | `login` |
| RegisterScreen | `/register` | `register` |
| ForgotPasswordScreen | `/forgot-password` | `forgot-password` |
| ResetPasswordScreen | `/reset-password` | `reset-password` |
| CompanySelectionScreen | `/select-company` | `select-company` |
| HomeShell (all features) | `/` | `home` |

### A.2 Design Tokens Reference

See `frontend/lib/core/theme/app_colors.dart` for current tokens.
See `frontend/lib/core/theme/app_theme.dart` for current ThemeData.
See `frontend/lib/core/theme/responsive.dart` for breakpoint definitions.
See `frontend/lib/core/widgets/monetary_text.dart` for financial typography.

---

## Appendix B: Quick Reference — 10 Most Impactful Changes

| Rank | Change | Impact | Effort | Stage |
|------|--------|--------|--------|-------|
| 1 | **Build bank reconciliation matching UI** | Critical — unlocks core accounting workflow | Large | 2 |
| 2 | **Create unified filter/date-range component** | High — fixes inconsistency across 20+ screens | Medium | 1 |
| 3 | **Refactor invoice form (extract components)** | High — reduces 1700-line file, enables feature parity | Large | 2 |
| 4 | **Rewrite expense screen with Riverpod + receipt** | High — fixes service-in-widget anti-pattern | Medium | 2 |
| 5 | **Rewrite journal form with Riverpod + auto-balance** | High — fixes setState, adds critical features | Medium | 3 |
| 6 | **Add bulk selection + column visibility to tables** | High — power-user efficiency | Medium | 1 |
| 7 | **Add P0 accessibility (Semantics, color-independent status)** | Critical — accessibility compliance | Medium | 1 |
| 8 | **Add period comparison to all reports** | High — unlocks financial analysis | Large | 4 |
| 9 | **Implement breadcrumbs across all screens** | Medium — improves navigation clarity | Small | 1 |
| 10 | **Add Cash Flow Statement report** | High — critical missing financial statement | Medium | 4 |

---

*End of UX Audit Report*
