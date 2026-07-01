# ApexBooks — Complete Backend Index
> Master summary of the entire ApexBooks backend for the frontend team.

---

## Final Statistics

| Metric | Count |
|--------|-------|
| **Total backend source files** | **72** |
| **Total modules** | **15** |
| **Total API routers** | **30** |
| **Total API endpoints** | **271** |
| **Total database tables** | **62** |
| **Total Pydantic request models** | **78** |
| **Total Pydantic response models** | **94** |
| **Total domain service files** | **16** |
| **Total background job tasks** | **9** |
| **Total accounting reports** | **21** |
| **Total external integrations** | **8** |
| **Total permissions** | **37** |
| **Total roles** | **4** |
| **Total feature flags** | **12** |
| **Total frontend-required files** | **47** |
| **Total backend-only files** | **25** |
| **Missing APIs** | **17** |
| **Broken endpoints** | **1** |

---

## Module Index

| Module | Router Files | Schema Files | Domain Files | Tables |
|--------|-------------|-------------|-------------|--------|
| Authentication | `auth.py` | `auth_schemas.py` | `auth/totp_service.py` | `users`, `tenant_memberships`, `password_reset_tokens`, `tenant_invitations` |
| Company/Settings | `companies.py` | `company_schemas.py` | `company/services.py` | `tenants`, `tenant_settings`, `numbering_series`, `branches` |
| Master Data | `masters.py` | `master_schemas.py` | — | `contacts`, `products`, `accounts`, `banking_profiles`, `expense_categories`, `tax_templates`, `payment_terms` |
| Sales Invoices | `invoices.py` | `document.py` | `accounting/auto_post.py` | `invoices`, `invoice_lines` |
| Credit/Debit Notes | `invoices.py` | `document.py` | — | `credit_notes`, `credit_note_lines`, `debit_notes`, `debit_note_lines` |
| Vendor Bills | `bills.py`, `bill_scan.py` | `bill_schemas.py` | `scanning/invoice_scanner.py` | `bills`, `bill_lines` |
| Payments | `payments.py` | `payment_schemas.py` | — | `payments`, `payment_allocations`, `bill_payments`, `bill_payment_allocations` |
| Purchase Orders | `purchase_orders.py` | `bill_schemas.py` | — | `purchase_orders`, `purchase_order_lines` |
| Sales Orders | `sales_orders.py` | `bill_schemas.py` | — | `sales_orders`, `sales_order_lines` |
| Delivery Challans | `delivery_challans.py` | `bill_schemas.py` | — | `delivery_challans`, `delivery_challan_lines` |
| Proforma Invoices | `proforma_invoices.py` | `bill_schemas.py` | — | `proforma_invoices`, `proforma_invoice_lines` |
| Returns | `returns.py` | `document.py` | — | `sales_returns`, `sales_return_lines`, `purchase_returns`, `purchase_return_lines` |
| Expenses | `expenses.py` | `expense_schemas.py` | — | `expenses` |
| Inventory | `inventory_adjustments.py` | `bill_schemas.py` | — | `inventory_adjustments`, `inventory_adjustment_lines`, `stock_ledger` |
| Accounting/Ledger | `accounting.py` | `accounting_schemas.py` | `accounting/services.py`, `accounting/period_lock.py` | `journal_entries`, `journal_lines`, `accounts`, `accounting_periods` |
| Financial Years | `financial_years.py` | `accounting_schemas.py` | `accounting/roll_forward.py` | `financial_years`, `financial_year_audits`, `opening_balance_snapshots`, `inventory_carry_forward` |
| Bank Reconciliation | `bank_reconciliation.py` | `bill_schemas.py` | — | `bank_statements`, `bank_transactions`, `bank_reconciliations` |
| Recurring Invoices | `recurring_invoices.py` | `document.py` | — | `recurring_invoices`, `recurring_invoice_items` |
| Terms Templates | `terms_templates.py` | `document.py` | — | `terms_templates` |
| Dashboard | `dashboard.py` | — | — | — |
| Sales Analytics | `sales.py` | — | — | — |
| Reports | `reports.py` | `report_schemas.py` | `accounting/report_services.py` | — |
| GST | `gst.py`, `gstr2a.py`, `gst_verify.py`, `hsn_lookup.py` | `gst_schemas.py` | `taxation/services.py`, `taxation/gst_verify/` | `gst_returns` |
| e-Invoice | `invoices.py` | `einvoice_schemas.py` | `taxation/einvoice_service.py` | — |
| e-Way Bill | `eway_bills.py` | `eway_bill_schemas.py` | `taxation/eway_bill_service.py` | `eway_bills` |
| Audit Logs | `audit.py` | — | `common/audit_log.py` | `audit_logs` |
| Reminders | `reminders.py` | — | — | — |
| Import/Export | `vyapar_import.py`, `tally.py` | — | — | — |
| Printing | — | — | `printing/invoice_pdf.py` | — |
| Background Jobs | — | — | `workers/tasks.py` | `webhook_events` |

