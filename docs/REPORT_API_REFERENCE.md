# ApexBooks — Report API Reference
> All report endpoints require: `Authorization: Bearer <token>` + `X-Tenant-ID: <uuid>`  
> Permission: `reports:view` (unless noted)

---

## 1. Trial Balance

### GET `/reports/trial-balance`
**Query Parameters:**
| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `as_of_date` | date (YYYY-MM-DD) | No | today | Cut-off date |

**Also available at:** `GET /accounting/trial-balance`

**Response:**
```json
{
  "as_of_date": "2025-03-31",
  "lines": [
    {
      "account_name": "Cash in Hand",
      "account_code": "1001",
      "account_type": "ASSET",
      "account_group": "Cash & Bank",
      "opening_debit": "0.0000",
      "opening_credit": "0.0000",
      "period_debit": "50000.0000",
      "period_credit": "30000.0000",
      "closing_balance": "20000.0000"
    }
  ],
  "total_debits": "500000.0000",
  "total_credits": "500000.0000",
  "is_balanced": true
}
```

**Export:**
- `GET /reports/trial-balance/excel` → XLSX file
- `GET /reports/trial-balance/pdf` → PDF file

---

## 2. Profit & Loss Statement

### GET `/reports/profit-loss`
**Also at:** `GET /accounting/profit-loss`

**Query Parameters:**
| Param | Type | Required | Default |
|-------|------|----------|---------|
| `date_from` | date | Yes | — |
| `date_to` | date | Yes | — |

**Response:**
```json
{
  "period_start": "2025-04-01",
  "period_end": "2026-03-31",
  "revenue_lines": [
    {
      "account_name": "Sales Revenue",
      "account_code": "4001",
      "amount": "5000000.0000"
    }
  ],
  "expense_lines": [
    {
      "account_name": "Purchase Account",
      "account_code": "5001",
      "amount": "3500000.0000"
    }
  ],
  "total_revenue": "5000000.0000",
  "total_expenses": "3500000.0000",
  "net_profit": "1500000.0000"
}
```

**Export:**
- `GET /reports/profit-loss/excel?date_from=...&date_to=...` → XLSX
- `GET /reports/profit-loss/pdf?date_from=...&date_to=...` → PDF

---

## 3. Balance Sheet

### GET `/reports/balance-sheet`
**Also at:** `GET /accounting/balance-sheet`

**Query Parameters:**
| Param | Type | Required | Default |
|-------|------|----------|---------|
| `as_of_date` | date | No | today |

**Response:**
```json
{
  "as_of_date": "2026-03-31",
  "assets": {
    "items": [
      { "account_name": "Cash in Hand", "account_code": "1001", "balance": "50000.0000" },
      { "account_name": "Accounts Receivable", "account_code": "1100", "balance": "250000.0000" }
    ],
    "total": "300000.0000"
  },
  "liabilities": {
    "items": [
      { "account_name": "Accounts Payable", "account_code": "2001", "balance": "150000.0000" }
    ],
    "total": "150000.0000"
  },
  "equity": {
    "items": [
      { "account_name": "Capital Account", "account_code": "3001", "balance": "100000.0000" }
    ],
    "total": "100000.0000"
  },
  "net_profit": "50000.0000",
  "is_balanced": true
}
```

**Export:**
- `GET /reports/balance-sheet/excel?as_of_date=...` → XLSX
- `GET /reports/balance-sheet/pdf?as_of_date=...` → PDF

---

## 4. Cash Flow Statement

### GET `/reports/cash-flow`

**Query Parameters:**
| Param | Type | Required |
|-------|------|----------|
| `start_date` | date | Yes |
| `end_date` | date | Yes |

