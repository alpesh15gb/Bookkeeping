# ApexBooks — Request & Response Reference
> All monetary fields use `Decimal` / string with 2–4 decimal places. All IDs are UUIDs (string format). All dates are ISO-8601 (`YYYY-MM-DD`).

---

## Authentication

### POST `/auth/register`
**Request:**
```json
{
  "email": "owner@company.in",
  "password": "Secure@123",
  "full_name": "Ramesh Kumar",
  "phone_number": "+919876543210",
  "company_legal_name": "ABC Traders Pvt Ltd",
  "company_gstin": "29AABCT1332L1ZP",
  "company_pan": "AABCT1332L"
}
```
**Validation:**
- `email`: valid email format
- `password`: min 8, max 128 chars; must contain uppercase, lowercase, digit, special char
- `full_name`: max 150
- `company_legal_name`: max 150
- `company_gstin`: pattern `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$` (optional)
- `company_pan`: pattern `^[A-Z]{5}[0-9]{4}[A-Z]$` (optional)

**Success 201:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "owner@company.in",
  "full_name": "Ramesh Kumar",
  "phone_number": "+919876543210",
  "is_active": true,
  "email_verified": false,
  "totp_enabled": false,
  "created_at": "2025-04-01T10:00:00+00:00"
}
```
**Error 400:** `{"detail": "Email already registered."}`  
**Error 422:** Pydantic validation error

---

### POST `/auth/login`
**Request:**
```json
{
  "email": "owner@company.in",
  "password": "Secure@123"
}
```
**Success 200:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "expires_in": 900
}
```
**Error 401:** `{"detail": "Invalid credentials."}`  
**Error 429:** Rate limit (10/min)

JWT access token payload:
```json
{
  "sub": "user-uuid",
  "type": "access",
  "scopes": ["tenant-uuid"],
  "exp": 1717000000
}
```

---

### POST `/auth/refresh`
**Request:**
```json
{
  "refresh_token": "eyJhbGci..."
}
```
**Success 200:** Same as login response.  
**Error 401:** `{"detail": "Invalid or expired refresh token."}`

---

## Company / Settings

### POST `/companies`
**Request:**
```json
{
  "legal_name": "ABC Traders Pvt Ltd",
  "trade_name": "ABC Traders",
  "gstin": "29AABCT1332L1ZP",
  "pan": "AABCT1332L",
  "financial_year_start": "2025-04-01"
}
```
**Success 201:** `CompanyResponse`

### CompanyResponse
```json
{
  "id": "uuid",
  "legal_name": "ABC Traders Pvt Ltd",
  "trade_name": "ABC Traders",
  "gstin": "29AABCT1332L1ZP",
  "pan": "AABCT1332L",
  "tax_mode": "GST_REGULAR",
  "financial_year_start": "2025-04-01",
  "created_at": "2025-04-01T10:00:00+00:00",
  "updated_at": "2025-04-01T10:00:00+00:00"
}
```

### POST `/companies/{id}/gst-toggle`
**Request:**
```json
{
  "tax_mode": "GST_REGULAR"
}
```
Allowed values: `NON_GST`, `GST_REGULAR`, `GST_COMPOSITION`

