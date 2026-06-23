# ApexBooks Document Management Framework

## Goal

All business documents use one UI framework. Modules differ by document type, API adapter, validation rules, ledger/tax rules, and conversion targets. List, edit, preview, status, filters, actions, spacing, typography, and responsive behavior stay identical.

Covered modules:

- Sales Invoice, Tax Invoice, Estimate, Proforma Invoice
- Sales Order, Delivery Challan
- Purchase Order, Purchase Invoice
- Credit Note, Debit Note
- Receipt Voucher, Payment Voucher
- Journal Voucher, Contra Voucher
- Expense Entry

## Component Architecture

Flutter source:

- `lib/document_framework/document_models.dart`
- `lib/document_framework/document_components.dart`
- `lib/document_framework/document_framework.dart`

Core widgets:

- `AppDocumentList`: header, summary, instant search, filter bar, desktop table, mobile cards, pagination, actions.
- `AppDocumentForm`: common form scaffold with document header, party, items, charges, tax, totals, notes, audit.
- `AppPartyCard`: party quick view.
- `AppItemGrid`: inline spreadsheet-style item entry surface.
- `AppTaxSummary`: CGST/SGST/IGST/CESS/HSN summary.
- `AppTotalsPanel`: sticky totals summary.
- `AppStatusChip`: site-wide document status.
- `AppDocumentPreview`: document viewer with action rail and tabs.
- `AppTimeline`: created/edited/printed/shared/paid/cancelled history.
- `AppFilterBar`, `AppSearchBar`, `AppActionMenu`, `AppAttachmentWidget`.

## List Wireframe

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ [icon] Invoices        [Documents 124] [Value ₹9.8L] [Outstanding ₹1.2L]  │
│                                      [+ New Invoice] [Import] [Export]     │
├────────────────────────────────────────────────────────────────────────────┤
│ Search no, party, mobile, GSTIN, amount, item                              │
├────────────────────────────────────────────────────────────────────────────┤
│ [Date Range] [Status] [Party] [Amount] [Created By] [Branch] [FY] chips   │
├────────────────────────────────────────────────────────────────────────────┤
│ □ Document No | Date | Party | Amount | Tax | Total | Balance | Status | ⋯ │
│ □ INV-001     | ...  | ...   | ...    | ... | ...   | ...     | Paid   | ⋯ │
└────────────────────────────────────────────────────────────────────────────┘
```

Mobile:

```text
┌──────────────────────────────┐
│ INV-001                  Paid│
│ ABC Traders                  │
│ 22 Jun 2026          ₹12,400 │
│ Outstanding ₹2,400           │
│ [copy] [delete]       Share  │
└──────────────────────────────┘
Swipe right: Edit. Swipe left: Share.
```

## Edit Wireframe

```text
┌──────────────────────────────────────┬────────────────────────┐
│ Document Header                      │ Sticky Totals          │
│ Party Information                    │ Subtotal               │
│ Item Grid                            │ Discount               │
│ Charges                              │ Tax                    │
│ Tax Summary                          │ Round Off              │
│ Notes & Attachments                  │ Grand Total            │
│ Audit Information                    │ Paid / Balance         │
└──────────────────────────────────────┴────────────────────────┘
```

Item entry is inline only. Popup item forms are not part of the primary workflow. Keyboard movement should follow: item -> description -> qty -> unit -> rate -> discount -> tax -> next row.

## Preview Wireframe

```text
┌──────────────────────────────────────────────┬─────────────────┐
│ Document / Ledger / GST / Attachments / ...  │ Edit            │
│ Modern document view                         │ Print           │
│ Ledger impact                                │ Download PDF    │
│ GST impact                                   │ WhatsApp        │
│ Timeline                                     │ Email           │
│ Payments                                     │ Duplicate       │
│ Audit trail                                  │ Convert         │
└──────────────────────────────────────────────┴─────────────────┘
```

## Status Model

Use `DocumentStatus` as the single source of truth.

- Draft
- Pending / Posted / Approved mapped to `posted`
- Overdue
- Paid
- Partially Paid
- Cancelled

All API statuses must normalize through `DocumentStatus.fromApi`.

## Conversion Workflow

Conversion is a framework action:

- Estimate -> Sales Order
- Sales Order -> Invoice
- Invoice -> Payment
- Purchase Order -> Purchase Bill

Rule: preserve party, addresses, tax treatment, item rows, charges, terms, attachments, source document link, and audit trail. The target form opens prefilled and requires only review/save.

## Module Configuration

Each module should eventually declare:

```dart
class DocumentModuleConfig {
  final AppDocumentType type;
  final String listRoute;
  final String createRoute;
  final String detailRoutePattern;
  final Future<List<AppDocumentRecord>> Function() load;
  final List<ConversionTarget> conversions;
  final DocumentRules rules;
}
```

Feature screens should become adapters:

```dart
AppDocumentList(
  documentType: AppDocumentType.salesInvoice,
  records: invoices.map(invoiceToDocumentRecord).toList(),
  actions: AppDocumentListActions(
    onNew: () => context.go('/invoices/create'),
    onOpen: (row) => context.go('/invoices/${row.id}'),
  ),
)
```

## React Reference Components

There is no React source app in this repository; `frontend/` is built Flutter web output. If a React client is added, use the same shape:

```tsx
export function AppDocumentList<T>({
  documentType,
  records,
  columns,
  actions,
}: DocumentListProps<T>) {
  return (
    <DocumentPage>
      <DocumentHeader />
      <AppSearchBar />
      <AppFilterBar />
      <ResponsiveDocumentBody desktop={<DocumentTable />} mobile={<DocumentCards />} />
    </DocumentPage>
  );
}
```

```tsx
export function AppDocumentForm({ sections, totals }: DocumentFormProps) {
  return (
    <DocumentFormLayout
      main={<>{sections.header}{sections.party}{sections.items}{sections.charges}{sections.tax}{sections.notes}{sections.audit}</>}
      aside={<AppTotalsPanel values={totals} />}
    />
  );
}
```

## Migration Plan

1. Land shared framework components and docs.
2. Migrate active lists: invoices, bills, expenses, payments.
3. Migrate remaining list modules with adapters only.
4. Replace create/edit screens with `AppDocumentForm` shell and inline `AppItemGrid`.
5. Replace detail pages with `AppDocumentPreview`.
6. Move conversion actions into framework-level actions.
7. Remove feature-specific duplicated filter/search/table/status code.

## UX Rules

- Create document: visible primary action on every list; no more than 3 clicks.
- Edit document: row action and detail action; no more than 2 clicks.
- Search is instant and covers no, party, mobile, GSTIN, amount, and item text.
- Desktop prioritizes scan density, sticky header, sorting, selection, pagination.
- Mobile uses cards with visible quick actions and swipe affordances.
- Status colors and action placement are framework-owned.