**Response (Indirect Method):**
```json
{
  "period_start": "2025-04-01",
  "period_end": "2026-03-31",
  "sections": [
    {
      "section": "Operating Activities",
      "items": [
        { "label": "Net Profit", "amount": "1500000.00" },
        { "label": "Depreciation", "amount": "50000.00" },
        { "label": "Increase in Receivables", "amount": "-100000.00" }
      ],
      "net": "1450000.00"
    },
    {
      "section": "Investing Activities",
      "items": [
        { "label": "Purchase of Fixed Assets", "amount": "-200000.00" }
      ],
      "net": "-200000.00"
    },
    {
      "section": "Financing Activities",
      "items": [
        { "label": "Loan Repayment", "amount": "-100000.00" }
      ],
      "net": "-100000.00"
    }
  ],
  "opening_cash_balance": "50000.00",
  "net_change": "1150000.00",
  "closing_cash_balance": "1200000.00"
}
```

**Export:**
- `GET /reports/cash-flow/excel?start_date=...&end_date=...`
- `GET /reports/cash-flow/pdf?start_date=...&end_date=...`

---

## 5. General Ledger (Account Statement)

### GET `/accounting/ledger/{account_id}`

**Query Parameters:**
| Param | Type | Required | Default |
|-------|------|----------|---------|
| `date_from` | date | No | FY start |
| `date_to` | date | No | today |
| `page` | int | No | 1 |
| `limit` | int | No | 100 |

**Response:**
```json
{
  "account_id": "uuid",
  "account_name": "Accounts Receivable",
  "account_code": "1100",
  "opening_balance": "0.0000",
  "lines": [
    {
      "entry_date": "2025-04-15",
      "reference_number": "INV-2025-0001",
      "description": "Sales Invoice to Rajesh Enterprises",
      "debit": "2950.0000",
      "credit": "0.0000",
      "running_balance": "2950.0000"
    },
    {
      "entry_date": "2025-05-10",
      "reference_number": "RCPT-2025-0001",
      "description": "Payment received",
      "debit": "0.0000",
      "credit": "2950.0000",
      "running_balance": "0.0000"
    }
  ],
  "closing_balance": "0.0000",
  "total_lines": 2
}
```

---

## 6. Day Book

No dedicated Day Book endpoint exists. Use:
```
GET /accounting/journals?date_from=YYYY-MM-DD&date_to=YYYY-MM-DD&page=1&limit=200
```
Returns all journal entries for the period. Filter by `source_type` for specific voucher types.

**[MISSING API — see MISSING_APIS.md]**

---

## 7. Cash Book

### GET `/reports/cash-book`

**Query Parameters:**
| Param | Type | Required |
|-------|------|----------|
| `start_date` | date | Yes |
| `end_date` | date | Yes |

**Response:**
```json
{
  "period_start": "2025-04-01",
  "period_end": "2025-04-30",
  "rows": [
    {
      "date": "2025-04-15",
      "description": "Invoice INV-2025-0001",
      "type": "INFLOW",
      "amount": "2950.0000"
    },
    {
      "date": "2025-04-20",
      "description": "Expense EXP-202504-0001",
      "type": "OUTFLOW",
      "amount": "1000.0000"
    }
  ],
  "summary": {
    "cash_inflow": "2950.0000",
    "cash_outflow": "1000.0000",
    "net": "1950.0000",
    "difference": "1950.0000"
  },
  "tax_summary": {
    "tax_paid": "0.0000",
    "tax_received": "450.0000",
    "tax_payable": "450.0000"
  }
}
```

**Export:**
- `GET /reports/cash-book/excel?start_date=...&end_date=...`
- `GET /reports/cash-book/pdf?start_date=...&end_date=...`

---

## 8. AR / AP Aging Reports

### GET `/reports/aging/ar` — Receivables Aging
### GET `/reports/aging/ap` — Payables Aging

**Query Parameters:**
| Param | Type | Required | Default |
|-------|------|----------|---------|
| `as_of_date` | date | No | today |

