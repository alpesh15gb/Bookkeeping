# ApexBooks — Accounting Workflow Guide
> Step-by-step API call sequences for all major accounting workflows.

---

## 1. Onboarding a New Company

```
1. POST /auth/register
   → Gets user + tenant created in one call
   → Returns access_token + refresh_token

2. GET /auth/me
   → Confirm user profile

3. GET /auth/memberships
   → Get tenant_id from memberships[0].tenant_id

4. POST /companies/{id}/gst-toggle
   body: { "tax_mode": "GST_REGULAR" }
   → Enable GST

5. PUT /settings
   body: { "origin_state_code": "27", "upi_id": "business@upi" }
   → Set home state

6. POST /settings/logo
   → Upload company logo (multipart/form-data)

7. POST /masters/accounts/seed-defaults
   → Creates 80+ standard accounts (Assets, Liabilities, Revenue, Expenses, GST)

8. POST /settings/series
   body: { "document_type": "INVOICE", "prefix": "INV-", ... }
   → Configure invoice numbering

9. POST /financial-years
   body: { "name": "FY 2025-26", "start_date": "2025-04-01", "end_date": "2026-03-31" }
   → Create current financial year
```

---

## 2. Sales Invoice Workflow (Complete)

### Step 1: Create Contact (if new)
```
POST /masters/contacts
→ Returns contact with id
```

### Step 2: Create Product (if new)
```
POST /masters/products
→ Returns product with id
```

### Step 3: Preview Invoice (optional, real-time totals)
```
POST /invoices/preview
body: { pos_state_code, contact_id, line_items: [...] }
→ Returns computed totals without saving
→ Use this for live tax calculation as user types
```

### Step 4: Create Invoice (DRAFT)
```
POST /invoices
→ Returns InvoiceResponse with status: "DRAFT"
→ invoice_number auto-assigned
```

### Step 5: Finalize Invoice
```
POST /invoices/{id}/finalize
→ Status: DRAFT → POSTED
→ Ledger entry created
→ Stock decremented (GOODS)
```

### Step 6: Generate e-Invoice (if enabled)
```
POST /invoices/{id}/e-invoice
→ Submits to NIC IRP
→ Returns IRN + QR code
→ Invoice.e_invoice_status: PENDING → GENERATED
```

### Step 7: Generate e-Way Bill (if goods > ₹50,000)
```
POST /eway-bills
body: { invoice_id, trans_mode, vehicle_number, trans_distance, ... }
→ Returns EWayBillResponse with eway_bill_number
```

### Step 8: Print / Email Invoice
```
GET /invoices/{id}/print   → PDF bytes
POST /invoices/{id}/email  → Queues email (Celery task)
```

### Step 9: Record Payment
```
POST /invoices/{id}/payment
body: { amount, payment_date, payment_mode, reference_number }
→ Invoice: POSTED → PARTIALLY_PAID or PAID
```

### Alternative: Standalone Receipt
```
POST /payments/receipts
body: { contact_id, payment_date, payment_mode, amount, allocations: [{invoice_id, amount}] }
→ Allows allocating one payment across multiple invoices
```

---

## 3. Purchase Invoice (Vendor Bill) Workflow

### Option A: Manual Entry
```
1. POST /masters/contacts          → Create vendor (contact_type: VENDOR)
2. POST /bills                     → Create bill (DRAFT)
3. POST /bills/{id}/finalize       → Post bill → ledger entries created
4. POST /bills/{id}/payment        → Record payment OR
   POST /payments/disbursements    → Standalone vendor payment with allocations
```

### Option B: OCR Scan Workflow
```
1. POST /bills/scan/preview        → Upload bill image/PDF
   body: multipart/form-data file
   → Returns { job_id }

2. GET /bills/scan/status?job_id={id}    → Poll until status: "done"
   → Returns extracted fields (vendor, amount, GST, line items)

3. User reviews and edits extracted data on frontend

4. POST /bills/scan/save           → Save corrected data as a bill
   → Creates Bill in DRAFT status

5. POST /bills/{id}/finalize       → Post bill
```

---

## 4. Purchase Order → Bill Workflow

