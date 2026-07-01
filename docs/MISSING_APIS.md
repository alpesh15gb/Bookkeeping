# ApexBooks — Missing & Incomplete APIs
> Functionality the frontend cannot build because APIs are missing, broken, or incomplete.

---

## Priority Legend
- 🔴 **Critical** — Core accounting flow is blocked
- 🟠 **High** — Important feature cannot be built
- 🟡 **Medium** — Partial workaround exists
- 🟢 **Low** — Nice to have

---

## 1. 🔴 BROKEN: Tally Import Permission

**Issue:** `POST /tally/import` requires permission `data:import`, but this permission is **not assigned to any role** in `ROLE_PERMISSIONS`. No user can access this endpoint.

**Affected endpoint:** `POST /tally/import`

**Suggested fix:**
- Add `data:import` to `owner` and `accountant` roles in `security.py`
- OR change the permission check to use `tenant:update`

**Workaround:** Use Vyapar import (`POST /import/vyapar`) which correctly uses `tenant:update`.

---

## 2. 🔴 MISSING: Day Book Report

**Issue:** No dedicated Day Book endpoint exists. The Day Book is a fundamental accounting report showing all transactions for a day/period across all voucher types.

**Suggested endpoint:**
```
GET /reports/day-book?date_from=2025-04-01&date_to=2025-04-30&page=1&limit=50
```

**Suggested response:**
```json
{
  "date_from": "2025-04-01",
  "date_to": "2025-04-30",
  "entries": [
    {
      "date": "2025-04-15",
      "voucher_type": "Sales Invoice",
      "voucher_number": "INV-2025-0001",
      "party_name": "Rajesh Enterprises",
      "debit": "2950.00",
      "credit": "0.00",
      "narration": "Sales of Steel Pipes"
    }
  ],
  "total_debit": "...",
  "total_credit": "...",
  "total": 150,
  "page": 1,
  "limit": 50
}
```

**Workaround:** `GET /accounting/journals?date_from=...&date_to=...` returns raw journal entries but lacks the voucher-type grouping and party names expected in a Day Book.

**Priority: 🔴 Critical** — Day Book is required by accountants daily.

---

## 3. 🔴 MISSING: Period Lock / Unlock API

**Issue:** Period locking logic exists in the codebase (`src/domains/accounting/period_lock.py`) and is enforced on all write endpoints, but there is **no API to lock or unlock a period**.

**Suggested endpoints:**
```
POST /accounting/periods/lock
{
  "period_date": "2025-04-30",
  "note": "April 2025 books closed"
}

POST /accounting/periods/unlock
{
  "period_date": "2025-04-30",
  "note": "Reopening for corrections"
}

GET /accounting/periods
```

**Priority: 🔴 Critical** — Without this, locked periods cannot be managed via the frontend.

---

## 4. 🔴 MISSING: 2FA Login Step

**Issue:** 2FA (TOTP) setup exists (`/auth/2fa/enable`, `/auth/2fa/verify`, `/auth/2fa/disable`), but the **login flow does not challenge for TOTP**. `POST /auth/login` returns full tokens without requiring TOTP, making 2FA effectively decorative.

**Suggested fix:** After successful password verification, if `user.totp_enabled`, return HTTP 202 with a `totp_required: true` field and a partial token. Then add:

```
POST /auth/2fa/challenge
{
  "partial_token": "...",
  "totp_code": "123456"
}
→ Returns full access + refresh tokens
```

**Priority: 🔴 Critical** — Security issue; 2FA is advertised but not enforced.

---

## 5. 🟠 MISSING: Stock Report / Stock Register

**Issue:** `stock_ledger` table exists with full inventory movement history, but there is no API to expose it as a stock report.

**Suggested endpoints:**
```
GET /reports/stock-register?product_id=uuid&date_from=...&date_to=...
GET /reports/stock-summary?as_of_date=...
GET /reports/stock-valuation?as_of_date=...
```

**Workaround:** `GET /masters/products` returns `current_stock`, but no history or valuation.

**Priority: 🟠 High** — Required for inventory-based businesses.

---

## 6. 🟠 MISSING: Contra Entry API

**Issue:** Contra entries (Cash ↔ Bank transfers) are possible via manual journal entries, but there is no dedicated Contra Entry API with proper voucher numbering, listing, and audit trail.

**Suggested endpoints:**
```
POST /accounting/contra
{
  "entry_date": "2025-04-15",
  "from_account_id": "uuid-cash",
  "to_account_id": "uuid-bank",
  "amount": "50000.00",
  "description": "Cash deposit"
}

GET /accounting/contra?date_from=...&date_to=...
```

**Workaround:** Use `POST /accounting/journals` with a manual double entry.

**Priority: 🟠 High** — Standard accounting requirement.

---

## 7. 🟠 MISSING: User Management API (Invite / List / Remove Members)

**Issue:** The `tenant_invitations` table exists, but there is **no API to invite users, list team members, or remove a member from a tenant**.

**Suggested endpoints:**
```
POST /companies/{id}/invite
{
  "email": "accountant@firm.in",
  "role": "accountant"
}

GET /companies/{id}/members

PUT /companies/{id}/members/{user_id}
{
  "role": "salesperson",
  "is_active": false
}

DELETE /companies/{id}/members/{user_id}
```

**Priority: 🟠 High** — Multi-user accounting is a core feature; team management is missing.

