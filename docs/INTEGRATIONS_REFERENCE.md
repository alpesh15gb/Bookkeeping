# ApexBooks — Integrations Reference

---

## 1. NIC IRP — e-Invoice (Invoice Registration Portal)

**Service:** National Informatics Centre IRP for e-Invoice generation under GST  
**Backend file:** `src/domains/taxation/einvoice_service.py`  
**Configuration:**

| Env Variable | Purpose |
|-------------|---------|
| `IRP_BASE_URL` | IRP endpoint (default: `https://einvoice1-sandbox.nic.in` — sandbox) |
| `IRP_CLIENT_ID` | API client ID from NIC portal |
| `IRP_CLIENT_SECRET` | API client secret |
| `IRP_USERNAME` | Taxpayer GSTIN login |
| `IRP_PASSWORD` | Taxpayer password |

**Production URL:** `https://einvoice1.nic.in`  
**Sandbox URL:** `https://einvoice1-sandbox.nic.in` (default for dev)

**Flow:**
1. Frontend calls `POST /invoices/{id}/e-invoice`
2. Backend authenticates with IRP using stored credentials
3. Constructs JSON payload per e-Invoice schema (IRN, QR, Ack)
4. Returns IRN and QR code to frontend
5. QR code is displayed on printed invoice PDF

**Celery task:** `tasks.submit_e_invoice_to_irp` — submitted async with 3 retries (60s delay)

**Error codes from IRP:**
- `2150` — GSTIN not found / inactive
- `2260` — Duplicate IRN
- `4004` — Authentication failed
- `4005` — Invalid JSON schema

**Frontend impact:** Show e-Invoice status (`PENDING`, `GENERATED`, `CANCELLED`, `FAILED`) on invoice detail page.

---

## 2. NIC e-Way Bill Portal

**Service:** NIC e-Way Bill generation for goods transport  
**Backend file:** `src/domains/taxation/eway_bill_service.py`  
**Configuration:**

| Env Variable | Purpose |
|-------------|---------|
| `IRP_BASE_URL` | Same as e-Invoice (NIC uses unified portal) |
| Tenant setting: `e_way_bill_username` | Portal username |
| Tenant setting: `e_way_bill_password_hash` | Encrypted password |

**Features:**
- Generate e-Way Bill for outward/inward supply
- Cancel within 24 hours
- Update vehicle number (transhipment / breakdown)
- Generate consolidated e-Way Bill for multiple consignments

**Validity:** Auto-calculated by NIC based on distance (1 day per 200 km for normal cargo)

**Frontend impact:**
- Show e-Way Bill number on invoice/bill after generation
- Show `valid_until` timestamp
- Surface a "Consolidate" option for multi-consignment transport

---

## 3. GST Verification API

**Service:** Third-party GSTIN live verification  
**Backend file:** `src/domains/taxation/gst_verify/service.py`  
**Provider:** `gstverify.dubey.app`

**Configuration:**
| Env Variable | Purpose |
|-------------|---------|
| `GST_VERIFY_API_KEY` | API key (if empty, verification fails with 502) |
| `GST_VERIFY_BASE_URL` | `https://api.gstverify.dubey.app` |

**Flow:**
1. `GET /gst/verify/captcha` — Frontend gets captcha image + session_id
2. User solves captcha
3. `POST /gst/verify` — Sends GSTIN + captcha + session_id
4. Returns taxpayer details (name, address, status, e-invoice eligibility)

**Use case:** Validate vendor/customer GSTIN before creating a contact.

---

## 4. OCR — PaddleOCR

**Service:** Open-source OCR for bill scanning  
**Backend file:** `src/domains/scanning/invoice_scanner.py`  
**Config:** `OCR_ENGINE=paddleocr` (default)

**What it does:**
- Extracts text from uploaded bill images/PDFs
- Parses vendor name, GSTIN, invoice number, date, amounts, line items
- Matches vendor to existing contacts by GSTIN or name
- Matches products by name or HSN code

**No API key required.** Runs locally on server.

**Latency:** 3–10 seconds per image (CPU-bound)

---

## 5. OCR — Google Cloud Vision

**Service:** Google Cloud Vision API for higher accuracy OCR  
**Config:** `OCR_ENGINE=google_vision` + `GOOGLE_VISION_API_KEY`

**Latency:** 1–3 seconds per image  
**Cost:** ~$1.50 per 1000 images (Google Vision pricing)

**When to use:** Production environments requiring high accuracy.

---

## 6. OCR — Nvidia NIM (LLM Vision)

**Service:** Nvidia NIM inference API with LLaMA 3.2 Vision for intelligent extraction  
**Config:** `NVIDIA_NIM_API_KEY` + `NVIDIA_NIM_MODEL=meta/llama-3.2-11b-vision-instruct`

**Latency:** 5–15 seconds per image  
**Accuracy:** Highest — understands context, handles complex layouts  
**Cost:** Per API call to Nvidia

**When to use:** Complex bills, handwritten items, unusual formats.

---

## 7. Email / SMTP

**Service:** Invoice emailing, password reset, overdue reminders  
**Backend file:** `src/common/email_helper.py`  
**Celery task:** `tasks.send_invoice_email`

