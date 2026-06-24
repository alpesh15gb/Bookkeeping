# PROJECT CONTEXT — ApexBooks
## Indian Accounting & GST Compliance Platform

**Last Updated:** 2026-06-25
**Branch:** master
**Latest Commit:** c658ae9 (fix: Auto-detect tax_mode from GSTIN during registration)

---

## Project Overview

- **Product:** ApexBooks — Multi-tenant accounting platform for Indian businesses
- **Purpose:** GST-compliant invoicing, accounting, expense tracking, and financial reporting
- **Target Users:** Indian SMBs needing GST invoicing, GSTR-1/2/3B filing, e-Invoicing, and double-entry bookkeeping
- **Current Stage:** Production (api.apexbooks.in live with 39 tenants)

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.12, FastAPI 0.110, Uvicorn 0.28 |
| Frontend | Vue.js (separate repo, deployed independently) |
| Mobile | Flutter 3.24 (separate repo, APK built via CI) |
| Database | PostgreSQL 15 (production), SQLite (local dev) |
| ORM | SQLAlchemy 2.0.28 |
| Migrations | Alembic 1.13.1 |
| Queue | Celery 5.3.6 + Redis 7 |
| Cache/Broker | Redis 7 |
| Auth | JWT (PyJWT 2.8), passlib+bcrypt, optional TOTP 2FA |
| PDF | ReportLab 4.1 |
| Excel | openpyxl 3.1 |
| OCR | PaddleOCR 3.0 (self-hosted) or Google Vision API |
| e-Invoice | NIC IRP sandbox integration |
| S3 | AWS S3 (ap-south-1) for document storage |
| Nginx | Reverse proxy with TLS, HSTS, rate limiting |
| CI/CD | GitHub Actions (test → SSH deploy → alembic upgrade) |

---

## Current Architecture

### Multi-Tenancy
Every tenant-scoped table has a `tenant_id` column (UUID, no FK for performance). Row-Level Security (RLS) policies enforce tenant isolation at the PostgreSQL level. The `X-Tenant-ID` header is forwarded by nginx and used by `enforce_permission()` to resolve the active tenant.

### Authentication Flow
1. User registers → creates User + Tenant + TenantMembership
2. Login returns JWT access_token (15min) + refresh_token (7 days)
3. Token carries user_id and role-based scopes
4. `enforce_permission("permission:name")` dependency checks scopes

### Auto-Posting
All financial documents (invoices, bills, expenses, credit/debit notes) are auto-posted to the ledger on creation. No manual DRAFT→POSTED step. Cancellation creates reversing journal entries.

### GST Engine
`GSTEngine.calculate_tax()` at `backend/src/domains/taxation/services.py` handles:
- Intra-state: CGST + SGST (or UTGST for union territories)
- Inter-state: IGST
- Reverse Charge Mechanism (RCM)
- GST-inclusive extraction
- Cess
- Odd-paise rounding

`GSTEngine.resolve_gst_rate()` auto-detects GST mode from tenant's GSTIN. Single source of truth helpers: `is_valid_gstin()`, `detect_tax_mode()`, `derive_origin_state_code()` at `backend/src/domains/company/services.py`.

### Accounting Engine
`LedgerPostingEngine` at `backend/src/domains/accounting/services.py` creates balanced journal entries. `AccountResolver` auto-creates accounts on first use (customer/vendor accounts, GST accounts, expense accounts). Chart of accounts is seeded per-tenant.

---

## Database Schema

### Auth & Tenancy
| Table | Purpose |
|-------|---------|
| `users` | User accounts (email, password_hash, 2FA) |
| `tenants` | Companies (legal_name, gstin, tax_mode, pan) |
| `tenant_memberships` | User↔Tenant with role (owner, accountant, salesperson, auditor) |
| `password_reset_tokens` | Password reset tokens |
| `tenant_invitations` | Pending user invitations |