### TenantSettingResponse
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "logo_url": "/static/logos/uuid.png",
  "currency": "INR",
  "gst_enabled": true,
  "e_invoicing_enabled": false,
  "upi_id": "business@upi",
  "display_settings": {},
  "extra_settings": {},
  "origin_state_code": "29",
  "created_at": "2025-04-01T10:00:00+00:00",
  "updated_at": "2025-04-01T10:00:00+00:00"
}
```

---

## Contacts

### POST/PUT `/masters/contacts`
**Request:**
```json
{
  "name": "Rajesh Enterprises",
  "email": "rajesh@enterprises.in",
  "phone": "9876543210",
  "contact_type": "CUSTOMER",
  "gstin": "27AABCE1234F1Z5",
  "pan": "AABCE1234F",
  "registration_type": "REGULAR",
  "billing_address": {
    "street": "123 MG Road",
    "city": "Mumbai",
    "state": "Maharashtra",
    "state_code": "27",
    "pincode": "400001",
    "country": "India"
  },
  "shipping_address": null,
  "state_code": "27",
  "opening_balance": "0.00"
}
```
**Validation:**
- `name`: max 150, required
- `contact_type`: `CUSTOMER`, `VENDOR`, `BOTH`
- `gstin`: 15-char GSTIN pattern (optional)
- `state_code`: exactly 2 digits `^[0-9]{2}$`
- `registration_type`: `REGULAR`, `COMPOSITION`, `CONSUMER`, `UNREGISTERED`, `SEZ`, `OVERSEAS`

**Success 201:** `ContactResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "name": "Rajesh Enterprises",
  "email": "rajesh@enterprises.in",
  "phone": "9876543210",
  "contact_type": "CUSTOMER",
  "gstin": "27AABCE1234F1Z5",
  "pan": "AABCE1234F",
  "registration_type": "REGULAR",
  "billing_address": { "street": "...", "city": "...", "state": "...", "state_code": "27", "pincode": "...", "country": "India" },
  "shipping_address": null,
  "state_code": "27",
  "is_active": true,
  "opening_balance": "0.0000",
  "credit_balance": "0.0000",
  "custom_fields": {},
  "created_at": "2025-04-01T10:00:00+00:00",
  "updated_at": "2025-04-01T10:00:00+00:00"
}
```

---

## Products

### POST/PUT `/masters/products`
**Request:**
```json
{
  "name": "Steel Pipe 1 inch",
  "sku": "SP-001",
  "hsn_sac": "73063090",
  "product_type": "GOODS",
  "uom": "MTR",
  "sales_price": "250.00",
  "purchase_price": "200.00",
  "gst_rate": "18.00",
  "opening_stock": "100.00",
  "reorder_level": "20.00"
}
```
**Validation:**
- `product_type`: `GOODS`, `SERVICE`
- `gst_rate`: 0–100, default 0
- `uom`: max 10

**Success 201:** `ProductResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "name": "Steel Pipe 1 inch",
  "sku": "SP-001",
  "hsn_sac": "73063090",
  "product_type": "GOODS",
  "uom": "MTR",
  "sales_price": "250.0000",
  "purchase_price": "200.0000",
  "gst_rate": "18.00",
  "opening_stock": "100.00",
  "current_stock": "100.00",
  "reorder_level": "20.00",
  "is_active": true,
  "updated_at": "2025-04-01T10:00:00+00:00"
}
```

---

## Sales Invoice

### POST `/invoices` — Create Invoice
**Request:**
```json
{
  "contact_id": "uuid",
  "issue_date": "2025-04-15",
  "due_date": "2025-05-15",
  "pos_state_code": "27",
  "currency": "INR",
  "exchange_rate": "1.000000",
  "reference_number": "PO-12345",
  "notes": "Thanks for your business.",
  "terms_and_conditions": "Payment due within 30 days.",
  "is_rcm": false,
  "is_gst_inclusive": false,
  "supply_type": "DOMESTIC",
  "tds_rate": "0.00",
  "tcs_rate": "0.00",
  "discount_total": "0.00",
  "shipping_charges": "0.00",
  "line_items": [
    {
      "product_id": "uuid",
      "description": "Steel Pipe 1 inch",
      "quantity": "10.0000",
      "rate": "250.0000",
      "discount": "0.00",
      "hsn_sac": "73063090",
      "gst_rate": "18.00"
    }
  ]
}
```
**Validation:**
- `pos_state_code`: exactly 2 digits
- `exchange_rate`: ≥ 0, default 1
- `tds_rate` / `tcs_rate`: 0–100
- `line_items`: at least 1 item
- `gst_rate` per line: 0–100

**Success 201:** `InvoiceResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "contact_id": "uuid",
  "invoice_number": "INV-2025-0001",
  "issue_date": "2025-04-15",
  "due_date": "2025-05-15",
  "status": "DRAFT",
  "subtotal": "2500.0000",
  "discount_total": "0.0000",
  "cgst_amount": "225.0000",
  "sgst_amount": "225.0000",
  "igst_amount": "0.0000",
  "utgst_amount": "0.0000",
  "cess_amount": "0.0000",
  "round_off": "0.0000",
  "shipping_charges": "0.0000",
  "total": "2950.0000",
  "amount_paid": "0.0000",
  "pos_state_code": "27",
  "irn": null,
  "qr_code": null,
  "e_invoice_status": "PENDING",
  "notes": "Thanks for your business.",
  "terms_and_conditions": "Payment due within 30 days.",
  "reference_number": "PO-12345",
  "is_rcm": false,
  "is_gst_inclusive": false,
  "supply_type": "DOMESTIC",
  "currency": "INR",
  "exchange_rate": "1.000000",
  "tds_rate": "0.00",
  "tds_amount": "0.0000",
  "tcs_rate": "0.00",
  "tcs_amount": "0.0000",
  "created_at": "2025-04-15T09:00:00+00:00",
  "updated_at": "2025-04-15T09:00:00+00:00",
  "line_items": [
    {
      "id": "uuid",
      "product_id": "uuid",
      "product_name": "Steel Pipe 1 inch",
      "description": "Steel Pipe 1 inch",
      "quantity": "10.0000",
      "rate": "250.0000",
      "discount": "0.0000",
      "subtotal": "2500.0000",
      "hsn_sac": "73063090",
      "gst_rate": "18.00",
      "cgst_rate": "9.00",
      "cgst_amount": "225.0000",
      "sgst_rate": "9.00",
      "sgst_amount": "225.0000",
      "igst_rate": "0.00",
      "igst_amount": "0.0000",
      "utgst_rate": "0.00",
      "utgst_amount": "0.0000",
      "cess_rate": "0.00",
      "cess_amount": "0.0000",
      "total": "2950.0000"
    }
  ],
  "contact": { "id": "uuid", "name": "Rajesh Enterprises", "gstin": "27AABCE1234F1Z5" }
}
```

### POST `/invoices/{id}/payment`
**Request:**
```json
{
  "amount": "2950.00",
  "payment_date": "2025-05-10",
  "payment_mode": "BANK",
  "reference_number": "UTR123456"
}
```
**Validation:** `payment_mode` in `{cash, bank, upi, pos, other}` (case-insensitive)

---

## Vendor Bill

### POST `/bills` — Create Bill
**Request:**
```json
{
  "contact_id": "uuid",
  "bill_number": "VB-2025-001",
  "issue_date": "2025-04-10",
  "due_date": "2025-05-10",
  "pos_state_code": "29",
  "itc_eligible": true,
  "is_gst_inclusive": false,
  "tds_rate": "0.00",
  "line_items": [
    {
      "product_id": "uuid",
      "quantity": "50.0000",
      "rate": "200.0000",
      "discount": "0.00",
      "hsn_sac": "73063090",
      "gst_rate": "18.00"
    }
  ]
}
```

---

## Payments

### POST `/payments/receipts`
**Request:**
```json
{
  "contact_id": "uuid",
  "payment_date": "2025-05-10",
  "payment_mode": "BANK",
  "amount": "2950.00",
  "reference_number": "UTR789",
  "description": "Receipt for Invoice INV-2025-0001",
  "allocations": [
    {
      "invoice_id": "uuid",
      "amount": "2950.00"
    }
  ]
}
```
**Validation:**
- `payment_mode`: `CASH`, `BANK`, `UPI`, `POS`, `OTHER`
- `allocations[].amount`: > 0
- Sum of allocations must equal `amount`

**Success 201:** `PaymentResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "contact_id": "uuid",
  "payment_number": "RCPT-2025-0001",
  "payment_date": "2025-05-10",
  "payment_mode": "BANK",
  "amount": "2950.0000",
  "reference_number": "UTR789",
  "description": "Receipt for Invoice INV-2025-0001",
  "status": "ACTIVE",
  "allocations": [
    {
      "id": "uuid",
      "invoice_id": "uuid",
      "amount": "2950.0000",
      "created_at": "2025-05-10T10:00:00+00:00"
    }
  ],
  "created_at": "2025-05-10T10:00:00+00:00",
  "updated_at": "2025-05-10T10:00:00+00:00"
}
```

---

## Expenses

### POST `/expenses`
**Request:**
```json
{
  "expense_category_id": "uuid",
  "bank_account_id": "uuid",
  "expense_date": "2025-04-20",
  "vendor_name": "Reliance Petrol Pump",
  "description": "Fuel for delivery vehicle",
  "amount": "1000.00",
  "gst_rate": "0.00",
  "place_of_supply_state_code": "27",
  "notes": "",
  "reference_number": "BILL-789"
}
```

**Success 201:** `ExpenseResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "expense_number": "EXP-202504-0001",
  "expense_category_id": "uuid",
  "bank_account_id": "uuid",
  "expense_date": "2025-04-20",
  "vendor_name": "Reliance Petrol Pump",
  "description": "Fuel for delivery vehicle",
  "amount": "1000.0000",
  "gst_rate": "0.00",
  "cgst_amount": "0.0000",
  "sgst_amount": "0.0000",
  "igst_amount": "0.0000",
  "utgst_amount": "0.0000",
  "cess_amount": "0.0000",
  "round_off": "0.0000",
  "total": "1000.0000",
  "status": "DRAFT",
  "notes": "",
  "reference_number": "BILL-789",
  "category_name": "Fuel & Transport",
  "created_at": "2025-04-20T10:00:00+00:00",
  "updated_at": "2025-04-20T10:00:00+00:00"
}
```

---

## Journal Entry (Manual)

### POST `/accounting/journals`
**Request:**
```json
{
  "entry_date": "2025-04-30",
  "reference_number": "JV-001",
  "description": "Depreciation entry for FY 2025-26",
  "lines": [
    {
      "account_id": "uuid-depreciation-account",
      "amount": "50000.00",
      "direction": "DEBIT",
      "narration": "Depreciation on machinery"
    },
    {
      "account_id": "uuid-accumulated-dep-account",
      "amount": "50000.00",
      "direction": "CREDIT",
      "narration": "Accumulated depreciation"
    }
  ]
}
```
**Validation:**
- Min 2 lines
- Sum of DEBITs must equal sum of CREDITs
- `direction`: `DEBIT` or `CREDIT`
- `amount`: > 0

**Success 201:** `JournalEntryResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "entry_date": "2025-04-30",
  "reference_number": "JV-001",
  "description": "Depreciation entry for FY 2025-26",
  "source_type": "MANUAL",
  "source_id": null,
  "is_locked": true,
  "lines": [
    {
      "id": "uuid",
      "account_id": "uuid",
      "amount": "50000.0000",
      "direction": "DEBIT",
      "narration": "Depreciation on machinery"
    },
    {
      "id": "uuid",
      "account_id": "uuid",
      "amount": "50000.0000",
      "direction": "CREDIT",
      "narration": "Accumulated depreciation"
    }
  ],
  "created_at": "2025-04-30T10:00:00+00:00",
  "updated_at": "2025-04-30T10:00:00+00:00"
}
```

---

## Financial Year

### POST `/financial-years`
**Request:**
```json
{
  "name": "FY 2025-26",
  "start_date": "2025-04-01",
  "end_date": "2026-03-31"
}
```

**FinancialYearResponse:**
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "name": "FY 2025-26",
  "start_date": "2025-04-01",
  "end_date": "2026-03-31",
  "status": "CURRENT",
  "is_current": true,
  "closed_at": null,
  "closed_by": null,
  "created_at": "...",
  "updated_at": "..."
}
```

