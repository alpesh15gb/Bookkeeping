# ApexBooks — API Endpoint Catalog
> Base URL: `https://api.apexbooks.in/api/v1`  
> All endpoints (unless noted) require: `Authorization: Bearer <access_token>` + `X-Tenant-ID: <tenant_uuid>`

---

## Authentication (`/auth`)

| Method | URL | Purpose | Auth | Permission | Rate Limit |
|--------|-----|---------|------|-----------|------------|
| POST | `/auth/register` | Register new user + company | None | — | 5/min |
| POST | `/auth/login` | Login; returns access + refresh token | None | — | 10/min |
| POST | `/auth/refresh` | Exchange refresh token for new pair | None | — | 30/min |
| POST | `/auth/logout` | Revoke refresh token | Bearer | — | — |
| GET  | `/auth/me` | Get current user profile | Bearer | — | — |
| GET  | `/auth/memberships` | List all tenant memberships for current user | Bearer | — | — |
| POST | `/auth/change-password` | Change own password | Bearer | — | 5/min |
| POST | `/auth/forgot-password` | Send reset email | None | — | 3/min |
| POST | `/auth/reset-password` | Reset password with token | None | — | 5/min |
| POST | `/auth/verify-email` | Mark email as verified | None | — | 5/min |
| POST | `/auth/2fa/enable` | Generate TOTP secret + QR code | Bearer | — | 3/min |
| POST | `/auth/2fa/verify` | Confirm TOTP and enable 2FA | Bearer | — | 5/min |
| POST | `/auth/2fa/disable` | Disable 2FA | Bearer | — | 3/min |

---

## Company & Settings (`/companies`, `/settings`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/companies` | Create additional tenant/company | `tenant:update` |
| GET  | `/companies/{id}` | Get company details | `tenant:view` |
| PUT  | `/companies/{id}` | Update company info | `tenant:update` |
| POST | `/companies/{id}/gst-toggle` | Enable/disable GST and set tax mode | `settings:update` |
| GET  | `/companies/{id}/branches` | List branches/warehouses | `tenant:view` |
| POST | `/companies/{id}/branches` | Create a branch | `tenant:update` |
| PUT  | `/companies/{id}/branches/{branch_id}` | Update a branch | `tenant:update` |
| DELETE | `/companies/{id}/branches/{branch_id}` | Soft-delete a branch | `tenant:update` |
| POST | `/settings/logo` | Upload company logo (PNG/JPG/GIF/WEBP, ≤5MB) | `settings:update` |
| GET  | `/settings` | Get tenant settings | `settings:view` |
| PUT  | `/settings` | Update tenant settings | `settings:update` |
| GET  | `/settings/series` | List numbering series | `settings:view` |
| POST | `/settings/series` | Create numbering series | `settings:update` |
| PUT  | `/settings/series/{series_id}` | Update numbering series | `settings:update` |
| POST | `/purge/request` | Request OTP to purge all company data | Owner only |
| POST | `/purge/verify` | Execute company data purge with OTP | Owner only |
| GET  | `/companies/{tenant_id}/export` | Export all tenant data as JSON | `tenant:update` |
| POST | `/companies/{tenant_id}/import` | Import tenant data from JSON backup | `tenant:update` |

---

## Master Data (`/masters`)

### Contacts
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/masters/contacts` | Create contact (customer/vendor) | `contact:create` |
| GET  | `/masters/contacts` | List contacts (page, limit, search, contact_type) | `contact:view` |
| GET  | `/masters/contacts/{id}` | Get single contact | `contact:view` |
| PUT  | `/masters/contacts/{id}` | Update contact | `contact:update` |
| DELETE | `/masters/contacts/{id}` | Soft-delete contact | `contact:delete` |

**Alias routes (frontend-friendly):**  
`GET /contacts` — same as `/masters/contacts` (page, limit)  
`GET /products` — same as `/masters/products` (page, limit)

### Products & Services
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/masters/products` | Create product/service | `invoice:create` |
| GET  | `/masters/products` | List products (page, limit, search, product_type) | `invoice:view` |
| GET  | `/masters/products/{id}` | Get single product | `invoice:view` |
| PUT  | `/masters/products/{id}` | Update product | `invoice:create` |
| DELETE | `/masters/products/{id}` | Soft-delete product | `invoice:create` |