```
1. POST /purchase-orders           → Create PO (DRAFT)
2. POST /purchase-orders/{id}/confirm  → Confirm PO (→ CONFIRMED)
3. POST /purchase-orders/{id}/receive  → Mark received (→ RECEIVED)

4. POST /bills                     → Create bill (reference_number = po_number)
5. POST /bills/{id}/finalize       → Post bill
```

---

## 5. Sales Order → Delivery → Invoice Workflow

```
1. POST /sales-orders              → Create SO (DRAFT)
2. POST /sales-orders/{id}/confirm → Confirm SO (→ CONFIRMED)

3. POST /delivery-challans         → Create delivery challan
4. POST /delivery-challans/{id}/issue → Issue DC (→ ISSUED)

5. POST /invoices                  → Create invoice (reference_number = so_number)
6. POST /invoices/{id}/finalize    → Post invoice
```

---

## 6. Proforma (Quotation) → Invoice Workflow

```
1. POST /proforma-invoices         → Create proforma (DRAFT)
2. POST /proforma-invoices/{id}/issue   → Issue to customer (→ ISSUED)
   Optional: GET /proforma-invoices/{id}/print → Send PDF to customer

3. POST /proforma-invoices/{id}/convert → Convert to real invoice
   → Creates Invoice (DRAFT) with same line items
   → Sets proforma status → CONVERTED
   → Returns { "invoice_id": "uuid" }

4. POST /invoices/{invoice_id}/finalize → Post converted invoice
```

---

## 7. Sales Return Workflow

```
1. POST /returns/sales
   body: {
     contact_id, return_date, pos_state_code,
     original_invoice_id (optional),
     line_items: [...]
   }
   → Creates Sales Return (POSTED immediately, no DRAFT step)
   → Ledger: DR Sales Return / CR Accounts Receivable
   → Stock: incremented

2. (If cancelling) POST /returns/sales/{id}/cancel
   → Reversal journal; stock decremented back
```

---

## 8. Credit Note Workflow

### Linked Credit Note (for specific invoice)
```
1. POST /invoices/credit-notes
   body: { invoice_id: "uuid", issue_date, reason, pos_state_code, line_items }
   → Status: DRAFT

2. POST /invoices/credit-notes/{id}/finalize
   → Status: POSTED
   → Ledger: DR Sales / CR Accounts Receivable + GST accounts
```

### Standalone Credit Note (general)
```
POST /invoices/credit-notes
body: { invoice_id: null, issue_date, reason, pos_state_code, line_items }
```

---

## 9. Expense Workflow

```
1. POST /masters/expense-categories        → Create category (if new)
2. POST /expenses/preview                  → Preview GST calculation
3. POST /expenses                          → Create expense (DRAFT)
4. POST /expenses/{id}/post                → Post expense (→ POSTED)
   → Ledger: DR expense account / CR cash-bank account
5. (If error) POST /expenses/{id}/cancel   → Reversal
```

---

## 10. Bank Reconciliation Workflow

```
1. GET /masters/banking-profiles           → Get bank account list

2. POST /bank-reconciliation/upload
   body: multipart CSV or Excel bank statement
   → Creates BankStatement + BankTransactions
   → Returns { statement_id, transactions_parsed }

3. GET /bank-reconciliation/statements/{id}/stats
   → Check reconciliation progress

4. POST /bank-reconciliation/statements/{statement_id}/auto-match
   → Automatically matches transactions to payments/bills
   → Returns { matched, matches[] }

5. GET /bank-reconciliation/statements/{statement_id}/suggestions
   → Get suggestions for unmatched transactions

6. GET /bank-reconciliation/pending-invoices  → AR for manual matching
7. GET /bank-reconciliation/pending-bills     → AP for manual matching

8. POST /bank-reconciliation/transactions/{transaction_id}/reconcile
   body: { payment_id OR bill_payment_id, amount, notes }
   → Links bank transaction to a payment record

9. POST /bank-reconciliation/bulk-reconcile
   body: { items: [{transaction_id, payment_id, amount}] }
   → Bulk reconcile multiple transactions at once

10. POST /bank-reconciliation/reconciliations/{id}/undo
    → Unlink a reconciliation if incorrect
```

