# ApexBooks — Frontend Handover Guide
> Executive guide for frontend teams: what to build first, how screens map to APIs, and critical gotchas.

---

## 1. Recommended Development Sequence

Build in this order to unlock incremental testing at each phase:

### Phase 1 — Foundation (Week 1-2)
1. **Auth screens** — Login, Register, Forgot Password, Reset Password
2. **Company setup** — First-run wizard: company name, GSTIN, tax mode, home state
3. **Global state** — Store `access_token`, `tenant_id`, `role`, `settings` in global state
4. **Token refresh** — Axios interceptor for auto-refresh on 401

### Phase 2 — Master Data (Week 2-3)
5. **Contacts** — List, Create, Edit, Delete (customers + vendors)
6. **Products** — List, Create, Edit, Delete (goods + services)
7. **Chart of Accounts** — List, Create, Seed Defaults
8. **Banking Profiles** — List, Create (bank accounts)
9. **Expense Categories** — List, Create

### Phase 3 — Core Sales Cycle (Week 3-5)
10. **Sales Invoice** — Create, List, Detail, Finalize, Cancel, Print PDF, Email
11. **Customer Receipt** — Record payment, allocate to invoices
12. **Credit Notes** — Create, Finalize
13. **Dashboard** — KPIs, revenue trend, overdue alerts

### Phase 4 — Core Purchase Cycle (Week 5-6)
14. **Vendor Bill** — Create, List, Detail, Finalize, Cancel, Print PDF
15. **Vendor Payment** — Record, allocate to bills
16. **Debit Notes** — Create, Finalize

### Phase 5 — Operations (Week 6-8)
17. **Expenses** — Create, Post, Cancel
18. **Purchase Orders** — Create, Confirm, Receive
19. **Sales Orders** — Create, Confirm, Deliver
20. **Delivery Challans** — Create, Issue
21. **Proforma Invoices** — Create, Issue, Convert
22. **Returns** — Sales Return, Purchase Return

### Phase 6 — Accounting & Reports (Week 8-10)
23. **Financial Years** — Create, Switch, Year-end Dashboard
24. **Manual Journal** — Create entry, List
25. **General Ledger** — Account statement with running balance
26. **Trial Balance, P&L, Balance Sheet** — JSON + PDF/Excel
27. **Cash Book, Cash Flow** — JSON + PDF/Excel
28. **Aging Reports, Outstanding** — AR/AP with exports
29. **Party Statement** — Customer/vendor ledger

### Phase 7 — GST & Compliance (Week 10-12)
30. **GSTR-1** — Report view + Excel/PDF export
31. **GSTR-2** — Report view + Excel/PDF export
32. **GSTR-3B** — Report view + Excel/PDF export
33. **GSTR-2A Reconciliation** — Upload JSON + view matches
34. **GSTIN Verification** — Captcha flow during contact creation
35. **e-Invoice** — Generate IRN on posted invoice
36. **e-Way Bill** — Create, cancel, vehicle update

### Phase 8 — Advanced Features (Week 12-14)
37. **Bank Reconciliation** — Upload statement, auto-match, manual reconcile
38. **OCR Bill Scanning** — Upload, poll, review, save
39. **Recurring Invoices** — Create templates, trigger
40. **Inventory Adjustments** — Create, confirm
41. **Terms Templates** — Create, list presets

### Phase 9 — Import / Admin (Week 14-15)
42. **Vyapar Import** — Upload .vyb file, show progress
43. **Data Export** — Download JSON backup
44. **Tally Export** — Download XML
45. **Audit Logs** — List with filters
46. **Company Settings** — Logo upload, numbering series, UPI ID
47. **Purge Data** — OTP flow (owner only)

---

## 2. Screen → API Mapping

### 2.1 Login Screen
| Action | API |
|--------|-----|
| Submit login form | `POST /auth/login` |
| Show validation errors | 422 response |
| Store tokens | memory + localStorage |
| Redirect after login | `GET /auth/memberships` → pick tenant |

### 2.2 Registration Screen
| Action | API |
|--------|-----|
| Submit registration | `POST /auth/register` |
| Then auto-login | `POST /auth/login` |
| First-run setup | `POST /companies/{id}/gst-toggle` + `PUT /settings` |

### 2.3 Invoice List Screen
| Action | API |
|--------|-----|
| Load list | `GET /invoices?page=1&limit=20&status=POSTED` |
| Search | `GET /invoices?search=rajesh&page=1` |
| Filter by status | `GET /invoices?status=DRAFT` |
| Filter by date | `GET /invoices?date_from=2025-04-01&date_to=2025-04-30` |
| Stats bar | `GET /invoices/stats` |
| Bulk delete | `POST /invoices/bulk-delete` |

### 2.4 Create Invoice Screen
| Action | API |
|--------|-----|
| Load contacts | `GET /contacts?limit=100` |
| Load products | `GET /products?limit=200` |
| Load tax templates | `GET /masters/tax-templates` |
| Load payment terms | `GET /masters/payment-terms` |
| Load terms templates | `GET /terms-templates` |
| Preview (real-time tax) | `POST /invoices/preview` |
| Save as draft | `POST /invoices` |
| Finalize | `POST /invoices/{id}/finalize` |
| Generate e-Invoice | `POST /invoices/{id}/e-invoice` |
| Generate e-Way Bill | `POST /eway-bills` |
| HSN lookup | `GET /gst/hsn/{code}` |

