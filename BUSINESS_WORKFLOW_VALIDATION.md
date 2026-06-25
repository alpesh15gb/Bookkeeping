# Business Workflow Validation Report — ApexBooks v1.0

**Date:** 2026-06-26

---

## Summary

All core business workflows validated end-to-end through API simulation.

---

## Workflows Validated

### 1. Company Registration → First Invoice

| Step | API | Result |
|------|-----|--------|
| Register with GSTIN | POST /auth/register | tax_mode = GST_REGULAR |
| Login | POST /auth/login | JWT issued |
| Create customer | POST /masters/contacts | 201 |
| Create product | POST /masters/products | 201 |
| Create invoice | POST /invoices | 201, auto-posted |

### 2. Purchase → ITC

| Step | API | Result |
|------|-----|--------|
| Create vendor | POST /masters/contacts | 201 |
| Create bill | POST /bills | 201, auto-posted |
| ITC recorded | Journal entries | CGST/SGST input accounts |

### 3. Invoice → Receipt → Settlement

| Step | API | Result |
|------|-----|--------|
| Create invoice | POST /invoices | 201, POSTED |
| Record receipt | POST /payments/receipts | 201 |
| Allocation | Against invoice | Amount allocated |

### 4. Expense → Posting

| Step | API | Result |
|------|-----|--------|
| Create expense | POST /expenses | 201, DRAFT |
| Post to ledger | POST /expenses/{id}/post | 200, POSTED |
| Journal entry | Auto-created | DR Expense, CR Cash |

### 5. Credit Note → Reversal

| Step | API | Result |
|------|-----|--------|
| Create credit note | POST /invoices/credit-notes | 201 |
| Reversal entry | Auto-created | Reversing journal |

### 6. Year-End Close

| Step | API | Result |
|------|-----|--------|
| Check readiness | GET /financial-years/{id}/dashboard | Score calculated |
| Close FY | POST /financial-years/{id}/close | LOCKED |
| New FY created | Auto-created | CURRENT |
| Roll-forward | Opening balances carried | Complete |

---

## Data Integrity Checks

| Check | Result |
|-------|--------|
| No orphaned journal lines | PASS |
| No unbalanced entries | PASS |
| All invoices have ledger postings | PASS |
| All payments have allocations | PASS |
| Soft-delete preserves audit trail | PASS |
