# CCR-005: Multiple order revisions and canonical idempotency keys

- Contract: ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)
- Status: Proposed for a future contract version
- Discovered during: Order Lifecycle implementation

## Issue

Contract v1 supports sequential `order.updated` revisions, but defines the canonical
idempotency key as `{tenant_id}:{event_name}:{source_id}:{event_version}` and requires
the path order ID, snapshot order ID, and `source_id` to match. Every update for one
order therefore has the same canonical key. After the first successful update, a
later revision has a different body but must reuse that key and is rejected as
`IDEMPOTENCY_CONFLICT`.

## Requested change

In a future contract version, include `order_revision`, `event_id`, or another
immutable occurrence discriminator in the canonical key for revisioned events.

## Order Lifecycle disposition

Contract v1 remains unchanged. The receiver enforces the canonical formula, exact
replay rules, and sequential revision checks. Under v1, only the first distinct
`order.updated` payload for a stable Medusa order ID can succeed.