**Response:**
```json
{
  "as_of_date": "2026-03-31",
  "contacts": [
    {
      "contact_id": "uuid",
      "contact_name": "Rajesh Enterprises",
      "buckets": [
        { "label": "Current", "count": 2, "amount": "50000.00" },
        { "label": "1-30 days", "count": 1, "amount": "25000.00" },
        { "label": "31-60 days", "count": 0, "amount": "0.00" },
        { "label": "61-90 days", "count": 0, "amount": "0.00" },
        { "label": "90+ days", "count": 1, "amount": "10000.00" }
      ]
    }
  ],
  "total_outstanding": "85000.00",
  "bucket_totals": [
    { "label": "Current", "count": 2, "amount": "50000.00" },
    { "label": "1-30 days", "count": 1, "amount": "25000.00" },
    { "label": "31-60 days", "count": 0, "amount": "0.00" },
    { "label": "61-90 days", "count": 0, "amount": "0.00" },
    { "label": "90+ days", "count": 1, "amount": "10000.00" }
  ]
}
```

**Export:**
- `GET /reports/aging/ar/excel?as_of_date=...`
- `GET /reports/aging/ar/pdf?as_of_date=...`
- `GET /reports/aging/ap/excel?as_of_date=...`
- `GET /reports/aging/ap/pdf?as_of_date=...`

---

## 9. Outstanding Documents

### GET `/reports/outstanding/ar` — Outstanding Invoices
### GET `/reports/outstanding/ap` — Outstanding Bills

**Query Parameters:** `as_of_date` (optional, default today)

**Response (AR):**
```json
{
  "as_of_date": "2026-03-31",
  "invoices": [
    {
      "invoice_id": "uuid",
      "invoice_number": "INV-2025-0001",
      "contact_name": "Rajesh Enterprises",
      "issue_date": "2025-04-15",
      "due_date": "2025-05-15",
      "total": "2950.00",
      "amount_paid": "0.00",
      "outstanding": "2950.00",
      "days_overdue": 320
    }
  ],
  "total_outstanding": "2950.00"
}
```

**Export:**
- `GET /reports/outstanding/ar/excel?as_of_date=...`
- `GET /reports/outstanding/ar/pdf?as_of_date=...`
- Same for `/ap`

---

## 10. Party Statement (Customer / Vendor Ledger)

### GET `/reports/party-statement`

**Query Parameters:**
| Param | Type | Required |
|-------|------|----------|
| `contact_id` | UUID | Yes |
| `start_date` | date | Yes |
| `end_date` | date | Yes |

**Response:**
```json
{
  "contact_id": "uuid",
  "contact_name": "Rajesh Enterprises",
  "period_start": "2025-04-01",
  "period_end": "2026-03-31",
  "rows": [
    {
      "date": "2025-04-15",
      "document_number": "INV-2025-0001",
      "document_type": "Invoice",
      "debit": "2950.00",
      "credit": "0.00",
      "balance": "2950.00 Dr"
    },
    {
      "date": "2025-05-10",
      "document_number": "RCPT-2025-0001",
      "document_type": "Receipt",
      "debit": "0.00",
      "credit": "2950.00",
      "balance": "0.00"
    }
  ],
  "summary": {
    "opening_balance": "0.00",
    "total_invoiced": "2950.00",
    "total_received": "2950.00",
    "closing_balance": "0.00",
    "closing_outstanding": "0.00"
  }
}
```

**Export:**
- `GET /reports/party-statement/pdf?contact_id=...&start_date=...&end_date=...`
- `GET /reports/party-statement/excel?contact_id=...&start_date=...&end_date=...`

---

## 11. Sales Analytics

### GET `/reports/sales-analytics`

**Query Parameters:**
| Param | Type | Required | Default |
|-------|------|----------|---------|
| `start_date` | date | Yes | — |
| `end_date` | date | Yes | — |
| `top_n` | int | No | 10 |

**Response:**
```json
{
  "period_start": "2025-04-01",
  "period_end": "2025-04-30",
  "total_invoiced": "500000.00",
  "total_received": "400000.00",
  "total_outstanding": "100000.00",
  "invoice_count": 45,
  "top_customers": [
    {
      "contact_id": "uuid",
      "contact_name": "Rajesh Enterprises",
      "invoice_count": 12,
      "total_invoiced": "150000.00"
    }
  ]
}
```

---

## 12. Purchase Analytics

### GET `/reports/purchase-analytics`

