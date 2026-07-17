# CCR-006: Payment failure and fulfillment lifecycle operations

- Contract: ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)
- Status: Proposed for a future contract version
- Discovered during: Payment and Fulfillment Lifecycle implementation

## Issue

Contract v1 defines `payment.captured`, but does not define `payment.failed`,
`fulfillment.created`, or `shipment.completed`. There are no paths, request schemas,
response schemas, event identity rules, status transitions, mapping rules, inventory
effects, or replay semantics for those three events.

Implementing them under `/api/integrations/medusa/v1` would create an undocumented
extension that cannot be Contract v1 JSON Schema validated.

## Requested change

In a future contract version, define:

- canonical endpoints and event schemas;
- stable event and counterpart identifiers;
- allowed order/payment/fulfillment state transitions;
- whether failed payments create accounting records;
- fulfillment line quantities, warehouse references, carrier and tracking data;
- when reservation-to-sale inventory conversion occurs;
- success and error response envelopes;
- duplicate and out-of-order delivery behavior.

## Current disposition

Contract v1 remains unchanged. Only `payment.captured` is exposed. The undefined
payment-failure and fulfillment/shipment operations are not implemented.