---

## e-Way Bill

### POST `/eway-bills`
**Request:**
```json
{
  "invoice_id": "uuid",
  "supply_type": "OUTWARD",
  "sub_supply_type": "SUPPLY",
  "trans_mode": "ROAD",
  "trans_distance": 120,
  "vehicle_number": "MH12AB1234",
  "vehicle_type": "REGULAR",
  "transporter_name": "FastCargo Logistics",
  "transporter_id": "29AABCT1332L1ZP"
}
```
**Validation:**
- `supply_type`: `OUTWARD`, `INWARD`
- `sub_supply_type`: `SUPPLY`, `IMPORT`, `EXPORT`, `JOB_WORK`, `SEZ`, `LINE_SALES`, `OTHER`
- `trans_mode`: `ROAD`, `RAIL`, `AIR`, `SHIP`
- `trans_distance`: 1–4000 km
- `vehicle_number`: pattern `^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$`
- `vehicle_type`: `REGULAR`, `ODC`

**Success 201:** `EWayBillResponse`
```json
{
  "id": "uuid",
  "tenant_id": "uuid",
  "invoice_id": "uuid",
  "bill_id": null,
  "eway_bill_number": "231000000001",
  "status": "GENERATED",
  "supply_type": "OUTWARD",
  "sub_supply_type": "SUPPLY",
  "transporter_id": "29AABCT1332L1ZP",
  "transporter_name": "FastCargo Logistics",
  "trans_distance": 120,
  "trans_mode": "ROAD",
  "vehicle_number": "MH12AB1234",
  "vehicle_type": "REGULAR",
  "valid_until": "2025-04-16T23:59:59+00:00",
  "vehicle_history": [],
  "created_at": "2025-04-15T10:00:00+00:00",
  "updated_at": "2025-04-15T10:00:00+00:00"
}
```

