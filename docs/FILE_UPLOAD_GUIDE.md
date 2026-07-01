# ApexBooks — File Upload Guide

---

## 1. Company Logo Upload

### POST `/settings/logo`
**Permission:** `settings:update`  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`

**Allowed formats:** `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`  
**Max size:** 5 MB (5,242,880 bytes)

**Response:**
```json
{
  "logo_url": "/static/logos/tenant-uuid.png",
  "detail": "Logo uploaded successfully"
}
```

**Storage location:** `static/logos/<tenant_id>.<ext>` on the server filesystem  
**Public URL:** Served at `https://api.apexbooks.in/static/logos/<tenant_id>.png`  
**Reference:** Stored in `tenant_settings.logo_url`

**Frontend usage:**
- Display in app header / sidebar
- Shown on all printed PDF documents (invoices, bills, etc.)
- Update `tenant_settings` after upload to persist the URL

**Error responses:**
```json
{"detail": "File type .bmp is not allowed. Allowed: .png, .jpg, .jpeg, .gif, .webp"}
{"detail": "File size 6291456 bytes exceeds the maximum allowed 5242880 bytes."}
```

---

## 2. OCR Bill Scanning (Async — Recommended)

### Step 1: POST `/bills/scan/preview`
**Permission:** `bill:create`  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`  
**Query params:** `confidence` (float, 0–1, default 0.7)

**Allowed formats:** `.jpg`, `.jpeg`, `.png`, `.tiff`, `.bmp`, `.webp`, `.pdf`  
**Max size:** 15 MB (15,728,640 bytes)

**Response:**
```json
{
  "job_id": "uuid-for-polling",
  "status": "queued"
}
```

### Step 2: GET `/bills/scan/status?job_id={job_id}`
**Permission:** `bill:create`

**Poll this endpoint every 2–3 seconds until `status = "done"` or `status = "failed"`.**

**Response when done:**
```json
{
  "job_id": "uuid",
  "status": "done",
  "vendor_name": "ABC Suppliers",
  "vendor_gstin": "29AABCT1332L1ZP",
  "invoice_number": "SUPP-2025-001",
  "invoice_date": "2025-04-10",
  "due_date": null,
  "total_amount": "11800.00",
  "taxable_amount": "10000.00",
  "cgst_amount": "900.00",
  "sgst_amount": "900.00",
  "igst_amount": "0.00",
  "line_items": [
    {
      "description": "Steel Pipes",
      "hsn_sac": "73063090",
      "quantity": "50.00",
      "rate": "200.00",
      "gst_rate": "18.00",
      "amount": "10000.00",
      "product_id": "uuid-if-matched",
      "product_name": "Steel Pipe 1 inch"
    }
  ],
  "contact_id": "uuid-if-matched",
  "confidence": 0.85
}
```

**Response when queued/processing:**
```json
{
  "job_id": "uuid",
  "status": "processing"
}
```

**Response when failed:**
```json
{
  "job_id": "uuid",
  "status": "failed",
  "error": "Could not extract text from image."
}
```

### Step 3: POST `/bills/scan/save`
**Permission:** `bill:create`  
**Content-Type:** `application/json`  

User reviews extracted data, makes corrections, then submits to save as a bill.

**Request body:** Standard `BillCreate` JSON (see REQUEST_RESPONSE_REFERENCE.md)

**Response:** `BillResponse` with status `DRAFT`

---

## 3. OCR Bill Scanning (Synchronous — Direct)

### POST `/bills/scan`
**Permission:** `bill:create`  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`  

**Same file constraints as async scan.**

**Blocks until OCR completes (may take 5–30 seconds depending on engine).**

**Response:** Same structure as async `status=done` response.

**When to use sync vs async:**
- **Async (preview + status):** Recommended for production UI — better UX, non-blocking
- **Sync (scan):** Quick scripts, testing, or when polling is inconvenient

---

## 4. Bank Statement Upload

