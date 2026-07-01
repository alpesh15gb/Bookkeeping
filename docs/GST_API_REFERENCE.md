# ApexBooks — GST API Reference
> Covers GSTIN validation, GSTR-1, GSTR-2, GSTR-3B, GSTR-2A reconciliation, HSN/SAC lookup, e-Invoice, e-Way Bill.

---

## 1. GSTIN Format Validation

### GET `/gst/validate-gstin/{gstin}`
**Auth:** None required  
**Purpose:** Validate GSTIN format (15 chars, checksum) without a live API call.

**Response (valid):**
```json
{
  "valid": true,
  "state_code": "27"
}
```
**Response (invalid):**
```json
{
  "valid": false,
  "detail": "Invalid GSTIN format."
}
```

---

## 2. Live GSTIN Verification (via GST portal captcha)

### GET `/gst/verify/captcha`
**Permission:** `contact:create`  
**Purpose:** Fetch a captcha image from the GST portal for GSTIN verification.

**Response:**
```json
{
  "session_id": "abc123-session-id",
  "image": "base64-encoded-png-string"
}
```

### POST `/gst/verify`
**Permission:** `contact:create`

**Request:**
```json
{
  "gstin": "27AABCE1234F1Z5",
  "captcha": "AB12",
  "session_id": "abc123-session-id"
}
```
**Validation:**
- `gstin`: exactly 15 characters

**Response:**
```json
{
  "gstin": "27AABCE1234F1Z5",
  "legal_name": "Rajesh Enterprises Private Limited",
  "trade_name": "Rajesh Enterprises",
  "status": "Active",
  "registration_date": "2018-07-01",
  "business_type": "Private Limited Company",
  "taxpayer_type": "Regular",
  "address": "123 MG Road, Andheri East, Mumbai, Maharashtra 400069",
  "state_code": "27",
  "nature_of_business": ["Wholesale Business", "Retail Business"],
  "is_field_visit": "No",
  "e_invoice_status": "Yes"
}
```
**Error 502:** GST portal unreachable or invalid captcha.

---

## 3. GSTR-1 (Outward Supplies)

### GET `/gst/gstr1`
**Permission:** `gst:report_view`  
**Also available at:** `GET /reports/gstr1`

**Query Parameters:**
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `start_date` | YYYY-MM-DD | Yes | Period start |
| `end_date` | YYYY-MM-DD | Yes | Period end |

**Response:**
```json
{
  "b2b": [
    {
      "customer_name": "Rajesh Enterprises",
      "gstin": "27AABCE1234F1Z5",
      "invoice_number": "INV-2025-0001",
      "invoice_date": "2025-04-15",
      "pos_state_code": "27",
      "supply_type": "INTRA",
      "taxable_value": "2500.00",
      "cgst_amount": "225.00",
      "sgst_amount": "225.00",
      "igst_amount": "0.00",
      "cess_amount": "0.00",
      "total_value": "2950.00"
    }
  ],
  "b2c_large": [
    {
      "invoice_number": "INV-2025-0002",
      "invoice_date": "2025-04-16",
      "pos_state_code": "29",
      "taxable_value": "300000.00",
      "igst_amount": "54000.00",
      "total_value": "354000.00"
    }
  ],
  "b2c_small": [
    {
      "pos_state_code": "27",
      "gst_rate": "18.00",
      "taxable_value": "50000.00",
      "cgst_amount": "4500.00",
      "sgst_amount": "4500.00",
      "igst_amount": "0.00",
      "cess_amount": "0.00"
    }
  ],
  "credit_debit_notes": [],
  "hsn_summary": [
    {
      "hsn_sac": "73063090",
      "description": "Steel pipes",
      "uom": "MTR",
      "quantity": "100.00",
      "taxable_value": "25000.00",
      "cgst_amount": "2250.00",
      "sgst_amount": "2250.00",
      "igst_amount": "0.00",
      "cess_amount": "0.00"
    }
  ]
}
```

### GSTR-1 Classification Rules