---

## All API Endpoints Quick Reference

### Authentication (13 endpoints)
```
POST   /auth/register
POST   /auth/login
POST   /auth/refresh
POST   /auth/logout
GET    /auth/me
GET    /auth/memberships
POST   /auth/change-password
POST   /auth/forgot-password
POST   /auth/reset-password
POST   /auth/verify-email
POST   /auth/2fa/enable
POST   /auth/2fa/verify
POST   /auth/2fa/disable
```

### Company & Settings (18 endpoints)
```
POST   /companies
GET    /companies/{id}
PUT    /companies/{id}
POST   /companies/{id}/gst-toggle
GET    /companies/{id}/branches
POST   /companies/{id}/branches
PUT    /companies/{id}/branches/{bid}
DELETE /companies/{id}/branches/{bid}
POST   /settings/logo
GET    /settings
PUT    /settings
GET    /settings/series
POST   /settings/series
PUT    /settings/series/{id}
POST   /purge/request
POST   /purge/verify
GET    /companies/{id}/export
POST   /companies/{id}/import
```

### Master Data (22 endpoints)
```
POST/GET/GET/PUT/DELETE  /masters/contacts (+ /{id})
POST/GET/GET/PUT/DELETE  /masters/products (+ /{id})
POST/GET/POST/POST/GET/PUT/DELETE  /masters/accounts (+ seed-defaults + dedupe-contact-accounts + /{id})
POST/GET/GET/PUT/DELETE  /masters/banking-profiles (+ /{id})
POST/GET/GET/PUT/DELETE  /masters/expense-categories (+ /{id})
GET  /masters/tax-templates
GET  /masters/payment-terms
GET  /contacts  (alias)
GET  /products  (alias)
```

### Sales Invoices + CN + DN (27 endpoints)
```
POST   /invoices
POST   /invoices/preview
GET    /invoices/stats
GET    /invoices
POST   /invoices/bulk-delete
GET    /invoices/{id}
PUT    /invoices/{id}
POST   /invoices/{id}/finalize
POST   /invoices/{id}/payment
POST   /invoices/{id}/cancel
DELETE /invoices/{id}
GET    /invoices/{id}/pdf-payload
GET    /invoices/{id}/print
POST   /invoices/{id}/e-invoice
POST   /invoices/{id}/e-invoice/cancel
POST   /invoices/{id}/clone
POST   /invoices/{id}/email
POST/POST/GET/GET/POST/POST/DELETE/GET  /invoices/credit-notes (+ /{id}/finalize/cancel/print)
POST/POST/GET/GET/POST/POST/DELETE/GET  /invoices/debit-notes (+ /{id}/finalize/cancel/print)
```

### Vendor Bills (13 endpoints)
```
POST   /bills
POST   /bills/preview
GET    /bills
POST   /bills/bulk-delete
GET    /bills/{id}
GET    /bills/{id}/pdf-payload
PUT    /bills/{id}
POST   /bills/{id}/finalize
POST   /bills/{id}/payment
POST   /bills/{id}/cancel
DELETE /bills/{id}
GET    /bills/{id}/print
POST   /bills/{id}/clone
POST   /bills/scan/preview
GET    /bills/scan/status
POST   /bills/scan/save
POST   /bills/scan
```

