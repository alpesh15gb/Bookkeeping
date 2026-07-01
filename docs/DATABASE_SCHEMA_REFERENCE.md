# ApexBooks — Database Schema Reference
> All tables use PostgreSQL (SQLite in development). UUIDs are v4. Timestamps are UTC with timezone.

---

## 1. `tenants` — Multi-tenant root

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| `id` | UUID PK | No | uuid4() | — |
| `legal_name` | VARCHAR(150) | No | — | Displayed in invoice header |
| `trade_name` | VARCHAR(150) | Yes | — | Optional DBA name |
| `gstin` | VARCHAR(15) | Yes | — | UNIQUE. Pattern: `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$` |
| `pan` | VARCHAR(10) | Yes | — | Pattern: `^[A-Z]{5}[0-9]{4}[A-Z]$` |
| `tax_mode` | VARCHAR(20) | No | `NON_GST` | Enum: `NON_GST`, `GST_REGULAR`, `GST_COMPOSITION` |
| `financial_year_start` | DATE | No | 2026-04-01 | Start month of FY (typically April 1) |
| `created_at` | TIMESTAMPTZ | No | now() | — |
| `updated_at` | TIMESTAMPTZ | No | now() | — |
| `deleted_at` | TIMESTAMPTZ | Yes | NULL | Soft delete |

**Unique constraints:** `gstin`  
**Frontend impact:** `legal_name`, `trade_name`, `gstin`, `tax_mode` displayed on all printed documents.

---

## 2. `users` — Platform accounts

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `email` | VARCHAR(255) UNIQUE | No | Login identifier |
| `password_hash` | VARCHAR(255) | No | bcrypt — never expose |
| `full_name` | VARCHAR(150) | No | Display name |
| `phone_number` | VARCHAR(15) | Yes | — |
| `is_active` | BOOLEAN | No | Default true |
| `failed_login_attempts` | INTEGER | No | Default 0 |
| `locked_until` | TIMESTAMPTZ | Yes | Account lockout |
| `last_login_at` | TIMESTAMPTZ | Yes | — |
| `email_verified` | BOOLEAN | No | Default false |
| `email_verify_token` | VARCHAR(255) | Yes | — |
| `email_verify_expires` | TIMESTAMPTZ | Yes | — |
| `totp_secret` | VARCHAR(32) | Yes | 2FA seed — never expose |
| `totp_enabled` | BOOLEAN | No | Default false |
| `created_at` | TIMESTAMPTZ | No | — |
| `updated_at` | TIMESTAMPTZ | No | — |
| `deleted_at` | TIMESTAMPTZ | Yes | Soft delete |

---

## 3. `tenant_memberships` — RBAC junction

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `tenant_id` | UUID FK→tenants | No | — |
| `user_id` | UUID FK→users | No | — |
| `role` | VARCHAR(50) | No | Enum: `owner`, `accountant`, `salesperson`, `auditor` |
| `is_active` | BOOLEAN | No | Default true |
| `created_at` | TIMESTAMPTZ | No | — |
| `updated_at` | TIMESTAMPTZ | No | — |

**Unique constraint:** `(tenant_id, user_id)`

---

## 4. `password_reset_tokens`

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `user_id` | UUID FK→users | No | — |
| `token` | VARCHAR(255) INDEX | No | Hashed reset token |
| `expires_at` | TIMESTAMPTZ | No | — |
| `used_at` | TIMESTAMPTZ | Yes | Set on redemption |
| `created_at` | TIMESTAMPTZ | No | — |

---

## 5. `contacts` — Customers & Vendors

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `tenant_id` | UUID | No | No FK (performance) |
| `name` | VARCHAR(150) | No | **Display name** |
| `email` | VARCHAR(255) | Yes | — |
| `phone` | VARCHAR(20) | Yes | — |
| `contact_type` | VARCHAR(10) | No | Enum: `CUSTOMER`, `VENDOR`, `BOTH` |
| `gstin` | VARCHAR(15) | Yes | — |
| `pan` | VARCHAR(10) | Yes | — |
| `registration_type` | VARCHAR(20) | No | Enum: `REGULAR`, `COMPOSITION`, `CONSUMER`, `UNREGISTERED`, `SEZ`, `OVERSEAS` |
| `billing_address` | JSON | No | `{street, city, state, state_code, pincode, country}` |
| `shipping_address` | JSON | Yes | Same shape as billing_address |
| `state_code` | VARCHAR(2) | No | Two-digit Indian state code |
| `is_active` | BOOLEAN | No | Default true |
| `opening_balance` | NUMERIC(15,4) | No | Default 0 |
| `credit_balance` | NUMERIC(15,4) | No | Default 0 |
| `custom_fields` | JSON | No | Default `{}` |
| `created_at` | TIMESTAMPTZ | No | — |
| `updated_at` | TIMESTAMPTZ | No | — |
| `deleted_at` | TIMESTAMPTZ | Yes | Soft delete |