| Supply Type | Criteria | Table |
|-------------|---------|-------|
| B2B | Customer has GSTIN | `b2b` |
| B2CL | No GSTIN, Inter-state, Invoice > ₹2.5 Lakh | `b2c_large` |
| B2CS | No GSTIN, Intra-state OR Inter-state ≤ ₹2.5 Lakh | `b2c_small` (grouped) |
| Export | `supply_type` = EXPORT_* | `exports` |
| Credit Notes | CN on B2B invoices | `credit_debit_notes` |
| Debit Notes | DN on B2B invoices | `credit_debit_notes` |

### GET `/gst/gstr1/export` — Excel for GST Offline Tool
**Query Parameters:** Same as `/gst/gstr1`  
**Response:** `.xlsx` file download  
**Content-Disposition:** `attachment; filename=GSTR1_YYYY-MM-DD_YYYY-MM-DD.xlsx`  
**Sheets in Excel:** B2B, B2CL, B2CS, CDNR, HSN, Summary

### GET `/gst/gstr1/pdf`
**Response:** PDF file download

---

## 4. GSTR-2 (Inward Supplies / Purchases)

### GET `/gst/gstr2`
**Permission:** `gst:report_view`  
**Also available at:** `GET /reports/gstr2`

**Query Parameters:** `start_date`, `end_date`

**Response:**
```json
{
  "b2b_purchases": [
    {
      "vendor_name": "ABC Traders",
      "gstin": "29AABCT1332L1ZP",
      "invoice_number": "VB-2025-001",
      "invoice_date": "2025-04-10",
      "pos_state_code": "27",
      "taxable_value": "10000.00",
      "cgst_amount": "900.00",
      "sgst_amount": "900.00",
      "igst_amount": "0.00",
      "cess_amount": "0.00",
      "total_value": "11800.00",
      "itc_eligible": true
    }
  ],
  "b2bur_purchases": [],
  "credit_debit_notes": [],
  "hsn_summary": [...]
}
```

### GET `/gst/gstr2/export` — Excel
### GET `/gst/gstr2/pdf` — PDF

---

## 5. GSTR-3B (Monthly Summary Return)

### GET `/gst/gstr3b/export`
**Permission:** `gst:report_view`  
**Also available at:** `GET /reports/gstr3b`

**Query Parameters:** `start_date`, `end_date`

**Response (JSON — also via `/reports/gstr3b`):**
```json
{
  "period_start": "2025-04-01",
  "period_end": "2025-04-30",
  "outward_taxable": {
    "taxable_value": "500000.00",
    "igst": "50000.00",
    "cgst": "25000.00",
    "sgst": "25000.00",
    "cess": "0.00"
  },
  "outward_zero_rated": {
    "taxable_value": "0.00",
    "igst": "0.00",
    "cgst": "0.00",
    "sgst": "0.00",
    "cess": "0.00"
  },
  "itc_available": {
    "igst": "10000.00",
    "cgst": "5000.00",
    "sgst": "5000.00",
    "cess": "0.00"
  },
  "net_tax_payable_igst": "40000.00",
  "net_tax_payable_cgst": "20000.00",
  "net_tax_payable_sgst": "20000.00",
  "net_tax_payable_cess": "0.00"
}
```

**GSTR-3B Excel Export:** `GET /gst/gstr3b/export?start_date=...&end_date=...`  
**GSTR-3B PDF:** `GET /gst/gstr3b/pdf?start_date=...&end_date=...`

---

## 6. GSTR-2A Reconciliation (Upload from GST Portal)

### POST `/gst/gstr2a/upload`
**Permission:** `gst:filing_manage`  
**Content-Type:** `multipart/form-data`  
**File:** JSON file downloaded from GST portal (GSTR-2A)  
**Allowed format:** JSON only

**Response:**
```json
{
  "total_suppliers": 15,
  "matched": 12,
  "unmatched": 2,
  "partially_matched": 1,
  "matches": [
    {
      "gstr2a_invoice": "VB-2025-001",
      "our_bill_number": "VB-2025-001",
      "supplier_gstin": "29AABCT1332L1ZP",
      "match_status": "FULL",
      "gstr2a_value": "11800.00",
      "our_bill_value": "11800.00"
    }
  ],
  "unmatched_items": [
    {
      "supplier_gstin": "33XYZAB5678C1Z2",
      "supplier_name": "Unknown Vendor",
      "invoice_number": "SUPP-2025-009",
      "invoice_date": "2025-04-12",
      "invoice_value": "5900.00",
      "taxable_value": "5000.00",
      "igst": "0.00",
      "cgst": "450.00",
      "sgst": "450.00",
      "cess": "0.00"
    }
  ]
}
```

