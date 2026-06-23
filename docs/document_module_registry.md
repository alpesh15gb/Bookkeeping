# Document Module Registry

| Module | Type | List Pattern | Form Pattern | Preview Pattern | Conversion |
| --- | --- | --- | --- | --- | --- |
| Sales Invoice | `salesInvoice` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Invoice -> Payment |
| Tax Invoice | `taxInvoice` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Invoice -> Payment |
| Estimate / Quotation | `estimate` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Estimate -> Sales Order |
| Proforma Invoice | `proformaInvoice` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Proforma -> Sales Invoice |
| Sales Order | `salesOrder` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Sales Order -> Invoice |
| Delivery Challan | `deliveryChallan` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Challan -> Invoice |
| Purchase Order | `purchaseOrder` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Purchase Order -> Purchase Bill |
| Purchase Invoice | `purchaseInvoice` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Purchase Invoice -> Payment Voucher |
| Credit Note | `creditNote` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Credit Note -> Adjustment |
| Debit Note | `debitNote` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Debit Note -> Adjustment |
| Receipt Voucher | `receiptVoucher` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Receipt -> Ledger allocation |
| Payment Voucher | `paymentVoucher` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Payment -> Ledger allocation |
| Journal Voucher | `journalVoucher` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Journal -> Reversal journal |
| Contra Voucher | `contraVoucher` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Contra -> Reversal contra |
| Expense Entry | `expenseEntry` | `AppDocumentList` | `AppDocumentForm` | `AppDocumentPreview` | Expense -> Payment Voucher |

## Shared Columns

Desktop columns are always:

1. Document No
2. Date
3. Party
4. Amount
5. Tax
6. Total
7. Balance
8. Status
9. Actions

If a module has no party, use ledger/account name in the party column. If a module has no tax, tax is zero. If a module has no outstanding concept, balance is zero.

## Shared Form Sections

All modules keep the same section order:

1. Header
2. Party Information
3. Item Entry Grid
4. Charges
5. Tax Summary
6. Sticky Totals
7. Notes & Attachments
8. Audit Information

Voucher modules may label party as ledger/account, but the layout and component remain `AppPartyCard`.

