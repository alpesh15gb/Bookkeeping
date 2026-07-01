# ApexBooks — Permissions Matrix
> Source of truth: `src/core/security.py` — `Permissions` class + `ROLE_PERMISSIONS` dict.

---

## 1. Permission Names

| Permission | Code | Description |
|-----------|------|-------------|
| Tenant View | `tenant:view` | View company profile and details |
| Tenant Update | `tenant:update` | Update company profile, GST toggle, branches |
| Settings View | `settings:view` | View tenant settings, numbering series |
| Settings Update | `settings:update` | Update settings, upload logo, create series |
| Contact Create | `contact:create` | Create contacts (customers / vendors) |
| Contact View | `contact:view` | View contacts list and detail |
| Contact Update | `contact:update` | Update contact details |
| Contact Delete | `contact:delete` | Soft-delete contacts |
| Invoice Create | `invoice:create` | Create and edit sales invoices, products, PO/SO/DC, adjustments |
| Invoice View | `invoice:view` | View invoices, products, PO/SO/DC, dashboard metrics |
| Invoice Update | `invoice:update` | Update draft invoices |
| Invoice Finalize | `invoice:finalize` | Post/cancel invoices, generate e-invoice/e-way bill |
| Invoice Delete | `invoice:delete` | Delete DRAFT invoices |
| Payment Create | `payment:create` | Create receipts, disbursements, bank reconciliation |
| Payment View | `payment:view` | View payments and reconciliations |
| Payment Delete | `payment:delete` | Delete DRAFT payments |
| Payment Cancel | `payment:cancel` | Cancel payments (reversal) |
| Ledger View | `ledger:view` | View journal entries, ledger, trial balance, balance sheet |
| Ledger Manual Post | `ledger:manual_post` | Create manual journal entries |
| Accounts Manage | `accounts:manage` | Create/update/delete accounts, seed chart of accounts |
| GST Report View | `gst:report_view` | View GSTR-1, GSTR-2, GSTR-3B reports |
| GST Filing Manage | `gst:filing_manage` | Upload GSTR-2A, manage GST returns |
| Credit Note Create | `credit_note:create` | Create and post credit notes |
| Credit Note View | `credit_note:view` | View credit notes |
| Debit Note Create | `debit_note:create` | Create and post debit notes |
| Debit Note View | `debit_note:view` | View debit notes |
| Audit View | `audit:view` | View audit logs |
| Reports View | `reports:view` | View all financial reports |
| Expense Create | `expense:create` | Create expenses |
| Expense View | `expense:view` | View expenses and categories |
| Expense Edit | `expense:edit` | Update DRAFT expenses |
| Expense Delete | `expense:delete` | Delete DRAFT expenses |
| Expense Finalize | `expense:finalize` | Post and cancel expenses |
| Bill Create | `bill:create` | Create and post vendor bills |
| Bill View | `bill:view` | View vendor bills and purchase orders |
| Bill Update | `bill:update` | Update DRAFT bills |
| Bill Delete | `bill:delete` | Delete DRAFT bills |

---

## 2. Role → Permissions Matrix

### Owner (all permissions)

| Permission | Owner | Accountant | Salesperson | Auditor |
|-----------|-------|-----------|------------|---------|
| `tenant:view` | ✅ | ✅ | — | ✅ |
| `tenant:update` | ✅ | — | — | — |
| `settings:view` | ✅ | ✅ | — | — |
| `settings:update` | ✅ | ✅ | — | — |
| `contact:create` | ✅ | ✅ | ✅ | — |
| `contact:view` | ✅ | ✅ | ✅ | ✅ |
| `contact:update` | ✅ | ✅ | ✅ | — |
| `contact:delete` | ✅ | — | — | — |
| `invoice:create` | ✅ | — | ✅ | — |
| `invoice:view` | ✅ | ✅ | ✅ | ✅ |
| `invoice:update` | ✅ | — | ✅ | — |
| `invoice:finalize` | ✅ | ✅ | — | — |
| `invoice:delete` | ✅ | — | — | — |
| `payment:create` | ✅ | ✅ | ✅ | — |
| `payment:view` | ✅ | ✅ | ✅ | ✅ |
| `payment:delete` | ✅ | — | — | — |
| `payment:cancel` | ✅ | ✅ | — | — |
| `ledger:view` | ✅ | ✅ | — | ✅ |
| `ledger:manual_post` | ✅ | ✅ | — | — |
| `accounts:manage` | ✅ | ✅ | — | — |
| `gst:report_view` | ✅ | ✅ | — | ✅ |
| `gst:filing_manage` | ✅ | ✅ | — | — |
| `credit_note:create` | ✅ | ✅ | — | — |
| `credit_note:view` | ✅ | ✅ | — | ✅ |
| `debit_note:create` | ✅ | ✅ | — | — |
| `debit_note:view` | ✅ | ✅ | — | ✅ |
| `audit:view` | ✅ | ✅ | — | ✅ |
| `reports:view` | ✅ | ✅ | — | ✅ |
| `expense:create` | ✅ | ✅ | — | — |
| `expense:view` | ✅ | ✅ | — | — |
| `expense:edit` | ✅ | — | — | — |
| `expense:delete` | ✅ | — | — | — |
| `expense:finalize` | ✅ | ✅ | — | — |
| `bill:create` | ✅ | ✅ | — | — |
| `bill:view` | ✅ | ✅ | — | — |
| `bill:update` | ✅ | ✅ | — | — |
| `bill:delete` | ✅ | ✅ | — | — |

