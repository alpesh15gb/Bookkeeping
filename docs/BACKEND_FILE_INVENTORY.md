# ApexBooks Backend — File Inventory
> Generated 2026-07-01 | Root: `backend/src/`

---

## 1. Entry Point

| File | Path | LOC (approx) | Purpose | Frontend Relevance |
|------|------|-------------|---------|-------------------|
| `main.py` | `src/main.py` | ~510 | FastAPI app factory, middleware stack, router mounting, lifespan, health check, global exception handlers | **Critical** — all routes are registered here |

---

## 2. Core Infrastructure (`src/core/`)

| File | LOC | Purpose | Frontend Relevance |
|------|-----|---------|-------------------|
| `config.py` | ~168 | All environment variables and settings (JWT, CORS, SMTP, S3, IRP, rate limits) | **Critical** — token expiry, allowed origins |
| `security.py` | ~188 | JWT creation/decoding, bcrypt hashing, RBAC `Permissions` class, `ROLE_PERMISSIONS` dict | **Critical** — permission names consumed by every guarded endpoint |
| `database.py` | ~220 | SQLAlchemy engine, session factory, `get_db_session` dependency, `tenant_context` ContextVar | Backend Only |
| `cache.py` | ~50 | Redis cache helpers (`cache_get`, `cache_set`, `make_cache_key`) | Backend Only |
| `celery.py` | ~30 | Celery app factory with Redis broker/backend | Backend Only |
| `rate_limiter.py` | ~55 | SlowAPI rate limiter setup; `rate_limiter_exceeded_handler` | Backend Only |
| `sentry.py` | ~35 | Sentry SDK initialisation | Backend Only |

---

## 3. API Layer (`src/api/`)

### 3a. Dependencies (`src/api/deps.py`)
| LOC | Purpose | Frontend Relevance |
|-----|---------|-------------------|
| ~147 | `get_current_user`, `get_tenant_context`, `enforce_permission` — injected into every protected route | **Critical** — defines required `Authorization` header and `X-Tenant-ID` header |

### 3b. Middleware (`src/api/idempotency_middleware.py`)
| LOC | Purpose | Frontend Relevance |
|-----|---------|-------------------|
| ~90 | Idempotency key deduplication on POST/PUT via `Idempotency-Key` header | **Important** — send header to prevent double-submission |

---

## 4. API Routers (`src/api/v1/`)

| File | Prefix | LOC | Module | Frontend Relevance |
|------|--------|-----|--------|-------------------|
| `auth.py` | `/api/v1/auth` | ~605 | Authentication | **Critical** |
| `companies.py` | `/api/v1` | ~1015 | Company & Settings | **Critical** |
| `masters.py` | `/api/v1/masters` | ~802 | Contacts, Products, Accounts, Banking Profiles, Expense Categories, Tax Templates, Payment Terms | **Critical** |
| `invoices.py` | `/api/v1/invoices` | ~2342 | Sales Invoices, Credit Notes, Debit Notes | **Critical** |
| `bills.py` | `/api/v1/bills` | ~1116 | Vendor Bills (Purchases) + OCR scan integration | **Critical** |
| `payments.py` | `/api/v1/payments` | ~475 | Customer Receipts, Vendor Disbursements | **Critical** |
| `purchase_orders.py` | `/api/v1/purchase-orders` | ~508 | Purchase Orders | **Critical** |
| `sales_orders.py` | `/api/v1/sales-orders` | ~512 | Sales Orders | **Critical** |
| `delivery_challans.py` | `/api/v1/delivery-challans` | ~335 | Delivery Challans | **Important** |
| `proforma_invoices.py` | `/api/v1/proforma-invoices` | ~703 | Proforma Invoices / Quotations | **Important** |
| `returns.py` | `/api/v1/returns` | ~382 | Sales Returns, Purchase Returns | **Critical** |
| `expenses.py` | `/api/v1/expenses` | ~565 | Expense Management | **Critical** |
| `accounting.py` | `/api/v1/accounting` | ~808 | Manual Journals, Ledger, Trial Balance, P&L, Balance Sheet, Year-End | **Critical** |
| `financial_years.py` | `/api/v1/financial-years` | ~787 | Financial Year CRUD, FY Close, Reopen, Opening Balances | **Critical** |
| `bank_reconciliation.py` | `/api/v1/bank-reconciliation` | ~1212 | Bank Statement Upload, Auto-Match, Reconciliation | **Important** |
| `reports.py` | `/api/v1/reports` | ~1194 | All financial reports (BS, P&L, Cash Flow, Aging, Cash Book, etc.) with PDF/Excel export | **Critical** |
| `gst.py` | `/api/v1/gst` | ~1216 | GSTR-1, GSTR-2, GSTR-3B, Excel/PDF export, GSTIN validation | **Critical** |
| `gst_verify.py` | `/api/v1/gst/verify` | ~73 | GSTIN live verification via captcha | **Important** |
| `gstr2a.py` | `/api/v1/gst/gstr2a` | ~117 | GSTR-2A upload & reconciliation against purchase bills | **Important** |
| `hsn_lookup.py` | `/api/v1/gst/hsn` | ~26 | HSN/SAC code description lookup | **Important** |
| `eway_bills.py` | `/api/v1/eway-bills` | ~109 | e-Way Bill generation, cancellation, vehicle update | **Important** |
| `inventory_adjustments.py` | `/api/v1/inventory-adjustments` | ~351 | Stock Adjustments (write-up/write-off) | **Important** |
| `recurring_invoices.py` | `/api/v1/recurring-invoices` | ~366 | Recurring Invoice templates | **Important** |
| `terms_templates.py` | `/api/v1/terms-templates` | ~167 | Reusable T&C templates | **Optional** |
| `dashboard.py` | `/api/v1/dashboard` | ~246 | Dashboard KPIs, revenue trend, overdue alerts, expense trend | **Critical** |
| `sales.py` | `/api/v1/sales` | ~184 | Sales analytics (summary, customer-wise, period-wise, transactions) | **Important** |
| `audit.py` | `/api/v1/audit-logs` | ~42 | Audit log listing | **Important** |
| `reminders.py` | `/api/v1/reminders` | ~78 | Overdue alerts and daily summary notifications | **Optional** |
| `bill_scan.py` | `/api/v1/bills` (scan sub-routes) | ~537 | OCR bill scanning (preview, status, save, direct scan) | **Important** |
| `vyapar_import.py` | `/api/v1/import` | ~1400 | Vyapar .vyb backup import | **Important** |
| `tally.py` | `/api/v1/tally` | ~767 | Tally XML import/export | **Important** |