---

## 8. 🟠 MISSING: Notification / Alert System API

**Issue:** The `reminders.py` router exists but is a stub. `POST /reminders` returns `{"message": "Reminder created (stub)"}`. There's no persistent notification system.

**Suggested endpoints:**
```
GET /notifications           → List unread notifications
POST /notifications/{id}/read → Mark as read
POST /notifications/read-all  → Mark all as read
```

**Priority: 🟠 High** — Dashboard alerts and reminders require this.

---

## 9. 🟠 MISSING: TDS/TCS Return Filing

**Issue:** TDS (`tds_rate`, `tds_amount`) and TCS (`tcs_rate`, `tcs_amount`) fields exist on invoices and bills, but there is **no TDS/TCS report API** and no API to file TDS returns.

**Suggested endpoints:**
```
GET /reports/tds-report?date_from=...&date_to=...
GET /reports/tcs-report?date_from=...&date_to=...
GET /reports/form-26q?quarter=Q1&year=2025    (TDS return data)
```

**Priority: 🟠 High** — TDS deduction tracking is mandatory for qualifying businesses.

---

## 10. 🟠 MISSING: Accounting Periods List / Management UI

**Issue:** `accounting_periods` table exists, `validate_period_open` is enforced, but there is no endpoint to:
- List all accounting periods and their lock status
- See which periods are locked

**Suggested:**
```
GET /accounting/periods → List all periods with is_locked status
```

**Priority: 🟠 High** — Required for accountants to know which periods are open.

---

## 11. 🟡 MISSING: Invoice Attachment API

**Issue:** No API exists for attaching files (PDFs, images) to invoices, bills, or expenses.

**Suggested endpoints:**
```
POST   /invoices/{id}/attachments      → Upload attachment
GET    /invoices/{id}/attachments      → List attachments
DELETE /invoices/{id}/attachments/{att_id} → Delete attachment
```

Same pattern for `/bills/{id}/attachments` and `/expenses/{id}/attachments`.

**Priority: 🟡 Medium** — Common in accounting software; workaround is external file management.

---

## 12. 🟡 INCOMPLETE: GST Return Filing State Machine

**Issue:** `gst_returns` table exists with `status` (`DRAFT`, `FILED`, `PENDING`, `ERROR`) and `reference_number` (ARN), but there is **no API to create, update, or retrieve GST return filing records**.

**Suggested endpoints:**
```
GET  /gst/returns?period_start=...&return_type=GSTR1
POST /gst/returns/{id}/file   → Mark as FILED with ARN
GET  /gst/returns/{id}
```

**Priority: 🟡 Medium** — GST filing tracking is informational; manual workaround exists.

---

## 13. 🟡 MISSING: Webhook / Event Subscription API

**Issue:** `webhook_events` table exists with `event_type`, `payload`, `status`, `retry_count`, but there is no API to register webhook endpoints or query webhook delivery status.

**Suggested endpoints:**
```
POST /webhooks/subscriptions    → Register URL for events
GET  /webhooks/subscriptions    → List subscriptions
DELETE /webhooks/subscriptions/{id}
GET  /webhooks/events           → Query delivery history
```

**Priority: 🟡 Medium** — Required for integrations with other systems.

---

## 14. 🟡 MISSING: Financial Year Period Lock Endpoint

**Issue:** `POST /financial-years/{fy_id}/close` closes the entire FY. But there is no way to lock specific months within an open FY (e.g., lock April but keep May open).

**Suggested:** See item #3 (Period Lock API).

---

## 15. 🟡 INCOMPLETE: Opening Balance Setting

**Issue:** `Contact.opening_balance` and `Account.opening_balance` exist, but there is no dedicated API to bulk-set opening balances at the start of a financial year.

**Suggested endpoint:**
```
POST /accounting/opening-balances
{
  "as_of_date": "2025-04-01",
  "balances": [
    { "account_id": "uuid", "balance": "50000.00", "balance_type": "DEBIT" }
  ]
}
```

**Priority: 🟡 Medium** — Workaround: Create manual journal entries.

---

## 16. 🟢 MISSING: Product Category / Group API

**Issue:** Products have no category structure. All products are flat. There is no API for product categories or groups.

**Priority: 🟢 Low** — Workaround: Use product name conventions.

---

## 17. 🟢 MISSING: Multi-Branch Inventory

**Issue:** Branch/warehouse model exists. Documents have `pos_state_code` but no `branch_id` FK. No branch-level inventory tracking.

**Priority: 🟢 Low** — Single-branch businesses unaffected.

---

## 18. 🟢 MISSING: Depreciation Schedule API

**Issue:** Fixed assets and depreciation are mentioned in accounting but there is no dedicated fixed asset register, depreciation calculation, or posting API.

**Priority: 🟢 Low** — Workaround: Manual journal entries for depreciation.

---

## Summary

| Priority | Count | Issues |
|---------|-------|--------|
| 🔴 Critical | 4 | Tally permission broken, Day Book missing, Period Lock missing, 2FA login missing |
| 🟠 High | 5 | Stock Report, Contra API, User Management, Notifications, TDS/TCS reports |
| 🟡 Medium | 5 | Attachments, GST return records, Webhooks, Period lock UI, Opening balances |
| 🟢 Low | 3 | Product categories, Multi-branch, Depreciation |
| **Total** | **17** | — |