---

## 3. Role Descriptions

| Role | Description | Typical User |
|------|-------------|-------------|
| `owner` | Full access to all features including company settings, data purge, GST toggle | Business owner, director |
| `accountant` | Can do all accounting operations but cannot delete contacts/invoices or change company structure | CA, internal accountant |
| `salesperson` | Can create and view invoices, contacts, and record receipts. No access to accounting, GST, or reports | Sales team |
| `auditor` | Read-only access to everything relevant for audit | External auditor, compliance officer |

---

## 4. Admin-Only Operations

The following operations require **owner** role (enforced by permission check on `tenant:update`):

| Operation | Endpoint |
|-----------|---------|
| Toggle GST mode | `POST /companies/{id}/gst-toggle` |
| Request data purge OTP | `POST /purge/request` |
| Execute data purge | `POST /purge/verify` |
| Export all company data | `GET /companies/{id}/export` |
| Import company data | `POST /companies/{id}/import` |
| Import Vyapar backup | `POST /import/vyapar` |

---

## 5. Endpoint → Required Permission Mapping

| Endpoint | Method | Permission |
|---------|--------|-----------|
| `/invoices` | POST | `invoice:create` |
| `/invoices` | GET | `invoice:view` |
| `/invoices/{id}` | GET | `invoice:view` |
| `/invoices/{id}` | PUT | `invoice:update` |
| `/invoices/{id}/finalize` | POST | `invoice:finalize` |
| `/invoices/{id}/payment` | POST | `payment:create` |
| `/invoices/{id}/cancel` | POST | `invoice:finalize` |
| `/invoices/{id}` | DELETE | `invoice:delete` |
| `/invoices/{id}/print` | GET | `invoice:view` |
| `/invoices/{id}/e-invoice` | POST | `invoice:finalize` |
| `/invoices/{id}/email` | POST | `invoice:view` |
| `/invoices/credit-notes` | POST | `credit_note:create` |
| `/invoices/credit-notes` | GET | `credit_note:view` |
| `/invoices/credit-notes/{id}/finalize` | POST | `credit_note:create` |
| `/invoices/debit-notes` | POST | `debit_note:create` |
| `/invoices/debit-notes` | GET | `debit_note:view` |
| `/bills` | POST | `bill:create` |
| `/bills` | GET | `bill:view` |
| `/bills/{id}/finalize` | POST | `bill:create` |
| `/bills/{id}/cancel` | POST | `bill:create` |
| `/payments/receipts` | POST | `payment:create` |
| `/payments/receipts` | GET | `payment:view` |
| `/payments/receipts/{id}/cancel` | POST | `payment:cancel` |
| `/payments/disbursements` | POST | `payment:create` |
| `/payments/disbursements/{id}/cancel` | POST | `payment:cancel` |
| `/purchase-orders` | POST | `bill:create` |
| `/purchase-orders` | GET | `bill:view` |
| `/sales-orders` | POST | `invoice:create` |
| `/sales-orders` | GET | `invoice:view` |
| `/delivery-challans` | POST | `invoice:create` |
| `/proforma-invoices` | POST | `invoice:create` |
| `/returns/sales` | POST | `invoice:create` |
| `/returns/purchase` | POST | `bill:create` |
| `/expenses` | POST | `expense:create` |
| `/expenses` | GET | `expense:view` |
| `/expenses/{id}/post` | POST | `expense:finalize` |
| `/expenses/{id}/cancel` | POST | `expense:finalize` |
| `/accounting/journals` | POST | `ledger:manual_post` |
| `/accounting/journals` | GET | `ledger:view` |
| `/accounting/ledger/{id}` | GET | `ledger:view` |
| `/accounting/trial-balance` | GET | `ledger:view` |
| `/accounting/profit-loss` | GET | `ledger:view` |
| `/accounting/balance-sheet` | GET | `ledger:view` |
| `/accounting/recalculate-balances` | POST | `accounts:manage` |
| `/accounting/year-end/prepare` | GET | `accounts:manage` |
| `/financial-years` | GET | `settings:view` |
| `/financial-years` | POST | `settings:update` |
| `/financial-years/{id}/close` | POST | `accounts:manage` |
| `/financial-years/{id}/reopen` | POST | `accounts:manage` |
| `/masters/accounts` | POST | `accounts:manage` |
| `/masters/accounts` | GET | `ledger:view` |
| `/masters/contacts` | POST | `contact:create` |
| `/masters/contacts` | GET | `contact:view` |
| `/masters/contacts/{id}` | DELETE | `contact:delete` |
| `/masters/products` | POST | `invoice:create` |
| `/masters/products` | GET | `invoice:view` |
| `/masters/banking-profiles` | POST | `settings:update` |
| `/masters/banking-profiles` | GET | `settings:view` |
| `/bank-reconciliation/upload` | POST | `payment:create` |
| `/bank-reconciliation/statements` | GET | `payment:view` |
| `/bank-reconciliation/bulk-reconcile` | POST | `payment:create` |
| `/gst/gstr1` | GET | `gst:report_view` |
| `/gst/gstr2` | GET | `gst:report_view` |
| `/gst/gstr3b/export` | GET | `gst:report_view` |
| `/gst/gstr2a/upload` | POST | `gst:filing_manage` |
| `/gst/verify` | POST | `contact:create` |
| `/gst/hsn/{code}` | GET | `invoice:create` |
| `/eway-bills` | POST | `invoice:finalize` |
| `/reports/*` | GET | `reports:view` |
| `/dashboard/metrics` | GET | `invoice:view` |
| `/audit-logs` | GET | `audit:view` |
| `/companies/{id}` | GET | `tenant:view` |
| `/companies/{id}` | PUT | `tenant:update` |
| `/settings` | GET | `settings:view` |
| `/settings` | PUT | `settings:update` |
| `/tally/import` | POST | `data:import` |
| `/import/vyapar` | POST | `tenant:update` |

