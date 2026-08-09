import uuid
from datetime import date
from decimal import Decimal

from src.infrastructure.database.models import Invoice, JournalEntry


def _payload(contact_id, product_id, **overrides):
    payload = {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-EDGE-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "shipping_charges": 25,
        "line_items": [{
            "product_id": str(product_id),
            "quantity": 1,
            "rate": 100,
            "discount": 0,
            "hsn_sac": "9983",
            "gst_rate": 18,
        }],
    }
    payload.update(overrides)
    return payload


def _account_net(entries):
    net = {}
    for entry in entries:
        for line in entry.lines:
            sign = Decimal("1") if line.direction == "DEBIT" else Decimal("-1")
            net[line.account_id] = net.get(line.account_id, Decimal("0")) + sign * line.amount
    return net


def test_delete_reverses_invoice_shipping_exactly(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"), gst_rate=Decimal("18"))
    created = client.post(
        "/api/v1/invoices",
        json=_payload(contact.id, product.id),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    invoice_id = uuid.UUID(created.json()["id"])

    original = db_session.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant.id,
        JournalEntry.source_type == "INVOICE",
        JournalEntry.source_id == invoice_id,
    ).one()
    assert any("Shipping" in (line.narration or "") for line in original.lines)

    deleted = client.delete(
        f"/api/v1/invoices/{invoice_id}", headers=combined_headers()
    )
    assert deleted.status_code == 204, deleted.text
    db_session.expire_all()

    original = db_session.query(JournalEntry).filter(JournalEntry.id == original.id).one()
    reversal = db_session.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant.id,
        JournalEntry.source_type == "INVOICE_REVERSAL",
        JournalEntry.source_id == invoice_id,
    ).one()
    assert original.reversal_transaction_id == reversal.id
    assert reversal.reverses_transaction_id == original.id
    assert all(amount == 0 for amount in _account_net([original, reversal]).values())

    document = db_session.query(Invoice).filter(Invoice.id == invoice_id).one()
    assert document.deleted_at is not None


def test_delete_reverses_rcm_invoice_with_shipping_exactly(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"), gst_rate=Decimal("18"))
    created = client.post(
        "/api/v1/invoices",
        json=_payload(contact.id, product.id, is_rcm=True),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    assert Decimal(created.json()["cgst_amount"]) == 0
    assert Decimal(created.json()["sgst_amount"]) == 0
    assert Decimal(created.json()["igst_amount"]) == 0
    invoice_id = uuid.UUID(created.json()["id"])

    original = db_session.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant.id,
        JournalEntry.source_type == "INVOICE",
        JournalEntry.source_id == invoice_id,
    ).one()
    assert any("RCM" in (line.narration or "") for line in original.lines)

    deleted = client.delete(
        f"/api/v1/invoices/{invoice_id}", headers=combined_headers()
    )
    assert deleted.status_code == 204, deleted.text
    db_session.expire_all()

    original = db_session.query(JournalEntry).filter(JournalEntry.id == original.id).one()
    reversal = db_session.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant.id,
        JournalEntry.source_type == "INVOICE_REVERSAL",
        JournalEntry.source_id == invoice_id,
    ).one()
    assert all(amount == 0 for amount in _account_net([original, reversal]).values())
