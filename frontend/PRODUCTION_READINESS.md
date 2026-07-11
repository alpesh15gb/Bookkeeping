# ApexBooks — Production Readiness Checklist

**Classification:** Production Release Candidate (RC) v3.0.0  
**Date:** 2026-07-07  
**Status:** ✅ Architecture proven, ⏳ Operational validation pending

---

## ✅ PASSED — Code Quality Gates

| Gate | Status | Evidence |
|:-----|:------:|:---------|
| Static analysis | ✅ Pass | `dart analyze` — 0 errors, 0 warnings |
| Unit tests | ✅ Pass | 313/313 passing across 36 test files |
| Architecture principles | ✅ Pass | Core frozen across 10 business engines |
| Financial invariants | ✅ Pass | Balanced journal, TB, BS, reconciliation rules |
| API contract alignment | ✅ Pass | 24 frontend services matched to backend endpoints |
| Permission model | ✅ Pass | 6 scopes enforced via PermissionGate |
| Business logic isolation | ✅ Pass | All logic in services, not UI |
| Explicit state machines | ✅ Pass | Invoice, PO, Bill, Payment, Reservation, FY status |

## ⏳ REMAINING — Operational Validation

### 1. End-to-End Workflow Reconciliation

Execute a complete business cycle against a **real backend database** and verify that every number reconciles:

| Step | Action | Verify |
|:-----|:-------|:-------|
| 1.1 | Create Purchase Order | PO created, status = Draft |
| 1.2 | Approve Purchase Order | Status = Confirmed |
| 1.3 | Create Goods Receipt | Stock increased, PO line.quantity_received updated |
| 1.4 | Create Vendor Bill | Payable created, Vendor balance updated |
| 1.5 | Pay Vendor | Payable reduced, Bank balance decreased |
| 1.6 | Create Sales Invoice | Receivable created, Stock deducted |
| 1.7 | Receive Customer Payment | Receivable reduced, Bank balance increased |
| 1.8 | Create Manual Journal | Debit == Credit, Ledger updated |
| 1.9 | Run Trial Balance | Total Debits == Total Credits |
| 1.10 | Run Balance Sheet | Assets == Liabilities + Equity |
| 1.11 | Run Profit & Loss | Net Profit matches ledger |
| 1.12 | Run GST Report | Output - Input == Net Liability |
| 1.13 | Close Financial Year | Opening balances created for next FY |

**Pass criteria:** All balances reconcile. No orphaned records. No data corruption.

### 2. Multi-User Concurrency Testing

| Scenario | Test |
|:---------|:-----|
| 2.1 | Two users edit the same invoice simultaneously |
| 2.2 | User A finalizes invoice while User B has it open |
| 2.3 | Duplicate finalize request (double-click) |
| 2.4 | Two users reserve the same stock simultaneously |
| 2.5 | User posts journal while another runs Trial Balance |
| 2.6 | Session expiry mid-edit |
| 2.7 | Token refresh during API call |

**Pass criteria:** No race conditions. Optimistic locking or version conflicts handled gracefully. No inconsistent state.

### 3. Load & Performance Testing

| Scenario | Dataset | Measure |
|:---------|:--------|:--------|
| 3.1 | 100,000 customers | Search latency < 2s |
| 3.2 | 100,000 products | Search latency < 2s |
| 3.3 | 500,000 invoices | List/filter latency < 3s |
| 3.4 | 1,000,000 journal entries | Trial Balance generation < 10s |
| 3.5 | 500,000 ledger lines | Ledger report < 5s |
| 3.6 | Concurrent dashboard load | < 3s with caching |
| 3.7 | Bank reconciliation with 50,000 transactions | Matching < 5s |

**Pass criteria:** All operations complete within acceptable latency. No OOM errors. UI remains responsive.

### 4. Security Review

| Check | Description |
|:------|:------------|
| 4.1 | JWT token expiry handled on every API call |
| 4.2 | Refresh token rotation works correctly |
| 4.3 | Tenant isolation — User A cannot see User B's data |
| 4.4 | Permission enforcement — unauthorized actions rejected |
| 4.5 | SQL injection — all inputs parameterized (backend) |
| 4.6 | XSS — all user inputs sanitized |
| 4.7 | CSRF — state-changing operations require valid session |
| 4.8 | Rate limiting — excessive requests blocked (backend) |
| 4.9 | Audit logging — all financial changes logged |

### 5. Backup & Disaster Recovery

| Check | Description |
|:------|:------------|
| 5.1 | Database backup completes successfully |
| 5.2 | Backup restore produces consistent data |
| 5.3 | Trial Balance balances after restore |
| 5.4 | Application upgrade preserves all data |
| 5.5 | Rollback procedure documented and tested |

### 6. Operational Readiness

| Check | Description |
|:------|:------------|
| 6.1 | Application logging configured (error/warn/info) |
| 6.2 | API error monitoring configured |
| 6.3 | Performance metrics collection configured |
| 6.4 | Alerting on critical errors configured |
| 6.5 | Deployment rollback procedure documented |
| 6.6 | Health check endpoint available |
| 6.7 | Startup/shutdown procedures documented |

---

## Release Decision Matrix

| Condition | Status | Decision |
|:----------|:------:|:---------|
| All Code Quality Gates pass | ✅ | Proceed to RC |
| End-to-End Reconciliation passes | ⏳ | Required for GA |
| Concurrency tests pass | ⏳ | Required for GA |
| Performance benchmarks met | ⏳ | Required for GA |
| Security review passes | ⏳ | Required for GA |
| Backup/restore validated | ⏳ | Required for GA |
| Operational readiness confirmed | ⏳ | Required for GA |

**Current Classification:** **v3.0.0 — Production Release Candidate (RC)**  
**Next Milestone:** **v3.0.0 — General Availability (GA)**  
**Gate:** All 7 Operational Validation items above must pass.

---

## Version History

| Version | Date | Classification |
|:--------|:-----|:---------------|
| v1.0.0 | — | Foundation |
| v1.3.0-MVP-ready | — | MVP |
| v2.0.0-milestone1 | — | Masters Complete |
| v2.1.0-business-foundation | — | Business Engines |
| v2.2.0-inventory-engine | — | Inventory |
| v2.3.0-purchase-engine | — | Purchases |
| **v3.0.0-accounting-engine** | **2026-07-07** | **Release Candidate** |
| v3.0.0 | TBD | General Availability |
