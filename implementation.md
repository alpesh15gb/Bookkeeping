Continue Implementation — Complete All Remaining Modules



Do not close the session. Do not provide architecture commentary, milestone summaries, or handoff reports between modules. Begin implementation immediately and continue module by module.



Payroll is not part of this project. Do not create payroll tables, repositories, screens, journals, tests, or roadmap items.



Current Repository Baseline

Schema:                 v7

Migration transitions:  6

Tests:                  416/416 green

Completed slices:

\- Journals

\- Invoices

\- Payments

\- Inventory

\- Purchasing



The offline platform is frozen.



Do Not Modify

SyncEngine

SyncScheduler

outbox semantics

pull checkpoint model

retry model

migration framework

persisted company/actor/device/financial-year scope

repository authority

lifecycle and sync-state separation

established transaction boundaries



Every new capability must use the existing vertical-slice template:



Drift tables

→ schema migration

→ domain entities and commands

→ repository interface

→ transactional repository implementation

→ journal integration where required

→ outbox pusher registration

→ optional pull applicator

→ providers/notifiers

→ UI screens

→ migration, repository, rollback, and workflow tests

Module 1 — Sales and Fulfilment



Implement the complete sales workflow.



Schema



Add:



SalesOrders

SalesOrderLines

SalesDeliveries

SalesDeliveryLines

delivery-to-invoice links



Bump schema:



v7 → v8



Update:



AppDatabase

fresh-database creation

migration upgrade path

reusable migration fixture

migration tests

Domain



Create:



SalesOrderEntity

SalesOrderLineEntity

SalesDeliveryEntity

SalesDeliveryLineEntity

SaveSalesOrderDraftCommand

DeliverSalesOrderCommand

CreateInvoiceFromDeliveryCommand

SalesRepository

Delivery transaction



Inside one Drift transaction:



Load the sales order.

Validate company and financial-year scope.

Validate open quantities.

Validate stock availability for every line before writing.

Create the delivery and delivery lines.

Decrease stock quantities.

Update inventory balances.

Write inventory ISSUE movements.

Calculate COGS using persisted weighted-average cost.

Create a balanced journal:

debit COGS

credit inventory

Update delivered quantities and order status.

Create the delivery outbox row.

Invoice-from-delivery transaction



Inside one transaction:



Validate posted delivery.

Reject already invoiced quantities.

Recompute prices, discounts, taxes, shipping, and totals.

Consume an invoice number allocation.

Create and freeze the customer invoice.

Link invoice lines to delivery lines.

Create the receivable/revenue journal.

Update invoiced delivery quantities.

Create the invoice outbox row.



Reuse the existing invoice numbering and financial calculation logic. Do not duplicate it in the Sales UI.



UI



Build:



Sales Order form

Sales Order list

Sales Order detail

Delivery confirmation

Delivery detail

Create Invoice from Delivery flow

Required tests

draft save

restart recovery

partial delivery

full delivery

insufficient-stock rejection

stock decrement

inventory movement

weighted-cost COGS

balanced COGS journal

duplicate delivery rejection

invoice creation from delivery

number allocation consumption

duplicate invoicing rejection

company isolation

outbox payloads

delivery rollback

invoice-generation rollback

Module 2 — Sales Returns and Purchase Returns



Implement both customer and supplier returns.



Schema



Add:



SalesReturns

SalesReturnLines

PurchaseReturns

PurchaseReturnLines

source-document links

return-to-credit/debit-note links



Bump schema:



v8 → v9

Customer return transaction



Inside one transaction:



Validate original delivery/invoice.

Validate returnable quantity.

Create return and lines.

Increase inventory.

Recompute weighted-average cost according to the documented return policy.

Write CUSTOMER\_RETURN inventory movements.

Reverse COGS:

debit inventory

credit COGS

Create credit-note data or adjustment record.

Create receivable/revenue/tax reversal journal.

Create outbox rows.

Supplier return transaction



Inside one transaction:



Validate original purchase receipt/invoice.

Validate returnable quantity.

Validate sufficient stock.

Create supplier return and lines.

Decrease inventory.

Write SUPPLIER\_RETURN movements.

Create inventory/GRIR/AP journal entries.

Create debit-note data or adjustment record.

Create outbox rows.

UI



Build:



Customer Return form/list/detail

