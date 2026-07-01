# ApexBooks — Feature Flags Reference
> Feature flags control major capabilities. Most are stored in `tenant_settings` or derived from `tenant.tax_mode`.

---

## 1. Tenant-Level Feature Flags

These flags live in the `tenant_settings` table and affect API behaviour.

### 1.1 `gst_enabled` (BOOLEAN)
**Source:** `tenant_settings.gst_enabled`  
**Also controlled by:** `tenant.tax_mode`  
**Default:** `true`

| Value | API Behaviour | Frontend Impact |
|-------|--------------|----------------|
| `false` / `tax_mode = NON_GST` | GSTIN validation skipped; GST fields set to zero; GSTR reports return empty | Hide all GST fields from invoice forms; hide GST menu |
| `true` / `tax_mode = GST_REGULAR` | Full GST calculation applied | Show GST fields, rates, GSTIN inputs |
| `true` / `tax_mode = GST_COMPOSITION` | Composition rates; no ITC; no B2B output tax | Show composition tax UI; disable ITC claims |

**Check via:** `GET /companies/{id}` → `tax_mode` field  
**Set via:** `POST /companies/{id}/gst-toggle`

---

### 1.2 `e_invoicing_enabled` (BOOLEAN)
**Source:** `tenant_settings.e_invoicing_enabled`  
**Default:** `false`

| Value | API Behaviour | Frontend Impact |
|-------|--------------|----------------|
| `false` | `POST /invoices/{id}/e-invoice` returns 400 "e-Invoicing is not enabled" | Hide "Generate e-Invoice" button |
| `true` | IRN generation triggers on request | Show "Generate e-Invoice" button on posted invoices |

**Set via:** `PUT /settings` with `{ "e_invoicing_enabled": true, "e_invoice_username": "...", "e_invoice_password_hash": "..." }`

**Mandatory for:** Businesses with aggregate turnover > ₹5 crore (per CBIC mandate).

---

### 1.3 E-Way Bill Credentials
**Source:** `tenant_settings.e_way_bill_username` and `e_way_bill_password_hash`

If these are empty, `POST /eway-bills` will attempt to generate but fail at the IRP API level.

**Frontend impact:** Show a warning/setup prompt if `e_way_bill_username` is null.

---

### 1.4 `origin_state_code` (VARCHAR 2)
**Source:** `tenant_settings.origin_state_code`  
**Default:** `null` (falls back to inferring from `tenant.gstin[:2]`)

**Impact on GST routing:**
- Determines intra-state vs inter-state for each invoice line
- If null, defaults to `"27"` (Maharashtra) as fallback

**Set via:** `PUT /settings`

**Frontend:** Must prompt user to set this during onboarding.

---

### 1.5 `currency` (VARCHAR 10)
**Source:** `tenant_settings.currency`  
**Default:** `INR`

Currently, all financial calculations are done in INR. Multi-currency support is available on invoices via `currency` + `exchange_rate` fields, but reporting is always in INR.

---

### 1.6 UPI ID
**Source:** `tenant_settings.upi_id`

If set, printed on invoice PDF for customer payment QR. Frontend should display UPI ID on invoice preview.

---

## 2. Invoice-Level Feature Flags

These are per-document fields that change calculation behaviour.

### 2.1 `is_rcm` (BOOLEAN)
**Default:** `false`  
**Effect:** Reverse Charge Mechanism — buyer self-assesses GST; output tax on invoice = 0  
**Frontend:** Show "Reverse Charge" toggle on invoice form; display RCM label on printed invoice

### 2.2 `is_gst_inclusive` (BOOLEAN)
**Default:** `false`  
**Effect:** Rate is treated as GST-inclusive; system back-calculates taxable value  
**Frontend:** Show "GST Inclusive" checkbox on invoice form; update rate display accordingly

### 2.3 `supply_type` (ENUM)
**Default:** `DOMESTIC`  
**Options:** `DOMESTIC`, `EXPORT_WITH_TAX`, `EXPORT_WITHOUT_TAX`, `SEZ_WITH_TAX`, `SEZ_WITHOUT_TAX`  
**Effect:** Determines export classification in GSTR-1  
**Frontend:** Show supply type dropdown for vendors who are exporters