**Indexes:** `(tenant_id)`, `(tenant_id, contact_type)`, `(tenant_id, deleted_at)`

---

## 6. `products` — Items / Services

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `tenant_id` | UUID | No | — |
| `name` | VARCHAR(150) | No | **Display name** |
| `sku` | VARCHAR(50) | Yes | — |
| `hsn_sac` | VARCHAR(8) | No | 4–8 digit HSN or SAC code |
| `product_type` | VARCHAR(10) | No | Enum: `GOODS`, `SERVICE` |
| `uom` | VARCHAR(10) | No | e.g. `PCS`, `KGS`, `NOS`, `HRS`, `MTR` |
| `sales_price` | NUMERIC(15,4) | No | Default 0, ≥ 0 |
| `purchase_price` | NUMERIC(15,4) | No | Default 0, ≥ 0 |
| `gst_rate` | NUMERIC(5,2) | No | Total GST % (e.g. 18.00) |
| `opening_stock` | NUMERIC(12,2) | No | Default 0 |
| `current_stock` | NUMERIC(12,2) | No | Default 0, updated by transactions |
| `reorder_level` | NUMERIC(12,2) | No | Default 0 |
| `party_item_rates` | JSON | No | Default `{}` — customer-specific prices |
| `is_active` | BOOLEAN | No | Default true |
| `created_at` | TIMESTAMPTZ | No | — |
| `updated_at` | TIMESTAMPTZ | No | — |
| `deleted_at` | TIMESTAMPTZ | Yes | Soft delete |

**Check constraints:** `sales_price >= 0`, `purchase_price >= 0`

---

## 7. `invoices` — Sales Invoices

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `tenant_id` | UUID | No | — |
| `contact_id` | UUID FK→contacts | Yes | — |
| `invoice_number` | VARCHAR(50) | No | UNIQUE per tenant |
| `issue_date` | DATE | No | — |
| `due_date` | DATE | No | — |
| `status` | VARCHAR(20) | No | `DRAFT`→`POSTED`→`PARTIALLY_PAID`→`PAID`→`CANCELLED` |
| `subtotal` | NUMERIC(15,4) | No | Before GST, after line discounts |
| `discount_total` | NUMERIC(15,4) | No | Total line discounts |
| `cgst_amount` | NUMERIC(15,4) | No | — |
| `sgst_amount` | NUMERIC(15,4) | No | — |
| `igst_amount` | NUMERIC(15,4) | No | — |
| `utgst_amount` | NUMERIC(15,4) | No | — |
| `cess_amount` | NUMERIC(15,4) | No | — |
| `round_off` | NUMERIC(15,4) | No | ±0.50 rounding |
| `shipping_charges` | NUMERIC(15,4) | No | Default 0 |
| `total` | NUMERIC(15,4) | No | **Invoice total** |
| `amount_paid` | NUMERIC(15,4) | No | Default 0, ≤ total |
| `pos_state_code` | VARCHAR(2) | No | Place of supply state code |
| `irn` | VARCHAR(64) | Yes | e-Invoice IRN number |
| `qr_code` | TEXT | Yes | e-Invoice QR code data |
| `e_invoice_status` | VARCHAR(20) | No | `PENDING`, `GENERATED`, `CANCELLED`, `FAILED` |
| `e_invoice_error` | TEXT | Yes | Error message from IRP |
| `notes` | TEXT | Yes | Internal notes |
| `terms_and_conditions` | TEXT | Yes | Printed on invoice |
| `reference_number` | VARCHAR(50) | Yes | PO reference |
| `vyapar_custom_fields` | JSON | No | Default `{}` |
| `sales_person_id` | UUID | Yes | Salesperson user ID |
| `is_rcm` | BOOLEAN | No | Reverse Charge Mechanism |
| `is_gst_inclusive` | BOOLEAN | No | GST included in rate |
| `supply_type` | VARCHAR(20) | No | `DOMESTIC`, `EXPORT_WITH_TAX`, `EXPORT_WITHOUT_TAX`, `SEZ_WITH_TAX`, `SEZ_WITHOUT_TAX` |
| `currency` | VARCHAR(10) | No | ISO 4217. Default `INR` |
| `exchange_rate` | NUMERIC(15,6) | No | Default 1 |
| `tds_rate` | NUMERIC(5,2) | No | Default 0 |
| `tds_amount` | NUMERIC(15,4) | No | Default 0 |
| `tcs_rate` | NUMERIC(5,2) | No | Default 0 |
| `tcs_amount` | NUMERIC(15,4) | No | Default 0 |
| `cancelled_at` | TIMESTAMPTZ | Yes | — |
| `cancelled_by` | UUID | Yes | User who cancelled |
| `created_at` | TIMESTAMPTZ | No | — |
| `updated_at` | TIMESTAMPTZ | No | — |
| `deleted_at` | TIMESTAMPTZ | Yes | Soft delete |