---

## 6. Frontend Permission Checking

The API does not expose a "current user permissions" endpoint. Frontend should:

1. Fetch user role from `GET /auth/memberships` → `role` field
2. Maintain a local role-to-permissions map (mirror of `ROLE_PERMISSIONS` in `security.py`)
3. Use it to show/hide UI elements (buttons, menu items, routes)

```javascript
const ROLE_PERMISSIONS = {
  owner: ['tenant:view', 'tenant:update', 'invoice:create', 'invoice:view', ...],
  accountant: ['tenant:view', 'settings:view', 'invoice:view', 'invoice:finalize', ...],
  salesperson: ['contact:view', 'contact:create', 'invoice:create', 'invoice:view', ...],
  auditor: ['tenant:view', 'invoice:view', 'ledger:view', 'reports:view', 'audit:view', ...]
};

function hasPermission(role, permission) {
  return ROLE_PERMISSIONS[role]?.includes(permission) ?? false;
}
```

The backend enforces permissions on every request regardless of frontend state.

---

## 7. Implicit Permissions via Data Import

`data:import` permission is referenced by the Tally import endpoint but is **not included** in any role's permission set in `ROLE_PERMISSIONS`. This means Tally import is effectively **unreachable** via the permission system. See MISSING_APIS.md.

---

## 8. Total Counts

| Roles | 4 |
|-------|---|
| Permissions | 37 |
| Owner permissions | 37 |
| Accountant permissions | 27 |
| Salesperson permissions | 7 |
| Auditor permissions | 11 |