### Chart of Accounts
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/masters/accounts` | Create account | `accounts:manage` |
| GET  | `/masters/accounts` | List accounts (page, limit) | `ledger:view` |
| POST | `/masters/accounts/seed-defaults` | Seed default chart of accounts | `accounts:manage` |
| POST | `/masters/accounts/dedupe-contact-accounts` | Merge duplicate AR/AP accounts | `accounts:manage` |
| GET  | `/masters/accounts/{id}` | Get account | `ledger:view` |
| PUT  | `/masters/accounts/{id}` | Update account | `accounts:manage` |
| DELETE | `/masters/accounts/{id}` | Delete account | `accounts:manage` |

### Banking Profiles
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/masters/banking-profiles` | Create bank account | `settings:update` |
| GET  | `/masters/banking-profiles` | List bank accounts | `settings:view` |
| GET  | `/masters/banking-profiles/{id}` | Get bank account | `settings:view` |
| PUT  | `/masters/banking-profiles/{id}` | Update bank account | `settings:update` |
| DELETE | `/masters/banking-profiles/{id}` | Delete bank account | `settings:update` |

### Expense Categories
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/masters/expense-categories` | Create expense category | `expense:create` |
| GET  | `/masters/expense-categories` | List categories | `expense:view` |
| GET  | `/masters/expense-categories/{id}` | Get category | `expense:view` |
| PUT  | `/masters/expense-categories/{id}` | Update category | `expense:edit` |
| DELETE | `/masters/expense-categories/{id}` | Delete category | `expense:delete` |

### Tax & Payment Terms
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| GET | `/masters/tax-templates` | List GST rate templates | `invoice:view` |
| GET | `/masters/payment-terms` | List payment terms | `invoice:view` |

---

## Sales Invoices (`/invoices`)

| Method | URL | Purpose | Permission | Notes |
|--------|-----|---------|-----------|-------|
| POST | `/invoices` | Create invoice (DRAFT) | `invoice:create` | Validates period open |
| POST | `/invoices/preview` | Preview invoice totals (no save) | `invoice:view` | — |
| GET  | `/invoices/stats` | Invoice aggregate stats | `invoice:view` | — |
| GET  | `/invoices` | List invoices | `invoice:view` | page, limit, search, status, contact_id, date_from, date_to |
| POST | `/invoices/bulk-delete` | Bulk delete DRAFT invoices | `invoice:delete` | Body: `{ids: [uuid]}` |
| GET  | `/invoices/{id}` | Get invoice | `invoice:view` | — |
| PUT  | `/invoices/{id}` | Update DRAFT invoice | `invoice:update` | — |
| POST | `/invoices/{id}/finalize` | Post invoice (DRAFT→POSTED) | `invoice:finalize` | Creates ledger entry |
| POST | `/invoices/{id}/payment` | Record partial/full payment | `payment:create` | — |
| POST | `/invoices/{id}/cancel` | Cancel POSTED invoice | `invoice:finalize` | Creates reversal journal |
| DELETE | `/invoices/{id}` | Delete DRAFT invoice | `invoice:delete` | — |
| GET  | `/invoices/{id}/pdf-payload` | Get all data for PDF render | `invoice:view` | — |
| GET  | `/invoices/{id}/print` | Stream PDF bytes | `invoice:view` | Content-Type: application/pdf |
| POST | `/invoices/{id}/e-invoice` | Generate IRN on NIC IRP | `invoice:finalize` | — |
| POST | `/invoices/{id}/e-invoice/cancel` | Cancel IRN on NIC IRP | `invoice:finalize` | — |
| POST | `/invoices/{id}/clone` | Clone to new DRAFT | `invoice:create` | — |
| POST | `/invoices/{id}/email` | Queue email to customer | `invoice:view` | Body: `{recipient_email}` optional |

### Credit Notes (`/invoices/credit-notes`)
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/invoices/credit-notes` | Create credit note (DRAFT) | `credit_note:create` |
| POST | `/invoices/credit-notes/preview` | Preview credit note | `credit_note:view` |
| GET  | `/invoices/credit-notes` | List credit notes | `credit_note:view` |
| GET  | `/invoices/credit-notes/{id}` | Get credit note | `credit_note:view` |
| POST | `/invoices/credit-notes/{id}/finalize` | Post credit note | `credit_note:create` |
| POST | `/invoices/credit-notes/{id}/cancel` | Cancel credit note | `credit_note:create` |
| DELETE | `/invoices/credit-notes/{id}` | Delete DRAFT credit note | `credit_note:create` |
| GET  | `/invoices/credit-notes/{id}/print` | Stream PDF | `credit_note:view` |