**Unique:** `(tenant_id, invoice_number)`, `irn`  
**Check:** total balance equation, `amount_paid <= total`, status enum, e_invoice_status enum

---

## 8. `invoice_lines`

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `invoice_id` | UUID FK→invoices | No | — |
| `product_id` | UUID FK→products | Yes | — |
| `description` | VARCHAR(255) | Yes | Override product name |
| `quantity` | NUMERIC(12,4) | No | — |
| `rate` | NUMERIC(15,4) | No | Per-unit price |
| `discount` | NUMERIC(15,4) | No | Default 0 (absolute ₹) |
| `subtotal` | NUMERIC(15,4) | No | `(rate × qty) - discount` |
| `hsn_sac` | VARCHAR(8) | No | — |
| `gst_rate` | NUMERIC(5,2) | No | Total GST % |
| `cgst_rate` / `cgst_amount` | NUMERIC | No | — |
| `sgst_rate` / `sgst_amount` | NUMERIC | No | — |
| `igst_rate` / `igst_amount` | NUMERIC | No | — |
| `utgst_rate` / `utgst_amount` | NUMERIC | No | — |
| `cess_rate` / `cess_amount` | NUMERIC | No | — |
| `total` | NUMERIC(15,4) | No | `subtotal + all_tax_amounts` |

---

## 9. `payments` — Customer Receipts (AR)

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | UUID PK | No | — |
| `tenant_id` | UUID | No | — |
| `contact_id` | UUID FK→contacts | Yes | — |
| `payment_number` | VARCHAR(50) | No | UNIQUE per tenant |
| `payment_date` | DATE | No | — |
| `payment_mode` | VARCHAR(20) | No | `CASH`, `BANK`, `UPI`, `POS`, `OTHER` |
| `amount` | NUMERIC(15,4) | No | — |
| `reference_number` | VARCHAR(50) | Yes | Cheque/UTR |
| `description` | TEXT | Yes | — |
| `status` | VARCHAR(20) | No | `ACTIVE`, `CANCELLED` |
| `created_at` | TIMESTAMPTZ | No | — |
| `updated_at` | TIMESTAMPTZ | No | — |
| `deleted_at` | TIMESTAMPTZ | Yes | Soft delete |

---

## 10. `payment_allocations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `payment_id` | UUID FK→payments | — |
| `invoice_id` | UUID FK→invoices | — |
| `amount` | NUMERIC(15,4) | > 0 |
| `created_at` | TIMESTAMPTZ | — |

---

## 11. `bills` — Vendor Bills (AP)

Same column structure as `invoices` except:
- `bill_number` instead of `invoice_number`
- No `irn`, `qr_code`, `e_invoice_status` fields
- Adds `itc_eligible` BOOLEAN (ITC eligibility flag for GSTR-3B)
- Status enum: `DRAFT`, `POSTED`, `UNPAID`, `PARTIALLY_PAID`, `PAID`, `CANCELLED`
- No `shipping_charges` column

---

## 12. `bill_lines` — Mirror of `invoice_lines` with `bill_id` FK

---

## 13. `bill_payments` — Vendor Disbursements (AP)

Mirror of `payments` with `payment_number` unique per tenant.

---