---

## 7. HSN / SAC Code Lookup

### GET `/gst/hsn/{hsn_code}`
**Permission:** `invoice:create`  
**`hsn_code`:** 6–8 digit numeric string

**Response:**
```json
{
  "hsn_code": "73063090",
  "description": "Other tubes, pipes and hollow profiles (e.g. open seam or welded, riveted or similarly closed) of iron or steel"
}
```
**Error 400:** Code not 6–8 digits.  
**Error 404:** Code not found in directory.

---

## 8. e-Invoice (IRP Integration)

### POST `/invoices/{id}/e-invoice`
**Permission:** `invoice:finalize`  
**Prerequisite:** Invoice must be in POSTED status.  
**Requires `e_invoicing_enabled = true` in tenant settings.**

**Triggers:** Async Celery task `submit_e_invoice_to_irp`

**Response:**
```json
{
  "invoice_id": "uuid",
  "irn": "a5c12b3d4e5f...64 hex characters",
  "qr_code": "base64-encoded-qr-data",
  "e_invoice_status": "GENERATED",
  "ack_number": "112233445566",
  "ack_date": "2025-04-15T10:30:00+00:00"
}
```

**Error cases:**
- Invoice not POSTED → HTTP 400
- e-invoicing not enabled → HTTP 400 `{"detail": "e-Invoicing is not enabled for this company."}`
- NIC IRP error → HTTP 502 with IRP error message

### POST `/invoices/{id}/e-invoice/cancel`
**Request:**
```json
{
  "cancel_reason": "1",
  "cancel_remarks": "Duplicate invoice"
}
```
`cancel_reason` values:
- `"1"` — Duplicate
- `"2"` — Data entry mistake
- `"3"` — Order cancelled
- `"4"` — Other

**Response:**
```json
{
  "invoice_id": "uuid",
  "e_invoice_status": "CANCELLED",
  "cancel_date": "2025-04-16T09:00:00+00:00"
}
```
**Constraint:** Must cancel within 24 hours of IRN generation.

---

## 9. e-Way Bill

### POST `/eway-bills`
**Permission:** `invoice:finalize`

**Required fields:**
| Field | Type | Description |
|-------|------|-------------|
| `invoice_id` | UUID | Source invoice |
| `supply_type` | string | `OUTWARD` or `INWARD` |
| `sub_supply_type` | string | `SUPPLY`, `IMPORT`, `EXPORT`, `JOB_WORK`, `SEZ`, `LINE_SALES`, `OTHER` |
| `trans_mode` | string | `ROAD`, `RAIL`, `AIR`, `SHIP` |
| `trans_distance` | int | 1–4000 km |
| `vehicle_number` | string | Pattern: `^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$` |
| `vehicle_type` | string | `REGULAR` or `ODC` |

**Optional fields:**
| Field | Description |
|-------|-------------|
| `transporter_id` | Transporter GSTIN |
| `transporter_name` | Transporter name |
| `trans_doc_number` | LR/RR number |
| `trans_doc_date` | LR date |

### POST `/eway-bills/{id}/cancel`
```json
{
  "cancel_reason": "2",
  "cancel_remarks": "Order cancelled by customer"
}
```
`cancel_reason`: `"1"` Duplicate, `"2"` Order Cancelled, `"3"` Active EWB exists, `"4"` Other  
**Constraint:** Must cancel within 24 hours.

### POST `/eway-bills/{id}/vehicle`
```json
{
  "vehicle_number": "MH14CD5678",
  "vehicle_type": "REGULAR",
  "from_place": "Pune",
  "from_state_code": "27",
  "reason_code": "1",
  "reason_remarks": "Truck breakdown"
}
```
`reason_code`: `"1"` Transporter change, `"2"` Breakdown, `"3"` Transhipment, `"4"` Other

