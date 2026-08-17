# Legacy migration CSV schema

`tools/legacy_to_csv.py` converts Vyapar `.vyb` backups and Tally XML
exports into the CSVs described below. The conversion runs the **same
import code the app uses in production** against a throwaway database and
then dumps the result — the numbers you review here are exactly what would
have landed in ApexBooks.

```
python -m tools.legacy_to_csv vyapar  backup.vyb  --out ./migration [--xlsx]
python -m tools.legacy_to_csv tally   export.xml --out ./migration [--xlsx]
```

**CSV is canonical.** The `--xlsx` bundle is for human review only — Excel
silently mangles 15-digit GSTINs and reformats dates, so never treat the
workbook as the source of truth or try to re-import from it.

All CSVs are UTF-8 with a BOM (opens cleanly in Excel), header row first,
dates as `YYYY-MM-DD`, money as plain decimal strings.

## Files and columns

### contacts.csv — parties
| column | notes |
|---|---|
| name | party name |
| contact_type | CUSTOMER / VENDOR / BOTH |
| gstin, pan | keep as text — do not let Excel reformat |
| email, phone | |
| state_code | 2-digit |
| billing_address | JSON blob |
| opening_balance | party ledger balance from the legacy books (signed: receivable positive) |

### products.csv — stock items
name, sku, hsn_sac, product_type, uom, sales_price, purchase_price,
gst_rate, opening_stock, current_stock, reorder_level

### invoices.csv / bills.csv — document headers
`invoice_number`/`bill_number`, `customer`/`vendor` (name), issue_date,
due_date, pos_state_code, status, subtotal, discount_total, cgst_amount,
sgst_amount, igst_amount, cess_amount, round_off, shipping_charges, total,
amount_paid (+ `tds_amount` on bills)

### invoice_lines.csv / bill_lines.csv — line items
document_number, product (name), description, hsn_sac, quantity, rate,
discount, subtotal, gst_rate, cgst_amount, sgst_amount, igst_amount, total

### payments.csv / bill_payments.csv — receipts and disbursements
payment_number, customer/vendor (name), payment_date, payment_mode, amount,
reference_number, status

### payment_allocations.csv / bill_payment_allocations.csv — settlement
payment_number, invoice_number/bill_number, amount

### expenses.csv
expense_number, category, expense_date, vendor_name, description, amount,
gst_rate, cgst_amount, sgst_amount, igst_amount, total, status

### stock_ledger.csv — inventory movements
product, entry_date, reference_type, quantity, balance_quantity, rate

### accounts.csv — chart of accounts
code, account_name, account_type, opening_balance
(ASSET/EXPENSE are debit-natured; LIABILITY/EQUITY/REVENUE credit-natured)

### proforma_invoices.csv — estimates
proforma_number, customer, issue_date, due_date, status, total

## Reconcile before you upload

1. **Totals** — `report.txt` prints the summed invoice value, bill value,
   GST collected/paid, active receipts/disbursements, and net opening
   balance. Compare these against your last GST return and the legacy
   closing trial balance.
2. **Opening balance** — `accounts.csv` net must equal the legacy trial
   balance (assets + expenses − liabilities − equity − revenue = 0).
3. **Statuses** — `PARTIALLY_PAID` documents carry an `amount_paid`; check
   `payment_allocations`/`bill_payment_allocations` settle them.
4. **Spot check** — open each CSV in Excel and verify a handful of rows
   against the legacy software.

Any `import_status` other than 200, or anything under **Warnings** in
`report.txt`, means the source file failed to map fully — resolve before
uploading. `summary.json` is the machine-readable version of the report.

## Uploading to ApexBooks

`POST /api/v1/import/csv` (permission `data:import`) consumes exactly the
schema above.  Send either a **ZIP of the CSVs** (zip the converter's output
directory) or the **CSV files themselves** as multiple multipart files.

```
POST /api/v1/import/csv?dry_run=true
Content-Type: multipart/form-data
  file: bundle.zip
  X-Tenant-ID: <tenant>
  Authorization: Bearer <token>
```

### The money-safety contract

* **Validation runs before anything is written.** Headers must match the
  converter schema exactly, every cross-file reference must resolve
  (customer/product/document), and every money invariant is checked:
  the DB-enforced document total formula, per-line identities, payment ⇄
  allocation ⇄ `amount_paid` settlement, derived document status, net-zero
  opening balances, and duplicate detection against the tenant.
* **`dry_run=true` (the default) only reports** — `valid`, `errors`,
  `warnings`, the money `totals` and would-be `counts`.  Nothing is written.
* **`dry_run=false` commits in a single transaction.**  Any validation error
  or write failure rolls back completely; a partial import is impossible.
* Re-importing an already-imported bundle is rejected: documents whose numbers
  already exist in the tenant (and contacts/products matched by
  GSTIN/SKU/name) are reported as errors.

### Response

```json
{
  "valid": true,
  "dry_run": true,
  "committed": false,
  "errors": [],
  "warnings": [],
  "totals": {
    "invoice_total": "995087.17", "invoice_gst": "151792.96",
    "bill_total": "156275.44", "bill_gst": "14061.19",
    "payments_received": "825502.09", "payments_made": "156275.33",
    "expenses_total": "0", "opening_balance_net": "0"
  },
  "counts": {"contacts_imported": 17, "invoices_imported": 23, "...": "..."}
}
```

`counts` is populated only after a successful commit.  `warnings` covers
non-blocking but real issues: documents dated outside the current financial
year (switch the FY or fix the dates first), a few-paise residual left by the
legacy importers' rounding (the document imports with a sub-₹1 residual), and
unknown extra columns.  `errors` is the reject list — fix and re-upload;
nothing was written.

**Excel files are refused** (`review-only`) — the workbook is for human
review only and must never be re-imported; CSV is canonical.

## Known caveats (from the importers themselves)

- **Tally**: the importer currently maps Sales → invoice, Purchase → bill,
  Receipt → payment, Payment → bill payment; journal/contra vouchers are
  skipped, and credit/debit notes are skipped. If your Tally export relies
  on those, review `summary.json` counts.
- **Vyapar**: invoice/bill numbers come from the backup as-is (duplicates
  are renumbered); linked transactions (e.g., payments against invoices)
  are imported where the backup records them.
- Documents land with the app's own statuses (`POSTED`, `PARTIALLY_PAID`,
  `PAID`, …); drafts are not imported.
