# API Compatibility Matrix — ApexBooks v1.0

**Date:** 2026-06-26

---

## Invoice Create — POST /api/v1/invoices

### Required Fields (Client Must Send)

| Field | Type | Notes |
|-------|------|-------|
| contact_id | UUID | Must be valid customer in tenant |
| issue_date | date | Must fall within open FY/period |
| due_date | date | Any valid date |
| pos_state_code | string | 2-digit state code |
| line_items | array | At least one line item |
| line_items[].product_id | UUID | Must be valid product in tenant |
| line_items[].quantity | Decimal | Must be > 0 |
| line_items[].rate | Decimal | Must be >= 0 |
| line_items[].hsn_sac | string | 4-8 digit HSN/SAC code |
| line_items[].gst_rate | Decimal | 0-100 |

### Optional Fields (Client May Omit)

| Field | Type | Default |
|-------|------|---------|
| invoice_number | string | Auto-generated |
| billing_address | dict | null |
| shipping_address | dict | null |
| currency | string | "INR" |
| exchange_rate | Decimal | 1.000000 |
| discount_rate | Decimal | 0.00 |
| shipping_charges | Decimal | 0.0000 |
| notes | string | null |
| terms_and_conditions | string | null |
| reference_number | string | null |
| sales_person_id | UUID | null |
| is_gst_inclusive | bool | false |
| is_rcm | bool | false |
| supply_type | string | "DOMESTIC" |
| tds_rate | Decimal | 0.00 |
| tcs_rate | Decimal | 0.00 |
| line_items[].description | string | Product name |
| line_items[].discount | Decimal | 0.0000 |

### Server-Calculated Fields (Never Sent by Client)

| Field | Calculation |
|-------|-------------|
| subtotal | sum(line.quantity × line.rate - line.discount) |
| discount_total | subtotal × discount_rate / 100 |
| cgst_amount | GSTEngine.calculate_tax() |
| sgst_amount | GSTEngine.calculate_tax() |
| igst_amount | GSTEngine.calculate_tax() |
| utgst_amount | GSTEngine.calculate_tax() |
| cess_amount | GSTEngine.calculate_tax() |
| round_off | rounded_total - raw_total |
| total | adjusted_subtotal + taxes + shipping + round_off |
| tds_amount | total × tds_rate / 100 |
| tcs_amount | total × tcs_rate / 100 |
| status | "DRAFT" (auto-posted to "POSTED") |

---

## Payment Create — POST /api/v1/payments/receipts

### Required Fields

| Field | Type | Notes |
|-------|------|-------|
| contact_id | UUID | Must be customer |
| payment_date | date | Must be in open period |
| payment_mode | string | CASH/BANK/UPI/POS/OTHER |
| amount | Decimal | Must be > 0 |
| allocations | array | At least one allocation |
| allocations[].invoice_id | UUID | Must be valid invoice |
| allocations[].amount | Decimal | Must be > 0 |

### Optional Fields

| Field | Type | Default |
|-------|------|---------|
| payment_number | string | Auto-generated |
| reference_number | string | null |
| description | string | null |

### Server-Managed

| Field | Behavior |
|-------|----------|
| financial_year_id | Not a field — inferred from payment_date |
| status | Server-managed internal state |

---

## Journal Create — POST /api/v1/accounting/journals

### Required Fields

| Field | Type | Notes |
|-------|------|-------|
| entry_date | date | Must be in open period |
| description | string | Max 255 chars |
| lines | array | At least 2 lines |
| lines[].account_id | UUID | Must be valid account |
| lines[].amount | Decimal | Must be > 0 |
| lines[].direction | string | DEBIT or CREDIT |

### Optional Fields

| Field | Type | Default |
|-------|------|---------|
| reference_number | string | Auto-generated |
| lines[].narration | string | null |

### Server-Assigned

| Field | Value |
|-------|-------|
| source_type | "MANUAL" (hardcoded) |
| source_id | entry_id (UUID) |

---

## Compatibility Score

| Entity | Score |
|--------|-------|
| Invoice | 100% — All client fields accepted, all omitted fields defaulted |
| Payment | 100% — All client fields accepted, FY inferred from date |
| Journal | 100% — All client fields accepted, source_type assigned server-side |

**Overall: 100% Compatible — No changes required on either side.**
