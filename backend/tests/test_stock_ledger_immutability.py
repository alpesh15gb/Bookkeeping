"""
Phase 1 Gate 1 — Stock-ledger immutability tests.

Structural append-only protection for stock movements, equivalent in
principle to the journal guards:

* existing stock rows cannot be UPDATEd (except reversal-linkage meta)
* existing stock rows cannot be DELETEd
* corrections create reversal movements; the original is never removed
* invoice cancellation links original -> reversal at movement level
* a posted-document edit cannot change historical stock rows
* stock balance remains correct after reversal
* attribution (created_by / source_channel) is stamped from server context
"""
import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from src.infrastructure.database.models import (
    Invoice, InvoiceLine, JournalEntry, StockLedger, Product,
)


def _goods_invoice_payload(contact_id, product_id, *, quantity=1, rate=100.0):
    return {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-SL-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "supply_type": "DOMESTIC",
        "post_on_create": True,
        "line_items": [
            {
                "product_id": str(product_id),
                "quantity": quantity,
                "rate": rate,
                "discount": 0.0,
                "hsn_sac": "1234",
                "gst_rate": 18.0,
            }
        ],
    }


def _posted_goods_invoice(client, combined_headers, contact, product, *, quantity=1):
    res = client.post(
        "/api/v1/invoices",
        json=_goods_invoice_payload(contact.id, product.id, quantity=quantity),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    return res.json()


def _invoice_stock_moves(db_session, tenant_id, invoice_id):
    return db_session.query(StockLedger).filter(
        StockLedger.tenant_id == tenant_id,
        StockLedger.reference_type == "INVOICE",
        StockLedger.reference_id == uuid.UUID(invoice_id),
    ).all()


# ---------------------------------------------------------------------------
# 1. Stock rows are structurally immutable
# ---------------------------------------------------------------------------

def test_stock_row_cannot_be_updated(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)

    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    move.quantity = Decimal("-99.0000")
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    db_session.expire_all()
    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    assert move.quantity == Decimal("-1.0000")


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

    assert db_session.query(StockLedger).filter(StockLedger.id == move_id).first() is not None


def test_only_reversal_linkage_meta_is_mutable_on_stock_row(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """The single escape-hatch check: quantity/balance/reference are never
    mutable, even in combination with linkage writes."""
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)

    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    move.reversal_movement_id = uuid.uuid4()
    move.reversed_by = uuid.uuid4()
    move.quantity = Decimal("-5.0000")  # financial field — must reject the batch
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()


# ---------------------------------------------------------------------------
# 2. Invoice cancellation: original intact + linked reversal + correct balance
# ---------------------------------------------------------------------------

def test_invoice_cancel_preserves_original_and_creates_linked_reversal(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    stock_before = db_session.query(Product).filter(Product.id == product.id).one().current_stock
    inv = _posted_goods_invoice(client, combined_headers, contact, product)
    assert Decimal(inv["total"]) > 0

    originals = _invoice_stock_moves(db_session, tenant.id, inv["id"])
    assert len(originals) == 1
    original = originals[0]
    assert original.quantity == Decimal("-1.0000")

    cancel = client.post(f"/api/v1/invoices/{inv['id']}/cancel", headers=combined_headers())
    assert cancel.status_code == 200, cancel.text

    db_session.expire_all()
    # Original movement untouched.
    original = db_session.query(StockLedger).filter(StockLedger.id == original.id).one()
    assert original.quantity == Decimal("-1.0000")

    # Reversal movement created, linked both ways.
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == uuid.UUID(inv["id"]),
    ).one()
    assert reversal.quantity == Decimal("1.0000")
    assert reversal.reverses_movement_id == original.id
    assert original.reversal_movement_id == reversal.id
    assert original.reversed_by == admin_user.id
    assert original.reversed_at is not None

    # Stock balance restored to the pre-invoice level.
    db_session.expire_all()
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == stock_before


def test_stock_balance_correct_after_cancel(client, combined_headers, tenant, contact_factory, product_factory, db_session):
    """Running balance on the reversal row reconciles to the restored stock."""
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product, quantity=3)

    cancel = client.post(f"/api/v1/invoices/{inv['id']}/cancel", headers=combined_headers())
    assert cancel.status_code == 200, cancel.text

    db_session.expire_all()
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == uuid.UUID(inv["id"]),
    ).one()
    stock_now = db_session.query(Product).filter(Product.id == product.id).one().current_stock
    assert reversal.quantity == Decimal("3.0000")
    assert reversal.balance_quantity == stock_now
    assert stock_now == Decimal("10")