### Debit Notes (`/invoices/debit-notes`)
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/invoices/debit-notes` | Create debit note (DRAFT) | `debit_note:create` |
| POST | `/invoices/debit-notes/preview` | Preview debit note | `debit_note:view` |
| GET  | `/invoices/debit-notes` | List debit notes | `debit_note:view` |
| GET  | `/invoices/debit-notes/{id}` | Get debit note | `debit_note:view` |
| POST | `/invoices/debit-notes/{id}/finalize` | Post debit note | `debit_note:create` |
| POST | `/invoices/debit-notes/{id}/cancel` | Cancel debit note | `debit_note:create` |
| DELETE | `/invoices/debit-notes/{id}` | Delete DRAFT debit note | `debit_note:create` |
| GET  | `/invoices/debit-notes/{id}/print` | Stream PDF | `debit_note:view` |

---

## Vendor Bills / Purchases (`/bills`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/bills` | Create bill (DRAFT) | `bill:create` |
| POST | `/bills/preview` | Preview bill totals | `bill:view` |
| GET  | `/bills` | List bills (page, limit, search, status, contact_id, date_from, date_to) | `bill:view` |
| POST | `/bills/bulk-delete` | Bulk delete DRAFT bills | `bill:delete` |
| GET  | `/bills/{id}` | Get bill | `bill:view` |
| GET  | `/bills/{id}/pdf-payload` | PDF render data | `bill:view` |
| PUT  | `/bills/{id}` | Update DRAFT bill | `bill:update` |
| POST | `/bills/{id}/finalize` | Post bill (DRAFT→POSTED) | `bill:create` |
| POST | `/bills/{id}/payment` | Record vendor payment | `payment:create` |
| POST | `/bills/{id}/cancel` | Cancel POSTED bill | `bill:create` |
| DELETE | `/bills/{id}` | Delete DRAFT bill | `bill:delete` |
| GET  | `/bills/{id}/print` | Stream PDF | `bill:view` |
| POST | `/bills/{id}/clone` | Clone to new DRAFT | `bill:create` |

### OCR Bill Scan (under `/bills`)
| Method | URL | Purpose | Notes |
|--------|-----|---------|-------|
| POST | `/bills/scan/preview` | Upload image/PDF → async OCR start | Returns `job_id` |
| GET  | `/bills/scan/status` | Poll OCR result by `job_id` | — |
| POST | `/bills/scan/save` | Save OCR-extracted bill data | — |
| POST | `/bills/scan` | Sync OCR scan (blocks) | Direct extraction |

---

## Payments & Receipts (`/payments`)

