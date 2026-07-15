# ApexBooks Production Acceptance

The release gate is executable from the repository root:

```bash
python scripts/production_acceptance.py
```

It fails immediately if migrations have multiple heads, any backend workflow
test fails, Flutter analysis reports an error/warning, or any Flutter test fails.

## Workflow evidence

| Business area | Release evidence |
|---|---|
| Onboarding, company, defaults, numbering and FY | `test_company.py`, `test_registration_gst_flow.py`, `test_financial_year_status.py` |
| Authentication, RBAC and tenant isolation | `test_auth.py`, `integration/test_auth_router.py`, `test_uat_business_simulation.py` |
| Customers, vendors, products, COA and opening values | `test_masters.py`, `integration/test_accounts_crud.py`, `test_api_contract_validation.py` |
| Quote → order → challan → invoice → receipt | `test_payments_flow.py::test_quotation_to_receipt_traceable_workflow` |
| Purchase order → bill → payment and returns | `test_purchase_orders.py`, `test_bills.py`, `test_payments_flow.py`, `test_credit_debit_notes.py` |
| Stock, warehouse, transfer and adjustment | `test_inventory_adjustments.py`, `test_delivery_challans.py`, Flutter inventory tests |
| Journals, contra, receipts, payments and reversals | `test_accounting_flow.py`, `test_payments_flow.py` |
| GST, returns, GSTR-1/2/3B and filing locks | `test_gst_compliance.py`, `test_registration_gst_flow.py`, unit GST tests |
| Trial Balance, P&L, Balance Sheet, ageing and party ledgers | `test_reports.py`, `test_premerge_verification.py`, complete sales workflow |
| Financial-year close, carry-forward and reopen | `test_year_end_e2e.py` |
| Audit actor, before/after state and rollback atomicity | `test_audit_logging.py` |
| PDF payload and printable PDF | Complete sales workflow plus report export tests |
| Duplicate submission and database invariants | `test_db_constraints.py`, `test_backend_integration_sprint.py` |
| Flutter calculations, forms, tables and responsive widgets | `frontend/test` |

The complete sales workflow is deliberately cross-layer. It verifies persisted
documents, balanced journal entries, one warehouse movement, GST totals,
cleared outstanding and ageing, customer statement, Trial Balance, Balance
Sheet, audit actions, PDF payload and generated `%PDF` bytes in one scenario.

## Explicitly not represented as completed functionality

RFQ and manufacturing remain future modules. Multi-currency is schema-ready but
is not treated as a completed accounting workflow. Batch/serial/expiry and full
offline transaction sync must not be advertised as production features until
their own end-to-end workflows are implemented and added to this gate.

Synthetic scale benchmarks are not part of stabilization acceptance. Production
readiness here means correctness, recoverability, usability and reconciliation.
