# ApexBooks — Import & Export Guide

---

## 1. Data Export (Backup)

### GET `/companies/{tenant_id}/export`
**Permission:** `tenant:update` (owner only)  
**Rate limit:** 60/minute  
**Response:** JSON file download  
**Content-Disposition:** `attachment; filename=tenant_export_YYYY-MM-DDTHH-MM-SS.json`

**What is exported:**
- Company info (tenant)
- Settings + numbering series
- All contacts
- All products
- All accounts
- All invoices + lines + payments
- All bills + lines + bill payments
- All expenses + categories
- All journal entries + lines
- All credit/debit notes
- All sales/purchase returns
- All purchase/sales orders
- All proforma invoices
- All delivery challans
- Banking profiles
- Financial years

**Response structure:**
```json
{
  "export_version": "1.0",
  "exported_at": "2025-04-01T10:00:00+00:00",
  "tenant": { ... },
  "settings": { ... },
  "contacts": [...],
  "products": [...],
  "accounts": [...],
  "invoices": [...],
  "bills": [...],
  "expenses": [...],
  "journal_entries": [...],
  "credit_notes": [...],
  "debit_notes": [...],
  "sales_returns": [...],
  "purchase_returns": [...],
  "purchase_orders": [...],
  "sales_orders": [...],
  "proforma_invoices": [...],
  "delivery_challans": [...],
  "banking_profiles": [...],
  "financial_years": [...]
}
```

---

## 2. Data Import (Restore)

### POST `/companies/{tenant_id}/import`
**Permission:** `tenant:update` (owner only)  
**Content-Type:** `application/json` (raw JSON body)  
**Body:** Same JSON structure as the export response

**What happens:**
1. Clears existing transactional data
2. Imports contacts, products, accounts
3. Imports invoices, bills, expenses, payments
4. Imports journal entries
5. Returns import summary

**Response:**
```json
{
  "status": "success",
  "imported": {
    "contacts": 150,
    "products": 80,
    "invoices": 500,
    "bills": 300
  }
}
```

**Warning:** This is a destructive operation. Use `/purge/verify` first if clearing all data.

---

## 3. Vyapar Backup Import

### POST `/import/vyapar`
**Permission:** `tenant:update`  
**Content-Type:** `multipart/form-data`  
**Field name:** `file`  
**File type:** `.vyb` (Vyapar backup file)

**What is a .vyb file:**
- ZIP archive containing a `.vyp` SQLite database
- Created by **File → Backup** in the Vyapar app

**What gets imported:**
- Contacts (from `kb_names` table)
- Products/items (from `kb_item` table)
- Sales invoices (from `kb_transactions`)
- Purchase bills (from `kb_purchase`)
- Proforma/estimates (from Vyapar estimates)
- Payments (from `kb_payment`)
- Stock entries (from `kb_stock`)
- E-invoice data (from Vyapar e-invoice records)
- Opening balances
- Custom fields
- Party-specific item rates

**Response:**
```json
{
  "contacts_imported": 250,
  "products_imported": 120,
  "invoices_imported": 1500,
  "bills_imported": 800,
  "estimates_imported": 50,
  "expenses_imported": 200,
  "payments_imported": 1200,
  "stock_entries_imported": 300,
  "linked_transactions_imported": 100,
  "custom_fields_imported": 50,
  "party_addresses_imported": 250,
  "party_item_rates_imported": 120,
  "e_invoice_data_imported": 30,
  "opening_balances_set": 80,
  "errors": []
}
```

**Error handling:** Non-fatal errors are collected in `errors[]` array and import continues. Fatal errors return HTTP 400.

**Size limits:** No explicit size limit documented, but large files (>100k records) may time out. Run import on backend directly for very large databases.

---

## 4. Tally XML Import

### POST `/tally/import`
**Permission:** `data:import` (**BROKEN** — this permission is not assigned to any role. See MISSING_APIS.md)  
**Content-Type:** `multipart/form-data`  
**Field name:** `file`  
**File type:** `.xml` (Tally XML export)