### 2.5 Invoice Detail Screen
| Action | API |
|--------|-----|
| Load invoice | `GET /invoices/{id}` |
| Print/Download PDF | `GET /invoices/{id}/print` |
| Email invoice | `POST /invoices/{id}/email` |
| Record payment | `POST /invoices/{id}/payment` |
| Cancel invoice | `POST /invoices/{id}/cancel` |
| Clone invoice | `POST /invoices/{id}/clone` |
| View journal entries | `GET /accounting/journals?source_type=INVOICE` |

### 2.6 Dashboard Screen
| Widget | API |
|--------|-----|
| Revenue/Expense KPIs | `GET /dashboard/metrics` |
| Revenue trend chart | `GET /dashboard/revenue-trend` |
| KPI cards | `GET /dashboard/kpis` |
| Overdue invoices | `GET /dashboard/overdue-alerts` |
| Expense trend chart | `GET /dashboard/expense-trend` |
| Outstanding AR | `GET /reports/outstanding/ar` |
| Cash/Bank balances | `GET /accounting/cash-bank-balances` |

### 2.7 GST Reports Screen
| Report | API |
|--------|-----|
| GSTR-1 JSON | `GET /gst/gstr1?start_date=...&end_date=...` |
| GSTR-1 Excel | `GET /gst/gstr1/export?...` |
| GSTR-1 PDF | `GET /gst/gstr1/pdf?...` |
| GSTR-2 JSON | `GET /gst/gstr2?...` |
| GSTR-3B Excel | `GET /gst/gstr3b/export?...` |
| GSTR-2A Upload | `POST /gst/gstr2a/upload` |
| GSTIN Verify | `GET /gst/verify/captcha` → `POST /gst/verify` |

### 2.8 Bank Reconciliation Screen
| Action | API |
|--------|-----|
| Upload bank statement | `POST /bank-reconciliation/upload` |
| View statement | `GET /bank-reconciliation/statements/{id}` |
| View transactions | `GET /bank-reconciliation/statements/{id}/transactions` |
| Get stats | `GET /bank-reconciliation/statements/{id}/stats` |
| Auto-match | `POST /bank-reconciliation/statements/{id}/auto-match` |
| Match suggestions | `GET /bank-reconciliation/statements/{id}/suggestions` |
| Manual reconcile | `POST /bank-reconciliation/transactions/{id}/reconcile` |
| Bulk reconcile | `POST /bank-reconciliation/bulk-reconcile` |
| Undo reconcile | `POST /bank-reconciliation/reconciliations/{id}/undo` |

### 2.9 OCR Bill Scan Screen
| Step | API |
|------|-----|
| Upload image | `POST /bills/scan/preview` → get `job_id` |
| Poll status | `GET /bills/scan/status?job_id=...` every 3s |
| Show extracted data | Display in editable form |
| Save as bill | `POST /bills/scan/save` |

### 2.10 Year-End Closing Screen
| Action | API |
|--------|-----|
| View current FY | `GET /financial-years/current` |
| Pre-close checklist | `GET /financial-years/{id}/dashboard` |
| Close FY | `POST /financial-years/{id}/close` |
| Switch to new FY | `POST /financial-years/switch` |
| View opening balances | `GET /financial-years/{id}/opening-balances` |
| Reopen FY | `POST /financial-years/{id}/reopen` |

---

## 3. Critical Frontend Gotchas

### 3.1 X-Tenant-ID is MANDATORY
Every authenticated request needs `X-Tenant-ID: <uuid>` header. Missing it → 422 error. Set it globally in your HTTP client after login.

### 3.2 Tokens Expire in 15 Minutes
Implement proactive token refresh at 14 minutes. If you wait for a 401 response, the user will experience a failed action.

### 3.3 Invoice Status Flow is Strict
- You cannot edit a POSTED invoice — only cancel + recreate
- You cannot delete a POSTED/PAID invoice
- Status goes: DRAFT → POSTED → PARTIALLY_PAID/PAID / CANCELLED
- The UI should disable editing fields when `status !== "DRAFT"`

### 3.4 GST Calculation — Always Use `/preview`
Never calculate GST on the frontend. Always use `POST /invoices/preview` or `POST /bills/preview` with the current line items to get accurate totals. The backend handles intra/inter-state routing, UTGST, cess, and round-off.

### 3.5 Period Locks Block Writes
If the accounting period is locked, all create/finalize calls return HTTP 400. The frontend should gracefully display this error and not retry.

### 3.6 No Pagination Defaults
Most list endpoints default to `page=1, limit=20`. For dropdowns and autocompletes, use `limit=200` to get all active records in one call (contacts, products, accounts).

