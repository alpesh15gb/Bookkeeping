# ApexBooks — Missing & Incomplete APIs
> Status of missing and incomplete APIs after the backend sprint.

---

## Sprint Resolution Summary
During the latest backend sprint, all **Critical (🔴)** and **High (🟠)** priority blockers were successfully implemented, tested, and deployed to production.

| ID | API / Feature | Priority | Sprint Status | Resolved Endpoint(s) |
|---|---|---|---|---|
| 1 | Tally Import Permission | 🔴 Critical | **RESOLVED** | `POST /tally/import` (Permissions fixed) |
| 2 | Day Book Report | 🔴 Critical | **RESOLVED** | `GET /reports/day-book` (+ Excel & PDF) |
| 3 | Period Lock / Unlock | 🔴 Critical | **RESOLVED** | `POST /accounting/periods/lock`, `/unlock`, `GET /accounting/periods` |
| 4 | 2FA Login Challenge Flow | 🔴 Critical | **RESOLVED** | `POST /auth/login` (Challenge response), `POST /auth/2fa/challenge` |
| 5 | Stock Register Report | 🟠 High | **RESOLVED** | `GET /reports/stock-register` |
| 6 | Contra Entry API | 🟠 High | **RESOLVED** | `POST /accounting/contra` |
| 7 | User & Team Management | 🟠 High | **RESOLVED** | `POST /companies/{id}/invite`, `GET /companies/{id}/members`, `PUT/DELETE members`, `/invitations/accept`, `/invitations/reject` |
| 8 | TDS / TCS Reports | 🟠 High | **RESOLVED** | `GET /reports/tds`, `GET /reports/tcs` (+ Excel & PDF) |
| 9 | GST Return Filing Status | 🟠 High | **RESOLVED** | `GET /gst/returns`, `POST /gst/returns`, `PUT /gst/returns/{id}` |

---

## Remaining Incomplete APIs

The following medium-to-low priority features remain outstanding:

### 1. 🟡 MISSING: Invoice Attachment API
*   **Description:** No API exists for attaching scanned source document files (PDFs, images) to invoices, bills, or expenses.
*   **Suggested endpoints:**
    *   `POST /invoices/{id}/attachments` — Upload file
    *   `GET /invoices/{id}/attachments` — List files
    *   `DELETE /invoices/{id}/attachments/{att_id}` — Delete file
*   **Workaround:** Store files in external cloud storage (e.g. Google Drive/S3) and paste URLs into document `notes` or `custom_fields`.
*   **Priority:** 🟡 Medium

### 2. 🟡 MISSING: Webhook / Event Subscription API
*   **Description:** `webhook_events` database table is implemented and populated by domain events, but there is no API to register subscriber URLs or manage webhooks.
*   **Suggested endpoints:**
    *   `POST /webhooks/subscriptions` — Register URL
    *   `GET /webhooks/subscriptions` — List registrations
    *   `DELETE /webhooks/subscriptions/{id}`
*   **Workaround:** Query audit logs `/audit-logs` periodically to poll for changes.
*   **Priority:** 🟡 Medium

### 3. 🟢 MISSING: Product Category / Group API
*   **Description:** Products are completely flat in the master database. There is no category or group structure.
*   **Suggested endpoints:**
    *   `POST /masters/product-categories`
    *   `GET /masters/product-categories`
*   **Workaround:** Implement naming conventions in the product name field (e.g., `Category - Product Name`).
*   **Priority:** 🟢 Low

### 4. 🟢 MISSING: Multi-Branch Inventory Tracking
*   **Description:** While the `Branch` table exists and branches can be managed, transactions do not have a `branch_id` database column. Inventory levels in the `StockLedger` are managed globally rather than per branch.
*   **Workaround:** Create distinct products for each location if separate counts are strictly necessary.
*   **Priority:** 🟢 Low

### 5. 🟢 MISSING: Depreciation Schedule API
*   **Description:** The system has no automated fixed asset register or depreciation calculation engine.
*   **Workaround:** Calculate depreciation externally and post it via manual journal entries (`POST /accounting/journals`).
*   **Priority:** 🟢 Low