## 14. `bill_payment_allocations` — Mirror of `payment_allocations` with `bill_id`

---

## 15. `journal_entries` — Double-Entry Ledger

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `entry_date` | DATE | — |
| `reference_number` | VARCHAR(50) | — |
| `description` | TEXT | — |
| `source_type` | VARCHAR(20) | `INVOICE`, `BILL`, `PAYMENT`, `BILL_PAYMENT`, `EXPENSE`, `MANUAL`, `CREDIT_NOTE`, `DEBIT_NOTE`, `ADJUSTMENT` |
| `source_id` | UUID | Links to originating document |
| `is_locked` | BOOLEAN | Default true; locked entries cannot be updated |
| `created_at` | TIMESTAMPTZ | — |
| `updated_at` | TIMESTAMPTZ | — |

**Mutation guard:** SQLAlchemy `before_update` event raises error if `is_locked=True`.

---

## 16. `journal_lines`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `entry_id` | UUID FK→journal_entries | — |
| `account_id` | UUID FK→accounts RESTRICT | Cannot delete account with journal lines |
| `amount` | NUMERIC(15,4) | > 0 |
| `direction` | VARCHAR(6) | `DEBIT` or `CREDIT` |
| `narration` | TEXT | — |

---

## 17. `accounts` — Chart of Accounts

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID FK→tenants | — |
| `name` | VARCHAR(150) | — |
| `code` | VARCHAR(50) | UNIQUE per tenant |
| `account_type` | VARCHAR(50) | e.g. `ASSET`, `LIABILITY`, `EQUITY`, `REVENUE`, `EXPENSE` |
| `account_group` | VARCHAR(100) | e.g. `Cash & Bank`, `Fixed Assets`, `GST Output` |
| `parent_id` | UUID FK→accounts | Self-referential hierarchy |
| `opening_balance` | NUMERIC(15,4) | — |
| `current_balance` | NUMERIC(15,4) | Maintained by ledger engine |
| `is_active` | BOOLEAN | — |
| `deleted_at` | TIMESTAMPTZ | Soft delete |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

**Unique:** `(tenant_id, code)`

---

## 18. `branches` — Office / Warehouse locations

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID FK→tenants | — |
| `name` | VARCHAR(150) | — |
| `gstin` | VARCHAR(15) | Branch GSTIN (can differ from HO) |
| `address` | JSON | `{street, city, state, state_code, pincode, country}` |
| `is_active` | BOOLEAN | — |
| `created_at` / `updated_at` / `deleted_at` | TIMESTAMPTZ | — |

---