---

## 11. Year-End Close Workflow

```
1. GET /financial-years                    → List all FYs; identify current

2. GET /financial-years/current            → Get current FY details

3. GET /financial-years/{fy_id}/dashboard
   → See pre-close checklist:
     - unposted_invoices: must be 0
     - unposted_bills: must be 0
     - unposted_expenses: must be 0
     - is_trial_balance_balanced: must be true
     - blocking_items: must be empty

4. Fix all blocking items:
   - POST /invoices/{id}/finalize or POST /invoices/{id}/cancel
   - POST /accounting/recalculate-balances (if balance issue)

5. POST /financial-years/{fy_id}/close
   body: { closing_date: "2026-03-31" }
   → FY status: LOCKED
   → Creates opening_balance_snapshots for all accounts
   → Creates inventory_carry_forward for all products
   → Auto-creates FY 2026-27

6. GET /financial-years/{fy_id}/opening-balances
   → Verify opening balances were captured

7. GET /financial-years/{fy_id}/inventory-carry-forward
   → Verify stock carry-forward

8. POST /financial-years/switch
   body: { financial_year_id: "new-fy-uuid" }
   → Switch context to new FY

9. POST /masters/accounts/seed-defaults (optional)
   → Add any new accounts needed for new FY
```

---

## 12. GST Filing Workflow

```
1. GET /gst/gstr1?start_date=2025-04-01&end_date=2025-04-30
   → Get GSTR-1 JSON data for review

2. GET /gst/gstr1/export?start_date=...&end_date=...
   → Download Excel for GST Offline Tool
   Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet

3. GET /gst/gstr2?start_date=...&end_date=...
   → Get GSTR-2 purchase summary

4. Upload GSTR-2A from GST portal for reconciliation:
   POST /gst/gstr2a/upload
   body: multipart JSON file from GST portal

5. GET /gst/gstr3b/export?start_date=...&end_date=...
   → Download GSTR-3B Excel summary

6. Review and file on GST portal manually
   (No direct GST portal filing API is integrated)
```

---

## 13. Recurring Invoice Setup

```
1. POST /recurring-invoices
   body: {
     contact_id, frequency: "MONTHLY", interval_value: 1,
     start_date, end_date, pos_state_code, items: [...]
   }

2. System auto-generates invoices via Celery beat schedule
   (Task: send_overdue_invoice_reminders runs daily)

3. Manual trigger: POST /recurring-invoices/{id}/generate
   → Immediately generates next invoice

4. GET /recurring-invoices → See all templates and next_generation_date
```

---

## 14. Double-Entry Accounting: Key Account Codes

Default accounts seeded by `POST /masters/accounts/seed-defaults`:

| Account Group | Account Name | Type | Code Range |
|---|---|---|---|
| Cash & Bank | Cash in Hand | Asset | 1001 |
| Cash & Bank | Bank Account | Asset | 1002 |
| Receivables | Accounts Receivable | Asset | 1100 |
| Payables | Accounts Payable | Liability | 2001 |
| GST Output | CGST Output | Liability | 2100 |
| GST Output | SGST Output | Liability | 2101 |
| GST Output | IGST Output | Liability | 2102 |
| GST Input | CGST Input | Asset | 1200 |
| GST Input | SGST Input | Asset | 1201 |
| GST Input | IGST Input | Asset | 1202 |
| Revenue | Sales Revenue | Revenue | 4001 |
| Purchases | Purchase Account | Expense | 5001 |
| Expenses | Other Expenses | Expense | 5100+ |

---

## 15. Manual Journal Entry (Contra / Adjustment)

Contra entry (Cash → Bank transfer):
```
POST /accounting/journals
body: {
  "entry_date": "2025-04-15",
  "description": "Transfer from Cash to Bank",
  "lines": [
    { "account_id": "uuid-bank",  "amount": "50000", "direction": "DEBIT" },
    { "account_id": "uuid-cash",  "amount": "50000", "direction": "CREDIT" }
  ]
}
```

**Rule:** DEBIT total must equal CREDIT total, else HTTP 400.
