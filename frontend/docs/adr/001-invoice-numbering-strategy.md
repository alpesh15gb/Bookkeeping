# ADR-001: Offline Invoice Numbering Strategy

**Date:** 2026-07-28  
**Status:** Accepted  

## Context

ApexBooks generates legally meaningful invoice numbers that must be unique,
sequential, compliant with statutory requirements, and immutable after issuance.
The application is offline-first — invoices may be issued without internet
connectivity.  Three approaches were considered:

1. **Provisional local number replaced after sync** — simplest, but causes
   audit and support issues when a customer-visible number changes.
2. **Permanent client-generated prefix** — avoids renumbering but creates
   multi-device collision risk and may not satisfy sequential-numbering laws.
3. **Pre-allocated server number ranges** — strongest audit properties but
   requires server-side allocation management.

## Decision

Use **pre-allocated server number ranges** with the rules below.

## Design

### Allocation contract

Ranges are scoped by:
- **Company** (`tenant_id`)
- **Financial year** (`financial_year_id`)
- **Series** (e.g. `SALES`, `PURCHASE`)
- **Document type** (e.g. `INVOICE`, `CREDIT_NOTE`)
- **Device** (`device_id`)

The server exposes an endpoint:

```
POST /api/v1/numbering/allocate  →  { "from": 1001, "to": 1050, "allocation_id": "uuid" }
GET  /api/v1/numbering/status    →  current utilisation per (company, series, device, FY)
```

- Each allocation returns a contiguous block `[from, to]`.
- Blocks never overlap for the same scoping key.
- The server tracks `next_free` per scoping key and advances it atomically.

### Client consumption

- The client stores the allocated block locally.
- Numbers are consumed monotonically — never skipped forward.
- On issue/post the client assigns `from + consumed_count` and increments `consumed_count`.
- If an invoice is voided after issuance, its number is recorded as `voided` and never reused.
- Unused numbers survive device restart via SQLite persistence.

### State model

```
Draft         → no legal number consumed; fully editable.
Ready/Issue   → number assigned by consuming from the local block.
Issued        → snapshot frozen; journal created; sync queued.
Voided        → the immutable issued record remains; a reversal/credit note is created.
Synced        → server confirmed the push.
Sync failed   → issued locally but server rejected; user must resolve.
```

A `Draft` must NOT consume a legal number.  The number is assigned only
at the irreversible `Issue` boundary.

### Sync validation

- The sync payload includes `allocation_id`, `number`, `series`, `fy_id`.
- The server rejects any push where the number falls outside the device's
  allocated range or was already consumed by another device.
- Idempotency key prevents duplicate processing.

### Device loss / reinstallation

- On first pull after reinstall the client fetches current allocation state.
- Any unused numbers from a lost device remain allocated to that device_id
  and are NOT silently returned to the pool.
- An admin endpoint on the server can force-release orphaned ranges.

### Local persistence

Two Drift tables are added:

1. `NumberAllocations` — per (company, device, series, FY) block with
   `from_num`, `to_num`, `consumed`, `allocation_id`, `is_active`.
2. `Invoices` — header with `number` (nullable for drafts), `allocation_id`,
   lifecycle status, sync status, and all immutable business fields.

## Consequences

| Concern | Mitigation |
|---------|-----------|
| Range exhaustion blocks issuance | The UI shows a clear warning and offers a manual "request more numbers" action that triggers a push + pull cycle. |
| Multi-device offline conflict | Impossible for issuance — ranges are disjoint per device. Two devices offline cannot issue the same number. |
| Statutory compliance | `(company, series, FY, number)` is unique. Sequence is monotonic. No gaps within an active range (voided numbers are recorded as voided, not recycled, so the sequence itself has gaps but the legal records account for them). |
| Backend dependency | Numbering requires a live allocation call. Without this the first issue after install waits for connectivity. Subsequent issues within the allocated range work fully offline. |
| FY rollover | Scope includes `financial_year_id`. A new FY clears the `next_free` cursor on the server. The client must pull fresh allocations at FY start. |