**Configuration:**
| Env Variable | Purpose |
|-------------|---------|
| `SMTP_HOST` | SMTP server (e.g. `smtp.sendgrid.net`) |
| `SMTP_PORT` | Default 587 (TLS) |
| `SMTP_USER` | SMTP username |
| `SMTP_PASSWORD` | SMTP password |
| `EMAIL_FROM` | Sender address |

**Email types sent by system:**
| Trigger | Template |
|---------|---------|
| `POST /invoices/{id}/email` | Invoice PDF attachment |
| `POST /auth/forgot-password` | Password reset link |
| `POST /auth/register` | Email verification link |
| Celery daily task | Overdue invoice reminders |
| Celery daily task | GST filing deadline alerts |
| Celery monthly task | Aging report summary |
| Celery daily task | Daily business summary |
| `POST /purge/request` | OTP for data purge |

**Frontend impact:**
- Show email status feedback after `POST /invoices/{id}/email`
- Response: `{"detail": "Invoice email queued to customer@example.com."}`
- Email is queued via Celery; delivery is async (no callback to frontend)

---

## 8. Redis

**Purpose:** Refresh token revocation store + rate limiter backend + Celery broker/backend  
**Config:** `REDIS_URL=redis://localhost:6379/0`

**Frontend impact:** None directly. Redis being down causes:
- Token refresh to fail (all users logged out)
- Rate limiter to potentially fail open or error
- Background tasks to not run

---

## 9. Celery (Background Job Queue)

**Celery beat schedule** (from `tasks.py`):

| Task | Schedule | Purpose |
|------|---------|---------|
| `send_overdue_invoice_reminders` | Daily 9 AM IST | Email overdue reminders to customers |
| `send_gst_filing_alerts` | Monthly (10th) | Alert about upcoming GSTR filing deadline |
| `generate_monthly_aging_report` | Monthly (1st) | Email aging report to owners |
| `cleanup_expired_invitations` | Daily midnight | Mark expired invitations as EXPIRED |
| `send_daily_business_summary` | Daily 9 PM IST | Email daily summary to owners |

**Triggered by API calls:**
| Task | Trigger |
|------|---------|
| `submit_e_invoice_to_irp` | `POST /invoices/{id}/e-invoice` |
| `generate_invoice_pdf` | Scheduled after invoice finalization |
| `send_invoice_email` | `POST /invoices/{id}/email` |
| `run_ocr_scan` | `POST /bills/scan/preview` |

---

## 10. Sentry (Error Monitoring)

**Config:** `SENTRY_DSN`  
**Backend file:** `src/core/sentry.py`

If `SENTRY_DSN` is set, all unhandled exceptions are reported to Sentry with full context.

**Frontend:** No direct integration. Frontend teams should set up their own Sentry project separately.

---

## 11. S3-Compatible Storage (Partial Implementation)

**Config:** `S3_BUCKET`, `S3_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

Currently configured but **not actively used** for file storage. Logos are stored on local filesystem. The S3 integration exists in `tasks.generate_invoice_pdf` for uploading generated PDFs, but may not be fully wired in the current codebase.

---

## 12. WhatsApp / SMS

**Status:** Not implemented. No integration exists.  
**Workaround:** Use email (`POST /invoices/{id}/email`) for customer communication.

---

## 13. Payment Gateway

**Status:** Not implemented. No payment gateway integration.  
**Current approach:** Record payments manually via `POST /payments/receipts`.

---

## 14. Banking API (Account Aggregator)

**Status:** Not implemented. Bank statements are uploaded manually as CSV/Excel.  
**Future:** Could integrate with AA (Account Aggregator) framework or Finvu/Setu for auto-fetching statements.

---

## 15. GST Portal (Direct Filing)

**Status:** Not implemented. Reports are generated as Excel/JSON for manual upload to GST portal.  
**No direct GSTR filing API** is integrated. The GSTR-1 Excel is compatible with the GST Offline Tool.

---

## Integration Status Summary

| Integration | Status | Notes |
|------------|--------|-------|
| NIC IRP (e-Invoice) | ✅ Implemented | Sandbox by default; requires production credentials |
| NIC e-Way Bill | ✅ Implemented | Requires portal credentials in settings |
| GST GSTIN Verify | ✅ Implemented | Requires API key |
| PaddleOCR (bill scan) | ✅ Implemented | Local, no key needed |
| Google Vision OCR | ✅ Implemented | Requires API key |
| Nvidia NIM OCR | ✅ Implemented | Requires API key |
| Email (SMTP) | ✅ Implemented | Requires SMTP config |
| Celery / Redis | ✅ Implemented | Requires Redis server |
| Sentry | ✅ Implemented | Requires DSN |
| S3 Storage | ⚠️ Partial | Config present, not fully wired |
| WhatsApp | ❌ Not implemented | — |
| SMS | ❌ Not implemented | — |
| Payment Gateway | ❌ Not implemented | — |
| Banking API / AA | ❌ Not implemented | — |
| GST Portal Direct Filing | ❌ Not implemented | Manual upload only |