### Master Data
| Table | Purpose |
|-------|---------|
| `contacts` | Customers and vendors (gstin, state_code, billing_address) |
| `products` | Products and services (hsn_sac, gst_rate, uom, stock) |
| `accounts` | Chart of accounts (code, type, group, parent) |
| `expense_categories` | Expense types linked to accounts |
| `banking_profiles` | Bank accounts |
| `numbering_series` | Auto-number sequences per document type |
| `tenant_settings` | Per-tenant config (currency, origin_state_code, e-invoicing) |
| `tax_templates` | Reusable tax configurations |
| `payment_terms` | Payment term definitions |
| `terms_templates` | Reusable T&C templates |

### Financial Documents
| Table | Purpose |
|-------|---------|
| `invoices` | Sales invoices (subtotal, cgst, sgst, igst, total, status) |
| `invoice_lines` | Line items with per-line tax breakdown |
| `bills` | Purchase invoices from vendors |
| `bill_lines` | Bill line items |
| `expenses` | Expense records with GST |
| `credit_notes` | Credit notes against invoices |
| `credit_note_lines` | Credit note line items |
| `debit_notes` | Debit notes against invoices |
| `debit_note_lines` | Debit note line items |
| `proforma_invoices` | Quotation/proforma documents |
| `proforma_invoice_lines` | Proforma line items |
| `sales_orders` | Sales order tracking |
| `sales_order_lines` | Sales order line items |
| `purchase_orders` | Purchase order tracking |
| `purchase_order_lines` | Purchase order line items |
| `delivery_challans` | Delivery challans |
| `delivery_challan_lines` | Challan line items |
| `recurring_invoices` | Recurring invoice templates |
| `recurring_invoice_items` | Recurring line items |
| `sales_returns` | Sales return documents |
| `sales_return_lines` | Return line items |
| `purchase_returns` | Purchase return documents |
| `purchase_return_lines` | Return line items |

### Accounting & Ledger
| Table | Purpose |
|-------|---------|
| `journal_entries` | Double-entry journal headers |
| `journal_lines` | Journal line items (amount + direction DEBIT/CREDIT) |
| `payments` | Customer receipts |
| `payment_allocations` | Payment↔Invoice links |
| `bill_payments` | Vendor payments |
| `bill_payment_allocations` | Bill payment↔Bill links |
| `financial_years` | Financial year periods with status (OPEN, CLOSING, LOCKED, ARCHIVED) |
| `financial_year_audits` | Year-end close audit trail |
| `accounting_periods` | Period lock management |
| `period_lock_audits` | Lock/unlock audit trail |
| `opening_balance_snapshots` | Year-end balance snapshots |
| `stock_ledger` | Inventory movement tracking |
| `bank_statements` | Imported bank statements |
| `bank_transactions` | Parsed bank transactions |
| `bank_reconciliations` | Reconciliation records |

### Compliance & Integration
| Table | Purpose |
|-------|---------|
| `gst_returns` | Filed GST return records |
| `eway_bills` | E-way bill records |
| `audit_logs` | All system events (action, before_state, after_state) |
| `idempotency_keys` | Duplicate request prevention |
| `webhook_events` | External webhook events |
| `inventory_adjustments` | Stock adjustments |
| `inventory_adjustment_lines` | Adjustment line items |
| `inventory_carry_forwards` | Stock carry-forward records |

---

## eSSL Connector

**Status:** NOT IMPLEMENTED — No eSSL/attendance integration exists in the codebase. This feature was mentioned in the handover request but has not been built.

---

## API Endpoints

### Auth (`/api/v1/auth`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/register` | Register user + tenant |
| POST | `/login` | Login, get JWT tokens |
| POST | `/refresh` | Refresh access token |
| POST | `/logout` | Invalidate refresh token |
| GET | `/me` | Current user info |
| GET | `/memberships` | User's tenant memberships |
| POST | `/change-password` | Change password |
| POST | `/forgot-password` | Request password reset |
| POST | `/reset-password` | Reset with token |
| POST | `/verify-email` | Verify email address |
| POST | `/2fa/enable` | Enable TOTP 2FA |
| POST | `/2fa/verify` | Verify TOTP code |
| POST | `/2fa/disable` | Disable TOTP 2FA |

