# CCR-003: Cancellation and immutable-order workflow expectations

- Contract: ApexBooks Integration Contract v1 (`integration-contract-v1`, `e31e965`)
- Status: Proposed for a future contract version
- Discovered during: Order Lifecycle implementation

## Issue

The implementation request asks the order-cancellation endpoint to create a credit-note
workflow for invoiced orders and mark a refund workflow pending for paid orders. It also
asks immutable financial changes submitted to `order.updated` to create an adjustment
workflow.

Contract v1 requires different behavior:

- Paid or invoiced cancellation makes no change and returns HTTP 409
  `REFUND_REQUIRED`. Cancellation occurs only after a later `payment.refunded` event.
- An update after invoice or capture returns HTTP 409 `ORDER_IMMUTABLE`.
- The Contract v1 order response has no adjustment, credit-note-workflow, or
  refund-workflow field.

## Requested change

If workflow creation from order endpoints is desired, define the workflow resources,
states, idempotency identity, accounting effects, and response schemas in a future
contract version.

## Order Lifecycle disposition

Contract v1 remains unchanged. This implementation cancels only unpaid, uninvoiced
DRAFT orders. Invoiced or paid cancellation returns `REFUND_REQUIRED`, and immutable
updates return `ORDER_IMMUTABLE`, with no workflow or accounting document created.
