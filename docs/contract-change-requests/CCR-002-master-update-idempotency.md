# CCR-002: Repeat master updates and canonical idempotency keys

- Contract: ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)
- Status: Proposed for a future contract version
- Discovered during: Phase 2 master-data synchronization

## Issue

Contract v1 defines the canonical key as
`{tenant_id}:{event_name}:{source_id}:{event_version}`. The master-data examples use
the stable entity ID as `source_id`. Consequently, every subsequent update for the
same entity, event name, and contract version has the same idempotency key. A new
payload must then be rejected as `IDEMPOTENCY_CONFLICT`, preventing legitimate
product, price, inventory, and customer updates.

## Requested change

In a future contract version, include an immutable event/revision discriminator in
the canonical key (for example the event ID or ERP entity revision), while retaining
stable entity identity in `source_id`.

## Phase 2 disposition

Contract v1 remains unchanged. The receiver validates the documented canonical
formula. Repeat updates are possible only when the sender supplies a distinct valid
`source_id`; the path identifier and payload entity identifier remain required to
match.