### Customer Receipts
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/payments/receipts` | Create customer receipt | `payment:create` |
| GET  | `/payments/receipts` | List receipts (page, limit, contact_id, date_from, date_to) | `payment:view` |
| GET  | `/payments/receipts/{id}` | Get receipt | `payment:view` |
| POST | `/payments/receipts/{id}/cancel` | Cancel receipt (reversal) | `payment:cancel` |

### Vendor Disbursements
| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/payments/disbursements` | Create vendor payment | `payment:create` |
| GET  | `/payments/disbursements` | List disbursements | `payment:view` |
| GET  | `/payments/disbursements/{id}` | Get disbursement | `payment:view` |
| POST | `/payments/disbursements/{id}/cancel` | Cancel disbursement | `payment:cancel` |

---

## Purchase Orders (`/purchase-orders`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/purchase-orders` | Create PO | `bill:create` |
| GET  | `/purchase-orders` | List POs (page, limit, status) | `bill:view` |
| GET  | `/purchase-orders/{id}` | Get PO | `bill:view` |
| GET  | `/purchase-orders/{id}/pdf-payload` | PDF data | `bill:view` |
| PUT  | `/purchase-orders/{id}` | Update PO | `bill:update` |
| POST | `/purchase-orders/{id}/confirm` | Confirm PO (DRAFT→CONFIRMED) | `bill:create` |
| POST | `/purchase-orders/{id}/receive` | Mark goods received (→RECEIVED) | `bill:create` |
| POST | `/purchase-orders/{id}/cancel` | Cancel PO | `bill:create` |
| GET  | `/purchase-orders/{id}/print` | Stream PDF | `bill:view` |

---

## Sales Orders (`/sales-orders`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/sales-orders` | Create SO | `invoice:create` |
| GET  | `/sales-orders` | List SOs (page, limit, status) | `invoice:view` |
| GET  | `/sales-orders/{id}` | Get SO | `invoice:view` |
| GET  | `/sales-orders/{id}/pdf-payload` | PDF data | `invoice:view` |
| PUT  | `/sales-orders/{id}` | Update SO | `invoice:update` |
| POST | `/sales-orders/{id}/confirm` | Confirm SO (DRAFT→CONFIRMED) | `invoice:finalize` |
| POST | `/sales-orders/{id}/deliver` | Mark delivered (→DELIVERED) | `invoice:finalize` |
| POST | `/sales-orders/{id}/cancel` | Cancel SO | `invoice:finalize` |
| GET  | `/sales-orders/{id}/print` | Stream PDF | `invoice:view` |

---

## Delivery Challans (`/delivery-challans`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/delivery-challans` | Create DC | `invoice:create` |
| GET  | `/delivery-challans` | List DCs (page, limit, status) | `invoice:view` |
| GET  | `/delivery-challans/{id}` | Get DC | `invoice:view` |
| PUT  | `/delivery-challans/{id}` | Update DC | `invoice:update` |
| POST | `/delivery-challans/{id}/issue` | Issue DC (DRAFT→ISSUED) | `invoice:finalize` |
| POST | `/delivery-challans/{id}/cancel` | Cancel DC | `invoice:finalize` |

---

## Proforma Invoices / Quotations (`/proforma-invoices`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/proforma-invoices` | Create proforma | `invoice:create` |
| POST | `/proforma-invoices/preview` | Preview proforma | `invoice:view` |
| GET  | `/proforma-invoices` | List proformas (page, limit, status, contact_id, date_from, date_to) | `invoice:view` |
| GET  | `/proforma-invoices/{id}` | Get proforma | `invoice:view` |
| PUT  | `/proforma-invoices/{id}` | Update DRAFT proforma | `invoice:update` |
| POST | `/proforma-invoices/{id}/issue` | Issue proforma (DRAFT→ISSUED) | `invoice:finalize` |
| POST | `/proforma-invoices/{id}/convert` | Convert to sales invoice | `invoice:create` |
| POST | `/proforma-invoices/{id}/cancel` | Cancel proforma | `invoice:finalize` |
| GET  | `/proforma-invoices/{id}/pdf-payload` | PDF data | `invoice:view` |
| DELETE | `/proforma-invoices/{id}` | Delete DRAFT proforma | `invoice:delete` |
| GET  | `/proforma-invoices/{id}/print` | Stream PDF | `invoice:view` |

