# ApexBooks v1.0.0 — Release Notes

**Release Date:** 2026-06-26
**Branch:** master
**Tag:** v1.0.0

---

## Overview

ApexBooks is a multi-tenant accounting platform for Indian businesses with GST compliance, invoicing, and financial reporting.

---

## Features

### Core Accounting
- Double-entry bookkeeping engine
- Auto-posting on document creation
- Chart of accounts with auto-creation
- Journal entries (manual and automatic)
- Financial year management (open/close/lock)
- Year-end roll-forward with opening balance carry-forward

### Invoicing
- Sales invoices with GST (CGST/SGST/IGST/UTGST/Cess)
- Purchase bills with input tax credit
- Credit notes and debit notes
- Proforma invoices
- Sales orders and purchase orders
- Delivery challans
- Recurring invoices
- PDF generation with UPI QR codes

### GST Compliance
- GSTR-1 (outward supplies)
- GSTR-2 (inward supplies)
- GSTR-3B (monthly summary)
- GSTIN validation (format + checksum)
- E-Invoice integration (NIC IRP)
- E-Way Bill integration
- GST-inclusive/exclusive tax handling
- Reverse charge mechanism
- Composition dealer support

### Payments
- Customer receipts
- Vendor payments
- Multiple payment modes (Cash, Bank, UPI, POS)
- Payment allocation against invoices

### Reports
- Trial Balance
- Balance Sheet
- Profit & Loss
- Cash Flow Statement
- AR/AP Aging
- Outstanding Receivables/Payables
- Cash Book
- Party Statement
- Sales/Purchase Analytics
- All reports available in JSON, PDF, and Excel

### Security
- JWT authentication (access + refresh tokens)
- Role-based access control (Owner, Accountant, Salesperson, Auditor)
- Multi-tenant isolation with RLS
- Password strength enforcement
- Account lockout on failed attempts
- Audit logging

### Multi-tenancy
- Tenant-scoped data isolation
- PostgreSQL Row-Level Security
- Per-tenant configuration
- Numbering series per tenant

---

## Bug Fixes in This Release

- Fixed Balance Sheet PDF export (missing imports + data structure mismatch)
- Fixed Balance Sheet Excel export (missing imports)
- Fixed Expense Preview endpoint (missing gst_rate in response)
- Fixed GST registration auto-detection (tax_mode from GSTIN)

---

## Known Issues

| ID | Severity | Description |
|----|----------|-------------|
| KI-003 | Medium | `/api/v1/search` endpoint not registered |
| KI-004 | Medium | `GET /financial-years/{fy_id}` endpoint missing |
| KI-005 | Low | Pydantic deprecation warnings |

---

## Deployment

```bash
docker compose build
docker compose up -d
alembic upgrade head
```

---

## Environment Variables

See `.env.example` for required configuration.