Supplier Return form/list/detail

Source-document selection

Return quantity validation

Immutable posted-return detail

Required tests

partial return

full return

over-return rejection

duplicate-return rejection

inventory reversal

journal reversal

tax reversal

company isolation

rollback across every affected table

correct outbox payloads

Module 3 — Credit Notes and Debit Notes



Implement legally numbered customer credit notes and supplier debit notes.



Schema



Add:



CreditNotes

CreditNoteLines

CreditNoteTaxLines

DebitNotes

DebitNoteLines

DebitNoteTaxLines



Extend number allocations to support document type and series.



Bump schema:



v9 → v10

Requirements

Draft documents consume no legal number.

Posting consumes a number inside the posting transaction.

Posted documents are immutable.

Totals are repository-computed.

Source invoice and return links are persisted.

Journals are balanced.

Outbox writes are atomic with posting.

Double posting is rejected.

Range exhaustion produces a clear validation error.

UI



Build:



Credit Note form/list/detail

Debit Note form/list/detail

Issue confirmation

Source invoice selection

Remaining balance display

Required tests

draft lifecycle

restart recovery

number consumption

immutable posting

journal correctness

tax adjustment

allocation rollback on failure

duplicate posting rejection

sync payloads

Module 4 — Banking and Reconciliation



Implement bank accounts, imported statements, matching, and reconciliation.



Schema



Add:



BankAccounts

BankStatements

BankStatementLines

BankMatches

BankReconciliations



Bump schema:



v10 → v11

Domain



Create:



bank account entity

statement entity

statement-line entity

match entity

reconciliation entity

import command

match command

unmatch command

finalize reconciliation command

BankingRepository

Requirements

Statement imports are idempotent.

Duplicate bank lines are detected by stable external ID or deterministic fingerprint.

Matching supports payments, receipts, and journal entries.

One accounting transaction cannot be matched beyond its available amount.

Partial matching is supported.



Reconciliation closing balance must equal:



opening balance + statement inflows - statement outflows

Finalized reconciliation is immutable.

Matching and unmatching are transactional.

Repository computes authoritative unmatched balances.

UI



Build:



Bank account list

Statement import screen

Statement line list

Match/unmatch workflow

Reconciliation summary

Immutable finalized reconciliation detail

Required tests

idempotent import

duplicate detection

full match

partial match

over-match rejection

unmatch

restart recovery

reconciliation balance validation

finalized reconciliation immutability

company isolation

rollback

sync payloads

Module 5 — Tax



Implement the project’s tax reporting capability. Do not add payroll taxes.



Schema



Add:



TaxCodes

TaxPeriods

TaxReturnLines

TaxReturns

filing/export metadata



Bump schema:



v11 → v12

Requirements

Tax codes are company-scoped.

Input and output tax are derived from posted source records.

Draft records do not enter tax returns.

Returns are generated for a defined period.

Repository calculates:

output tax

input tax

adjustments

net payable/refundable

Finalized returns are immutable.

Source transactions remain traceable from each tax-return line.

Re-running a draft return is idempotent.

Finalization creates any required journal and outbox rows atomically.

UI



Build:



Tax code list/detail

Tax period list

Generate tax return

Tax return summary

Source transaction drill-down

Finalized return detail

Export action

Required tests

input/output classification

date-period boundaries

company isolation

draft exclusion

tax rounding

adjustment handling

idempotent regeneration

finalization

rollback

sync payload

Module 6 — Accounting Reports



Implement repository-backed reports. Reports are read models and must not mutate accounting state.



Required reports

Trial Balance

General Ledger

Profit and Loss

Balance Sheet

Cash Flow

Aged Receivables

Aged Payables

Inventory Valuation

Stock Movement Report

Sales Register

Purchase Register

Tax Summary

Requirements

company-scoped

financial-year scoped

date-range filtering

account filtering where relevant

repository/query-layer calculations only

no authoritative total calculated in widgets

debit/credit equality verification

drill-down to source documents

export-ready structured results

deterministic ordering

stable rounding rules

UI



Build:



Reports dashboard

Filters

Summary views

Drill-down views

Empty/error/loading states

Export actions

Required tests

report totals

date filtering

financial-year filtering

company isolation

balanced trial balance

P\&L calculation

balance-sheet equation

aged bucket boundaries