### Payments (8 endpoints)
```
POST/GET/GET/POST  /payments/receipts (+ /{id}/cancel)
POST/GET/GET/POST  /payments/disbursements (+ /{id}/cancel)
```

### Purchase Orders (9 endpoints)
```
POST/GET/GET/GET/PUT/POST/POST/POST/GET  /purchase-orders (CRUD + confirm/receive/cancel/print)
```

### Sales Orders (9 endpoints)
```
POST/GET/GET/GET/PUT/POST/POST/POST/GET  /sales-orders (CRUD + confirm/deliver/cancel/print)
```

### Delivery Challans (6 endpoints)
```
POST/GET/GET/PUT/POST/POST  /delivery-challans (CRUD + issue/cancel)
```

### Proforma Invoices (11 endpoints)
```
POST/POST/GET/GET/PUT/POST/POST/POST/GET/DELETE/GET  /proforma-invoices
```

### Returns (8 endpoints)
```
POST/GET/GET/POST  /returns/sales (+ /{id}/cancel)
POST/GET/GET/POST  /returns/purchase (+ /{id}/cancel)
```

### Expenses (10 endpoints)
```
POST/POST/POST/GET/GET/PUT/DELETE/POST/POST/POST  /expenses (CRUD + preview/bulk-delete/post/cancel/clone)
```

### Inventory Adjustments (6 endpoints)
```
POST/GET/GET/PUT/POST/POST  /inventory-adjustments (CRUD + confirm/cancel)
```

### Accounting & Ledger (11 endpoints)
```
POST/GET/GET   /accounting/journals
GET            /accounting/ledger/{account_id}
GET            /accounting/trial-balance
GET            /accounting/profit-loss
GET            /accounting/balance-sheet
GET            /accounting/cash-bank-balances
POST           /accounting/recalculate-balances
GET            /accounting/year-end/prepare
POST           /accounting/year-end/close  (deprecated)
```

### Financial Years (10 endpoints)
```
GET/POST       /financial-years
POST           /financial-years/switch
GET            /financial-years/current
GET/POST/POST/GET/GET/GET  /financial-years/{id} (dashboard/close/reopen/audit/opening-balances/inventory-carry-forward)
```

### Bank Reconciliation (15 endpoints)
```
POST           /bank-reconciliation/upload
GET/GET/DELETE /bank-reconciliation/statements (+ /{id})
GET            /bank-reconciliation/statements/{id}/stats
GET            /bank-reconciliation/statements/{id}/transactions
POST           /bank-reconciliation/statements/{id}/auto-match
GET            /bank-reconciliation/statements/{id}/suggestions
POST           /bank-reconciliation/bulk-reconcile
GET            /bank-reconciliation/pending-invoices
GET            /bank-reconciliation/pending-bills
POST           /bank-reconciliation/transactions/{id}/reconcile
GET/GET/POST   /bank-reconciliation/reconciliations (+ /{id}/undo)
```

### Recurring Invoices (6 endpoints)
### Terms Templates (6 endpoints)
### Dashboard (5 endpoints)
### Sales Analytics (4 endpoints)
### Reports (28 endpoints — JSON + Excel + PDF for each)
### GST (13 endpoints)
### e-Way Bills (6 endpoints)
### Audit Logs (1 endpoint)
### Reminders (2 endpoints)
### Import (3 endpoints)
### Health (2 endpoints)

---

## All Database Tables