### Companies (`/api/v1/companies`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/companies` | Create additional company |
| GET | `/companies/{id}` | Get company details |
| PUT | `/companies/{id}` | Update company |
| POST | `/companies/{id}/gst-toggle` | Toggle GST mode |
| GET | `/companies/{id}/settings` | Get tenant settings |
| PUT | `/companies/{id}/settings` | Update settings |
| POST | `/companies/{id}/numbering-series` | Create numbering series |
| GET | `/companies/{id}/numbering-series` | List numbering series |
| PUT | `/companies/{id}/numbering-series/{ns_id}` | Update series |
| POST | `/companies/{id}/branches` | Create branch |
| GET | `/companies/{id}/branches` | List branches |
| PUT | `/companies/{id}/branches/{branch_id}` | Update branch |

### Masters (`/api/v1/masters`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/contacts` | Create contact |
| GET | `/contacts` | List contacts |
| GET | `/contacts/{id}` | Get contact |
| PUT | `/contacts/{id}` | Update contact |
| DELETE | `/contacts/{id}` | Soft delete contact |
| POST | `/products` | Create product |
| GET | `/products` | List products |
| GET | `/products/{id}` | Get product |
| PUT | `/products/{id}` | Update product |
| DELETE | `/products/{id}` | Soft delete product |
| GET | `/accounts` | List chart of accounts |
| POST | `/accounts` | Create account |
| PUT | `/accounts/{id}` | Update account |
| DELETE | `/accounts/{id}` | Delete account |
| POST | `/banking-profiles` | Create bank profile |
| GET | `/banking-profiles` | List bank profiles |
| GET | `/expense-categories` | List expense categories |

### Invoices (`/api/v1/invoices`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/invoices` | Create invoice (auto-posts) |
| GET | `/invoices` | List invoices (paginated, filterable) |
| GET | `/invoices/stats` | Invoice statistics |
| POST | `/invoices/preview` | Preview without saving |
| GET | `/invoices/{id}` | Get invoice detail |
| PUT | `/invoices/{id}` | Update draft invoice |
| DELETE | `/invoices/{id}` | Soft delete draft |
| POST | `/invoices/{id}/finalize` | Finalize draft |
| POST | `/invoices/{id}/payment` | Record payment |
| POST | `/invoices/{id}/cancel` | Cancel with reversal |
| GET | `/invoices/{id}/pdf-payload` | PDF generation data |
| GET | `/invoices/{id}/print` | Print/view PDF |
| POST | `/invoices/{id}/clone` | Clone invoice |
| POST | `/invoices/{id}/e-invoice` | Generate e-Invoice |
| POST | `/invoices/{id}/e-invoice/cancel` | Cancel e-Invoice |
| POST | `/invoices/bulk-delete` | Bulk soft delete |
| POST | `/invoices/credit-notes` | Create credit note |
| POST | `/invoices/credit-notes/preview` | Preview credit note |
| GET | `/invoices/credit-notes` | List credit notes |
| GET | `/invoices/credit-notes/{id}` | Get credit note |
| POST | `/invoices/credit-notes/{id}/finalize` | Finalize credit note |
| POST | `/invoices/credit-notes/{id}/cancel` | Cancel credit note |
| DELETE | `/invoices/credit-notes/{id}` | Delete draft |
| POST | `/invoices/debit-notes` | Create debit note |
| POST | `/invoices/debit-notes/preview` | Preview debit note |
| GET | `/invoices/debit-notes` | List debit notes |
| GET | `/invoices/debit-notes/{id}` | Get debit note |
| POST | `/invoices/debit-notes/{id}/finalize` | Finalize debit note |
| POST | `/invoices/debit-notes/{id}/cancel` | Cancel debit note |
| DELETE | `/invoices/debit-notes/{id}` | Delete draft |