### POST `/eway-bills/consolidated`
```json
{
  "vehicle_number": "MH12AB1234",
  "vehicle_type": "REGULAR",
  "from_place": "Mumbai",
  "from_state_code": "27",
  "eway_bill_numbers": ["231000000001", "231000000002"]
}
```
**Response:**
```json
{
  "consolidated_eway_bill_number": "910000000001",
  "consolidated_date": "2025-04-15T11:00:00+00:00",
  "vehicle_number": "MH12AB1234",
  "status": "GENERATED",
  "eway_bills": ["231000000001", "231000000002"]
}
```

---

## 10. GST State Codes Reference

| Code | State |
|------|-------|
| 01 | Jammu & Kashmir |
| 02 | Himachal Pradesh |
| 03 | Punjab |
| 04 | Chandigarh |
| 05 | Uttarakhand |
| 06 | Haryana |
| 07 | Delhi |
| 08 | Rajasthan |
| 09 | Uttar Pradesh |
| 10 | Bihar |
| 11 | Sikkim |
| 12 | Arunachal Pradesh |
| 13 | Nagaland |
| 14 | Manipur |
| 15 | Mizoram |
| 16 | Tripura |
| 17 | Meghalaya |
| 18 | Assam |
| 19 | West Bengal |
| 20 | Jharkhand |
| 21 | Odisha |
| 22 | Chhattisgarh |
| 23 | Madhya Pradesh |
| 24 | Gujarat |
| 26 | Dadra and Nagar Haveli and Daman and Diu |
| 27 | Maharashtra |
| 28 | Andhra Pradesh (old) |
| 29 | Karnataka |
| 30 | Goa |
| 31 | Lakshadweep |
| 32 | Kerala |
| 33 | Tamil Nadu |
| 34 | Puducherry |
| 35 | Andaman and Nicobar |
| 36 | Telangana |
| 37 | Andhra Pradesh |
| 38 | Ladakh |
| 97 | Other Territory |
| 99 | Centre Jurisdiction |

---

## 11. GST Tax Mode / Registration Types

**Tenant `tax_mode`:**
| Value | Description |
|-------|-------------|
| `NON_GST` | Company not GST registered |
| `GST_REGULAR` | Regular GST taxpayer (monthly/quarterly filing) |
| `GST_COMPOSITION` | Composition scheme (flat rate, no ITC, B2C only) |

**Contact `registration_type`:**
| Value | Description |
|-------|-------------|
| `REGULAR` | GST regular taxpayer |
| `COMPOSITION` | Composition scheme taxpayer |
| `CONSUMER` | End consumer (unregistered, B2C) |
| `UNREGISTERED` | Business without GST registration |
| `SEZ` | Special Economic Zone unit |
| `OVERSEAS` | Foreign entity (exports) |

---

## 12. GST on Exports

On invoice, set `supply_type`:
- `EXPORT_WITH_TAX` — IGST charged, customer gets refund
- `EXPORT_WITHOUT_TAX` — No IGST (under Bond/LUT)
- `SEZ_WITH_TAX` — Supply to SEZ with IGST
- `SEZ_WITHOUT_TAX` — Supply to SEZ without tax

For export invoices in GSTR-1: automatically placed in **Table 6A (Exports)**.

---

## 13. ITC (Input Tax Credit)

On bills (purchases):
- `itc_eligible = true` (default) — eligible for ITC claim in GSTR-3B
- `itc_eligible = false` — ineligible (personal use, blocked credit under Sec 17(5))

In GSTR-3B, only bills with `itc_eligible = true` appear in **Table 4 (ITC Available)**.

---

## 14. Error Codes Specific to GST

| Error | HTTP | Description |
|-------|------|-------------|
| `GSTIN format invalid` | 400 | GSTIN doesn't match the 15-char pattern |
| `e-Invoicing not enabled` | 400 | Tenant `e_invoicing_enabled = false` |
| `Invoice not in POSTED status` | 400 | Cannot generate IRN for DRAFT/CANCELLED |
| `IRN already exists` | 409 | Duplicate IRN — unique constraint |
| `IRP portal unreachable` | 502 | NIC IRP API timeout |
| `Captcha invalid` | 502 | GST verify captcha rejected |
| `e-Way Bill cancellation window exceeded` | 400 | More than 24 hours since generation |