### 2.4 `itc_eligible` (BOOLEAN — bills only)
**Default:** `true`  
**Effect:** Controls whether bill appears in GSTR-3B Table 4 (ITC)  
**Frontend:** Show "ITC Eligible" toggle on bill form

---

## 3. Product-Level Feature Flags

### 3.1 `product_type` (GOODS / SERVICE)
**Effect:**
- `GOODS`: Stock movements tracked; `current_stock` updated on invoice/bill
- `SERVICE`: No stock tracking; inventory fields hidden

**Frontend:** Show/hide stock-related fields based on product_type

### 3.2 `gst_rate` (0–100)
- If `0.00`: product is exempt or zero-rated
- Common rates: 0, 5, 12, 18, 28

---

## 4. Display / UI Settings

### 4.1 `display_settings` (JSON in `tenant_settings`)
Free-form JSON for UI customisation. Currently used for:
```json
{
  "theme_color": "#1a73e8",
  "show_watermark": false,
  "invoice_template": "classic"
}
```
Frontend should read and apply these on invoice print/PDF generation.

### 4.2 `extra_settings` (JSON in `tenant_settings`)
Free-form JSON for miscellaneous flags. May include:
```json
{
  "auto_post_on_create": false,
  "default_payment_terms_days": 30,
  "show_bank_details_on_invoice": true,
  "enable_stock_alerts": true
}
```

---

## 5. Application-Level Feature Flags (Not DB-stored)

These are configured via environment variables and affect all tenants.

| Flag | Env Variable | Default | Effect |
|------|-------------|---------|--------|
| Rate limiting | `RATE_LIMIT_ENABLED` | `true` | Disable for dev/test only |
| Demo data seeding | `SEED_ON_STARTUP` | `false` | Seeds demo accounts on startup |
| OCR engine | `OCR_ENGINE` | `paddleocr` | `"google_vision"` or `"paddleocr"` |
| GST Verify API | `GST_VERIFY_API_KEY` | `""` | If empty, GSTIN live verify fails |
| IRP / e-Invoice | `IRP_CLIENT_ID` + `IRP_CLIENT_SECRET` | `""` | If empty, e-invoice generation fails |
| Sentry error tracking | `SENTRY_DSN` | `""` | If empty, errors not sent to Sentry |

---

## 6. Feature Flag Impact Summary

| Feature | Flag | Where Set | Frontend Gate |
|---------|------|-----------|--------------|
| GST filing | `tax_mode = GST_REGULAR` | Company toggle | Show GST menu, GSTR reports |
| Composition GST | `tax_mode = GST_COMPOSITION` | Company toggle | Show composition UI |
| e-Invoice | `e_invoicing_enabled = true` | Settings | Show e-Invoice button on posted invoices |
| e-Way Bill | `e_way_bill_username` set | Settings | Show e-Way Bill creation option |
| Multi-currency | `invoice.currency != INR` | Per invoice | Show exchange rate field |
| RCM | `invoice.is_rcm = true` | Per invoice | Show RCM badge on invoice |
| GST Inclusive | `invoice.is_gst_inclusive = true` | Per invoice | Recalculate rate display |
| Stock tracking | `product.product_type = GOODS` | Per product | Show stock fields |
| ITC claim | `bill.itc_eligible = true` | Per bill | Include in GSTR-3B Table 4 |

---

## 7. Checking Feature Flags on Frontend

**On app load, call:**
1. `GET /auth/memberships` → get role
2. `GET /companies/{tenant_id}` → get `tax_mode`, `gstin`
3. `GET /settings` → get `gst_enabled`, `e_invoicing_enabled`, `e_way_bill_username`, `upi_id`, `origin_state_code`, `display_settings`

Cache these in global state. Re-fetch when user changes company.

---

## 8. Not Yet Implemented Feature Flags

The following features have database columns or partial code but **no working API**:

| Feature | Status |
|---------|--------|
| Multi-branch inventory | DB column exists (`branch_id` on documents) but not enforced |
| Payroll module | Not implemented |
| Manufacturing module | Not implemented |
| TDS/TCS portal filing | Fields stored but no NIC API integration |
| GST direct filing | No portal submission API |
| WhatsApp invoice sharing | Not implemented |
| SMS notifications | Not implemented |