### Bills (`/api/v1/bills`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/bills` | Create vendor bill |
| GET | `/bills` | List bills |
| GET | `/bills/{id}` | Get bill detail |
| PUT | `/bills/{id}` | Update draft bill |
| DELETE | `/bills/{id}` | Soft delete |
| POST | `/bills/{id}/finalize` | Finalize draft |
| POST | `/bills/{id}/payment` | Record payment |
| POST | `/bills/{id}/cancel` | Cancel bill |
| POST | `/bills/bulk-delete` | Bulk delete |

### Expenses (`/api/v1/expenses`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/expenses` | Create expense |
| GET | `/expenses` | List expenses |
| GET | `/expenses/{id}` | Get expense detail |
| PUT | `/expenses/{id}` | Update draft expense |
| DELETE | `/expenses/{id}` | Soft delete |
| POST | `/expenses/{id}/post` | Post to ledger |
| POST | `/expenses/{id}/cancel` | Cancel expense |
| POST | `/expenses/bulk-delete` | Bulk delete |
| POST | `/expenses/preview` | Preview expense |

### Payments (`/api/v1/payments`)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/payments` | Record customer receipt |
| GET | `/payments` | List payments |
| GET | `/payments/{id}` | Get payment detail |
| DELETE | `/payments/{id}` | Delete payment |
| POST | `/disbursements` | Record vendor payment |
| GET | `/disbursements` | List disbursements |

### Reports (`/api/v1/reports`)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/trial-balance` | Trial balance as of date |
| GET | `/balance-sheet` | Balance sheet as of date |
| GET | `/profit-loss` → `/accounting/profit-loss` | P&L for period |
| GET | `/cash-flow` | Cash flow statement |
| GET | `/aging/{type}` | AR/AP aging |
| GET | `/outstanding/{type}` | Outstanding amounts |
| GET | `/gst/gstr1` | GSTR-1 report |
| GET | `/gst/gstr2` | GSTR-2 report |
| GET | `/gst/gstr3b/export` | GSTR-3B export |
| GET | `/gst/gstr1/export` | GSTR-1 Excel export |
| GET | `/gst/gstr1/pdf` | GSTR-1 PDF |
| GET | `/gst/gstr2/export` | GSTR-2 Excel export |
| GET | `/gst/gstr2/pdf` | GSTR-2 PDF |
| GET | `/gst/gstr3b/pdf` | GSTR-3B PDF |
| GET | `/cash-book` | Cash book report |
| Various | `*/excel` and `*/pdf` | Export endpoints for all reports |

### Accounting (`/api/v1/accounting`)
| Method | Path | Description |
|--------|------|-------------|
| GET | `/profit-loss` | Profit & Loss report |
| POST | `/journals` | Create manual journal |
| GET | `/journals` | List journal entries |
| POST | `/journals/{id}/reverse` | Reverse journal |
| GET | `/financial-years` | List financial years |
| POST | `/financial-years/{id}/close` | Close financial year |

### Other Endpoints
| Prefix | Key Endpoints |
|--------|--------------|
| `/api/v1/dashboard` | Metrics, revenue trend, expense trend |
| `/api/v1/proforma-invoices` | CRUD + finalize proforma invoices |
| `/api/v1/sales-orders` | CRUD sales orders |
| `/api/v1/purchase-orders` | CRUD purchase orders |
| `/api/v1/delivery-challans` | CRUD delivery challans |
| `/api/v1/recurring-invoices` | CRUD recurring invoice templates |
| `/api/v1/sales-returns` | CRUD sales returns |
| `/api/v1/purchase-returns` | CRUD purchase returns |
| `/api/v1/inventory` | Stock adjustments, inventory reports |
| `/api/v1/bank-reconciliation` | Bank statement import, reconciliation |
| `/api/v1/gst` | GSTIN validation, GSTR reports |
| `/api/v1/gst-verify` | GST portal verification |
| `/api/v1/gstr2a` | GSTR-2A reconciliation |
| `/api/v1/search` | Global search |