**What is a Tally XML export:**
- Exported from Tally via: `Company → Export → XML`
- Contains `ENVELOPE > BODY > IMPORTDATA > REQUESTDATA > TALLYMESSAGE` elements

**What gets imported:**
- `LEDGER` → Contacts (Sundry Debtors → CUSTOMER; Sundry Creditors → VENDOR)
- `STOCKITEM` → Products (with HSN, GST rate, UOM)
- `VOUCHER` → Invoices, Bills, Payments, Expenses, Credit Notes, Debit Notes

**Response:**
```json
{
  "contacts_imported": 200,
  "products_imported": 100,
  "invoices_imported": 1000,
  "bills_imported": 500,
  "expenses_imported": 300,
  "payments_imported": 800,
  "errors": []
}
```

---

## 5. Tally XML Export

### GET `/tally/export`
**Permission:** `tenant:view`  
**Response:** XML file download  
**Content-Disposition:** `attachment; filename=tally_export_YYYY-MM-DD.xml`

**What is exported:**
- Contacts as Tally Ledgers (with GSTIN, address, opening balance)
- Products as Tally Stock Items (with HSN, GST rate)
- Invoices as Sales Vouchers
- Bills as Purchase Vouchers
- Payments as Receipt/Payment Vouchers
- Credit/Debit Notes as Credit/Debit Note Vouchers
- Expenses as Journal Vouchers

**Tally XML structure:**
```xml
<ENVELOPE>
  <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
  <BODY>
    <IMPORTDATA>
      <REQUESTDATA>
        <TALLYMESSAGE xmlns:UDF="...">
          <LEDGER NAME="Rajesh Enterprises">...</LEDGER>
          <STOCKITEM NAME="Steel Pipe">...</STOCKITEM>
          <VOUCHER VCHTYPE="Sales">...</VOUCHER>
        </TALLYMESSAGE>
      </REQUESTDATA>
    </IMPORTDATA>
  </BODY>
</ENVELOPE>
```

---

## 6. GST Report Exports

### GSTR-1 Excel Export
```
GET /gst/gstr1/export?start_date=2025-04-01&end_date=2025-04-30
```
**Response:** `.xlsx` file  
**Excel Sheets:**
- B2B (Registered Business Supplies)
- B2CL (Large Inter-state B2C)
- B2CS (Small/Intra-state B2C)
- CDNR (Credit/Debit Notes)
- HSN (HSN-wise Summary)
- Summary

**Compatible with:** GST Offline Tool (GSTN official tool)

### GSTR-1 PDF
```
GET /gst/gstr1/pdf?start_date=...&end_date=...
```

### GSTR-2 Excel Export
```
GET /gst/gstr2/export?start_date=...&end_date=...
```
**Excel Sheets:** B2B Purchases, CDNR, HSN Summary

### GSTR-2 PDF
```
GET /gst/gstr2/pdf?start_date=...&end_date=...
```

### GSTR-3B Excel Export
```
GET /gst/gstr3b/export?start_date=...&end_date=...
```
**Excel Sheets:** Table 3.1, Table 4 (ITC), Table 5, Summary

### GSTR-3B PDF
```
GET /gst/gstr3b/pdf?start_date=...&end_date=...
```

---

## 7. Financial Report Exports

All financial reports support both Excel (XLSX) and PDF export:

| Report | Excel Endpoint | PDF Endpoint |
|--------|---------------|-------------|
| Trial Balance | `GET /reports/trial-balance/excel?as_of_date=...` | `GET /reports/trial-balance/pdf?as_of_date=...` |
| Profit & Loss | `GET /reports/profit-loss/excel?date_from=...&date_to=...` | `GET /reports/profit-loss/pdf?...` |
| Balance Sheet | `GET /reports/balance-sheet/excel?as_of_date=...` | `GET /reports/balance-sheet/pdf?...` |
| Cash Flow | `GET /reports/cash-flow/excel?start_date=...&end_date=...` | `GET /reports/cash-flow/pdf?...` |
| AR Aging | `GET /reports/aging/ar/excel?as_of_date=...` | `GET /reports/aging/ar/pdf?...` |
| AP Aging | `GET /reports/aging/ap/excel?...` | `GET /reports/aging/ap/pdf?...` |
| Outstanding AR | `GET /reports/outstanding/ar/excel?...` | `GET /reports/outstanding/ar/pdf?...` |
| Outstanding AP | `GET /reports/outstanding/ap/excel?...` | `GET /reports/outstanding/ap/pdf?...` |
| Party Statement | `GET /reports/party-statement/excel?contact_id=...&start_date=...&end_date=...` | `GET /reports/party-statement/pdf?...` |
| Cash Book | `GET /reports/cash-book/excel?start_date=...&end_date=...` | `GET /reports/cash-book/pdf?...` |

---

## 8. GSTR-2A Reconciliation Import

### POST `/gst/gstr2a/upload`
**Content-Type:** `multipart/form-data`  
**Field name:** `file`  
**Accepted format:** JSON file (downloaded from GST portal)

**How to get GSTR-2A JSON from GST portal:**
1. Login to `gst.gov.in`
2. Services → Returns → Auto Drafted Returns
3. Select GSTR-2A → Download JSON

**What happens:**
- Parses B2B invoices from GSTR-2A
- Matches against purchase bills in ApexBooks by invoice number + supplier GSTIN
- Returns matched, unmatched, and partially matched items

---

## 9. Bank Statement Import

### POST `/bank-reconciliation/upload`
**Content-Type:** `multipart/form-data`  
**Field name:** `file`  
**Accepted formats:** CSV, Excel (.xlsx, .xls)

**Supported bank formats (auto-detected):**
- HDFC Bank
- ICICI Bank
- SBI (State Bank of India)
- Axis Bank
- Kotak Bank
- Yes Bank
- Generic (any CSV with Date, Description, Debit, Credit columns)

**Response:**
```json
{
  "statement_id": "uuid",
  "transactions_parsed": 150,
  "date_range": {
    "from": "2025-04-01",
    "to": "2025-04-30"
  }
}
```

**Query parameter:** `bank_format=AUTO` (default) or specify: `HDFC`, `ICICI`, `SBI`, `AXIS`, `KOTAK`, `YES`, `GENERIC`

---

## 10. Document PDF Downloads

Each document type has a print endpoint returning raw PDF bytes:

| Document | Endpoint |
|---------|---------|
| Sales Invoice | `GET /invoices/{id}/print` |
| Vendor Bill | `GET /bills/{id}/print` |
| Credit Note | `GET /invoices/credit-notes/{id}/print` |
| Debit Note | `GET /invoices/debit-notes/{id}/print` |
| Purchase Order | `GET /purchase-orders/{id}/print` |
| Sales Order | `GET /sales-orders/{id}/print` |
| Proforma Invoice | `GET /proforma-invoices/{id}/print` |

**Response headers:**
```
Content-Type: application/pdf
Content-Disposition: inline; filename=INV-2025-0001.pdf
```

**Note:** The token can also be passed as a query parameter for direct browser download links: `GET /invoices/{id}/print?token=<access_token>`

---

## 11. PDF Payload Endpoint (for Custom Frontend Rendering)

If you want to render PDFs on the frontend (e.g. using a React PDF library instead of server-generated PDF):

| Document | PDF Payload Endpoint |
|---------|---------------------|
| Invoice | `GET /invoices/{id}/pdf-payload` |
| Bill | `GET /bills/{id}/pdf-payload` |
| Purchase Order | `GET /purchase-orders/{id}/pdf-payload` |
| Sales Order | `GET /sales-orders/{id}/pdf-payload` |
| Proforma Invoice | `GET /proforma-invoices/{id}/pdf-payload` |

Returns all data needed to render a complete PDF document including company details, line items, tax summary, banking info, and terms.