---

## e-Invoice

### POST `/invoices/{id}/e-invoice`
**Success 200:** `EInvoiceResponse`
```json
{
  "invoice_id": "uuid",
  "irn": "a5c12...64 hex chars",
  "qr_code": "base64-encoded-qr-data",
  "e_invoice_status": "GENERATED",
  "ack_number": "112233445566",
  "ack_date": "2025-04-15T10:30:00+00:00"
}
```

---

## Numbering Series

### POST `/settings/series`
**Request:**
```json
{
  "document_type": "INVOICE",
  "prefix": "INV-",
  "next_number": 1,
  "suffix": "",
  "padding_digits": 4
}
```
Allowed `document_type` values: `INVOICE`, `BILL`, `PAYMENT`, `JOURNAL`, `CREDIT_NOTE`, `DEBIT_NOTE`, `EXPENSE`, `PURCHASE_ORDER`, `SALES_ORDER`, `DELIVERY_CHALLAN`, `PROFORMA_INVOICE`

---

## Recurring Invoice

### POST `/recurring-invoices`
**Request:**
```json
{
  "contact_id": "uuid",
  "frequency": "MONTHLY",
  "interval_value": 1,
  "start_date": "2025-05-01",
  "end_date": "2026-03-31",
  "pos_state_code": "27",
  "notes": "Monthly maintenance invoice",
  "items": [
    {
      "product_id": "uuid",
      "quantity": "1.0000",
      "rate": "5000.00",
      "discount": "0.00",
      "hsn_sac": "998319",
      "gst_rate": "18.00"
    }
  ]
}
```
**Validation:**
- `frequency`: `DAILY`, `WEEKLY`, `MONTHLY`, `QUARTERLY`, `YEARLY`
- `interval_value`: ≥ 1
- `start_date` must be before `end_date`