---

## Frontend Status

Frontend is a separate Vue.js application, not in this repository. It is deployed independently. The backend serves API endpoints only.

**Flutter mobile app** exists in a separate repo (`flutter_client/`). APK is built via `build-android.yml` CI workflow.

---

## Features Completed

- [x] Multi-tenant architecture with RLS
- [x] User registration, login, JWT auth, 2FA
- [x] Contact (customer/vendor) CRUD
- [x] Product/service CRUD with stock tracking
- [x] Chart of accounts with auto-creation
- [x] Sales invoice CRUD with GST (CGST/SGST/IGST/UTGST/Cess)
- [x] Invoice preview, clone, PDF generation
- [x] Credit notes and debit notes
- [x] Vendor bills with GST input tax
- [x] Expenses with GST
- [x] Customer receipts and vendor payments
- [x] Auto-posting to ledger on document creation
- [x] Journal entry creation and reversal
- [x] Financial year management (open/close/lock)
- [x] Period locking with audit trail
- [x] Year-end roll-forward
- [x] GST engine (intra/inter-state, RCM, inclusive, cess)
- [x] GSTR-1, GSTR-2, GSTR-3B report generation
- [x] GSTR Excel/PDF export for offline tool
- [x] E-Invoice integration (NIC IRP)
- [x] E-Way Bill integration
- [x] GSTIN validation (format + checksum)
- [x] GST toggle (NON_GST ↔ GST_REGULAR ↔ GST_COMPOSITION)
- [x] Registration auto-detects tax_mode from GSTIN
- [x] Proforma invoices
- [x] Sales orders, purchase orders
- [x] Delivery challans
- [x] Recurring invoices
- [x] Sales returns, purchase returns
- [x] Inventory adjustments with stock ledger
- [x] Bank statement import and reconciliation
- [x] Dashboard with metrics and trends
- [x] AR/AP aging reports
- [x] Balance sheet, P&L, cash flow, trial balance
- [x] Cash book report
- [x] OCR bill scanning (PaddleOCR / Google Vision)
- [x] Document upload to S3
- [x] UPI QR code generation on invoices
- [x] Multi-currency support
- [x] TDS/TCS on invoices and bills
- [x] Rate limiting (slowapi)
- [x] Audit logging (before/after state)
- [x] Idempotency keys
- [x] Password reset via email
- [x] Email notifications (overdue reminders, GST filing alerts)
- [x] Celery background tasks
- [x] CI/CD pipeline (GitHub Actions)

---

## Pending Work

### Critical
- [ ] Wait for CI/CD deployment of commit c658ae9 and verify tax_mode fix on production
- [ ] Run `scan_gst_config.py` periodically to catch configuration drift
- [ ] Address 5 Category B tenants with GST_REGULAR but no GSTIN (manual decision needed)

### High
- [ ] Add Sentry error tracking integration (SENTRY_DSN configured but not wired)
- [ ] Add comprehensive API rate limiting per tenant
- [ ] Add database connection pooling tuning for production load
- [ ] Add backup verification (automated restore testing)
- [ ] Add monitoring/alerting (Prometheus/Grafana or similar)

### Medium
- [ ] Implement eSSL/attendance connector (not started)
- [ ] Add TOTP 2FA enforcement option per tenant
- [ ] Add role-based dashboard customization
- [ ] Add batch import for invoices/bills from CSV/Excel
- [ ] Add customer/vendor portal (self-service invoice viewing)
- [ ] Add WhatsApp/SMS notifications
- [ ] Add multi-company consolidated reports
- [ ] Add budget tracking module
- [ ] Add fixed asset management