---

## Returns (`/returns`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/returns/sales` | Create sales return | `invoice:create` |
| GET  | `/returns/sales` | List sales returns (page, limit, contact_id, date_from, date_to) | `invoice:view` |
| GET  | `/returns/sales/{id}` | Get sales return | `invoice:view` |
| POST | `/returns/sales/{id}/cancel` | Cancel sales return | `invoice:finalize` |
| POST | `/returns/purchase` | Create purchase return | `bill:create` |
| GET  | `/returns/purchase` | List purchase returns | `bill:view` |
| GET  | `/returns/purchase/{id}` | Get purchase return | `bill:view` |
| POST | `/returns/purchase/{id}/cancel` | Cancel purchase return | `bill:create` |

---

## Expenses (`/expenses`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/expenses` | Create expense (DRAFT) | `expense:create` |
| POST | `/expenses/preview` | Preview expense GST calculation | `expense:view` |
| POST | `/expenses/bulk-delete` | Bulk delete DRAFT expenses | `expense:delete` |
| GET  | `/expenses` | List expenses (page, limit, category_id, date_from, date_to, status, search) | `expense:view` |
| GET  | `/expenses/{id}` | Get expense | `expense:view` |
| PUT  | `/expenses/{id}` | Update DRAFT expense | `expense:edit` |
| DELETE | `/expenses/{id}` | Delete DRAFT expense | `expense:delete` |
| POST | `/expenses/{id}/post` | Post expense (DRAFT→POSTED) | `expense:finalize` |
| POST | `/expenses/{id}/cancel` | Cancel POSTED expense | `expense:finalize` |
| POST | `/expenses/{id}/clone` | Clone expense | `expense:create` |

---

## Inventory Adjustments (`/inventory-adjustments`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/inventory-adjustments` | Create adjustment | `invoice:create` |
| GET  | `/inventory-adjustments` | List adjustments (page, limit) | `invoice:view` |
| GET  | `/inventory-adjustments/{id}` | Get adjustment | `invoice:view` |
| PUT  | `/inventory-adjustments/{id}` | Update adjustment | `invoice:update` |
| POST | `/inventory-adjustments/{id}/confirm` | Confirm adjustment (updates stock) | `invoice:finalize` |
| POST | `/inventory-adjustments/{id}/cancel` | Cancel confirmed adjustment | `invoice:finalize` |

---

## Accounting & Ledger (`/accounting`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/accounting/journals` | Create manual journal entry | `ledger:manual_post` |
| GET  | `/accounting/journals` | List journal entries (page, limit, date_from, date_to, source_type) | `ledger:view` |
| GET  | `/accounting/journals/{id}` | Get journal entry | `ledger:view` |
| GET  | `/accounting/ledger/{account_id}` | Ledger card / running balance (date_from, date_to) | `ledger:view` |
| GET  | `/accounting/trial-balance` | Trial balance (as_of_date) | `ledger:view` |
| GET  | `/accounting/profit-loss` | P&L statement (date_from, date_to) | `ledger:view` |
| GET  | `/accounting/balance-sheet` | Balance sheet (as_of_date) | `ledger:view` |
| GET  | `/accounting/cash-bank-balances` | Current cash/bank balances | `ledger:view` |
| POST | `/accounting/recalculate-balances` | Recalculate all account balances | `accounts:manage` |
| GET  | `/accounting/year-end/prepare` | Pre-close checklist | `accounts:manage` |
| POST | `/accounting/year-end/close` | **DEPRECATED** — use `/financial-years/{id}/close` | `accounts:manage` |

---

