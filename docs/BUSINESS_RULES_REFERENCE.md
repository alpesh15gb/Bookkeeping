# ApexBooks — Business Rules Reference
> Documents all accounting, GST, inventory, and lifecycle business rules enforced by the backend.

---

## 1. Document Lifecycle Rules

### 1.1 Invoice (Sales Invoice)

```
DRAFT ──[finalize]──▶ POSTED ──[payment recorded]──▶ PARTIALLY_PAID ──[full payment]──▶ PAID
  │                      │
  │                      └──[cancel]──▶ CANCELLED
  └──[delete]──▶ (hard delete, DRAFT only)
```

| Transition | Trigger | What happens |
|-----------|---------|-------------|
| DRAFT → POSTED | `POST /invoices/{id}/finalize` | Ledger journal entry created; stock decremented (GOODS); invoice number locked |
| POSTED → PARTIALLY_PAID | `POST /invoices/{id}/payment` | `amount_paid` updated; payment allocation created; status set |
| PARTIALLY_PAID → PAID | `POST /invoices/{id}/payment` | When `amount_paid == total`; status → PAID |
| POSTED/PARTIALLY_PAID → CANCELLED | `POST /invoices/{id}/cancel` | Reversal journal entry created; stock restored; `cancelled_at`/`cancelled_by` set |
| DRAFT → (deleted) | `DELETE /invoices/{id}` | Hard delete only if status == DRAFT; forbidden otherwise |

**Rules:**
- Cannot finalize if period is locked
- Cannot modify a POSTED invoice — only cancel + recreate
- `invoice_number` is auto-generated via NumberingSeries on first save (or on finalize for DRAFT)
- Duplicate `invoice_number` per tenant rejected with HTTP 409
- Cannot delete a POSTED/PAID invoice — must cancel first

### 1.2 Vendor Bill (Purchases)

```
DRAFT ──[finalize]──▶ POSTED ──[payment recorded]──▶ UNPAID ──▶ PARTIALLY_PAID ──▶ PAID
  │                      │
  └──[delete]──▶ (deleted)  └──[cancel]──▶ CANCELLED
```

Same lifecycle as Invoice. Bill does NOT have e-invoice or IRN.

### 1.3 Credit Note

```
DRAFT ──[finalize]──▶ POSTED ──[cancel]──▶ CANCELLED
  └──[delete]──▶ (deleted)
```

- Credit note can reference an invoice (`invoice_id`) or be standalone
- On finalize: reversal journal entry created; if linked to GOODS invoice, stock restored
- Amount reduces the customer's outstanding balance

### 1.4 Debit Note

Mirror of Credit Note but increases vendor outstanding.

### 1.5 Sales Order

```
DRAFT ──[confirm]──▶ CONFIRMED ──[deliver]──▶ DELIVERED
  └──────────────────────────────────────[cancel]──▶ CANCELLED
```

Sales Orders do NOT create ledger entries. They are operational documents only.

### 1.6 Purchase Order

```
DRAFT ──[confirm]──▶ CONFIRMED ──[receive]──▶ RECEIVED
  └──────────────────────────────────────[cancel]──▶ CANCELLED
```

### 1.7 Delivery Challan

```
DRAFT ──[issue]──▶ ISSUED ──[cancel]──▶ CANCELLED
```

Delivery Challans do NOT create ledger entries or update stock by default.

### 1.8 Proforma Invoice

```
DRAFT ──[issue]──▶ ISSUED ──[convert]──▶ CONVERTED
  │                   └──[cancel]──▶ CANCELLED
  └──[delete]──▶ (deleted)
```

On convert: creates a real invoice in DRAFT status; sets `converted_invoice_id`.

### 1.9 Expense

```
DRAFT ──[post]──▶ POSTED ──[cancel]──▶ CANCELLED
  └──[delete]──▶ (deleted)
```

### 1.10 Inventory Adjustment

```
DRAFT ──[confirm]──▶ CONFIRMED ──[cancel]──▶ CANCELLED
```

On confirm: `current_stock` updated; stock ledger entry created; journal entry for the value change.

### 1.11 Customer Receipt (Payment)

`ACTIVE ──[cancel]──▶ CANCELLED`  
On cancel: reversal journal entry; invoice `amount_paid` decremented.

### 1.12 Returns

```
(no draft) created as POSTED ──[cancel]──▶ CANCELLED
```

Sales Return: increases stock + credits customer; creates ledger entries.  
Purchase Return: decreases stock + debits vendor; creates ledger entries.

---

## 2. GST Calculation Rules

### 2.1 Intra-state vs Inter-state

- If invoice `pos_state_code` == company's `origin_state_code` → **Intra-state** → split into CGST + SGST
- If `pos_state_code` != `origin_state_code` → **Inter-state** → IGST only
- UT transactions → CGST + UTGST

### 2.2 GST Split Formula