1. `tenants` — Companies
2. `users` — Platform accounts
3. `tenant_memberships` — User ↔ Company roles
4. `password_reset_tokens`
5. `tenant_invitations`
6. `contacts` — Customers & Vendors
7. `products` — Items & Services
8. `accounts` — Chart of Accounts
9. `banking_profiles` — Bank accounts
10. `expense_categories`
11. `tax_templates`
12. `payment_terms`
13. `invoices`
14. `invoice_lines`
15. `payments` (AR receipts)
16. `payment_allocations`
17. `bills`
18. `bill_lines`
19. `bill_payments`
20. `bill_payment_allocations`
21. `journal_entries`
22. `journal_lines`
23. `branches`
24. `tenant_settings`
25. `numbering_series`
26. `credit_notes`
27. `credit_note_lines`
28. `debit_notes`
29. `debit_note_lines`
30. `purchase_orders`
31. `purchase_order_lines`
32. `sales_orders`
33. `sales_order_lines`
34. `delivery_challans`
35. `delivery_challan_lines`
36. `proforma_invoices`
37. `proforma_invoice_lines`
38. `eway_bills`
39. `expenses`
40. `gst_returns`
41. `stock_ledger`
42. `webhook_events`
43. `inventory_adjustments`
44. `inventory_adjustment_lines`
45. `audit_logs`
46. `bank_statements`
47. `bank_transactions`
48. `bank_reconciliations`
49. `accounting_periods`
50. `period_lock_audits`
51. `financial_years`
52. `financial_year_audits`
53. `sales_returns`
54. `sales_return_lines`
55. `purchase_returns`
56. `purchase_return_lines`
57. `opening_balance_snapshots`
58. `inventory_carry_forward`
59. `recurring_invoices`
60. `recurring_invoice_items`
61. `terms_templates`
62. `idempotency_records`

---

## High-Risk Accounting Areas

| Risk | Area | Mitigation |
|------|------|-----------|
| 🔴 Period Lock API missing | Accountants cannot lock periods via UI | Document as known issue; catch 400 errors gracefully |
| 🔴 Journal entries are immutable | Cannot edit journal entries | Guide users to cancel + recreate source documents |
| 🔴 2FA not enforced on login | Security gap | Implement pending TOTP login challenge |
| 🟠 Negative stock allowed | Inventory accuracy | Warn user on frontend when quantity exceeds stock |
| 🟠 Tally import permission broken | Import feature unavailable | Use Vyapar import or fix `ROLE_PERMISSIONS` |
| 🟠 No Day Book API | Core accounting report missing | Use journal entries list as workaround |
| 🟡 S3 storage not wired | Logo storage is local filesystem only | Implement S3 for production; logos lost on server restart |
| 🟡 TOTP setup exists but has no login challenge | 2FA decorative | Add TOTP challenge step to login |

---

## Document Map

| File | Purpose |
|------|---------|
| `BACKEND_FILE_INVENTORY.md` | Every backend file, its purpose, and frontend relevance |
| `API_ENDPOINT_CATALOG.md` | All 271 API endpoints with HTTP methods, URLs, permissions |
| `DATABASE_SCHEMA_REFERENCE.md` | All 62 tables with fields, types, constraints, relationships |
| `REQUEST_RESPONSE_REFERENCE.md` | Request models, response models, validation rules, sample JSON |
| `BUSINESS_RULES_REFERENCE.md` | Document lifecycle, GST rules, ledger posting, inventory, period locks |
| `ACCOUNTING_WORKFLOW_GUIDE.md` | Step-by-step API call sequences for every major workflow |
| `REPORT_API_REFERENCE.md` | All financial reports with query params, response schemas, exports |
| `GST_API_REFERENCE.md` | GSTIN validation, GSTR-1/2/3B, e-Invoice, e-Way Bill, HSN lookup |
| `AUTHENTICATION_GUIDE.md` | JWT flow, token refresh, multi-tenant, 2FA, CORS, rate limits |
| `PERMISSIONS_MATRIX.md` | 4 roles × 37 permissions, endpoint permission mapping |
| `FEATURE_FLAGS_REFERENCE.md` | GST mode, e-invoicing, OCR, currency, and all feature toggles |
| `IMPORT_EXPORT_GUIDE.md` | Vyapar, Tally, JSON backup, GSTR exports, PDF downloads |
| `FILE_UPLOAD_GUIDE.md` | Logo, OCR scan, bank statement, GSTR-2A upload specs |
| `INTEGRATIONS_REFERENCE.md` | NIC IRP, e-Way Bill, GSTIN verify, OCR engines, email, Celery |
| `MISSING_APIS.md` | 17 missing/broken APIs with priority and workarounds |
| `FRONTEND_HANDOVER_GUIDE.md` | Dev sequence, screen→API mapping, gotchas, form/table specs |
| `COMPLETE_BACKEND_INDEX.md` | This file — master summary and statistics |