## Financial Years (`/financial-years`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| GET  | `/financial-years` | List all FYs | `settings:view` |
| POST | `/financial-years` | Create new FY | `settings:update` |
| POST | `/financial-years/switch` | Switch active FY | `settings:update` |
| GET  | `/financial-years/current` | Get current FY | `settings:view` |
| GET  | `/financial-years/{fy_id}/dashboard` | Year-end readiness dashboard | `settings:view` |
| POST | `/financial-years/{fy_id}/close` | Close FY (creates opening balances) | `accounts:manage` |
| POST | `/financial-years/{fy_id}/reopen` | Reopen locked FY (requires reason) | `accounts:manage` |
| GET  | `/financial-years/{fy_id}/audit` | FY audit trail | `audit:view` |
| GET  | `/financial-years/{fy_id}/opening-balances` | Opening balance snapshots | `ledger:view` |
| GET  | `/financial-years/{fy_id}/inventory-carry-forward` | Inventory roll-forward snapshots | `ledger:view` |

---

## Bank Reconciliation (`/bank-reconciliation`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/bank-reconciliation/upload` | Upload CSV/Excel bank statement | `payment:create` |
| GET  | `/bank-reconciliation/statements` | List bank statements (page, limit) | `payment:view` |
| GET  | `/bank-reconciliation/statements/{id}` | Get statement | `payment:view` |
| DELETE | `/bank-reconciliation/statements/{id}` | Delete statement | `payment:create` |
| GET  | `/bank-reconciliation/statements/{id}/stats` | Reconciliation statistics | `payment:view` |
| GET  | `/bank-reconciliation/statements/{statement_id}/transactions` | List transactions | `payment:view` |
| POST | `/bank-reconciliation/statements/{statement_id}/auto-match` | Auto-match transactions | `payment:create` |
| GET  | `/bank-reconciliation/statements/{statement_id}/suggestions` | Match suggestions | `payment:view` |
| POST | `/bank-reconciliation/bulk-reconcile` | Bulk reconcile transactions | `payment:create` |
| GET  | `/bank-reconciliation/pending-invoices` | Outstanding AR for matching | `payment:view` |
| GET  | `/bank-reconciliation/pending-bills` | Outstanding AP for matching | `payment:view` |
| POST | `/bank-reconciliation/transactions/{transaction_id}/reconcile` | Reconcile single transaction | `payment:create` |
| GET  | `/bank-reconciliation/reconciliations` | List reconciliations | `payment:view` |
| GET  | `/bank-reconciliation/reconciliations/{id}` | Get reconciliation | `payment:view` |
| POST | `/bank-reconciliation/reconciliations/{id}/undo` | Undo reconciliation | `payment:create` |

---

## Recurring Invoices (`/recurring-invoices`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/recurring-invoices` | Create recurring template | `invoice:create` |
| GET  | `/recurring-invoices` | List templates | `invoice:view` |
| GET  | `/recurring-invoices/{id}` | Get template | `invoice:view` |
| PUT  | `/recurring-invoices/{id}` | Update template | `invoice:update` |
| DELETE | `/recurring-invoices/{id}` | Delete template | `invoice:delete` |
| POST | `/recurring-invoices/{id}/generate` | Manually trigger invoice generation | `invoice:create` |

---

## Terms Templates (`/terms-templates`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/terms-templates` | Create T&C template | `invoice:create` |
| GET  | `/terms-templates` | List templates | `invoice:view` |
| GET  | `/terms-templates/presets` | Get India-specific presets | None |
| GET  | `/terms-templates/{id}` | Get template | `invoice:view` |
| PUT  | `/terms-templates/{id}` | Update template | `invoice:update` |
| DELETE | `/terms-templates/{id}` | Delete template | `invoice:delete` |

---

## Dashboard (`/dashboard`)

| Method | URL | Purpose | Permission | Query Params |
|--------|-----|---------|-----------|-------------|
| GET | `/dashboard/metrics` | Core KPIs (revenue, outstanding, etc.) | `invoice:view` | date_from, date_to |
| GET | `/dashboard/revenue-trend` | Monthly revenue chart data | `invoice:view` | — |
| GET | `/dashboard/kpis` | Key performance indicators | `invoice:view` | — |
| GET | `/dashboard/overdue-alerts` | List of overdue invoices | `invoice:view` | — |
| GET | `/dashboard/expense-trend` | Monthly expense chart data | `expense:view` | — |