## 19. `tenant_settings`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID FK→tenants | — |
| `logo_url` | VARCHAR(255) | Path to uploaded logo |
| `currency` | VARCHAR(10) | Default `INR` |
| `gst_enabled` | BOOLEAN | Default true |
| `e_invoicing_enabled` | BOOLEAN | Default false |
| `e_invoice_username` | VARCHAR(100) | IRP portal username |
| `e_invoice_password_hash` | VARCHAR(255) | Encrypted |
| `e_way_bill_username` | VARCHAR(100) | — |
| `e_way_bill_password_hash` | VARCHAR(255) | Encrypted |
| `upi_id` | VARCHAR(100) | Displayed on invoice |
| `display_settings` | JSON | UI customisation (colors, fonts) |
| `extra_settings` | JSON | Feature flags and misc |
| `origin_state_code` | VARCHAR(2) | Company's state for GST routing |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 20. `numbering_series`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID FK→tenants | — |
| `document_type` | VARCHAR(50) | `INVOICE`, `BILL`, `PAYMENT`, `JOURNAL`, `CREDIT_NOTE`, `DEBIT_NOTE`, `EXPENSE`, `PURCHASE_ORDER`, `SALES_ORDER`, `DELIVERY_CHALLAN`, `PROFORMA_INVOICE` |
| `prefix` | VARCHAR(50) | e.g. `INV-`, `BILL-` |
| `next_number` | INTEGER | Auto-incremented with SELECT FOR UPDATE |
| `suffix` | VARCHAR(50) | Optional trailing suffix |
| `padding_digits` | INTEGER | Default 4 (e.g. `0001`) |
| `is_active` | BOOLEAN | Only one active series per document_type |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 21. `banking_profiles` — Bank accounts

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID FK→tenants | — |
| `bank_name` | VARCHAR(150) | — |
| `account_number` | VARCHAR(50) | — |
| `ifsc_code` | VARCHAR(11) | — |
| `account_type` | VARCHAR(20) | e.g. `CURRENT`, `SAVINGS` |
| `branch_name` | VARCHAR(150) | — |
| `is_primary` | BOOLEAN | Only one primary per tenant |
| `is_active` | BOOLEAN | — |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 22. `expense_categories`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `name` | VARCHAR(150) | — |
| `description` | TEXT | — |
| `linked_account_id` | UUID FK→accounts | GL account to debit |
| `is_active` | BOOLEAN | — |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 23. `expenses`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `expense_number` | VARCHAR(50) | Auto-generated: `EXP-YYYYMM-NNNN` |
| `expense_category_id` | UUID FK→expense_categories | — |
| `bank_account_id` | UUID FK→banking_profiles | Payment account |
| `expense_date` | DATE | — |
| `vendor_name` | VARCHAR(150) | Free text (no Contact FK) |
| `description` | TEXT | — |
| `amount` | NUMERIC(15,4) | Base amount before GST |
| `gst_rate` | NUMERIC(5,2) | — |
| `cgst_amount` / `sgst_amount` / `igst_amount` / `utgst_amount` / `cess_amount` | NUMERIC(15,4) | — |
| `round_off` | NUMERIC(15,4) | — |
| `total` | NUMERIC(15,4) | — |
| `status` | VARCHAR(20) | `DRAFT`, `POSTED`, `CANCELLED` |
| `notes` | TEXT | — |
| `reference_number` | VARCHAR(50) | — |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 24. `purchase_orders`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` / `contact_id` | UUID | — |
| `po_number` | VARCHAR(50) | — |
| `issue_date` / `expected_date` | DATE | — |
| `status` | VARCHAR(20) | `DRAFT`, `CONFIRMED`, `RECEIVED`, `CANCELLED` |
| `subtotal` / `cgst_amount` / `sgst_amount` / `igst_amount` / `total` | NUMERIC | — |
| `pos_state_code` | VARCHAR(2) | — |
| `notes` / `terms_and_conditions` | TEXT | — |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 25. `purchase_order_lines` — Same structure as invoice_lines

---

## 26. `sales_orders`

Same as `purchase_orders` but with `so_number` and statuses: `DRAFT`, `CONFIRMED`, `DELIVERED`, `CANCELLED`

---

## 27. `sales_order_lines` — Same structure as invoice_lines

---

## 28. `delivery_challans`

| Key fields | Notes |
|-----------|-------|
| `dc_number` | — |
| `challan_date` / `expected_delivery_date` | — |
| `status` | `DRAFT`, `ISSUED`, `CANCELLED` |
| `purpose` | `SUPPLY`, `JOB_WORK`, `SAMPLE`, `OTHER` |
| `transporter_name` / `vehicle_number` | — |

---

## 29. `delivery_challan_lines` — Same structure as invoice_lines

---

## 30. `proforma_invoices`

Same as invoices but:
- Status: `DRAFT`, `ISSUED`, `CONVERTED`, `CANCELLED`
- Adds `converted_invoice_id` FK→invoices

---

## 31. `proforma_invoice_lines` — Same structure as invoice_lines

---

## 32. `credit_notes`

| Key fields | Notes |
|-----------|-------|
| `cn_number` | — |
| `invoice_id` | Optional FK→invoices (null = standalone) |
| `issue_date` | — |
| `status` | `DRAFT`, `POSTED`, `CANCELLED` |
| `subtotal` / `cgst_amount` / `sgst_amount` / `igst_amount` / `total` | — |
| `reason` | TEXT |

---

## 33. `credit_note_lines` — Same structure as invoice_lines

---

## 34. `debit_notes` — Mirror of credit_notes with `dn_number`

---

## 35. `debit_note_lines`

---

## 36. `sales_returns`

| Key fields | Notes |
|-----------|-------|
| `return_number` | — |
| `contact_id` | — |
| `return_date` | — |
| `status` | `DRAFT`, `POSTED`, `CANCELLED` |
| `original_invoice_id` | Optional FK→invoices |
| GST amounts | — |

---

## 37. `sales_return_lines`

---

## 38. `purchase_returns` — Mirror of sales_returns with vendor contact

---

## 39. `purchase_return_lines`

---

## 40. `inventory_adjustments`

| Key fields | Notes |
|-----------|-------|
| `adjustment_number` | — |
| `adjustment_date` | — |
| `reason` | TEXT |
| `status` | `DRAFT`, `CONFIRMED`, `CANCELLED` |

---

## 41. `inventory_adjustment_lines`

| Column | Type | Notes |
|--------|------|-------|
| `product_id` | UUID FK→products | — |
| `quantity_change` | NUMERIC(12,2) | Positive = increase, negative = decrease |
| `unit_cost` | NUMERIC(15,4) | For valuation |

---

## 42. `eway_bills`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `invoice_id` | UUID FK→invoices | — |
| `bill_id` | UUID FK→bills | — |
| `eway_bill_number` | VARCHAR(50) | From NIC portal |
| `status` | VARCHAR(20) | `PENDING`, `GENERATED`, `CANCELLED` |
| `supply_type` | VARCHAR(10) | `OUTWARD`, `INWARD` |
| `sub_supply_type` | VARCHAR(20) | `SUPPLY`, `IMPORT`, `EXPORT`, etc. |
| `transporter_id` | VARCHAR(15) | Transporter GSTIN |
| `transporter_name` | VARCHAR(150) | — |
| `trans_doc_number` | VARCHAR(50) | LR/RR number |
| `trans_doc_date` | DATE | — |
| `trans_distance` | INTEGER | km (1–4000) |
| `trans_mode` | VARCHAR(10) | `ROAD`, `RAIL`, `AIR`, `SHIP` |
| `vehicle_number` | VARCHAR(20) | — |
| `vehicle_type` | VARCHAR(10) | `REGULAR`, `ODC` |
| `valid_until` | TIMESTAMPTZ | Auto-calculated by NIC |
| `vehicle_history` | JSON | History of vehicle updates |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 43. `gst_returns` — GST Filing State Machine

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `return_type` | VARCHAR(20) | `GSTR1`, `GSTR2`, `GSTR3B` |
| `period_start` / `period_end` | DATE | Return period |
| `status` | VARCHAR(20) | `DRAFT`, `FILED`, `PENDING`, `ERROR` |
| `filed_at` | TIMESTAMPTZ | — |
| `reference_number` | VARCHAR(50) | ARN from GST portal |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 44. `stock_ledger` — Inventory movement audit trail

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `product_id` | UUID FK→products | — |
| `transaction_date` | DATE | — |
| `transaction_type` | VARCHAR(30) | `INVOICE`, `BILL`, `ADJUSTMENT`, `OPENING`, `RETURN` |
| `source_id` | UUID | Links to originating document |
| `quantity_change` | NUMERIC(12,2) | ±quantity |
| `running_balance` | NUMERIC(12,2) | Stock after this entry |
| `unit_cost` | NUMERIC(15,4) | FIFO/weighted average cost |
| `created_at` | TIMESTAMPTZ | — |

---

## 45. `bank_statements`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `banking_profile_id` | UUID FK→banking_profiles | — |
| `statement_date` | DATE | — |
| `opening_balance` / `closing_balance` | NUMERIC(15,4) | — |
| `currency` | VARCHAR(10) | Default `INR` |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 46. `bank_transactions`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `bank_statement_id` | UUID FK→bank_statements | — |
| `transaction_date` | DATE | — |
| `amount` | NUMERIC(15,4) | — |
| `description` | TEXT | Narration from bank |
| `reference_number` | VARCHAR(50) | — |
| `is_reconciled` | BOOLEAN | Default false |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 47. `bank_reconciliations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `bank_transaction_id` | UUID FK→bank_transactions | — |
| `payment_id` | UUID FK→payments | — |
| `bill_payment_id` | UUID FK→bill_payments | — |
| `amount` | NUMERIC(15,4) | Reconciled amount |
| `notes` | TEXT | — |
| `created_at` | TIMESTAMPTZ | — |