---

## 5. Domain Services (`src/domains/`)

| File | LOC | Purpose | Frontend Relevance |
|------|-----|---------|-------------------|
| `accounting/services.py` | ~2200 | `AccountResolver`, `LedgerPostingEngine`, `update_account_balances`, `LedgerValidationError` | Backend Only |
| `accounting/auto_post.py` | ~1300 | Automated ledger posting for invoices, bills, payments, expenses | Backend Only |
| `accounting/report_services.py` | ~1900 | Report generation services (Balance Sheet, P&L, Trial Balance, Cash Book, Aging, etc.) | Backend Only |
| `accounting/period_lock.py` | ~100 | `validate_period_open` — blocks writes to locked accounting periods | Backend Only |
| `accounting/roll_forward.py` | ~230 | Year-end roll forward of opening balances and inventory | Backend Only |
| `accounting/reports.py` | ~340 | Helper functions for accounting reports | Backend Only |
| `accounting/cash_book_export.py` | ~180 | Cash book Excel/PDF export helpers | Backend Only |
| `taxation/services.py` | ~230 | `GSTEngine` — GST rate resolution, CGST/SGST/IGST split logic | Backend Only |
| `taxation/einvoice_service.py` | ~290 | E-Invoice generation and cancellation via NIC IRP | Backend Only |
| `taxation/eway_bill_service.py` | ~380 | e-Way Bill generation, cancellation, vehicle update via NIC portal | Backend Only |
| `taxation/hsn_directory.py` | ~630 | 4000+ HSN/SAC code descriptions (static lookup) | Backend Only |
| `taxation/gst_verify/service.py` | ~200 | GSTIN live verification captcha service | Backend Only |
| `company/services.py` | ~270 | `resolve_origin_state_code`, `NumberingSeriesService` | Backend Only |
| `auth/totp_service.py` | ~25 | TOTP 2FA — secret generation, QR code, verify | Backend Only |
| `printing/invoice_pdf.py` | ~3200 | PDF generation for all documents (invoice, bill, PO, SO, DC, proforma, GSTR reports, BS, P&L, etc.) | Backend Only |
| `scanning/invoice_scanner.py` | ~2600 | OCR scanning — PaddleOCR + Google Vision + LLM extraction | Backend Only |

---

## 6. Schemas (`src/schemas/`)

