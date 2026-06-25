# Invoice Payload Compatibility Report

**Date:** 2026-06-26

---

## Priority 1 — Invoice Creation Endpoint

### Frontend Sends vs Backend Schema

| Field | Frontend Sends | Backend Schema | Default | Compatible |
|-------|---------------|----------------|---------|------------|
| contact_id | Yes | Required | — | YES |
| issue_date | Yes | Required | — | YES |
| due_date | Yes | Required | — | YES |
| pos_state_code | Yes | Required | — | YES |
| billing_address | null | Optional[dict] | None | YES |
| shipping_address | null | Optional[dict] | None | YES |
| currency | Yes | Optional[str] | "INR" | YES |
| exchange_rate | Yes | Optional[Decimal] | 1.000000 | YES |
| is_gst_inclusive | Yes | Optional[bool] | False | YES |
| is_rcm | Yes | Optional[bool] | False | YES |
| supply_type | Yes | Optional[str] | "DOMESTIC" | YES |
| tds_rate | Yes | Optional[Decimal] | 0.00 | YES |
| tcs_rate | Yes | Optional[Decimal] | 0.00 | YES |
| notes | Yes | Optional[str] | None | YES |
| reference_number | Yes | Optional[str] | None | YES |

### Invoice Line Fields

| Field | Frontend Sends | Backend Schema | Default | Compatible |
|-------|---------------|----------------|---------|------------|
| product_id | Yes | Required | — | YES |
| description | Yes | Optional[str] | None | YES |
| quantity | Yes | Required (gt=0) | — | YES |
| rate | Yes | Required (ge=0) | — | YES |
| hsn_sac | Yes | Required | — | YES |
| gst_rate | Yes | Required | — | YES |
| discount | **No** | Optional[Decimal] | 0.0000 | YES |

### Tax Amounts — Backend Calculates Automatically

| Field | Frontend Sends | Backend Behavior |
|-------|---------------|-----------------|
| cgst_amount | No | **Auto-calculated** by GSTEngine |
| sgst_amount | No | **Auto-calculated** by GSTEngine |
| igst_amount | No | **Auto-calculated** by GSTEngine |
| cess_amount | No | **Auto-calculated** by GSTEngine |
| total | No | **Auto-calculated** (subtotal + taxes + round_off) |
| subtotal | No | **Auto-calculated** (qty × rate - discount) |

**Verdict: FULLY COMPATIBLE** — Backend derives all tax amounts from product_id + gst_rate + pos_state_code.

---

## Priority 2 — Address Handling

- `billing_address`: Schema type `Optional[dict]`, default `None`
- `shipping_address`: Schema type `Optional[dict]`, default `None`
- Endpoint does NOT populate from contact — it stores whatever the client sends
- Sending `null` is safe: no validation rejects it

**Verdict: FULLY COMPATIBLE** — null addresses are accepted and stored as-is.

---

## Priority 3 — Optional Invoice Fields

| Field | Classification | Notes |
|-------|---------------|-------|
| terms_and_conditions | Optional | Default None, stored if provided |
| sales_person_id | Optional | Default None, UUID reference |
| tds_amount | Server-calculated | Computed from tds_rate × total after flush |
| tcs_amount | Server-calculated | Computed from tcs_rate × total after flush |
| invoice_number | Server-generated | Auto-generated via NumberingSeries if omitted |
| discount_rate | Optional | Default 0.00, header-level discount |
| shipping_charges | Optional | Default 0.0000 |

**Verdict: FULLY COMPATIBLE** — All optional fields have safe defaults.

---

## Priority 4 — Payment Endpoint

| Field | Frontend Behavior | Backend Behavior | Compatible |
|-------|------------------|-----------------|------------|
| financial_year_id | Not sent | **Not a field** — FY inferred from payment_date via period_lock | YES |
| status | Not sent | **Server-generated** — always set to internal state | YES |
| payment_number | Not sent | **Auto-generated** via NumberingSeries | YES |
| allocations | Required | Frontend must send at least one allocation | YES |

The `PaymentCreate` schema has no `financial_year_id` field. The `validate_period_open()` function checks the payment_date against the current FY and any closed periods. Status is managed internally by the payment service.

**Verdict: FULLY COMPATIBLE** — FY is inferred from date, status is server-managed.

---

## Priority 5 — Journal Endpoint

| Field | Frontend Behavior | Backend Behavior | Compatible |
|-------|------------------|-----------------|------------|
| source_type | Not sent | **Hardcoded to "MANUAL"** in endpoint | YES |
| source_id | Not sent | **Set to entry_id** (UUID) in endpoint | YES |
| reference_number | Optional | Auto-generated via NumberingSeries if omitted | YES |

The `JournalEntryCreate` schema does NOT include `source_type` or `source_id`. The endpoint at `accounting.py:115-116` hardcodes:
```python
source_type="MANUAL"
source_id=entry_id
```

