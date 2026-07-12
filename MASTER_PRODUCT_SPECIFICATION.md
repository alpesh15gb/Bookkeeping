# ApexBooks — Master Product Specification

> Version 1.0 | 2026-07-13
> 
> This document is the single source of truth for every menu, screen, dialog, button, form field, report, setting, workflow, print template, API endpoint, permission, and keyboard shortcut in ApexBooks. It serves as the blueprint for all implementation work.

---

## Table of Contents

1. [Navigation Tree](#1-navigation-tree)
2. [Screen Specifications](#2-screen-specifications)
3. [Dialogs & Modals](#3-dialogs--modals)
4. [Forms & Fields](#4-forms--fields)
5. [Reports](#5-reports)
6. [Settings Pages](#6-settings-pages)
7. [Print Templates](#7-print-templates)
8. [API Endpoint Mapping](#8-api-endpoint-mapping)
9. [Permissions Matrix](#9-permissions-matrix)
10. [Keyboard Shortcuts](#10-keyboard-shortcuts)
11. [Workflows](#11-workflows)
12. [Implementation Status](#12-implementation-status)

---

## 1. Navigation Tree

### 1.1 Sidebar / Drawer Structure

```
OVERVIEW
├── Dashboard                          [DashboardScreen]
│   ├── KPI Cards (6 cards)
│   ├── Revenue Trend Chart (fl_chart bar)
│   ├── Overdue Alerts
│   ├── GST Summary
│   └── Quick Actions: New Invoice, Refresh

TRANSACTIONS
├── Invoices                           [InvoiceListScreen]
│   ├── InvoiceDetailScreen (right-panel / full-screen)
│   ├── InvoiceFormScreen (create/edit)
│   ├── InvoiceSearchBar
│   ├── InvoiceTableBody
│   └── InvoiceListProvider
│
├── Purchases                          [HubTabWidget]
│   ├── Orders tab                     [PurchaseOrderListScreen]
│   │   ├── PurchaseOrderDetailScreen
│   │   ├── PurchaseOrderFormScreen
│   │   └── PurchaseOrderTableBody
│   ├── Receipts tab                   [GoodsReceiptListScreen]
│   │   ├── GoodsReceiptDetailScreen
│   │   ├── GoodsReceiptFormScreen
│   │   └── GoodsReceiptTableBody
│   ├── Bills tab                      [BillListScreen]
│   │   ├── BillDetailScreen
│   │   ├── BillTableBody
│   │   └── ⚠️ MISSING: BillFormScreen
│   ├── Payments tab                   [VendorPaymentListScreen]
│   │   ├── VendorPaymentFormScreen
│   │   └── VendorPaymentDetailScreen
│   └── Returns tab                    [PurchaseReturnListScreen]
│       ├── PurchaseReturnDetailScreen
│       ├── PurchaseReturnFormScreen
│       └── PurchaseReturnTableBody
│
├── Inventory                          [HubTabWidget]
│   ├── Stock tab                      [InventoryListScreen]
│   ├── Ledger tab                     [StockMovementListScreen]
│   ├── Transfers tab                  [TransferListScreen]
│   │   ├── TransferDetailScreen
│   │   └── TransferFormScreen
│   ├── Adjustments tab                [AdjustmentListScreen]
│   │   └── AdjustmentFormScreen
│   └── Warehouses tab                 [WarehouseListScreen]
│       └── ⚠️ MISSING: WarehouseFormScreen, WarehouseDetailScreen

FINANCIALS
├── Ledger                             [HubTabWidget]
│   ├── COA tab                        [AccountListScreen]
│   │   ├── AccountDetailScreen
│   │   └── AccountFormScreen
│   ├── Journals tab                   [JournalListScreen]
│   │   └── ⚠️ MISSING: JournalFormScreen
│   └── Trial Balance tab              [TrialBalanceScreen]
│
├── ⚠️ MISSING: Profit & Loss
├── ⚠️ MISSING: Balance Sheet
├── ⚠️ MISSING: Cash Flow Statement
├── ⚠️ MISSING: Bank Reconciliation
│
└── Banking                            [BankingProfileListScreen]
    ├── BankingProfileDetailScreen
    └── BankingProfileFormScreen

DIRECTORIES
├── Contacts                           [ContactListScreen]
│   ├── ContactDetailScreen
│   └── ContactFormScreen
│
└── Products                           [ProductListScreen]
    ├── ProductDetailScreen
    └── ProductFormScreen

SYSTEM
├── Settings                           [HubTabWidget]
│   ├── Taxes tab                      [TaxTemplateListScreen] (read-only)
│   ├── Terms tab                      [PaymentTermListScreen] (read-only)
│   └── Categories tab                 [ExpenseCategoryListScreen]
│
├── ⚠️ MISSING: Company Profile
├── ⚠️ MISSING: Financial Year
├── ⚠️ MISSING: Numbering Series
├── ⚠️ MISSING: Team/Roles
├── ⚠️ MISSING: Branches
├── ⚠️ MISSING: GST Config
├── ⚠️ MISSING: Email/SMTP
├── ⚠️ MISSING: Backup & Restore
├── ⚠️ MISSING: Data Import/Export
│
├── ⚠️ MISSING: GST (GSTR-1, GSTR-3B, E-Invoice, E-Way Bill)
├── ⚠️ MISSING: Reports (15+ report screens)
├── ⚠️ MISSING: Expenses
├── ⚠️ MISSING: Quotations
├── ⚠️ MISSING: Sales Orders
├── ⚠️ MISSING: Delivery Challans
├── ⚠️ MISSING: Credit Notes
├── ⚠️ MISSING: Debit Notes
├── ⚠️ MISSING: Recurring Invoices
└── ⚠️ MISSING: Audit Log Viewer
```

### 1.2 Auth Routes

```
/                              → HomeShell (requires auth + tenant)
/login                         → LoginScreen
/register                      → RegisterScreen
/forgot-password               → ForgotPasswordScreen
/reset-password                → ResetPasswordScreen
/select-company                → CompanySelectionScreen
/splash                        → AppSplash
/2fa                           → ⚠️ MISSING: TwoFactorScreen
```

### 1.3 Breadcrumbs

- `core/navigation/breadcrumbs.dart` — Widget exists, **never used** anywhere in the app.

---

## 2. Screen Specifications

### 2.1 DashboardScreen

| Property | Value |
|----------|-------|
| **File** | `features/dashboard/presentation/dashboard_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /dashboard/kpis`, `/dashboard/metrics`, `/dashboard/revenue-trend`, `/dashboard/expense-trend`, `/dashboard/overdue-alerts` |
| **Permission** | `invoice:view` |
| **Layout** | Mobile: single column. Desktop: responsive grid with KPI cards, chart + alerts side-by-side |
| **Sections** | Header (greeting, overview title, date, Refresh button, New Invoice button), KPI Grid (6 cards), Revenue/Expense Chart (fl_chart BarChart), Overdue Alerts, GST Summary Card |
| **States** | ✅ Loading (KpiCardSkeleton, ShimmerSkeleton), ✅ Error (ErrorView with retry), ✅ Empty (handled per card) |
| **Refreshes** | Auto-refresh every 60s + manual Refresh button + pull-to-refresh |

#### Dashboard KPI Cards

| Card | API Field | Color | Icon |
|------|-----------|-------|------|
| Receivables | `outstanding` | `danger` | `account_balance_wallet_rounded` |
| Payables | `totalExpenses` | `warning` | `shopping_cart_rounded` |
| Net Profit | `netProfit` | `success` | `trending_up_rounded` |
| Sales | `totalInvoiced` | `primary` | `receipt_long_rounded` |
| Collected | `totalCollected` | `info` | `payments_rounded` |
| GST Liability | (computed from metrics) | `accent` | `account_balance_rounded` |

#### Dashboard GST Summary

| Field | Source |
|-------|--------|
| Period | Dynamic from DateTime.now() |
| CGST | `metrics.cgstTotal` |
| SGST | `metrics.sgstTotal` |
| IGST | `metrics.igstTotal` |
| CESS | `metrics.cessTotal` |
| Total Tax | Computed |

---

### 2.2 InvoiceListScreen

| Property | Value |
|----------|-------|
| **File** | `features/sales/presentation/invoice_list_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /invoices?page=&limit=&search=&status=&contact_id=&date_from=&date_to=` |
| **Permission** | `invoice:view` |
| **Layout** | Desktop: split view (list left, detail right). Mobile: list full-screen, detail pushes |
| **Pagination** | Server-side, 25 items per page |
| **Filters** | Status filter bar (All/Draft/Posted/Sent/Partial/Paid), search by number or client |
| **Columns** | Invoice#, Client, Issue Date, Due Date, Amount, Balance Due, Status |
| **States** | ✅ Loading (TableRowSkeleton), ✅ Error (ErrorView + retry), ✅ Empty (EmptyInvoices) |
| **Actions** | Row tap → opens detail panel, New Invoice button → InvoiceFormScreen |
| **Sort** | Server-side: invoiceNumber, contactName, issueDate, dueDate, total |

#### Invoice Status Badges

| Status | Tone | Icon |
|--------|------|------|
| DRAFT | `neutral` | — |
| POSTED | `primary` | — |
| SENT | `info` | — |
| PARTIAL | `warning` | — |
| PAID | `success` | — |
| OVERDUE | `danger` | — |
| CANCELLED | `neutral` | — |

---

### 2.3 InvoiceFormScreen

| Property | Value |
|----------|-------|
| **File** | `features/sales/presentation/invoice_form_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `POST /invoices`, `PUT /invoices/{id}`, `POST /invoices/preview`, `POST /invoices/{id}/clone` |
| **Permission** | `invoice:create`, `invoice:update` |
| **Layout** | Single scroll column, constrained to 1200px width, responsive |
| **Sections** | |
| _Header Card_ | Customer autocomplete (searches name + GSTIN), Issue Date, Due Date, Reference Number |
| _Lines Card_ | Line items with Product autocomplete, HSN/SAC, Quantity, Rate, Discount %, GST Rate dropdown, per-line totals |
| _Totals Bar_ | Sticky bottom: Subtotal, Discount, CGST/SGST/IGST, Round Off, Grand Total |
| **Validation** | Client-side: required customer, at least 1 line item, positive rates/quantities |
| **Unsaved Changes** | ✅ PopScope guard |
| **Keyboard Shortcuts** | Ctrl+S / Cmd+S (Save), Alt+N (Add Line) |

---

### 2.4 InvoiceDetailScreen

| Property | Value |
|----------|-------|
| **File** | `features/sales/presentation/invoice_detail_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /invoices/{id}`, `POST /invoices/{id}/finalize`, `POST /invoices/{id}/cancel`, `POST /invoices/{id}/payment`, `POST /invoices/{id}/clone`, `POST /invoices/{id}/email`, `GET /invoices/{id}/print` |
| **Permission** | `invoice:view`, `invoice:finalize` |
| **Layout** | Uses `TransactionDetailLayout` |
| **Sections** | Action bar (Print, Finalize, Cancel, Clone, Email, Record Payment), Summary header (bill-to, dates, status), Lines table, Totals card, Notes/Terms |
| **States** | ✅ Loading (DetailSectionSkeleton), ✅ Error (ErrorView) |
| **⚠️ Broken** | Print button shows snackbar only — no PDF download |
| **⚠️ Missing** | "Record Payment" button on detail screen (API exists, no UI) |
| **⚠️ Missing** | "Email Invoice" button (API exists, no UI) |

---

### 2.5 ContactListScreen

| Property | Value |
|----------|-------|
| **File** | `features/masters/contacts/presentation/contact_list_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /masters/contacts` |
| **Permission** | `contact:view` |
| **Layout** | Uses BaseListScreen + ApexDataTable + DetailInspector split view |
| **Columns** | Name, Phone (if any), GSTIN (if any), Type (Customer/Vendor/Both), Balance, Status |
| **States** | ✅ Loading (TableRowSkeleton via ApexDataTable), ✅ Error, ✅ Empty |
| **Actions** | Create Contact, Edit (row → detail → edit button), Delete (with confirmation) |

---

### 2.6 ContactFormScreen

| Property | Value |
|----------|-------|
| **File** | `features/masters/contacts/presentation/contact_form_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `POST /masters/contacts`, `PUT /masters/contacts/{id}` |
| **Permission** | `contact:create`, `contact:update` |
| **Fields** | Name (required), Email, Phone, Contact Type (Customer/Vendor/Both) (required), GSTIN, PAN, Registration Type (Regular/Composition/Unregistered), Billing Address (street, city, state, state code, pincode, country), Shipping Address (same fields), Opening Balance, Credit Balance |
| **Unsaved Changes** | ✅ PopScope guard |
| **Keyboard Shortcuts** | Ctrl+S / Cmd+S |

---

### 2.7 ContactDetailScreen

| Property | Value |
|----------|-------|
| **File** | `features/masters/contacts/presentation/contact_detail_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /masters/contacts/{id}`, `DELETE /masters/contacts/{id}` |
| **Permission** | `contact:view`, `contact:delete` |
| **Layout** | Uses `EntityDetailPage` with sections and action menu |

---

### 2.8 ProductListScreen

| Property | Value |
|----------|-------|
| **File** | `features/masters/products/presentation/product_list_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /masters/products` |
| **Permission** | `invoice:view` |
| **Layout** | BaseListScreen + ApexDataTable + DetailInspector |
| **Columns** | Name, SKU, HSN/SAC, Sales Price, Purchase Price, GST Rate, Stock, Status |

---

### 2.9 ProductFormScreen

| Property | Value |
|----------|-------|
| **File** | `features/masters/products/presentation/product_form_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `POST /masters/products`, `PUT /masters/products/{id}` |
| **Fields** | Name (required), SKU, HSN/SAC, Product Type (Goods/Services), UOM, Sales Price, Purchase Price, GST Rate, Opening Stock, Reorder Level, Is Active |

---

### 2.10 AccountListScreen (Chart of Accounts)

| Property | Value |
|----------|-------|
| **File** | `features/masters/accounts/presentation/account_list_screen.dart` |
| **Status** | ✅ Complete |
| **API** | `GET /masters/accounts` |
| **Permission** | `accounts:manage` |
| **Layout** | Custom tree view with expand/collapse, PageHeader, search, filter chips |
| **Features** | Tree view with depth-based indentation, account type badges, expand/collapse, search, Account Group / Account filter chips, Seed Defaults button, hover states |
| **States** | ✅ Loading (Shimmer skeleton), ✅ Error, ✅ Empty (EmptyAccounts) |

---

### 2.11 AccountFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /masters/accounts`, `PUT /masters/accounts/{id}` |
| **Fields** | Name (required), Code (required), Account Type (Asset/Liability/Income/Expense/Equity), Parent Account (tree selector), Opening Balance, Is Active |

---

### 2.12 PurchaseOrderListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /purchase-orders?page=&limit=&status=` |
| **Permission** | `bill:view` |
| **Layout** | Split view with DetailInspector |
| **Filters** | Status filter (All/Draft/Confirmed/Received/Cancelled) |
| **States** | ✅ Loading, ✅ Error, ✅ Empty |
| **Sort** | Client-side: poNumber, contactName, orderDate, dueDate, total |

---

### 2.13 PurchaseOrderFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /purchase-orders`, `PUT /purchase-orders/{id}` |
| **Sections** | Header (Vendor, PO Number, Order Date, Due Date), Lines (product, qty, rate, discount, GST), Totals bar |
| **Unsaved Changes** | ✅ PopScope guard |
| **Keyboard Shortcuts** | Ctrl+S, Alt+N |

---

### 2.14 PurchaseOrderDetailScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /purchase-orders/{id}`, `POST /purchase-orders/{id}/confirm`, `POST /purchase-orders/{id}/receive`, `POST /purchase-orders/{id}/cancel`, `GET /purchase-orders/{id}/print` |
| **Layout** | Uses TransactionDetailLayout |
| **⚠️ Broken** | Print button shows snackbar only |

---

### 2.15 BillListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /bills` |
| **Permission** | `invoice:view` |
| **Layout** | Split view with DetailInspector |
| **⚠️ Missing** | BillFormScreen — **cannot create bills from UI** |
| **⚠️ Missing** | Status filter bar |

---

### 2.16 BillDetailScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete (view/post/cancel) |
| **API** | `GET /bills/{id}`, `POST /bills/{id}/finalize`, `POST /bills/{id}/cancel`, `GET /bills/{id}/print` |
| **Layout** | Uses TransactionDetailLayout |
| **Actions** | Post, Cancel, Print |
| **⚠️ Broken** | Print button shows snackbar only |

---

### 2.17 ⚠️ BillFormScreen (MISSING — CRITICAL)

| Property | Value |
|----------|-------|
| **Status** | ❌ **Missing — must be built** |
| **API** | `POST /bills`, `PUT /bills/{id}`, `POST /bills/preview`, `POST /bills/{id}/clone` |
| **Permission** | `bill:create`, `bill:update` |
| **Fields needed** | Vendor (contact autocomplete), Bill Number, Bill Date, Due Date, Reference Number, Line Items (product autocomplete, description, qty, rate, discount, GST rate), Subtotal, Discount Total, CGST/SGST/IGST, Round Off, Grand Total, Notes, TDS Rate/Amount, ITC Eligible checkbox |

---

### 2.18 GoodsReceiptListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /goods-receipts` |
| **Layout** | Split view with DetailInspector |

---

### 2.19 GoodsReceiptFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /goods-receipts` |
| **Sections** | PO selector (loads confirmed POs), Receipt Number, Receipt Date, Warehouse, Line items with received qty |

---

### 2.20 GoodsReceiptDetailScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /goods-receipts/{id}`, `POST /goods-receipts/{id}/confirm`, `POST /goods-receipts/{id}/cancel` |

---

### 2.21 VendorPaymentListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /payments/disbursements` |

---

### 2.22 VendorPaymentFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /payments/disbursements` |
| **Sections** | Vendor autocomplete, Payment Number, Payment Date, Payment Mode (Cash/Bank/UPI/POS/Other), Amount, Reference Number, Description, Outstanding Bills table with allocation |
| **Unsaved Changes** | ✅ PopScope guard |

---

### 2.23 PurchaseReturnListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /returns/purchase` |

---

### 2.24 PurchaseReturnFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /returns/purchase` |
| **Sections** | Bill selector, Return Number, Return Date, Line items with return qty, Reason |

---

### 2.25 PurchaseReturnDetailScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /returns/purchase/{id}`, `POST /returns/purchase/{id}/cancel` |

---

### 2.26 InventoryListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /products` (flat list with current_stock) |
| **Layout** | Summary bar (total products, low stock count, total valuation), toolbar (search, low-stock filter, refresh), desktop table / mobile card list |
| **Columns** | Product Name, SKU, Current Stock, Reorder Level, Stock Value |
| **Low Stock** | Warning indicator when stock ≤ reorder level |

---

### 2.27 StockMovementListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /stock-ledger?page=&limit=&product_id=&reference_type=` |
| **Columns** | Date, Product, Reference Type (Sale/Purchase/Adjustment/Transfer/Opening), Quantity, Balance, Rate |

---

### 2.28 TransferListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /transfers` |

---

### 2.29 TransferFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /transfers` |
| **Sections** | Transfer Number, Transfer Date, Source Warehouse, Destination Warehouse, Line items (product, quantity) |

---

### 2.30 TransferDetailScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /transfers/{id}`, `POST /transfers/{id}/complete`, `POST /transfers/{id}/cancel` |

---

### 2.31 AdjustmentListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /inventory-adjustments` |

---

### 2.32 AdjustmentFormScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /inventory-adjustments` |
| **Sections** | Adjustment Number, Date, Reason, Line items (product, quantity change ±, unit cost) |
| **Keyboard Shortcuts** | Ctrl+S, Alt+N |

---

### 2.33 WarehouseListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ List only |
| **API** | `GET /warehouses` |
| **⚠️ Missing** | WarehouseFormScreen, WarehouseDetailScreen |

---

### 2.34 JournalListScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ List only |
| **API** | `GET /accounting/journals?page=&limit=&source_type=` |
| **Missing** | JournalFormScreen, JournalDetailScreen |

---

### 2.35 TrialBalanceScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /accounting/trial-balance?as_of_date=` |
| **Layout** | PageHeader, search, table with debit/credit columns, unbalanced/banner indicator, sticky totals footer |
| **Columns** | Account Code, Account Name, Debit, Credit |

---

### 2.36 ⚠️ ProfitLossScreen (MISSING)

| Property | Value |
|----------|-------|
| **Status** | ❌ **Missing — must be built** |
| **Backend** | `GET /accounting/profit-loss?date_from=&date_to=` returns ProfitLossReport |
| **Model** | `features/accounting/financial_statements/models/profit_loss.dart` (exists) |
| **Service** | `FinancialStatementService.getProfitLoss()` (exists) |
| **Sections needed** | Income section (list of income accounts + totals), Expense section (list of expense accounts + totals), Net Profit/Loss line |

---

### 2.37 ⚠️ BalanceSheetScreen (MISSING)

| Property | Value |
|----------|-------|
| **Status** | ❌ **Missing — must be built** |
| **Backend** | `GET /accounting/balance-sheet?as_on_date=` returns BalanceSheetReport |
| **Model** | `features/accounting/financial_statements/models/balance_sheet.dart` (exists) |
| **Service** | `FinancialStatementService.getBalanceSheet()` (exists) |
| **Sections needed** | Assets (Current + Fixed), Liabilities (Current + Long-term), Equity, Net Profit addition, Total verification |

---

### 2.38 LoginScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **Layout** | Two-pane on desktop (brand panel + form card), centered card on mobile |
| **Fields** | Email, Password |
| **Validation** | Email format, password non-empty |
| **Actions** | Login, Forgot Password link, Register link |

---

### 2.39 RegisterScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `POST /auth/register` |
| **Layout** | Multi-step: user details → company details |
| **Fields** | Full Name, Email, Phone, Password, Confirm Password; Company Name, GSTIN, Address |
| **Features** | Password strength meter, expandable company fields |

---

### 2.40 CompanySelectionScreen

| Property | Value |
|----------|-------|
| **Status** | ✅ Complete |
| **API** | `GET /auth/memberships`, `POST /companies` |
| **Layout** | Card list of tenant memberships, or "Create Company" button if none |

---

---

## 3. Dialogs & Modals

### 3.1 DialogService

| Dialog | Method | Icon | Use Case |
|--------|--------|------|----------|
| Confirm | `DialogService().confirm()` | `help_outline_rounded` (or `warning_amber_rounded` for destructive) | Generic yes/no |
| Delete Confirmation | `DialogService().confirmDelete()` | `warning_amber_rounded` | Delete record with red confirmation |
| Unsaved Changes | `DialogService().unsavedChanges()` | `edit_note_rounded` | Form back navigation guard |
| Success | `DialogService().success()` | `check_circle_rounded` | Operation completed |
| Error | `DialogService().error()` | `error_outline_rounded` | Operation failed, optional retry |
| Progress | `DialogService().progress()` | Spinner | Long-running operation |

### 3.2 ApexDialogs (⚠️ Duplicate — compete with DialogService)

| Dialog | Use Case |
|--------|----------|
| `ApexDialogs.delete()` | Delete confirmation |
| `ApexDialogs.formError()` | Form submission error |
| `ApexDialogs.unsavedChanges()` | Unsaved changes (duplicate of DialogService) |

### 3.3 EntitySelector (shared bottom sheet)

| Property | Value |
|----------|-------|
| **File** | `core/selectors/entity_selector.dart` |
| **Purpose** | Searchable bottom-sheet for selecting from lists (contacts, products, accounts) |
| **Usage** | Invoice form (customer, product), PO form (vendor, product), Adjustment form (product), Transfer form (product), GR form (PO selector) |

---

## 4. Forms & Fields

### 4.1 Shared Form Widgets

| Widget | File | Purpose |
|--------|------|---------|
| ApexTextField | `core/forms/apex_text_field.dart` | ApexForm-compatible text field |
| ApexTextField (alternate) | `core/widgets/form_fields.dart` | Standalone TextFormField |
| ApexPasswordField | `core/widgets/form_fields.dart` | Password with visibility toggle |
| ApexSubmitButton | `core/widgets/form_fields.dart` | Themed submit button |
| ApexDropdownField | `core/forms/dropdown_date_fields.dart` | Dropdown with items |
| ApexDateField | `core/forms/dropdown_date_fields.dart` | Date picker |
| ApexGSTField | `core/forms/gst_percentage_fields.dart` | GSTIN input with validation |
| ApexPercentageField | `core/forms/gst_percentage_fields.dart` | Percentage input |
| ApexMoneyField | `core/forms/money_field.dart` | Currency input with ₹ prefix |

### 4.2 Form Validation Patterns

| Validation | File | Function |
|-----------|------|----------|
| Email | `core/utils/formatters.dart` | `emailValidator()` |
| Password | `core/utils/formatters.dart` | `passwordValidator()` |
| GSTIN | `core/utils/formatters.dart` | `gstinValidator()` |
| PAN | `core/utils/formatters.dart` | `panValidator()` |
| Phone | `core/utils/formatters.dart` | `phoneValidator()` |
| Decimal parse | `core/utils/formatters.dart` | `parseDecimal()` (safe: handles int/double/String/null) |
| Double safe parse | `core/utils/formatters.dart` | `parseDoubleSafe()` |
| Int safe parse | `core/utils/formatters.dart` | `parseIntSafe()` |

---

## 5. Reports

### 5.1 Implemented Reports

| Report | API Endpoint | Backend | Frontend | PDF | Excel | Status |
|--------|-------------|---------|----------|-----|-------|--------|
| Trial Balance | `GET /accounting/trial-balance` | ✅ | ✅ TrialBalanceScreen | ❌ | ❌ | **Complete** (screen OK, export missing) |
| Dashboard KPIs | `GET /dashboard/kpis` | ✅ | ✅ DashboardScreen | ❌ | ❌ | **Complete** |
| Dashboard Metrics | `GET /dashboard/metrics` | ✅ | ✅ | ❌ | ❌ | **Complete** |
| Revenue Trend | `GET /dashboard/revenue-trend` | ✅ | ✅ Chart | ❌ | ❌ | **Complete** |
| Overdue Alerts | `GET /dashboard/overdue-alerts` | ✅ | ✅ | ❌ | ❌ | **Complete** |

### 5.2 Backend-Ready Reports (MISSING Frontend)

| Report | API Endpoint | Backend | Frontend | PDF | Excel | Priority |
|--------|-------------|---------|----------|-----|-------|----------|
| Profit & Loss | `GET /accounting/profit-loss` | ✅ | ❌ | ✅ | ✅ | **P1 — Critical** |
| Balance Sheet | `GET /accounting/balance-sheet` | ✅ | ❌ | ✅ | ✅ | **P1 — Critical** |
| Cash Flow | `GET /reports/cash-flow` | ✅ | ❌ | ✅ | ✅ | P2 |
| AR Aging | `GET /reports/aging/receivables` | ✅ | ❌ | ✅ | ✅ | P2 |
| AP Aging | `GET /reports/aging/payables` | ✅ | ❌ | ✅ | ✅ | P2 |
| GSTR-1 | `GET /reports/gst/gstr1` | ✅ | ❌ | ✅ | ✅ | **P1 — Critical** |
| GSTR-3B | `GET /reports/gst/gstr3b` | ✅ | ❌ | ✅ | ✅ | **P1 — Critical** |
| GSTR-2 | `GET /reports/gst/gstr2` | ✅ | ❌ | ✅ | ✅ | P2 |
| Outstanding AR | `GET /reports/outstanding/receivables` | ✅ | ❌ | ✅ | ✅ | P2 |
| Outstanding AP | `GET /reports/outstanding/payables` | ✅ | ❌ | ✅ | ✅ | P2 |
| Party Statement | `GET /reports/party-statement` | ✅ | ❌ | ✅ | ✅ | P2 |
| Cash Book | `GET /reports/cash-book` | ✅ | ❌ | ✅ | ✅ | P2 |
| Day Book | `GET /reports/day-book` | ✅ | ❌ | ✅ | ✅ | P2 |
| Stock Register | `GET /reports/stock-register` | ✅ | ❌ | ✅ | ✅ | P2 |
| TDS Report | `GET /reports/tds` | ✅ | ❌ | ✅ | ✅ | P2 |
| TCS Report | `GET /reports/tcs` | ✅ | ❌ | ✅ | ✅ | P2 |
| Sales Analytics | `GET /reports/analytics/sales` | ✅ | ❌ | ❌ | ❌ | P3 |
| Purchase Analytics | `GET /reports/analytics/purchases` | ✅ | ❌ | ❌ | ❌ | P3 |
| Consolidated BS | `GET /reports/balance-sheet` | ✅ | ❌ | ✅ | ✅ | P2 (reports router has richer results) |

---

## 6. Settings Pages

### 6.1 Current Settings (Incomplete)

| Page | Backend | Frontend | Status |
|------|---------|----------|--------|
| Tax Templates (list) | `GET /masters/tax-templates` | ✅ TaxTemplateListScreen (read-only) | Complete |
| Payment Terms (list) | `GET /masters/payment-terms` | ✅ PaymentTermListScreen (read-only) | Complete |
| Expense Categories | `POST/GET/PUT/DELETE /masters/expense-categories` | ✅ ExpenseCategoryListScreen + FormScreen | Complete |

### 6.2 Missing Settings Pages

| Page | Backend API | Priority |
|------|-----------|----------|
| Company Profile | `GET/PUT /companies/{id}`, `PUT /settings` | P1 |
| Financial Year | `GET/POST /financial-years`, `/switch`, `/current` | P1 |
| Numbering Series | `GET/POST/PUT /settings/series` | P1 |
| GST Configuration | `POST /companies/{id}/gst-toggle`, `PUT /settings` | P1 |
| Team & Roles | `GET/POST/PUT/DELETE /companies/{id}/members`, `/invite` | P1 |
| Branches | `GET/POST/PUT/DELETE /companies/{id}/branches` | P1 |
| Period Lock | `GET/POST /accounting/periods/lock`, `/unlock` | P1 |
| Opening Balances | `POST /accounting/opening-balances` | P1 |
| Backup & Restore | `GET /companies/{id}/export`, `POST /companies/{id}/import` | P2 |
| Bank Accounts | `POST/GET/PUT/DELETE /masters/banking-profiles` | Already has list/form screens |
| Email Configuration | ❌ No backend endpoint | P3 |
| SMS Configuration | ❌ No backend endpoint | P3 |
| Invoice Settings | ❌ No backend endpoint | P3 |
| Printing Settings | ❌ No backend endpoint | P3 |
| Feature Flags | ❌ No backend endpoint | P3 |
| Audit Logs | `GET /audit-logs` (backend exists, no screen) | P2 |
| Data Import | `POST /import/vyapar`, `/tally/import` | P2 |
| Data Export | `GET /tally/export` | P2 |
| Danger Zone (Purge) | `POST /purge/request`, `/purge/verify` | P2 |

---

## 7. Print Templates

### 7.1 Current Print Status

| Document | Backend | Frontend Button | Actual Print | Status |
|----------|---------|-----------------|--------------|--------|
| Invoice PDF | `GET /invoices/{id}/print` | ✅ Print button | ❌ Shows snackbar only | **Broken** |
| Bill PDF | `GET /bills/{id}/print` | ✅ Print button | ❌ Shows snackbar only | **Broken** |
| PO PDF | `GET /purchase-orders/{id}/print` | ✅ Print button | ❌ Shows snackbar only | **Broken** |
| Party Statement PDF | Imported from reports service | ❌ No UI | ❌ | Missing |
| Balance Sheet PDF | `GET /reports/balance-sheet/pdf` | ❌ No UI | ❌ | Missing |
| P&L PDF | `GET /reports/profit-loss/pdf` | ❌ No UI | ❌ | Missing |
| Trial Balance PDF | `GET /reports/trial-balance/pdf` | ❌ No UI | ❌ | Missing |
| Cash Flow PDF | `GET /reports/cash-flow/pdf` | ❌ No UI | ❌ | Missing |
| Aging PDF | `GET /reports/aging/{type}/pdf` | ❌ No UI | ❌ | Missing |
| Day Book PDF | `GET /reports/day-book/pdf` | ❌ No UI | ❌ | Missing |
| Credit Note PDF | `GET /invoices/credit-notes/{id}/print` | ❌ No UI | ❌ | Missing |
| Debit Note PDF | `GET /invoices/debit-notes/{id}/print` | ❌ No UI | ❌ | Missing |

### 7.2 DownloadService

| Property | Value |
|----------|-------|
| **File** | `core/download/download_service.dart` |
| **Capabilities** | PDF, Excel, CSV, JSON downloads. File save dialog. Platform-aware. |
| **Status** | ✅ Infrastructure exists, **never called** from any screen |

---

## 8. API Endpoint Mapping

### 8.1 Complete Endpoint-to-Screen Matrix

| # | Endpoint | Method | Frontend Screen | Status |
|---|----------|--------|-----------------|--------|
| **AUTH** | | | | |
| A01 | `/auth/register` | POST | RegisterScreen | ✅ |
| A02 | `/auth/login` | POST | LoginScreen | ✅ |
| A03 | `/auth/refresh` | POST | (internal) | ✅ |
| A04 | `/auth/logout` | POST | LoginScreen | ✅ |
| A05 | `/auth/me` | GET | AuthController | ✅ |
| A06 | `/auth/memberships` | GET | CompanySelectionScreen | ✅ |
| A07 | `/auth/change-password` | POST | — | ❌ |
| A08 | `/auth/forgot-password` | POST | ForgotPasswordScreen | ✅ |
| A09 | `/auth/reset-password` | POST | ResetPasswordScreen | ✅ |
| A10 | `/auth/verify-email` | POST | — | ❌ |
| A11 | `/auth/2fa/enable` | POST | — | ❌ |
| A12 | `/auth/2fa/verify` | POST | — | ❌ |
| A13 | `/auth/2fa/disable` | POST | — | ❌ |
| A14 | `/auth/2fa/challenge` | POST | — | ❌ |
| **INVOICES** | | | | |
| I01 | `/invoices` | POST | InvoiceFormScreen | ✅ |
| I02 | `/invoices/stats` | GET | InvoiceListScreen | ✅ |
| I03 | `/invoices` | GET | InvoiceListScreen | ✅ |
| I04 | `/invoices/preview` | POST | InvoiceFormScreen | ✅ |
| I05 | `/invoices/bulk-delete` | POST | InvoiceListScreen | ✅ |
| I06 | `/invoices/{id}` | GET | InvoiceDetailScreen | ✅ |
| I07 | `/invoices/{id}` | PUT | InvoiceFormScreen | ✅ |
| I08 | `/invoices/{id}` | DELETE | InvoiceDetailScreen | ✅ |
| I09 | `/invoices/{id}/finalize` | POST | InvoiceDetailScreen | ✅ |
| I10 | `/invoices/{id}/cancel` | POST | InvoiceDetailScreen | ✅ |
| I11 | `/invoices/{id}/payment` | POST | — | ⚠️ (no UI button) |
| I12 | `/invoices/{id}/print` | GET | InvoiceDetailScreen | ⚠️ (broken) |
| I13 | `/invoices/{id}/clone` | POST | InvoiceFormScreen | ✅ |
| I14 | `/invoices/{id}/email` | POST | — | ❌ |
| I15 | `/invoices/{id}/e-invoice` | POST | — | ❌ |
| I16 | `/invoices/{id}/e-invoice/cancel` | POST | — | ❌ |
| **CREDIT NOTES** | | | All missing | ❌ |
| **DEBIT NOTES** | | | All missing | ❌ |
| **BILLS** | | | | |
| B01 | `/bills` | POST | — | ❌ (no form) |
| B02 | `/bills/preview` | POST | — | ❌ |
| B03 | `/bills` | GET | BillListScreen | ✅ |
| B04 | `/bills/bulk-delete` | POST | BillListScreen | ✅ |
| B05 | `/bills/{id}` | GET | BillDetailScreen | ✅ |
| B06 | `/bills/{id}` | PUT | — | ❌ |
| B07 | `/bills/{id}/finalize` | POST | BillDetailScreen | ✅ |
| B08 | `/bills/{id}/cancel` | POST | BillDetailScreen | ✅ |
| B09 | `/bills/{id}/payment` | POST | VendorPaymentFormScreen | ✅ |
| B10 | `/bills/{id}` | DELETE | BillDetailScreen | ⚠️ |
| B11 | `/bills/{id}/print` | GET | BillDetailScreen | ⚠️ (broken) |
| B12 | `/bills/{id}/clone` | POST | — | ❌ |
| **PAYMENTS** | | | | |
| P01 | `/payments/receipts` | POST | PaymentFormScreen | ✅ |
| P02 | `/payments/receipts` | GET | — | ❌ (no list) |
| P03 | `/payments/receipts/{id}` | GET | — | ❌ |
| P04 | `/payments/receipts/{id}/cancel` | POST | — | ❌ |
| P05 | `/payments/disbursements` | POST | VendorPaymentFormScreen | ✅ |
| P06 | `/payments/disbursements` | GET | VendorPaymentListScreen | ✅ |
| P07 | `/payments/disbursements/{id}` | GET | — | ❌ |
| P08 | `/payments/disbursements/{id}/cancel` | POST | — | ❌ |
| **MASTER DATA** | | | | |
| M01-M38 | Full CRUD contacts/products/accounts/banking/expense/tax/terms | All | All list/form/detail screens | ✅ |
| **COMPANY** | | | | |
| C01-C22 | All company/branch/settings/series/invite/export/import/purge | All | — | ❌ |
| **ACCOUNTING** | | | | |
| A01-A12 | All journal/ledger/trial/BS/P&L/period/opening | All | TrialBalanceScreen only | ⚠️ |
| **All others** | | | | |
| EXPENSES | All | All | — | ❌ |
| RETURNS (sales) | All | All | — | ❌ |
| SALES ORDERS | All | All | — | ❌ |
| PROFORMA INV | All | All | — | ❌ |
| DELIVERY CHALLANS| All | All | — | ❌ |
| RECURRING INV | All | All | — | ❌ |
| E-WAY BILLS | All | All | — | ❌ |
| REPORTS | 30+ | All | — | ❌ |
| GST | 12+ | All | — | ❌ |
| BANK REC | 14+ | All | — | ❌ |
| FINANCIAL YEARS | 10+ | All | — | ❌ |
| AUDIT LOGS | 1 | All | — | ❌ |
| REMINDERS | 2 | All | — | ❌ |
| TALLY/VYAPAR | 3 | All | — | ❌ |

### 8.2 Summary

| Category | Total | Complete | Partial | Missing |
|----------|-------|----------|---------|---------|
| Auth | 14 | 8 | 0 | 6 |
| Invoices | 16 | 8 | 2 | 6 |
| Credit/Debit Notes | 16 | 0 | 0 | 16 |
| Bills | 12 | 3 | 3 | 6 |
| Payments | 8 | 3 | 0 | 5 |
| Master Data | 38 | 38 | 0 | 0 |
| Company/Settings | 22 | 0 | 0 | 22 |
| Accounting | 12 | 1 | 0 | 11 |
| Expenses | 10 | 0 | 0 | 10 |
| Returns | 8 | 4 | 0 | 4 |
| Purchase Orders | 8 | 8 | 0 | 0 |
| Sales Orders | 8 | 0 | 0 | 8 |
| Delivery Challans | 6 | 0 | 0 | 6 |
| Proforma Invoices | 10 | 0 | 0 | 10 |
| Recurring Invoices | 6 | 0 | 0 | 6 |
| Inventory Adjustments | 6 | 6 | 0 | 0 |
| Warehouses | 5 | 1 | 1 | 3 |
| Stock Ledger | 2 | 1 | 1 | 0 |
| Transfers | 6 | 6 | 0 | 0 |
| Reports | 30+ | 0 | 0 | 30+ |
| GST | 12+ | 0 | 0 | 12+ |
| Bank Reconciliation | 14+ | 0 | 0 | 14+ |
| Financial Years | 10+ | 0 | 0 | 10+ |
| Audit/Reminders | 4 | 0 | 0 | 4 |
| **Total** | ~250+ | **87** | **7** | **~155+** |

---

## 9. Permissions Matrix

### 9.1 Permission Codes

| Code | Scope |
|------|-------|
| `tenant:view` | View company profile |
| `tenant:update` | Update company profile |
| `settings:view` | View settings |
| `settings:update` | Update settings |
| `contact:create` | Create contacts |
| `contact:view` | View contacts |
| `contact:update` | Update contacts |
| `contact:delete` | Delete contacts |
| `invoice:create` | Create invoices |
| `invoice:view` | View invoices |
| `invoice:update` | Update invoices |
| `invoice:finalize` | Finalize/post invoices |
| `invoice:delete` | Delete invoices |
| `payment:create` | Create payments |
| `payment:view` | View payments |
| `payment:delete` | Delete payments |
| `payment:cancel` | Cancel payments |
| `ledger:view` | View ledger/reports |
| `ledger:manual_post` | Post manual journal entries |
| `accounts:manage` | Manage chart of accounts |
| `gst:report_view` | View GST reports |
| `gst:filing_manage` | File/manage GST returns |
| `credit_note:create` | Create credit notes |
| `credit_note:view` | View credit notes |
| `debit_note:create` | Create debit notes |
| `debit_note:view` | View debit notes |
| `audit:view` | View audit logs |
| `reports:view` | View reports |
| `expense:create` | Create expenses |
| `expense:view` | View expenses |
| `expense:edit` | Edit expenses |
| `expense:delete` | Delete expenses |
| `expense:finalize` | Finalize/post expenses |
| `bill:create` | Create bills |
| `bill:view` | View bills |
| `bill:update` | Update bills |
| `data:import` | Import data (⚠️ missing from frontend) |

### 9.2 Role Permissions

| Role | Permissions |
|------|------------|
| **OWNER** | Full access — all permissions |
| **ACCOUNTANT** | All except `contact:delete`, `invoice:create`, `invoice:update`, `invoice:delete`, `expense:edit`, `expense:delete` |
| **SALESPERSON** | `contact:create`, `contact:view`, `contact:update`, `invoice:create`, `invoice:view`, `invoice:update`, `payment:create`, `payment:view` |
| **AUDITOR** | Read-only: `tenant:view`, `settings:view`, `contact:view`, `invoice:view`, `payment:view`, `ledger:view`, `gst:report_view`, `credit_note:view`, `debit_note:view`, `audit:view`, `reports:view`, `bill:view`, `expense:view` |

### 9.3 PermissionGate Usage

| Screen | Gate Used? | Status |
|--------|-----------|--------|
| ContactFormScreen | ✅ | Complete |
| BankingProfileFormScreen | ✅ | Complete |
| ProductFormScreen | ✅ | Complete |
| ExpenseCategoryFormScreen | ✅ | Complete |
| AccountListScreen | ✅ | Complete |
| AccountFormScreen | ✅ | Complete |
| InvoiceListScreen | ❌ | Missing |
| InvoiceFormScreen | ❌ | Missing |
| InvoiceDetailScreen | ❌ | Missing |
| BillListScreen | ❌ | Missing |
| Purchase screens | ❌ | Missing |
| Inventory screens | ❌ | Missing |
| Navigation sidebar | ❌ | Missing (salesperson sees all) |

---

## 10. Keyboard Shortcuts

### 10.1 Currently Implemented

| Shortcut | Action | Scope |
|----------|--------|-------|
| Ctrl+S / Cmd+S | Save current form | Invoice, PO, GR, PR, VP, Adjustment, Contact, Product, Account, Expense Category forms |
| Alt+N | Add new line item | Invoice, PO, Adjustment forms |
| Ctrl+K / Cmd+K | Open command palette | Global |
| Escape | Close command palette / detail panel | Global |
| Tab / Shift+Tab | Navigate form fields | All forms |

### 10.2 Planned Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+N | New invoice (from any screen) |
| Ctrl+P | Open command palette / quick search |
| F2 | Rename / edit selected item |
| F5 | Refresh current list |
| Delete | Delete selected item (with confirmation) |
| Alt+← | Go back / navigate up |
| Alt+→ | Go forward / navigate down |
| Ctrl+D | Duplicate selected line item |
| Ctrl+F | Focus search bar |

---

## 11. Workflows

### 11.1 Sales Workflow (Current)

```
Contact (exists) 
  → ❌ Quotation (MISSING)
    → ❌ Sales Order (MISSING)
      → ❌ Delivery Challan (MISSING)
        → Invoice (COMPLETE)
          → ⚠️ Record Payment (no UI button, API exists)
            → ✅ Dashboard (KPI updates)
```

**Flow completion: 45%**

### 11.2 Purchase Workflow (Current)

```
Vendor/Contact (exists)
  → Purchase Order (COMPLETE)
    → Goods Receipt (COMPLETE)
      → ❌ Bill (MISSING — no form screen)
        → Vendor Payment (COMPLETE)
          → Purchase Return (COMPLETE)
```

**Flow completion: 60%** (Critical blocker: Bill form missing)

### 11.3 Inventory Workflow (Current)

```
Product (exists)
  → Stock List (COMPLETE)
  → Stock Adjustment (COMPLETE)
  → Stock Transfer (COMPLETE)
  → Warehouse (COMPLETE — list only)
  → Stock Ledger (COMPLETE)
```

**Flow completion: 75%**

### 11.4 Accounting Workflow (Current)

```
COA (exists)
  → ⚠️ Manual JE (list only, no form)
    → Trial Balance (COMPLETE)
      → ❌ P&L (MISSING)
        → ❌ Balance Sheet (MISSING)
          → ❌ Cash Flow (MISSING)
            → ❌ Bank Reconciliation (MISSING)
```

**Flow completion: 20%**

### 11.5 GST Workflow (Current)

```
❌ GSTR-1 (MISSING)
❌ GSTR-3B (MISSING)
❌ E-Invoice (MISSING)
❌ E-Way Bill (MISSING)
❌ ITC Tracking (MISSING)
```

**Flow completion: 0%**

---

## 12. Implementation Status

### 12.1 Module Scores

| Module | Score | Status |
|--------|-------|--------|
| Dashboard | 85% | ✅ Production-ready |
| Inventory | 75% | ✅ Functional |
| Sales (Invoices) | 65% | ⚠️ Core works, pre/post missing |
| Purchases (excl. Bill) | 60% | ⚠️ PO/GR/Returns work, Bill form critical |
| Auth | 90% | ✅ Production-ready |
| Linux Desktop | 70% | ✅ Solid foundation |
| Mobile | 45% | ⚠️ Desktop-first, usable |
| Security (backend) | 85% | ✅ Strong |
| Security (frontend) | 25% | ❌ PermissionGate missing on most screens |
| **Purchases (Bill form)** | **0%** | ❌ **CRITICAL BLOCKER** |
| **Accounting screens** | **20%** | ❌ Most missing |
| **GST screens** | **0%** | ❌ **CRITICAL BLOCKER** |
| **Reports screens** | **0%** | ❌ **CRITICAL BLOCKER** |
| **Settings screens** | **10%** | ❌ Critical blocker |
| **Printing** | **0%** | ❌ **CRITICAL BLOCKER** |
| **Barcode** | **0%** | ❌ Not started |
| **Full Production** | **~25%** | ❌ Not ready |

### 12.2 Overall Production Readiness

| Aspect | Readiness |
|--------|-----------|
| Backend API completeness | ~85% |
| Frontend screen completeness | ~25% |
| Workflow completeness | ~40% |
| UX/DX quality | ~60% |
| Printing/Reports | ~5% |
| Mobile experience | ~45% |
| **Overall** | **~25%** |

### 12.3 Summary of Blocks

A real business **cannot** use ApexBooks today because:
1. **Cannot create vendor bills** — breaks purchase-to-pay cycle
2. **Cannot see Profit & Loss or Balance Sheet** — cannot file taxes
3. **Cannot view any GST return** — defeats the primary purpose of an Indian accounting app
4. **Cannot print any document** — no PDF download works
5. **Cannot configure company settings** — no company profile, financial year, or series management
6. **Cannot view any report** — 30+ reports available on backend, zero on frontend
7. **Cannot manage bank reconciliation** — full backend exists, no UI

---

## Appendix: Key Files Reference

| Component | File |
|-----------|------|
| Root entry | `frontend/lib/main.dart` |
| App widget | `frontend/lib/app/apex_app.dart` |
| Router | `frontend/lib/core/routing/router.dart` |
| Theme | `frontend/lib/core/theme/app_theme.dart` |
| Colors | `frontend/lib/core/theme/app_colors.dart` |
| Responsive | `frontend/lib/core/theme/responsive.dart` |
| Navigation shell | `frontend/lib/features/home/home_shell.dart` |
| Navigation widgets | `frontend/lib/features/home/home_shell_widgets.dart` |
| Screen barrel | `frontend/lib/features/screens.dart` |
| API client | `frontend/lib/core/network/api_client.dart` |
| Interceptors | `frontend/lib/core/network/interceptors.dart` |
| Token state | `frontend/lib/core/network/auth_token_state.dart` |
| Dio extensions | `frontend/lib/core/network/dio_extensions.dart` |
| Error mapper | `frontend/lib/core/network/error_mapper.dart` |
| Result type | `frontend/lib/core/result/result.dart` |
| Base model | `frontend/lib/core/api/base_model.dart` |
| Base repo | `frontend/lib/core/api/base_repository.dart` |
| Base CRUD | `frontend/lib/core/crud/base_crud.dart` |
| Session storage | `frontend/lib/core/storage/session_storage.dart` |
| Permissions | `frontend/lib/core/permissions/permissions.dart` |
| Permission gate | `frontend/lib/core/permissions/permission_gate.dart` |
| Feature flags | `frontend/lib/core/config/feature_flags.dart` |
| Data table | `frontend/lib/core/tables/apex_data_table.dart` |
| Table body | `frontend/lib/core/tables/table_body.dart` |
| Table toolbar | `frontend/lib/core/tables/table_toolbar.dart` |
| Pagination | `frontend/lib/core/tables/table_pagination.dart` |
| Controller | `frontend/lib/core/tables/table_controller.dart` |
| Page header | `frontend/lib/core/widgets/page_header.dart` |
| Status badge | `frontend/lib/core/widgets/status_badge.dart` |
| States | `frontend/lib/core/widgets/states.dart` |
| Skeleton loader | `frontend/lib/core/widgets/skeleton_loader.dart` |
| Empty states | `frontend/lib/core/widgets/empty_states.dart` |
| Detail layout | `frontend/lib/core/widgets/transaction_detail_layout.dart` |
| Entity detail | `frontend/lib/core/widgets/entity_detail_page.dart` |
| Detail inspector | `frontend/lib/core/widgets/detail_inspector.dart` |
| Dialog service | `frontend/lib/core/dialogs/dialog_service.dart` |
| Apex dialogs | `frontend/lib/core/dialogs/apex_dialogs.dart` |
| Download service | `frontend/lib/core/download/download_service.dart` |
| Command palette | `frontend/lib/core/search/command_palette.dart` |
| Number formatting | `frontend/lib/core/formatting/number_formatting.dart` |
| Validators | `frontend/lib/core/utils/formatters.dart` |
| Monetary text | `frontend/lib/core/widgets/monetary_text.dart` |
| Search bar | `frontend/lib/core/widgets/search_bar.dart` |
| Backend main | `backend/src/main.py` |
| Backend config | `backend/src/core/config.py` |
| Backend security | `backend/src/core/security.py` |
| Backend deps | `backend/src/api/deps.py` |
| Backend permissions | `backend/src/core/security.py` |
| Auth routes | `backend/src/api/v1/auth.py` |
| Invoice routes | `backend/src/api/v1/invoices.py` |
| Bill routes | `backend/src/api/v1/bills.py` |
| All others | `backend/src/api/v1/` |
| DB models | `backend/src/infrastructure/database/models.py` |
| Accounting engine | `backend/src/domains/accounting/services.py` |
| Auto posting | `backend/src/domains/accounting/auto_post.py` |
| GST engine | `backend/src/domains/taxation/services.py` |
| Report services | `backend/src/domains/accounting/report_services.py` |
| PDF generation | `backend/src/domains/printing/invoice_pdf.py` |
| Celery tasks | `backend/src/workers/tasks.py` |
| Docker compose | `docker-compose.yml` |
| Host nginx | `nginx.conf` |
