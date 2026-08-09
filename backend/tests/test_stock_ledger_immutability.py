"""Stock-ledger append-only protection under the direct posting contract."""
import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from src.infrastructure.database.models import Invoice, JournalEntry, StockLedger, Product


def _goods_invoice_payload(contact_id, product_id, *, quantity=1, rate=100.0):
    return {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-SL-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "supply_type": "DOMESTIC",
        "line_items": [{
            "product_id": str(product_id),
            "quantity": quantity,
            "rate": rate,
            "discount": 0.0,
            "hsn_sac": "1234",
            "gst_rate": 18.0,
        }],
    }


def _posted_goods_invoice(client, combined_headers, contact, product, *, quantity=1):
    res = client.post(
        "/api/v1/invoices",
        json=_goods_invoice_payload(contact.id, product.id, quantity=quantity),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    assert res.json()["status"] == "POSTED"
    return res.json()


def _invoice_stock_moves(db_session, tenant_id, invoice_id):
    return db_session.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "INVOICE",
        StockLedger.reference_id == uuid.UUID(str(invoice_id)),
    ).all()


def test_stock_row_cannot_be_updated(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    move.quantity = Decimal("-99")
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    db_session.expire_all()
    assert _invoice_stock_moves(db_session, tenant.id, inv["id"])[0].quantity == Decimal("-1")


def test_stock_row_cannot_be_deleted(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    move_id = move.id
    db_session.delete(move)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    assert db_session.query(StockLedger).filter(StockLedger.id == move_id).one()


def test_only_reversal_linkage_meta_is_mutable_on_stock_row(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    move.reversal_movement_id = uuid.uuid4()
    move.reversed_by = uuid.uuid4()
    move.quantity = Decimal("-5")
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()


def test_invoice_delete_preserves_original_and_creates_linked_reversal(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    stock_before = db_session.query(Product).filter(Product.id == product.id).one().current_stock
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    original = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    assert original.quantity == Decimal("-1")

    deleted = client.delete(f"/api/v1/invoices/{inv['id']}", headers=combined_headers())
    assert deleted.status_code == 204, deleted.text

    db_session.expire_all()
    original = db_session.query(StockLedger).filter(StockLedger.id == original.id).one()
    assert original.quantity == Decimal("-1")
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == uuid.UUID(inv["id"]),
    ).one()
    assert reversal.quantity == Decimal("1")
    assert reversal.reverses_movement_id == original.id
    assert original.reversal_movement_id == reversal.id
    assert original.reversed_by == admin_user.id
    assert original.reversed_at is not None
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == stock_before


def test_stock_balance_correct_after_delete(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product, quantity=3)
    deleted = client.delete(f"/api/v1/invoices/{inv['id']}", headers=combined_headers())
    assert deleted.status_code == 204
    db_session.expire_all()
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == uuid.UUID(inv["id"]),
    ).one()
    stock_now = db_session.query(Product).filter(Product.id == product.id).one().current_stock
    assert reversal.quantity == Decimal("3")
    assert reversal.balance_quantity == stock_now
    assert stock_now == Decimal("10")


def test_posted_invoice_edit_keeps_original_stock_and_adds_reversal_replacement(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    original_id = uuid.UUID(inv["id"])
    move_before = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    original_move_id = move_before.id

    edit = client.put(
        f"/api/v1/invoices/{original_id}",
        json={
            "line_items": _goods_invoice_payload(contact.id, product.id, rate=999)["line_items"]
        },
        headers=combined_headers(),
    )
    assert edit.status_code == 200, edit.text
    replacement_id = uuid.UUID(edit.json()["id"])
    assert replacement_id != original_id

    db_session.expire_all()
    original_move = db_session.query(StockLedger).filter(StockLedger.id == original_move_id).one()
    assert original_move.quantity == Decimal("-1")
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == original_id,
    ).one()
    replacement_move = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE",
        StockLedger.reference_id == replacement_id,
    ).one()
    assert reversal.quantity == Decimal("1")
    assert replacement_move.quantity == Decimal("-1")
    assert original_move.reversal_movement_id == reversal.id
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == Decimal("9")


def test_stock_movement_attribution_stamped_from_server_context(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    assert move.created_by == admin_user.id
    assert move.source_channel == "API"

    deleted = client.delete(f"/api/v1/invoices/{inv['id']}", headers=combined_headers())
    assert deleted.status_code == 204
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == uuid.UUID(inv["id"]),
    ).one()
    assert reversal.created_by == admin_user.id


def test_sales_return_preserves_prior_movements_and_is_protected(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    inv_db = db_session.query(Invoice).filter(Invoice.id == uuid.UUID(inv["id"])).one()
    payload = {
        "invoice_id": inv["id"],
        "contact_id": str(contact.id),
        "issue_date": str(date.today()),
        "pos_state_code": "27",
        "line_items": [{
            "invoice_line_id": str(inv_db.lines[0].id),
            "product_id": str(product.id),
            "quantity": "1",
            "rate": "100",
            "hsn_sac": "1234",
            "gst_rate": "18",
        }],
    }
    ret = client.post("/api/v1/returns/sales", json=payload, headers=combined_headers())
    assert ret.status_code == 201, ret.text
    db_session.expire_all()
    assert _invoice_stock_moves(db_session, tenant.id, inv["id"])[0].quantity == Decimal("-1")
    return_move = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "SALES_RETURN"
    ).one()
    assert return_move.quantity == Decimal("1")
    db_session.delete(return_move)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    assert db_session.query(StockLedger).filter(StockLedger.id == return_move.id).one()


def test_failed_posting_leaves_no_stock_movement(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("1"))
    res = client.post(
        "/api/v1/invoices",
        json=_goods_invoice_payload(contact.id, product.id, quantity=5),
        headers=combined_headers(),
    )
    assert res.status_code == 422
    db_session.expire_all()
    assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 0
    assert db_session.query(StockLedger).filter(StockLedger.tenant_id == tenant.id).count() == 0
    assert db_session.query(JournalEntry).filter(JournalEntry.tenant_id == tenant.id).count() == 0