### Low
- [ ] Add API documentation (OpenAPI/Swagger auto-generation)
- [ ] Add GraphQL endpoint for flexible queries
- [ ] Add webhook support for external integrations
- [ ] Add data export/import utilities
- [ ] Add tenant-level feature flags

---

## Known Bugs

1. **GST toggle endpoint** (`companies.py:204-221`): When switching from NON_GST to GST_REGULAR, the `origin_state_code` auto-detection requires `tenant.gstin` to be set. If GSTIN was added after registration but before toggle, the origin_state_code may not be derived.

2. **Registration flow**: The `auth.py` fix (c658ae9) auto-detects `tax_mode` from GSTIN, but existing tenants created before this fix remain in `NON_GST` mode even if they have a GSTIN. The `GSTEngine.resolve_gst_rate()` auto-detection covers this at calculation time, but the `tax_mode` field in the database is inconsistent.

3. **Profit & Loss endpoint**: The P&L report is at `/api/v1/accounting/profit-loss`, not `/api/v1/reports/profit-loss`. The reports router does not include P&L directly.

---

## Design Decisions

### Why auto-posting instead of manual DRAFT→POSTED?
Eliminates a workflow step that users frequently forgot, causing "draft invoices" that were sent to customers but never posted to the ledger. Auto-posting ensures ledger consistency.

### Why `amount + direction` instead of `debit/credit` columns on journal_lines?
Single amount column with a direction enum prevents impossible states (both debit and credit > 0 on the same row). The check constraint `amount > 0` enforces positive amounts.

### Why soft-delete everywhere?
Indian GST law requires retaining financial records for 6 years. Hard deletes would violate compliance. Soft-delete via `deleted_at` column preserves audit trail.

### Why fallback origin_state_code = "36" (Telangana)?
Prevents HTTP 500 crashes when tenant has no GSTIN or origin_state_code configured. "36" is a safe default that allows the system to function. The `scan_gst_config.py` script catches these misconfigurations.

### Why `tenant_id` without FK constraint?
Performance optimization. Every query filters by `tenant_id`. FK constraint would add overhead on every INSERT/UPDATE. Referential integrity is enforced at the application level.

### Why Celery for background tasks?
E-Invoice submission, PDF generation, email sending, and OCR scanning are I/O-bound operations that would block the API. Celery with Redis provides reliable async processing with retries.

---

## Configuration

### Required Environment Variables
```
APP_ENV=production|development
DATABASE_URL=postgresql://postgres:PASSWORD@db:5432/bookkeeping
REDIS_URL=redis://redis:6379/0
JWT_SECRET_KEY=<32+ char secret>
SECRET_KEY=<32+ char secret>
ALLOWED_ORIGINS=https://apexbooks.in,https://api.apexbooks.in
SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD, EMAIL_FROM
S3_BUCKET, S3_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
IRP_BASE_URL, IRP_CLIENT_ID, IRP_CLIENT_SECRET, IRP_USERNAME, IRP_PASSWORD
```

### Docker Services
- `db` — PostgreSQL 15 (port 5432 internal)
- `redis` — Redis 7 (port 6379 internal)
- `backend` — FastAPI (port 8000)
- `worker` — Celery worker (concurrency=2)
- `frontend` — Nginx serving Vue.js (port 8080)

### Celery Beat Schedules
| Task | Schedule |
|------|----------|
| `send_overdue_invoice_reminders` | Daily 09:00 UTC |
| `send_gst_filing_alerts` | 10th/20th of month 10:00 UTC |
| `generate_monthly_aging_report` | 1st of month 02:00 UTC |
| `cleanup_expired_invitations` | Daily 03:00 UTC |
| `send_daily_business_summary` | Daily 21:00 UTC |

### Redis Usage
- Celery broker and result backend
- OCR scan result caching (10-minute TTL)
- Rate limiting counters (slowapi)
- Session/token blacklist (logout)