---

## 48. `financial_years`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | — |
| `tenant_id` | UUID | — |
| `name` | VARCHAR(50) | e.g. `FY 2025-26` |
| `start_date` / `end_date` | DATE | — |
| `status` | VARCHAR(20) | `ACTIVE`, `CURRENT`, `LOCKED`, `ARCHIVED`, `READY_TO_CLOSE` |
| `is_current` | BOOLEAN | Only one per tenant |
| `closed_at` | TIMESTAMPTZ | — |
| `closed_by` | UUID | — |
| `created_at` / `updated_at` | TIMESTAMPTZ | — |

---

## 49. `financial_year_audits` — FY audit trail

| Column | Notes |
|--------|-------|
| `fy_id` | FK→financial_years |
| `action` | `CREATED`, `CLOSED`, `REOPENED`, `LOCKED` |
| `performed_by` | UUID (user) |
| `detail` | TEXT |
| `created_at` | — |

---

## 50. `accounting_periods` — Period locks

| Column | Notes |
|--------|-------|
| `tenant_id` | — |
| `period_start` / `period_end` | DATE range |
| `is_locked` | BOOLEAN |
| `locked_by` / `locked_at` | — |

---

## 51. `period_lock_audits`

| Column | Notes |
|--------|-------|
| `tenant_id` / `period_date` | — |
| `action` | `LOCK` or `UNLOCK` |
| `locked_by` / `locked_at` | — |
| `note` | TEXT |