| File | LOC | Contents | Frontend Relevance |
|------|-----|---------|-------------------|
| `auth_schemas.py` | ~56 | `UserRegister`, `UserLogin`, `TokenResponse`, `UserResponse`, `TenantResponse` | **Critical** |
| `company_schemas.py` | ~125 | `CompanyCreate/Response`, `BranchCreate/Response`, `TenantSettingUpdate/Response`, `NumberingSeriesCreate/Response`, `GstToggleRequest` | **Critical** |
| `master_schemas.py` | ~190 | `ContactCreate/Update/Response`, `ProductCreate/Update/Response`, `AccountCreate/Response`, `BankingProfileCreate/Response`, `ExpenseCategoryCreate/Response`, `TaxTemplateResponse`, `PaymentTermResponse` | **Critical** |
| `document.py` | ~615 | `InvoiceCreate/Update/Response/List`, `CreditNote/DebitNote`, `SalesReturn/PurchaseReturn`, `RecurringInvoice`, `TermsTemplate`, `PaymentAllocation` schemas | **Critical** |
| `bill_schemas.py` | ~559 | `BillCreate/Update/Response`, `BillPayment`, `PurchaseOrder`, `SalesOrder`, `DeliveryChallan`, `ProformaInvoice`, `InventoryAdjustment`, `BankStatement/Transaction/Reconciliation` schemas | **Critical** |
| `payment_schemas.py` | ~103 | `PaymentCreate/Response/List`, `BillPaymentCreate/Response/List`, `PaymentAllocationCreate/Response` | **Critical** |
| `accounting_schemas.py` | ~166 | `JournalEntryCreate/Response`, `LedgerReportResponse`, `TrialBalanceResponse`, `ProfitLossResponse`, `BalanceSheetResponse`, `YearEndPrepareResponse`, `FinancialYearCreate/Response` | **Critical** |
| `expense_schemas.py` | ~86 | `ExpenseCreate/Update/Response/List`, `ExpensePreviewRequest/Response` | **Critical** |
| `gst_schemas.py` | ~149 | `GSTR1Response`, `GSTR2Response`, all GST line item schemas | **Critical** |
| `report_schemas.py` | ~370 | `BalanceSheetResponse`, `GSTR1Response`, `GSTR3BResponse`, `AgingReportResponse`, `CashFlowResponse`, `SalesAnalyticsResponse`, `PurchaseAnalyticsResponse`, `OutstandingAR/APResponse`, `PartyStatementResponse`, `TrialBalanceResponse`, `CashBookResponse` | **Critical** |
| `einvoice_schemas.py` | ~23 | `EInvoiceResponse`, `EInvoiceCancelRequest/Response` | **Important** |
| `eway_bill_schemas.py` | ~68 | `EWayBillCreate`, `EWayBillVehicleUpdate`, `EWayBillCancelRequest`, `EWayBillResponse`, `ConsolidatedEWayBillCreate/Response` | **Important** |

---

## 7. Infrastructure / Database (`src/infrastructure/database/`)

| File | LOC | Purpose | Frontend Relevance |
|------|-----|---------|-------------------|
| `models.py` | ~1922 | All 36 SQLAlchemy ORM models (all database tables) | **Critical** — defines every field the frontend displays or edits |
| `idempotency.py` | ~30 | `IdempotencyRecord` table for deduplication middleware | Backend Only |
| `mixins.py` | ~35 | `TimestampMixin` (created_at / updated_at) | Backend Only |

---

## 8. Workers (`src/workers/`)

| File | LOC | Purpose | Frontend Relevance |
|------|-----|---------|-------------------|
| `tasks.py` | ~530 | Celery tasks: `submit_e_invoice_to_irp`, `generate_invoice_pdf`, `send_invoice_email`, `send_overdue_invoice_reminders`, `send_gst_filing_alerts`, `generate_monthly_aging_report`, `cleanup_expired_invitations`, `send_daily_business_summary`, `run_ocr_scan` | **Important** — async operations triggered by frontend actions |

---

## 9. Common Utilities (`src/common/`)

| File | LOC | Purpose | Frontend Relevance |
|------|-----|---------|-------------------|
| `audit_log.py` | ~230 | Audit log writing, `set_audit_context` | Backend Only |
| `email_helper.py` | ~260 | SMTP email sender (invoices, password reset, reminders) | Backend Only |
| `events.py` | ~80 | Domain event bus | Backend Only |

---

## 10. Migrations & Scripts

| File | LOC | Purpose | Frontend Relevance |
|------|-----|---------|-------------------|
| `alembic/` | N/A | Database migration framework (Alembic) | Backend Only |
| `migrations/V001__rls_policies.sql` | ~640 | Row-Level Security policies for multi-tenancy | Backend Only |
| `scripts/scan_gst_config.py` | ~200 | Utility to inspect GST config | Backend Only |
| `scripts/analyze_vyb.py` | ~70 | Utility to inspect Vyapar backup | Backend Only |

---

## 11. Static Assets

| Path | Purpose | Frontend Relevance |
|------|---------|-------------------|
| `static/logos/` | Company logo images served at `/static/logos/<tenant_id>.ext` | **Critical** — displayed in invoice PDFs and app header |
| `static/logo.png` | Default logo | Optional |
| `assets/fonts/` | Fonts used in PDF generation | Backend Only |

---

## Summary Counts

| Category | Count |
|----------|-------|
| Routers (API files) | 30 |
| Domain service files | 16 |
| Schema files | 12 |
| Database model files | 3 |
| Core infrastructure files | 7 |
| Worker files | 1 |
| Common utility files | 3 |
| **Total backend source files** | **72** |