For a line with `gst_rate = 18%` on `subtotal = 1000`:

```
Intra-state:
  CGST = 1000 × 9% = 90
  SGST = 1000 × 9% = 90

Inter-state:
  IGST = 1000 × 18% = 180
```

### 2.3 GST-Inclusive Price Handling

If `is_gst_inclusive = true`:
```
  taxable_amount = rate / (1 + gst_rate/100)
  gst_amount     = rate - taxable_amount
```

### 2.4 Reverse Charge Mechanism (RCM)

If `is_rcm = true`:
- Tax liability shifts to buyer
- Outward supply GST is zero
- Buyer creates a self-invoice for ITC

### 2.5 GST Composition Scheme

If `tax_mode = GST_COMPOSITION`:
- No input tax credit
- Flat composition tax (not item-level GST)
- B2C only — cannot charge GST to customers

### 2.6 CESS

Cess applies to specific goods (tobacco, luxury, coal). Rate set per line item. Calculated as `cess_rate% × subtotal`.

### 2.7 Round-off

```
round_off = round(total_before_roundoff) - total_before_roundoff
Max round_off allowed: ±₹0.50
```

---

## 3. Ledger Posting Rules

### 3.1 Invoice Finalization Ledger Entry

```
DR  Accounts Receivable (customer AR account)      ← total invoice amount
CR  Sales Revenue Account                          ← subtotal
CR  CGST Output Tax                                ← cgst_amount
CR  SGST Output Tax                                ← sgst_amount
CR  IGST Output Tax                                ← igst_amount
CR  CESS Output Tax                                ← cess_amount
```

### 3.2 Payment Receipt Ledger Entry

```
DR  Cash/Bank Account (based on payment_mode)      ← payment amount
CR  Accounts Receivable (customer AR account)      ← payment amount
```

### 3.3 Bill Finalization Ledger Entry

```
DR  Expense / Purchase Account                     ← subtotal
DR  CGST Input Tax                                 ← cgst_amount
DR  SGST Input Tax                                 ← sgst_amount
DR  IGST Input Tax                                 ← igst_amount
CR  Accounts Payable (vendor AP account)           ← total bill amount
```

### 3.4 Vendor Payment Ledger Entry

```
DR  Accounts Payable (vendor AP account)           ← payment amount
CR  Cash/Bank Account                              ← payment amount
```

### 3.5 Expense Posting Ledger Entry

```
DR  Expense Category's linked_account              ← expense amount
DR  CGST/SGST/IGST Input Tax                       ← tax amounts
CR  Cash/Bank Account                              ← total
```

### 3.6 Cancellation / Reversal

All cancellations create a **mirror reversal journal entry** with all debits/credits swapped. The original locked journal entry is never modified.

### 3.7 Journal Entry Immutability

Once created, journal entries have `is_locked = true`. Any attempt to UPDATE them raises an error. The frontend should never try to edit journal entries — only cancel the source document.

---

## 4. Inventory Rules

### 4.1 Stock Movement

| Transaction | Effect |
|-------------|--------|
| Invoice POSTED (GOODS product) | `current_stock` decremented |
| Invoice CANCELLED | `current_stock` restored |
| Bill POSTED (GOODS product) | `current_stock` incremented |
| Bill CANCELLED | `current_stock` reversed |
| Inventory Adjustment CONFIRMED | `current_stock` changed by `quantity_change` |
| Sales Return POSTED | `current_stock` incremented |
| Purchase Return POSTED | `current_stock` decremented |

### 4.2 Negative Stock

The backend currently allows negative stock. The frontend should warn the user when `quantity > current_stock` for GOODS products.

### 4.3 Reorder Alert

When `current_stock <= reorder_level`, the product is flagged. Frontend should surface this via product list or dashboard.

### 4.4 Stock Ledger

Every stock movement creates an entry in `stock_ledger` with `running_balance`. Use this for stock audit trail.

---

## 5. Voucher Numbering Rules

- Each document type has exactly **one active** `NumberingSeries` per tenant
- `next_number` is incremented atomically using `SELECT FOR UPDATE`
- Format: `{prefix}{next_number padded to padding_digits}{suffix}`
- Example: prefix=`INV-`, next_number=5, padding=4 → `INV-0005`
- On creating a new series, all other active series for that document type are deactivated
- Manual override of `invoice_number` is possible on creation (bypasses series)

---

## 6. Period Lock Rules

- Accounting periods can be **locked** by `owner` or `accountant`
- A locked period prevents creating, updating, or cancelling any transaction dated within it
- Endpoint: `POST /accounting/periods/lock` (**not yet implemented as a dedicated endpoint** — see MISSING_APIS.md)
- `validate_period_open(db, tenant_id, date)` is called in: invoice create/finalize, bill create/finalize, payment create, expense post, sales return, purchase return
- When locked: HTTP 400 `{"detail": "Period YYYY-MM is locked."}`

---