**Verdict: FULLY COMPATIBLE** — source_type and source_id are server-assigned.

---

## Priority 6 — Compatibility Matrix

| Entity | Field | Client Sends | Backend Calculates | Backend Defaults | Client Required | Action |
|--------|-------|-------------|-------------------|-----------------|----------------|--------|
| Invoice | contact_id | Yes | — | — | Yes | None |
| Invoice | issue_date | Yes | — | — | Yes | None |
| Invoice | due_date | Yes | — | — | Yes | None |
| Invoice | pos_state_code | Yes | — | — | Yes | None |
| Invoice | billing_address | null | — | None | No | None |
| Invoice | shipping_address | null | — | None | No | None |
| Invoice | currency | Yes | — | "INR" | No | None |
| Invoice | exchange_rate | Yes | — | 1.0 | No | None |
| Invoice | is_gst_inclusive | Yes | — | False | No | None |
| Invoice | is_rcm | Yes | — | False | No | None |
| Invoice | supply_type | Yes | — | "DOMESTIC" | No | None |
| Invoice | tds_rate | Yes | — | 0.00 | No | None |
| Invoice | tcs_rate | Yes | — | 0.00 | No | None |
| Invoice | notes | Yes | — | None | No | None |
| Invoice | reference_number | Yes | — | None | No | None |
| Invoice | invoice_number | No | — | Auto-gen | No | None |
| Invoice | discount_rate | No | — | 0.00 | No | None |
| Invoice | shipping_charges | No | — | 0.00 | No | None |
| Invoice | terms_and_conditions | No | — | None | No | None |
| Invoice | sales_person_id | No | — | None | No | None |
| Invoice | subtotal | No | Yes | — | — | None |
| Invoice | discount_total | No | Yes | — | — | None |
| Invoice | cgst_amount | No | Yes | — | — | None |
| Invoice | sgst_amount | No | Yes | — | — | None |
| Invoice | igst_amount | No | Yes | — | — | None |
| Invoice | cess_amount | No | Yes | — | — | None |
| Invoice | total | No | Yes | — | — | None |
| Invoice | round_off | No | Yes | — | — | None |
| Invoice | tds_amount | No | Yes | — | — | None |
| Invoice | tcs_amount | No | Yes | — | — | None |
| InvoiceLine | product_id | Yes | — | — | Yes | None |
| InvoiceLine | description | Yes | — | None | No | None |
| InvoiceLine | quantity | Yes | — | — | Yes | None |
| InvoiceLine | rate | Yes | — | — | Yes | None |
| InvoiceLine | hsn_sac | Yes | — | — | Yes | None |
| InvoiceLine | gst_rate | Yes | — | — | Yes | None |
| InvoiceLine | discount | No | — | 0.0000 | No | None |
| InvoiceLine | cgst_amount | No | Yes | — | — | None |
| InvoiceLine | sgst_amount | No | Yes | — | — | None |
| InvoiceLine | igst_amount | No | Yes | — | — | None |
| InvoiceLine | total | No | Yes | — | — | None |
| Payment | contact_id | Yes | — | — | Yes | None |
| Payment | payment_date | Yes | — | — | Yes | None |
| Payment | payment_mode | Yes | — | — | Yes | None |
| Payment | amount | Yes | — | — | Yes | None |
| Payment | allocations | Yes | — | — | Yes | None |
| Payment | payment_number | No | — | Auto-gen | No | None |
| Payment | financial_year_id | N/A | Inferred from date | — | — | None |
| Payment | status | N/A | Server-managed | — | — | None |
| Journal | entry_date | Yes | — | — | Yes | None |
| Journal | description | Yes | — | — | Yes | None |
| Journal | lines | Yes | — | — | Yes | None |
| Journal | reference_number | No | — | Auto-gen | No | None |
| Journal | source_type | N/A | Hardcoded "MANUAL" | — | — | None |
| Journal | source_id | N/A | Set to entry_id | — | — | None |

---

## Priority 7 — Final Decision

| Entity | Decision |
|--------|----------|
| Invoice Creation | **Fully Compatible** |
| Invoice Lines | **Fully Compatible** |
| Payment Creation | **Fully Compatible** |
| Journal Creation | **Fully Compatible** |

---

## Summary

**Zero backend changes required. Zero frontend changes required.**

The backend already:
1. Accepts all fields the frontend sends
2. Defaults all omitted optional fields safely
3. Calculates all tax amounts server-side (GSTEngine)
4. Auto-generates invoice numbers, payment numbers, journal reference numbers
5. Infers financial year from payment date
6. Assigns source_type="MANUAL" for journal entries
7. Accepts null addresses without rejection

The frontend Release Candidate and backend Release Candidate are **fully compatible** for production.
