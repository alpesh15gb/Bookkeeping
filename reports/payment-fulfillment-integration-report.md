# Payment and Fulfillment Integration Report

## Scope implemented

The Contract v1 `POST /api/integrations/medusa/v1/payments/captured` operation is
implemented in the ApexBooks backend integration layer. It reuses Foundation HMAC
authentication, tenant validation, timestamp validation, replay protection,
idempotency processing, `integration_entity_map`, and `integration_event_log`.

On the first valid capture, one transaction:

1. resolves and locks the existing integration order;
2. validates payment identity, sequence, currency, amount, and cumulative captures;
3. creates and posts the full order invoice;
4. persists invoice and invoice-line mappings;
5. converts order reservations to `SALE_OUT` inventory movements;
6. creates the accounting receipt and invoice allocation;
7. posts invoice and receipt journal entries;
8. updates invoice and order payment status;
9. persists payment mapping, response state, and audit history.

Later contiguous captures reuse the same invoice, create a new receipt, and cannot
exceed the order total. Exact duplicate delivery returns the cached Contract v1
response and does not repeat accounting or inventory effects.

## Persistence

Migration `20260718_0005` adds:

- `integration_payment_state`
- `integration_payment_inventory_movement`
- `integration_invoice_line_map`
- `integration_payment_audit`

## Explicit exclusions

No refund, return, credit-note, warehouse-allocation-change, checkout, storefront, or
SalesOrder-creation behavior was implemented or modified.

`payment.failed`, `fulfillment.created`, and `shipment.completed` are absent from the
frozen Contract v1 and therefore were not exposed with invented payloads. See the
contract-gaps report and CCR-006.