---

## Credit Note

### POST `/invoices/credit-notes`
**Request:**
```json
{
  "invoice_id": "uuid",
  "issue_date": "2025-04-20",
  "reason": "Goods returned damaged",
  "pos_state_code": "27",
  "line_items": [
    {
      "product_id": "uuid",
      "quantity": "2.0000",
      "rate": "250.00",
      "discount": "0.00",
      "hsn_sac": "73063090",
      "gst_rate": "18.00"
    }
  ]
}
```
`invoice_id` is optional (standalone credit note).

---

## Inventory Adjustment

### POST `/inventory-adjustments`
**Request:**
```json
{
  "adjustment_number": "ADJ-2025-001",
  "adjustment_date": "2025-04-30",
  "reason": "Stock count discrepancy",
  "line_items": [
    {
      "product_id": "uuid",
      "quantity_change": "-5.00",
      "unit_cost": "200.00"
    }
  ]
}
```
`quantity_change`: positive = stock increase, negative = stock decrease.

---

## Paginated List Responses

All paginated endpoints return:
```json
{
  "items": [...],
  "total": 150,
  "page": 1,
  "limit": 20
}
```

---

## Standard Error Responses

### 400 Bad Request
```json
{"detail": "Human-readable error message."}
```

### 401 Unauthorized
```json
{"detail": "Not authenticated."}
```

### 403 Forbidden
```json
{"detail": "Permission denied. Required: invoice:create"}
```

### 404 Not Found
```json
{"detail": "Record not found."}
```

### 409 Conflict / Duplicate
```json
{"detail": "Invoice number INV-2025-0001 already exists for this tenant."}
```

### 422 Validation Error
```json
{
  "detail": [
    {
      "loc": ["body", "line_items", 0, "gst_rate"],
      "msg": "ensure this value is less than or equal to 100",
      "type": "value_error.number.not_le"
    }
  ]
}
```

### 429 Rate Limited
```json
{"error": "Rate limit exceeded.", "detail": "10 per 1 minute"}
```

### 500 Internal Server Error
```json
{"detail": "An unexpected error occurred. Please try again or contact support."}
```

### Business Rule Errors
```json
{"detail": "Cannot modify a locked journal entry. Create a reversal entry instead."}
{"detail": "Period 2025-03 is locked. Unlock it before creating transactions."}
{"detail": "Invoice INV-0001 is already finalized. Cancel it before making changes."}
{"detail": "Financial year FY 2024-25 is closed. Reopen it to make changes."}
{"detail": "Cannot delete a contact with linked invoices or bills."}
{"detail": "Allocation amounts (₹3,000) exceed payment amount (₹2,950)."}
```