### POST `/bank-reconciliation/upload`
**Permission:** `payment:create`  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`

**Allowed formats:** CSV (`.csv`), Excel (`.xlsx`, `.xls`)  
**Max size:** Not explicitly limited (reasonable limit: 10 MB recommended)

**Query parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `banking_profile_id` | UUID | Required | Bank account to associate statement with |
| `bank_format` | string | `AUTO` | Bank CSV format: `HDFC`, `ICICI`, `SBI`, `AXIS`, `KOTAK`, `YES`, `GENERIC` |

**Auto-detected formats (from column headers):**
- HDFC: `Date`, `Narration`, `Value Date`, `Debit Amount`, `Credit Amount`
- ICICI: `Transaction Date`, `Transaction Remarks`, `Debit Amount(INR)`, `Credit Amount(INR)`
- SBI: `Txn Date`, `Description`, `Debit`, `Credit`
- Generic: Attempts to find any date, description, debit, credit columns

**Response:**
```json
{
  "statement_id": "uuid",
  "banking_profile_id": "uuid",
  "transactions_parsed": 150,
  "date_range": {
    "from": "2025-04-01",
    "to": "2025-04-30"
  },
  "opening_balance": "50000.00",
  "closing_balance": "125000.00"
}
```

**Error responses:**
```json
{"detail": "Could not detect date column in the CSV file."}
{"detail": "No transactions found in the uploaded file."}
{"detail": "File format not supported. Upload CSV or Excel."}
```

---

## 5. GSTR-2A Upload

### POST `/gst/gstr2a/upload`
**Permission:** `gst:filing_manage`  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`  
**Accepted format:** JSON only (from GST portal)

**No size limit documented.** Typical GSTR-2A files are 50KB–2MB.

**See GST_API_REFERENCE.md for response structure.**

---

## 6. Tally XML Import

### POST `/tally/import`
**Permission:** `data:import` (**BROKEN** — no role has this permission. See MISSING_APIS.md)  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`  
**Accepted format:** `.xml`

---

## 7. Vyapar Backup Import

### POST `/import/vyapar`
**Permission:** `tenant:update`  
**Content-Type:** `multipart/form-data`  
**Form field:** `file`  
**Accepted format:** `.vyb`

**No explicit size limit** but files > 50 MB may time out. Default timeout is 5 minutes.

---

## 8. JSON Data Import (Backup Restore)

### POST `/companies/{tenant_id}/import`
**Permission:** `tenant:update`  
**Content-Type:** `application/json` (raw JSON body, NOT multipart)

**See IMPORT_EXPORT_GUIDE.md for full structure.**

---

## 9. General File Upload Guidelines

| Rule | Detail |
|------|--------|
| Authentication | Always include `Authorization: Bearer <token>` + `X-Tenant-ID` headers |
| Content-Type | `multipart/form-data` for all file uploads (except JSON import which is `application/json`) |
| Field name | Always `file` (unless documented otherwise) |
| Error format | HTTP 400 with `{"detail": "..."}`  |
| Max logo size | 5 MB |
| Max bill scan size | 15 MB |
| Allowed logo formats | PNG, JPG, JPEG, GIF, WEBP |
| Allowed bill scan formats | JPG, JPEG, PNG, TIFF, BMP, WEBP, PDF |
| Allowed bank statement formats | CSV, XLSX, XLS |

---

## 10. OCR Engine Configuration

The OCR engine is configured server-side via `OCR_ENGINE` environment variable:

| Engine | Config | Speed | Accuracy | Cost |
|--------|--------|-------|----------|------|
| `paddleocr` | Default | Medium | Good | Free |
| `google_vision` | Requires `GOOGLE_VISION_API_KEY` | Fast (1–3s) | Excellent | Pay per use |
| LLM (Nvidia NIM) | Requires `NVIDIA_NIM_API_KEY` | Slow (5–10s) | Very High | Pay per use |

The frontend cannot switch OCR engines — this is a server configuration.

---

## 11. File Storage

All uploaded logos are stored on the **local filesystem** of the server at `static/logos/`. In production with multiple servers, this must be replicated or replaced with S3-compatible storage.

S3 configuration (for future): `S3_BUCKET`, `S3_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` are in config but not actively used for logo storage currently.

Scanned bill files are **not stored** — they are processed in memory and discarded.
