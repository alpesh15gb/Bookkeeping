# Payment and Fulfillment Contract Gaps

Contract reviewed: ApexBooks Integration Contract v1, tag
`integration-contract-v1`, commit `e31e965`.

## Undefined requested operations

The frozen contract has no definition for:

- `payment.failed`
- `fulfillment.created`
- `shipment.completed`

Without paths and JSON Schemas, these events cannot satisfy the requirement to
validate incoming Contract v1 payloads. Their entity mappings, duplicates, replay
identity, state transitions, and error envelopes are likewise undefined.

## Fulfillment inventory ambiguity

Contract v1 currently converts reservations to stock-out movements on the first
`payment.captured` event. A future fulfillment lifecycle must specify whether that
conversion moves to fulfillment creation or shipment completion, and how existing
captures are reconciled. Fulfillment line warehouse allocation is also undefined;
Contract v1 order lines contain no warehouse identifier (see CCR-004).

## Future contract changes

CCR-006 requests complete payment-failure and fulfillment/shipment operations. A
future version should define paths, schemas, counterpart IDs, quantities, warehouse
references, carrier/tracking fields, transition rules, replay behavior, and ownership
of inventory conversion.

Refunds, returns, credit notes, and warehouse-allocation changes remain outside this
implementation and require their existing Contract v1 operations or a future approved
contract change as appropriate.
