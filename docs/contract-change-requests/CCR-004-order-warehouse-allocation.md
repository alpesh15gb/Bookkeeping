# CCR-004: Warehouse selection for order reservations

- Contract: ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)
- Status: Proposed for a future contract version
- Discovered during: Order Lifecycle implementation

## Issue

Contract v1 requires `order.created` to create reservation movements and validate
inventory references, but `OrderLine` contains no warehouse or fulfillment-location
identifier. Inventory is authoritative per variant and warehouse, so the sender cannot
express the intended reservation allocation.

## Requested change

In a future contract version, add an explicit warehouse allocation per goods line or
define a normative receiver-side allocation policy.

## Order Lifecycle disposition

Contract v1 remains unchanged. The receiver allocates goods reservations
deterministically across mapped inventory levels ordered by `warehouse_id`, using only
available unreserved capacity. Services create no inventory movement.