inventory valuation

source drill-down



Schema changes are optional here. Only bump the schema if persisted report snapshots or export history are added.



Module 7 — Fixed Assets



Implement fixed-asset management.



Schema



Add:



FixedAssets

AssetCategories

AssetDepreciationSchedules

AssetDepreciationEntries

AssetDisposals

AssetTransfers



Bump the schema once for this module.



Requirements

acquisition from purchase invoice or manual entry

depreciation method documented and implemented

monthly depreciation posting

accumulated depreciation

net book value

disposal gain/loss

transfers between locations/cost centers

immutable posted depreciation entries

journal and outbox writes in the same transaction

duplicate period posting rejected

UI



Build:



Asset list/detail

Asset creation

Depreciation preview

Post depreciation

Disposal workflow

Transfer workflow

Required tests

acquisition

depreciation calculation

repeated-period rejection

restart recovery

journal generation

disposal gain/loss

rollback

company isolation

sync payload

Module 8 — Manufacturing



Implement this module only if manufacturing is part of the product scope. It is not payroll.



If manufacturing is not required, record it as intentionally excluded and proceed to Module 9.



Schema



Add:



BillsOfMaterial

BillOfMaterialLines

ProductionOrders

MaterialConsumptions

FinishedGoodReceipts

ProductionVariances

Requirements

BOM versioning

component availability validation

raw-material consumption

finished-goods receipt

weighted-average valuation update

production variance

inventory movements

balanced journals

atomic rollback

outbox payloads

UI and tests



Build complete forms, lists, details, posting workflows, and rollback tests following the same repository template.



Module 9 — Administration and Audit

Schema



Add or complete:



roles

permissions

user-role assignments

audit events

company settings

document-series settings

financial-year settings



Bump schema if required.



Requirements

role-based feature access

company-scoped permissions

persisted audit trail for posted/issued/reversed operations

actor and device captured from persisted operation scope

audit records immutable

financial-year lock dates

prevention of posting into locked periods

configurable document number series

no silent deletion of financial records

UI



Build:



Roles and Permissions

Company Settings

Financial Years

Document Number Series

Audit Log

Required tests

authorization

company isolation

locked-period rejection

audit immutability

document-series validation

scope persistence

rollback where applicable

Module 10 — Remaining Sync Hardening



Only after all business modules are complete, implement the documented backend compatibility work.



Add

revision/version fields

conflict detection

explicit conflict state and resolution workflow

delete/tombstone events

updated\_since or equivalent incremental recovery

background sync scheduling

sync diagnostics

retry visibility

large-batch pagination tests

attachment synchronization only if attachments are in scope



Existing checkpoint and outbox semantics must remain intact. Extend them; do not replace them.



Required tests

stale revision rejection

conflict persistence

conflict resolution

tombstone application

interrupted pagination recovery

company isolation

duplicate event handling

large dataset processing

restart during push

restart during pull

Global Acceptance Rules



Every module must satisfy all of the following:



Company isolation.

Financial-year scope where relevant.

Restart recovery.

Repository-owned calculations.

Lifecycle and sync state stored separately.

Operation scope persisted in the outbox.

Idempotent push behavior.

Transactional outbox creation.

Rollback leaves no partial cross-domain writes.

Full migration path from v1 to the latest schema.

Fresh database creation at the latest schema.

Full test suite remains green.

No new analyzer errors.

No payroll code or payroll roadmap items.

Execution Order



Implement continuously in this order:



Sales

→ Returns

→ Credit/Debit Notes

→ Banking and Reconciliation

→ Tax

→ Reports

→ Fixed Assets

→ Manufacturing only if in scope

→ Administration and Audit

→ Sync Hardening



Do not pause after a module to ask what to do next.



Do not give progress commentary in place of implementation.



After each schema module:



bump the schema once;

add one migration transition;

update the migration fixture;

run migration tests;

continue immediately.



After each business module:



run its workflow tests;

run the full suite;

fix failures;

continue immediately to the next module.

Final Completion Criterion



Only provide the final implementation report when:



every in-scope module above is complete;

payroll has not been added;

all migration transitions pass;

every rollback test passes;

the full suite is green;

there are zero new analyzer errors;

platform contracts remain structurally intact.



Begin now with the Sales tables and the v7 → v8 migration. Do not close the session.