---

## Sales Analytics (`/sales`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| GET | `/sales/summary` | Sales totals (date_from, date_to) | `invoice:view` |
| GET | `/sales/customer-wise` | Sales grouped by customer | `invoice:view` |
| GET | `/sales/period-wise` | Sales grouped by month | `invoice:view` |
| GET | `/sales/transactions` | Sales transaction list (paginated) | `invoice:view` |

---

## Reports (`/reports`)

| Method | URL | Purpose | Permission | Export |
|--------|-----|---------|-----------|--------|
| GET | `/reports/balance-sheet` | Balance sheet (as_of_date) | `reports:view` | — |
| GET | `/reports/balance-sheet/excel` | Balance sheet Excel | `reports:view` | XLSX |
| GET | `/reports/balance-sheet/pdf` | Balance sheet PDF | `reports:view` | PDF |
| GET | `/reports/trial-balance` | Trial balance | `reports:view` | — |
| GET | `/reports/trial-balance/excel` | Trial balance Excel | `reports:view` | XLSX |
| GET | `/reports/trial-balance/pdf` | Trial balance PDF | `reports:view` | PDF |
| GET | `/reports/profit-loss` | P&L (date_from, date_to) | `reports:view` | — |
| GET | `/reports/profit-loss/excel` | P&L Excel | `reports:view` | XLSX |
| GET | `/reports/profit-loss/pdf` | P&L PDF | `reports:view` | PDF |
| GET | `/reports/cash-flow` | Cash flow (date_from, date_to) | `reports:view` | — |
| GET | `/reports/cash-flow/excel` | Cash flow Excel | `reports:view` | XLSX |
| GET | `/reports/cash-flow/pdf` | Cash flow PDF | `reports:view` | PDF |
| GET | `/reports/aging/ar` | AR aging | `reports:view` | — |
| GET | `/reports/aging/ap` | AP aging | `reports:view` | — |
| GET | `/reports/aging/{report_type}/excel` | Aging Excel | `reports:view` | XLSX |
| GET | `/reports/aging/{report_type}/pdf` | Aging PDF | `reports:view` | PDF |
| GET | `/reports/outstanding/ar` | Outstanding AR | `reports:view` | — |
| GET | `/reports/outstanding/ap` | Outstanding AP | `reports:view` | — |
| GET | `/reports/outstanding/{report_type}/excel` | Outstanding Excel | `reports:view` | XLSX |
| GET | `/reports/outstanding/{report_type}/pdf` | Outstanding PDF | `reports:view` | PDF |
| GET | `/reports/party-statement` | Party ledger statement (contact_id, date_from, date_to) | `reports:view` | — |
| GET | `/reports/party-statement/pdf` | Party statement PDF | `reports:view` | PDF |
| GET | `/reports/party-statement/excel` | Party statement Excel | `reports:view` | XLSX |
| GET | `/reports/gstr1` | GSTR-1 via reports router | `gst:report_view` | — |
| GET | `/reports/gstr2` | GSTR-2 via reports router | `gst:report_view` | — |
| GET | `/reports/gstr3b` | GSTR-3B via reports router | `gst:report_view` | — |
| GET | `/reports/sales-analytics` | Sales analytics (date_from, date_to, top_n) | `reports:view` | — |
| GET | `/reports/purchase-analytics` | Purchase analytics | `reports:view` | — |
| GET | `/reports/cash-book` | Cash book (date_from, date_to) | `reports:view` | — |
| GET | `/reports/cash-book/excel` | Cash book Excel | `reports:view` | XLSX |
| GET | `/reports/cash-book/pdf` | Cash book PDF | `reports:view` | PDF |

---

