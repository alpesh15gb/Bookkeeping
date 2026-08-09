import uuid
from datetime import date
from decimal import Decimal

from src.core.config import settings
from src.infrastructure.database.models import Bill, Invoice, Payment, BillPayment


def _invoice_payload(contact_id, product_id, *, quantity=1, rate=1000):
    return {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-DEP-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "line_items": [{
            "product_id": str(product_id),
            "quantity": quantity,
            "rate": rate,
            "discount": 0,
            "hsn_sac": "1234",
            "gst_rate": 18,
        }],
    }


def _bill_payload(contact_id, product_id, *, quantity=1, rate=1000):
    return {
        "contact_id": str(contact_id),
        "bill_number": f"BILL-DEP-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "line_items": [{
            "product_id": str(product_id),
            "quantity": quantity,
            "rate": rate,
            "discount": 0,
            "hsn_sac": "1234",
            "gst_rate": 18,
        }],
    }


def test_reversed_receipt_history_does_not_permanently_block_invoice_delete(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    customer = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    invoice = client.post(
        "/api/v1/invoices",
        json=_invoice_payload(customer.id, product.id),
        headers=combined_headers(),
    )
    assert invoice.status_code == 201, invoice.text
    invoice_data = invoice.json()

    receipt = client.post(
        "/api/v1/payments/receipts",
        json={
            "contact_id": str(customer.id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 100,
            "allocations": [{"invoice_id": invoice_data["id"], "amount": 100}],
        },
        headers=combined_headers(),
    )
    assert receipt.status_code == 201, receipt.text
    receipt_id = receipt.json()["id"]

    blocked = client.delete(
        f"/api/v1/invoices/{invoice_data['id']}", headers=combined_headers()
    )
    assert blocked.status_code == 409, blocked.text
    assert "receipt" in blocked.json()["detail"].lower()

    reversed_receipt = client.delete(
        f"/api/v1/payments/receipts/{receipt_id}", headers=combined_headers()
    )
    assert reversed_receipt.status_code == 204, reversed_receipt.text

    # The PaymentAllocation row intentionally remains as audit history, but its
    # now-cancelled/soft-deleted parent must not block the invoice forever.
    deleted = client.delete(
        f"/api/v1/invoices/{invoice_data['id']}", headers=combined_headers()
    )
    assert deleted.status_code == 204, deleted.text
    old_payment = db_session.query(Payment).filter(Payment.id == uuid.UUID(receipt_id)).one()
    assert old_payment.deleted_at is not None
    assert db_session.query(Invoice).filter(
        Invoice.id == uuid.UUID(invoice_data["id"])
    ).one().deleted_at is not None


def test_active_credit_note_blocks_invoice_until_note_is_reversed(
    client, combined_headers, contact_factory, product_factory,
):
    customer = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    invoice = client.post(
        "/api/v1/invoices",
        json=_invoice_payload(customer.id, product.id, rate=1000),
        headers=combined_headers(),
    )
    assert invoice.status_code == 201, invoice.text
    inv = invoice.json()

    note = client.post(
        "/api/v1/invoices/credit-notes",
        json={
            "invoice_id": inv["id"],
            "issue_date": str(date.today()),
            "reason": "Customer return",
            "line_items": [{
                "product_id": str(product.id),
                "quantity": 1,
                "rate": 100,
                "discount": 0,
                "hsn_sac": "1234",
                "gst_rate": 18,
            }],
        },
        headers=combined_headers(),
    )
    assert note.status_code == 201, note.text

    blocked = client.delete(f"/api/v1/invoices/{inv['id']}", headers=combined_headers())
    assert blocked.status_code == 409, blocked.text
    assert "credit note" in blocked.json()["detail"].lower()

    assert client.delete(
        f"/api/v1/invoices/credit-notes/{note.json()['id']}",
        headers=combined_headers(),
    ).status_code == 204
    assert client.delete(
        f"/api/v1/invoices/{inv['id']}", headers=combined_headers()
    ).status_code == 204


def test_active_eway_bill_blocks_invoice_until_statutory_cancellation(
    client, combined_headers, contact_factory, product_factory,
):
    previous_mock = settings.COMPLIANCE_MOCK_ENABLED
    settings.COMPLIANCE_MOCK_ENABLED = True
    try:
        customer = contact_factory(contact_type="CUSTOMER")
        product = product_factory(
            product_type="GOODS",
            current_stock=Decimal("10"),
            sales_price=Decimal("60000"),
            purchase_price=Decimal("50000"),
        )
        invoice = client.post(
            "/api/v1/invoices",
            json=_invoice_payload(customer.id, product.id, rate=60000),
            headers=combined_headers(),
        )
        assert invoice.status_code == 201, invoice.text
        inv = invoice.json()
        eway = client.post(
            "/api/v1/eway-bills",
            json={
                "invoice_id": inv["id"],
                "supply_type": "OUTWARD",
                "sub_supply_type": "SUPPLY",
                "transporter_name": "Test Transport",
                "trans_distance": 100,
                "trans_mode": "ROAD",
                "vehicle_number": "MH12AB1234",
                "vehicle_type": "REGULAR",
            },
            headers=combined_headers(),
        )
        assert eway.status_code == 201, eway.text

        blocked = client.delete(
            f"/api/v1/invoices/{inv['id']}", headers=combined_headers()
        )
        assert blocked.status_code == 409, blocked.text
        assert "e-way" in blocked.json()["detail"].lower()

        cancelled = client.post(
            f"/api/v1/eway-bills/{eway.json()['id']}/cancel",
            json={"cancel_reason": "2", "cancel_remarks": "Invoice correction"},
            headers=combined_headers(),
        )
        assert cancelled.status_code == 200, cancelled.text
        assert client.delete(
            f"/api/v1/invoices/{inv['id']}", headers=combined_headers()
        ).status_code == 204
    finally:
        settings.COMPLIANCE_MOCK_ENABLED = previous_mock


def test_reversed_vendor_payment_and_purchase_return_dependencies(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    vendor = contact_factory(contact_type="VENDOR")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    bill = client.post(
        "/api/v1/bills",
        json=_bill_payload(vendor.id, product.id),
        headers=combined_headers(),
    )
    assert bill.status_code == 201, bill.text
    bill_data = bill.json()

    payment = client.post(
        "/api/v1/payments/disbursements",
        json={
            "contact_id": str(vendor.id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 100,
            "allocations": [{"bill_id": bill_data["id"], "amount": 100}],
        },
        headers=combined_headers(),
    )
    assert payment.status_code == 201, payment.text
    blocked_payment = client.delete(
        f"/api/v1/bills/{bill_data['id']}", headers=combined_headers()
    )
    assert blocked_payment.status_code == 409, blocked_payment.text
    assert client.delete(
        f"/api/v1/payments/disbursements/{payment.json()['id']}",
        headers=combined_headers(),
    ).status_code == 204

    returned = client.post(
        "/api/v1/returns/purchase",
        json={
            "bill_id": bill_data["id"],
            "contact_id": str(vendor.id),
            "issue_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "bill_line_id": bill_data["lines"][0]["id"],
                "product_id": str(product.id),
                "quantity": 1,
                "rate": 1,
                "hsn_sac": "1234",
                "gst_rate": 0,
            }],
        },
        headers=combined_headers(),
    )
    assert returned.status_code == 201, returned.text
    blocked_return = client.delete(
        f"/api/v1/bills/{bill_data['id']}", headers=combined_headers()
    )
    assert blocked_return.status_code == 409, blocked_return.text
    assert "purchase return" in blocked_return.json()["detail"].lower()

    assert client.delete(
        f"/api/v1/returns/purchase/{returned.json()['id']}",
        headers=combined_headers(),
    ).status_code == 204
    final_delete = client.delete(
        f"/api/v1/bills/{bill_data['id']}", headers=combined_headers()
    )
    assert final_delete.status_code == 204, final_delete.text
    old_payment = db_session.query(BillPayment).filter(
        BillPayment.id == uuid.UUID(payment.json()["id"])
    ).one()
    assert old_payment.deleted_at is not None
    assert db_session.query(Bill).filter(
        Bill.id == uuid.UUID(bill_data["id"])
    ).one().deleted_at is not None