---

## Testing Status

### Test Files (39 files)
| File | Tests | Coverage |
|------|-------|----------|
| `test_registration_gst_flow.py` | 7 | Registration→GST lifecycle |
| `test_gst_toggle.py` | 4 | GST mode toggle |
| `test_gst_compliance.py` | 3 | GSTR-1/GSTR-2 compilation |
| `test_invoices.py` | 6 | GST engine, ledger posting |
| `test_premerge_verification.py` | 9 | Intra/inter-state, toggle |
| `test_invoicing_flow.py` | 6 | Invoice lifecycle |
| `test_bills.py` | 1 | Vendor bill flow |
| `test_expenses.py` | 17 | Expense CRUD + GST |
| `test_credit_debit_notes.py` | 17 | Credit/debit note lifecycle |
| `test_payments_flow.py` | 4 | Payment workflows |
| `test_reports.py` | 20+ | All report types |
| `test_accounting_flow.py` | 4 | Journal, ledger, trial balance |
| `test_company.py` | 6 | Company settings, numbering |
| `test_masters.py` | 6 | Contact/product CRUD |
| `test_auth.py` | 2 | Auth flow, RLS |
| `test_dashboard.py` | 9 | Dashboard metrics |
| `test_einvoice_flow.py` | 4 | E-Invoice lifecycle |
| `test_eway_bill_flow.py` | 4 | E-Way Bill lifecycle |
| `test_proforma_invoices.py` | 2 | Proforma invoice |
| `test_sales_orders.py` | ~2 | Sales orders |
| `test_purchase_orders.py` | ~2 | Purchase orders |
| `test_delivery_challans.py` | ~2 | Delivery challans |
| `test_recurring_invoices.py` | 3 | Recurring invoices |
| `test_sales.py` | ~2 | Sales returns |
| `test_bank_reconciliation.py` | 2 | Bank reconciliation |
| `test_inventory_adjustments.py` | 2 | Inventory adjustments |
| `test_year_end.py` + `test_year_end_e2e.py` | ~4 | Year-end close |
| `test_financial_year_status.py` | 1 | FY status |
| `test_audit_logging.py` | 2 | Audit trail |
| `test_db_constraints.py` | 4 | DB constraints |
| `test_api_contract_validation.py` | ~15 | API contract |
| `test_terms_templates.py` | ~2 | Terms templates |
| `integration/test_auth_router.py` | 9 | Auth integration |
| `integration/test_accounts_crud.py` | 19 | Account CRUD |
| `unit/test_accounting_service.py` | ~3 | Accounting unit |
| `unit/test_auth_service.py` | ~3 | Auth unit |
| `unit/test_invoice_scanner.py` | ~3 | OCR scanner |

### Pending Tests
- [ ] Load/stress testing (no k6/locust scripts)
- [ ] E2E browser tests (no Playwright/Cypress)
- [ ] Mobile app tests
- [ ] Production smoke test automation

---

## Next Development Session

1. **Verify CI/CD deployment** — Check GitHub Actions for commit c658ae9 deployment status
2. **Re-run production smoke test** — `python smoke_test.py` should show 28/28 after deployment
3. **Run production scanner** — `docker compose exec -T backend python /tmp/scan_gst_config.py` to verify all Category A/B issues are resolved
4. **Clean up smoke test data** — Delete test tenants created during verification
5. **Address 5 Category B tenants** — Decision needed: add GSTIN or revert to NON_GST
6. **Sentry integration** — Wire `SENTRY_DSN` into FastAPI and Celery error handlers

---

## Resume Instructions

When continuing development:
1. Read this file completely
2. Check `git log --oneline -10` for latest changes
3. Run `python -m pytest -n0 --tb=short` to verify test suite
4. Continue from "Next Development Session" section
5. Never rebuild completed functionality
6. Preserve existing architecture unless a defect is found