Same structure as Sales Analytics but for vendor bills:
```json
{
  "period_start": "...",
  "period_end": "...",
  "total_billed": "...",
  "total_paid": "...",
  "total_outstanding": "...",
  "bill_count": 30,
  "top_vendors": [...]
}
```

---

## 13. Dashboard Metrics

### GET `/dashboard/metrics`

**Query Parameters:** `date_from`, `date_to` (optional)

**Response:**
```json
{
  "total_revenue": "500000.00",
  "total_outstanding_ar": "100000.00",
  "total_outstanding_ap": "50000.00",
  "total_expenses": "200000.00",
  "invoices_count": 45,
  "receipts_count": 38,
  "overdue_invoices": 5,
  "cash_balance": "150000.00"
}
```

### GET `/dashboard/revenue-trend`
```json
[
  { "month": "2025-04", "revenue": "80000.00", "receipts": "75000.00" },
  { "month": "2025-05", "revenue": "90000.00", "receipts": "85000.00" }
]
```

### GET `/dashboard/kpis`
```json
{
  "gross_profit_margin": "30.00",
  "net_profit_margin": "20.00",
  "current_ratio": "2.5",
  "receivables_turnover_days": "45",
  "payables_turnover_days": "30"
}
```

### GET `/dashboard/overdue-alerts`
```json
{
  "overdue_invoices": [
    {
      "invoice_number": "INV-2025-0001",
      "contact_name": "Rajesh Enterprises",
      "due_date": "2025-05-15",
      "outstanding": "2950.00",
      "days_overdue": 10
    }
  ],
  "total_overdue": "2950.00"
}
```

### GET `/dashboard/expense-trend`
```json
[
  { "month": "2025-04", "expenses": "20000.00" },
  { "month": "2025-05", "expenses": "18000.00" }
]
```

---

## 14. Invoice Statistics

### GET `/invoices/stats`

**Response:**
```json
{
  "total_invoices": 150,
  "draft_count": 5,
  "posted_count": 100,
  "paid_count": 40,
  "cancelled_count": 5,
  "total_revenue": "5000000.00",
  "total_outstanding": "500000.00",
  "total_overdue": "100000.00"
}
```

---

## 15. Sales Summary (Sales Router)

### GET `/sales/summary?date_from=...&date_to=...`
```json
{
  "total_sales": "500000.00",
  "total_received": "400000.00",
  "total_gst": "90000.00",
  "outstanding": "100000.00"
}
```

### GET `/sales/customer-wise`
```json
[
  {
    "contact_id": "uuid",
    "contact_name": "Rajesh Enterprises",
    "invoice_count": 12,
    "total": "150000.00"
  }
]
```

### GET `/sales/period-wise`
```json
[
  { "period": "2025-04", "total": "80000.00", "invoice_count": 10 }
]
```

### GET `/sales/transactions?page=1&limit=20`
```json
[
  {
    "invoice_number": "INV-2025-0001",
    "contact_name": "Rajesh Enterprises",
    "issue_date": "2025-04-15",
    "total": "2950.00",
    "status": "PAID"
  }
]
```

---

## Export Format Notes

| Export Type | Content-Type | Filename Pattern |
|-------------|-------------|-----------------|
| Excel | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` | `TrialBalance_2025-03-31.xlsx` |
| PDF | `application/pdf` | `TrialBalance_2025-03-31.pdf` |
| JSON | `application/json` | Inline response |

All export endpoints accept the same query parameters as the JSON endpoints.

---

## Reminders API

### GET `/reminders`
Returns combined list of:
1. Overdue invoices (as payment reminders)
2. Daily business summary

```json
[
  {
    "title": "Payment Overdue: Invoice INV-2025-0001",
    "message": "Invoice for Rajesh Enterprises is overdue since 15-May-2025. Outstanding: ₹2,950.00."
  },
  {
    "title": "Daily Business Summary — 01-Jul-2026",
    "message": "Today's Sales: ₹50,000.00 | Receipts: ₹45,000.00 | Expenses/Bills: ₹10,000.00."
  }
]
```