## 7. Financial Year Rules

### 7.1 FY Status Machine

```
ACTIVE ──[close]──▶ LOCKED ──[reopen]──▶ ACTIVE
                  ──[archive]──▶ ARCHIVED
```

`READY_TO_CLOSE` is a transient state set during the close process.

### 7.2 Pre-Close Checklist

Before closing a FY (`GET /financial-years/{fy_id}/dashboard`):
- All invoices must be POSTED or CANCELLED (no DRAFTs in the FY period)
- All bills must be POSTED or CANCELLED
- All expenses must be POSTED or CANCELLED
- Trial balance must be balanced (debits == credits)
- Any unresolved items appear in `blocking_items`

### 7.3 FY Close Actions

1. Marks FY status as `LOCKED`
2. Creates `opening_balance_snapshots` for all accounts
3. Creates `inventory_carry_forward` for all products
4. Automatically creates the next FY if it doesn't exist
5. Writes FY audit trail entry

### 7.4 Single Current FY

Only one FY can have `is_current = true` per tenant. The system auto-detects the current FY from today's date against FY date ranges.

---

## 8. TDS / TCS Rules

### 8.1 TDS (Tax Deducted at Source)

- Applied on invoice and bill level
- `tds_rate` is set as a percentage (e.g. 10.00 for 10%)
- `tds_amount = subtotal × tds_rate / 100`
- TDS does NOT reduce `total` on the invoice — it reduces the payment amount due
- **Frontend**: Show `Net Payable = total - tds_amount` to user

### 8.2 TCS (Tax Collected at Source)

- Applied on sales invoices only
- `tcs_rate` and `tcs_amount` stored on invoice
- TCS is added to the invoice total: customer pays `total + tcs_amount`

---

## 9. Duplicate Prevention

| Scenario | Rule |
|---------|------|
| Invoice number | UNIQUE `(tenant_id, invoice_number)` — HTTP 409 on duplicate |
| Bill number | UNIQUE `(tenant_id, bill_number)` |
| Payment number | UNIQUE `(tenant_id, payment_number)` |
| IRN | UNIQUE across all tenants |
| Contact name | Case-insensitive normalised before checking for duplicates |
| GSTIN | UNIQUE per tenant on contacts |

---

## 10. Delete Restrictions

| Model | Delete allowed? | Restriction |
|-------|----------------|-------------|
| Contact | Soft-delete only | Cannot delete if linked to active invoices, bills, payments |
| Product | Soft-delete only | Cannot delete if linked to active invoice/bill lines |
| Account | Soft-delete only | Cannot delete if linked to journal lines (FK RESTRICT) |
| Invoice | Hard delete (DRAFT only) | POSTED → must cancel; PAID → cannot delete |
| Bill | Hard delete (DRAFT only) | Same as Invoice |
| Expense | Hard delete (DRAFT only) | POSTED → must cancel |
| Payment | Cancel only (reversal) | No hard delete |
| Journal Entry | No delete/update | Immutable; reverse via cancellation |
| Financial Year | No delete | — |

---

## 11. Multi-Tenant Isolation

- Every database query includes `tenant_id` filter
- `tenant_id` is derived from the JWT `scopes` claim + `X-Tenant-ID` header verification
- Membership is validated on each request via `get_tenant_context`
- Row-Level Security (PostgreSQL) policies are defined in `V001__rls_policies.sql` as an additional layer

---

## 12. Approval Workflows

There is **no formal approval workflow** in the current backend. All users with `invoice:finalize` permission can post directly. Implement approval as a frontend-only flow or request the missing API (see MISSING_APIS.md).

---

## 13. Discount Rules

- Discount is applied **per line item** as an absolute amount (₹), not percentage
- `subtotal = (rate × quantity) - discount`
- Line-level discount must not exceed `rate × quantity`
- Header-level discount (`discount_total`) is the sum of all line discounts

---

## 14. Rounding and Precision

| Field | Precision |
|-------|-----------|
| Rate, Subtotal, Total | 4 decimal places (NUMERIC 15,4) |
| GST rates | 2 decimal places (NUMERIC 5,2) |
| Quantity | 4 decimal places (NUMERIC 12,4) |
| Exchange rate | 6 decimal places (NUMERIC 15,6) |
| Display | Round to 2 decimal places for UI |
| `round_off` | System-calculated; ≤ ±₹0.50 |

---

## 15. Export / Overseas Supply

`supply_type` on Invoice:
- `DOMESTIC`: Standard domestic B2B or B2C
- `EXPORT_WITH_TAX`: Export with IGST
- `EXPORT_WITHOUT_TAX`: Export under bond/LUT (zero-rated)
- `SEZ_WITH_TAX`: Supply to SEZ with IGST
- `SEZ_WITHOUT_TAX`: Supply to SEZ under bond (zero-rated)

For exports, `pos_state_code` is typically `96` (Outside India).