---

## 52. `opening_balance_snapshots` — FY close audit

| Column | Notes |
|--------|-------|
| `financial_year_id` | FK→financial_years |
| `account_id` | FK→accounts |
| `closing_balance` | NUMERIC(15,4) |
| `snapshot_date` | DATE |

---

## 53. `inventory_carry_forward` — FY close stock snapshot

| Column | Notes |
|--------|-------|
| `financial_year_id` | FK→financial_years |
| `product_id` | FK→products |
| `closing_stock` | NUMERIC(12,2) |
| `unit_cost` | NUMERIC(15,4) |

---

## 54. `recurring_invoices`

| Column | Notes |
|--------|-------|
| `contact_id` | — |
| `frequency` | `DAILY`, `WEEKLY`, `MONTHLY`, `QUARTERLY`, `YEARLY` |
| `interval_value` | INTEGER (e.g. every 2 months) |
| `start_date` / `end_date` | — |
| `next_generation_date` | DATE |
| `is_active` | — |
| `pos_state_code` / `notes` / `terms_and_conditions` | — |

---

## 55. `recurring_invoice_items`

| Column | Notes |
|--------|-------|
| `recurring_invoice_id` | FK→recurring_invoices |
| `product_id` | FK→products |
| `quantity` / `rate` / `discount` / `gst_rate` / `hsn_sac` | — |

---

## 56. `terms_templates`

| Column | Notes |
|--------|-------|
| `tenant_id` | — |
| `name` | VARCHAR(150) |
| `content` | TEXT |
| `is_active` | — |

---

## 57. `tax_templates`

| Column | Notes |
|--------|-------|
| `tenant_id` | NULL = global |
| `name` | e.g. `GST 18%` |
| `rate` | NUMERIC(5,2) |
| `is_active` | — |

---

## 58. `payment_terms`

| Column | Notes |
|--------|-------|
| `tenant_id` | NULL = global |
| `name` | e.g. `Net 30` |
| `days` | INTEGER |
| `is_active` | — |

---

## 59. `audit_logs` — Immutable audit trail

| Column | Notes |
|--------|-------|
| `tenant_id` | — |
| `actor_id` | User UUID |
| `action` | e.g. `INVOICE_CREATED`, `PAYMENT_CANCELLED` |
| `entity_type` | e.g. `Invoice`, `Payment` |
| `entity_id` | UUID of affected record |
| `changes` | JSON diff |
| `ip_address` | — |
| `timestamp` | TIMESTAMPTZ |

---

## 60. `tenant_invitations`

| Column | Notes |
|--------|-------|
| `tenant_id` | FK→tenants |
| `email` | Invited email |
| `role` | `owner`, `accountant`, etc. |
| `token` | Unique invitation token |
| `status` | `PENDING`, `ACCEPTED`, `EXPIRED` |
| `expires_at` | — |

---

## 61. `webhook_events`

| Column | Notes |
|--------|-------|
| `event_type` | e.g. `invoice.created` |
| `payload` | JSON |
| `status` | `PENDING`, `DELIVERED`, `FAILED` |
| `retry_count` | INTEGER |

---

## 62. `idempotency_records`

| Column | Notes |
|--------|-------|
| `key` | VARCHAR UNIQUE — from `Idempotency-Key` header |
| `response_code` | HTTP status |
| `response_body` | JSON |
| `created_at` | — |

---

## Total Tables: 62