### 3.7 Voucher Numbers Are Auto-Generated
Never ask the user to enter a voucher number manually (unless they choose to override). The `invoice_number` is auto-assigned from `NumberingSeries`. If `NumberingSeries` is not set up, the backend will still generate a fallback number.

### 3.8 `pos_state_code` is Required on Every Invoice/Bill
This is the Place of Supply state code (2 digits). It drives CGST/SGST vs IGST determination. Default to the company's `origin_state_code` for intra-state sales. For inter-state, use the customer's `state_code`.

### 3.9 Ledger Entries Are Immutable
Never provide an "Edit Journal Entry" screen. Journal entries have `is_locked = true` and cannot be updated. To correct an error, the user must cancel the source document.

### 3.10 Role-Based UI
The API enforces permissions but the frontend should also hide inaccessible UI elements (buttons, menu items) to avoid confusing 403 errors. See PERMISSIONS_MATRIX.md for the role → permission mapping.

### 3.11 Decimal Precision
All monetary values use 4 decimal places internally (`"2950.0000"`). Display rounded to 2 decimal places (`"₹2,950.00"`). Never parse them as JavaScript `float` — use a Decimal library (e.g., `decimal.js`) to avoid floating point errors.

### 3.12 Contact Type Filtering
Use `contact_type` query param to filter contacts:
- `GET /masters/contacts?contact_type=CUSTOMER` for invoice customer dropdown
- `GET /masters/contacts?contact_type=VENDOR` for bill vendor dropdown
- `GET /masters/contacts?contact_type=BOTH` contacts appear in both

### 3.13 Soft Deletes
All records use soft deletes (`deleted_at` field). The API automatically filters them out. If a contact/product appears to be "missing", it may have been soft-deleted.

---

## 4. Forms to Build

| Form | Key Fields |
|------|-----------|
| Register | email, password (with strength meter), full_name, company_legal_name, GSTIN, PAN |
| Login | email, password |
| Company Settings | legal_name, trade_name, GSTIN, tax_mode, logo upload, origin_state_code, UPI ID |
| Contact | name, contact_type, GSTIN (with live verify button), state_code, billing/shipping address |
| Product | name, SKU, HSN/SAC (with lookup), product_type, UOM, sales_price, purchase_price, gst_rate |
| Invoice | contact, date, due_date, pos_state_code, supply_type, TDS%, TCS%, line items, discount, shipping, notes, T&C |
| Bill | contact, bill_number, date, due_date, pos_state_code, itc_eligible, TDS%, line items |
| Payment (Receipt) | contact, date, payment_mode, amount, reference, allocations to invoices |
| Expense | category, date, vendor_name, amount, gst_rate, bank_account, notes |
| Journal Entry | entry_date, reference, description, lines (account + direction + amount + narration) |
| e-Way Bill | invoice_id, trans_mode, distance, vehicle_number, transporter details |
| Financial Year | name, start_date, end_date |
| Numbering Series | document_type, prefix, next_number, padding_digits |
| Recurring Invoice | contact, frequency, interval, start/end dates, line items |
| Bank Reconciliation | file upload (CSV/Excel), banking_profile_id, bank_format |
| Inventory Adjustment | adjustment_number, date, reason, lines (product + quantity_change + unit_cost) |

---

## 5. Tables to Build

| Table | Key Columns |
|-------|------------|
| Invoices List | Invoice No., Customer, Date, Due Date, Amount, Status, Outstanding |
| Bills List | Bill No., Vendor, Date, Due Date, Amount, Status |
| Contacts List | Name, Type, GSTIN, Phone, Email, Balance |
| Products List | Name, SKU, HSN, Type, Sales Price, Purchase Price, GST%, Stock |
| Payments List | Payment No., Contact, Date, Mode, Amount, Status |
| Journal Entries | Date, Reference, Description, Source, Debit, Credit |
| Accounts List | Code, Name, Type, Group, Balance |
| Expenses List | Expense No., Date, Category, Vendor, Amount, Status |
| Bank Transactions | Date, Description, Amount, Type, Reconciled |
| Audit Logs | Timestamp, User, Action, Entity, Changes |
| Financial Years | Name, Start, End, Status, Is Current |
| GST Returns | Period, Type, Status, Filed At, ARN |

---

## 6. Known Issues to Work Around

| Issue | Workaround |
|-------|-----------|
| Day Book missing | Use journal entries list with date filters |
| Period lock UI missing | Document as "coming soon"; show error message when 400 returned |
| User management API missing | Cannot build team management screen |
| 2FA not enforced on login | Show 2FA setup page but warn it's not mandatory |
| Tally import permission broken | Hide Tally import or use Vyapar import instead |
| Stock report missing | Show `current_stock` from product detail as workaround |

---

## 7. Environment Configuration

Frontend needs these environment variables:

```env
VITE_API_BASE_URL=https://api.apexbooks.in/api/v1
VITE_STATIC_BASE_URL=https://api.apexbooks.in/static
VITE_APP_NAME=ApexBooks
```

Logo URL construction: `${VITE_STATIC_BASE_URL}/${settings.logo_url}` if `logo_url` starts with `/static/`, else use it as-is.