## GST Compliance (`/gst`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| GET | `/gst/validate-gstin/{gstin}` | Validate GSTIN format | None |
| GET | `/gst/gstr1` | GSTR-1 JSON report (start_date, end_date) | `gst:report_view` |
| GET | `/gst/gstr1/export` | GSTR-1 Excel (offline tool) | `gst:report_view` |
| GET | `/gst/gstr1/pdf` | GSTR-1 PDF | `gst:report_view` |
| GET | `/gst/gstr2` | GSTR-2 JSON report | `gst:report_view` |
| GET | `/gst/gstr2/export` | GSTR-2 Excel | `gst:report_view` |
| GET | `/gst/gstr2/pdf` | GSTR-2 PDF | `gst:report_view` |
| GET | `/gst/gstr3b/export` | GSTR-3B Excel | `gst:report_view` |
| GET | `/gst/gstr3b/pdf` | GSTR-3B PDF | `gst:report_view` |
| GET | `/gst/verify/captcha` | Get GSTIN verification captcha | `contact:create` |
| POST | `/gst/verify` | Verify GSTIN with captcha | `contact:create` |
| POST | `/gst/gstr2a/upload` | Upload GSTR-2A JSON → reconcile | `gst:filing_manage` |
| GET | `/gst/hsn/{hsn_code}` | HSN/SAC code lookup | `invoice:create` |

---

## e-Way Bills (`/eway-bills`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/eway-bills` | Generate e-Way Bill | `invoice:finalize` |
| GET  | `/eway-bills` | List e-Way Bills | `invoice:view` |
| GET  | `/eway-bills/{id}` | Get e-Way Bill | `invoice:view` |
| POST | `/eway-bills/{id}/cancel` | Cancel e-Way Bill | `invoice:finalize` |
| POST | `/eway-bills/{id}/vehicle` | Update vehicle/transporter | `invoice:finalize` |
| POST | `/eway-bills/consolidated` | Generate consolidated e-Way Bill | `invoice:finalize` |

---

## Audit Logs (`/audit-logs`)

| Method | URL | Purpose | Permission | Filters |
|--------|-----|---------|-----------|---------|
| GET | `/audit-logs` | List audit logs (page, limit, entity_type, action, actor_id) | `audit:view` | — |

---

## Reminders (`/reminders`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| GET | `/reminders` | Get overdue invoices + daily summary | `invoice:view` |
| POST | `/reminders` | Create reminder (stub) | — |

---

## Data Import (`/import`, `/tally`)

| Method | URL | Purpose | Permission |
|--------|-----|---------|-----------|
| POST | `/import/vyapar` | Import Vyapar .vyb backup | `tenant:update` |
| POST | `/tally/import` | Import Tally XML backup | `data:import` |
| GET  | `/tally/export` | Export to Tally XML | `tenant:view` |

---

## Health Check

| Method | URL | Purpose | Auth |
|--------|-----|---------|------|
| GET | `/health` | Deep health check (DB + Redis ping) | None |
| GET | `/` | API info / docs link | None |

---

## Total Endpoint Count

| Category | Count |
|----------|-------|
| Authentication | 13 |
| Company & Settings | 18 |
| Master Data | 22 |
| Sales Invoices + CN + DN | 27 |
| Vendor Bills | 13 |
| Payments | 8 |
| Purchase Orders | 9 |
| Sales Orders | 9 |
| Delivery Challans | 6 |
| Proforma Invoices | 11 |
| Returns | 8 |
| Expenses | 10 |
| Inventory Adjustments | 6 |
| Accounting & Ledger | 11 |
| Financial Years | 10 |
| Bank Reconciliation | 15 |
| Recurring Invoices | 6 |
| Terms Templates | 6 |
| Dashboard | 5 |
| Sales Analytics | 4 |
| Reports (financial) | 28 |
| GST Compliance | 13 |
| e-Way Bills | 6 |
| Audit Logs | 1 |
| Reminders | 2 |
| Data Import | 3 |
| Health / Root | 2 |
| **TOTAL** | **271** |