# ---------------------------------------------------------------------------
# 3. Posted-document edits cannot change historical stock rows
# ---------------------------------------------------------------------------

def test_posted_invoice_edit_cannot_change_stock_rows(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)

    moves_before = _invoice_stock_moves(db_session, tenant.id, inv["id"])
    assert len(moves_before) == 1

    edit = _goods_invoice_payload(contact.id, product.id, rate=999.0)
    edit["invoice_number"] = inv["invoice_number"]
    res = client.put(f"/api/v1/invoices/{inv['id']}", json=edit, headers=combined_headers())
    assert res.status_code == 400

    db_session.expire_all()
    moves_after = _invoice_stock_moves(db_session, tenant.id, inv["id"])
    assert len(moves_after) == 1
    assert moves_after[0].quantity == moves_before[0].quantity
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == Decimal("9")


# ---------------------------------------------------------------------------
# 4. Attribution is stamped from server context
# ---------------------------------------------------------------------------

def test_stock_movement_attribution_stamped_from_server_context(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)

    move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    assert move.created_by == admin_user.id
    assert move.source_channel == "API"

    # A client-supplied actor is never trusted: stamping overwrites nothing
    # because the value comes from the session, not the payload.
    cancel = client.post(f"/api/v1/invoices/{inv['id']}/cancel", headers=combined_headers())
    assert cancel.status_code == 200, cancel.text
    reversal = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE_REVERSAL",
        StockLedger.reference_id == uuid.UUID(inv["id"]),
    ).one()
    assert reversal.created_by == admin_user.id


# ---------------------------------------------------------------------------
# 5. Returns preserve prior movements (append-only + reversal rows)
# ---------------------------------------------------------------------------

def test_sales_return_preserves_prior_movements_and_is_protected(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("10"))
    inv = _posted_goods_invoice(client, combined_headers, contact, product)

    inv_db = db_session.query(Invoice).filter(Invoice.id == uuid.UUID(inv["id"])).one()
    invoice_line_id = str(inv_db.lines[0].id)
    payload = {
        "invoice_id": inv["id"],
        "contact_id": str(contact.id),
        "issue_date": str(date.today()),
        "pos_state_code": "27",
        "line_items": [
            {
                "invoice_line_id": invoice_line_id,
                "product_id": str(product.id),
                "quantity": "1",
                "rate": "100.0",
                "hsn_sac": "1234",
                "gst_rate": "18.0",
            }
        ],
    }
    ret = client.post("/api/v1/returns/sales", json=payload, headers=combined_headers())
    assert ret.status_code == 201, ret.text

    db_session.expire_all()
    # Prior INVOICE movement untouched.
    invoice_move = _invoice_stock_moves(db_session, tenant.id, inv["id"])[0]
    assert invoice_move.quantity == Decimal("-1.0000")
    # Return created a restock movement (append-only).
    return_move = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "SALES_RETURN",
    ).one()
    assert return_move.quantity == Decimal("1.0000")

    # The return movement is itself structurally immutable.
    db_session.delete(return_move)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    assert db_session.query(StockLedger).filter(StockLedger.id == return_move.id).first() is not None


# ---------------------------------------------------------------------------
# 6. Atomicity: stock effect lives in the same transaction as the document
# ---------------------------------------------------------------------------

def test_failed_posting_leaves_no_stock_movement(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """Insufficient stock must roll back the whole operation — including any
    stock movement — leaving zero history behind."""
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
