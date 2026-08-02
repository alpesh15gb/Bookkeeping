"""
Regression + contract tests for the invoice detail and draft-create endpoints.

Root cause this suite guards against:
  GET /api/v1/invoices/{id} returned HTTP 500 (and the Flutter app masked it as
  "The server is unavailable") whenever the invoice's customer was missing
  optional master data (`billing_address` / `state_code` are NULLable in the
  DB but were required by `ContactResponse`).
"""
import uuid
from datetime import date
from decimal import Decimal

from src.infrastructure.database.models import Invoice, InvoiceLine
from src.schemas.document import InvoiceResponse, PaginatedInvoiceResponse


def _build_invoice(db, tenant_id, contact, product, status="DRAFT", **kw):
    inv = Invoice(
        id=uuid.uuid4(),
        tenant_id=tenant_id,
        contact_id=contact.id,
        invoice_number=f"INV-TEST-{uuid.uuid4().hex[:8].upper()}",
        issue_date=date.today(),
        due_date=date.today(),
        status=status,
        subtotal=Decimal("5000.0000"),
        discount_total=Decimal("0.0000"),
        cgst_amount=Decimal("450.0000"),
        sgst_amount=Decimal("450.0000"),
        igst_amount=Decimal("0.0000"),
        utgst_amount=Decimal("0.0000"),
        cess_amount=Decimal("0.0000"),
        round_off=Decimal("0.0000"),
        shipping_charges=Decimal("0.0000"),
        total=Decimal("5900.0000"),
        amount_paid=Decimal("0.0000"),
        pos_state_code=contact.state_code or "27",
        e_invoice_status="PENDING",
        **kw,
    )
    db.add(inv)
    db.flush()
    db.add(
        InvoiceLine(
            id=uuid.uuid4(),
            invoice_id=inv.id,
            product_id=product.id,
            description=product.name,
            quantity=Decimal("1"),
            rate=Decimal("5000.0000"),
            discount=Decimal("0.0000"),
            subtotal=Decimal("5000.0000"),
            hsn_sac=product.hsn_sac,
            gst_rate=Decimal("18.00"),
            cgst_rate=Decimal("9.00"),
            cgst_amount=Decimal("450.0000"),
            sgst_rate=Decimal("9.00"),
            sgst_amount=Decimal("450.0000"),
            igst_rate=Decimal("0.00"),
            igst_amount=Decimal("0.0000"),
            utgst_rate=Decimal("0.00"),
            utgst_amount=Decimal("0.0000"),
            cess_rate=Decimal("0.00"),
            cess_amount=Decimal("0.0000"),
            total=Decimal("5900.0000"),
        )
    )
    db.commit()
    return inv


def test_invoice_detail_success(client, combined_headers, contact_factory, product_factory, db_session):
    """A fully-populated invoice returns 200 with the expected schema fields."""
    contact = contact_factory()
    product = product_factory()
    inv = _build_invoice(db_session, contact.tenant_id, contact, product)

    res = client.get(f"/api/v1/invoices/{inv.id}", headers=combined_headers())
    assert res.status_code == 200
    body = res.json()
    assert body["id"] == str(inv.id)
    assert body["status"] == "DRAFT"
    assert body["subtotal"] == "5000.0000"
    assert body["total"] == "5900.0000"
    assert body["contact"]["name"] == contact.name
    assert body["lines"][0]["product_name"] == product.name
    # response_model contract is valid
    InvoiceResponse.model_validate(body)


def test_invoice_detail_nullable_contact_does_not_500(
    client, combined_headers, tenant, product_factory, db_session,
):
    """Regression: a customer with NULL billing_address/state_code must not 500."""
    from src.infrastructure.database.models import Contact

    contact = Contact(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Minimal Customer",
        contact_type="CUSTOMER",
        registration_type="REGULAR",
        billing_address=None,
        state_code=None,
        is_active=True,
    )
    db_session.add(contact)
    db_session.commit()

    product = product_factory()
    inv = _build_invoice(db_session, tenant.id, contact, product)

    res = client.get(f"/api/v1/invoices/{inv.id}", headers=combined_headers())
    assert res.status_code == 200
    body = res.json()
    assert body["contact"]["name"] == "Minimal Customer"
    assert body["contact"]["billing_address"] is None
    assert body["contact"]["state_code"] is None


def test_invoice_detail_nullable_optional_fields(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    """Empty e-invoice fields, notes, terms, reference serialize cleanly."""
    contact = contact_factory()
    product = product_factory()
    inv = _build_invoice(
        db_session,
        contact.tenant_id,
        contact,
        product,
        irn=None,
        qr_code=None,
        notes=None,
        terms_and_conditions=None,
        reference_number=None,
    )

    res = client.get(f"/api/v1/invoices/{inv.id}", headers=combined_headers())
    assert res.status_code == 200
    body = res.json()
    assert body["irn"] is None
    assert body["qr_code"] is None
    assert body["notes"] is None
    assert body["terms_and_conditions"] is None
    assert body["reference_number"] is None
    assert body["e_invoice_status"] == "PENDING"
    assert body["lines"][0]["product_name"] is not None


def test_invoice_detail_404(client, combined_headers, tenant):
    """Unknown invoice id returns 404, not a server error."""
    res = client.get(
        f"/api/v1/invoices/{uuid.uuid4()}",
        headers=combined_headers(),
    )
    assert res.status_code == 404
    assert "not found" in res.json()["detail"].lower()


def test_invoice_detail_401(client, tenant):
    """Missing auth token returns 401."""
    res = client.get(
        f"/api/v1/invoices/{uuid.uuid4()}",
        headers={"X-Tenant-ID": str(tenant.id)},
    )
    assert res.status_code == 401


def test_invoice_detail_tenant_isolation(
    client, combined_headers, contact_factory, product_factory, db_session, tenant,
):
    """An invoice in tenant A is not visible to a request scoped to tenant B."""
    from src.infrastructure.database.models import Tenant

    contact = contact_factory()
    product = product_factory()
    inv = _build_invoice(db_session, tenant.id, contact, product)

    other_tenant = Tenant(
        id=uuid.uuid4(),
        legal_name="Other Co",
        trade_name="Other Co",
        gstin="29ABCDE1234F1Z5",
        pan="ABCDE1234F",
        financial_year_start=date(2026, 4, 1),
        tax_mode="GST_REGULAR",
    )
    db_session.add(other_tenant)
    db_session.commit()

    headers = dict(combined_headers())
    headers["X-Tenant-ID"] = str(other_tenant.id)
    res = client.get(f"/api/v1/invoices/{inv.id}", headers=headers)
    # 403 = caller not a member of the other tenant; 404 = not found. Either way
    # the invoice data must never leak across tenants.
    assert res.status_code in (403, 404)
    if res.status_code == 404:
        assert "not found" in res.json()["detail"].lower()


def test_invoice_list_schema(client, combined_headers, contact_factory, product_factory, db_session):
    """Invoice list response matches the PaginatedInvoiceResponse contract."""
    contact = contact_factory()
    product = product_factory()
    _build_invoice(db_session, contact.tenant_id, contact, product)

    res = client.get("/api/v1/invoices", headers=combined_headers())
    assert res.status_code == 200
    body = res.json()
    PaginatedInvoiceResponse.model_validate(body)
    assert body["total"] == 1
    item = body["items"][0]
    assert item["id"] is not None
    assert item["invoice_number"] is not None
    assert item["contact_name"] == contact.name


def test_invoice_create_draft_stays_draft(
    client, combined_headers, contact_factory, product_factory, tenant, db_session,
):
    """POST /invoices with post_on_create=false creates a DRAFT, no ledger/stock effects."""
    from src.infrastructure.database.models import JournalEntry, StockLedger

    # GST_REGULAR so tax is computed (matches a real configured tenant).
    tenant.tax_mode = "GST_REGULAR"
    db_session.commit()

    contact = contact_factory()
    product = product_factory()

    payload = {
        "contact_id": str(contact.id),
        "issue_date": "2026-08-03",
        "due_date": "2026-08-03",
        "pos_state_code": "27",
        "is_gst_inclusive": False,
        "is_rcm": False,
        "supply_type": "DOMESTIC",
        "post_on_create": False,
        "line_items": [
            {
                "product_id": str(product.id),
                "quantity": "1",
                "rate": "5000",
                "discount": "0",
                "hsn_sac": product.hsn_sac,
                "gst_rate": "18",
            }
        ],
    }
    res = client.post("/api/v1/invoices", headers=combined_headers(), json=payload)
    assert res.status_code == 201
    body = res.json()
    assert body["status"] == "DRAFT"
    assert body["subtotal"] == "5000.0000"
    assert body["total"] == "5900.0000"
    assert body["invoice_number"]  # auto-generated

    # No auto-posting for a draft: no journal entry, no stock movement.
    journals = db_session.query(JournalEntry).all()
    assert not journals, "draft save must not create journal entries"
    moves = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "INVOICE"
    ).all()
    assert not moves, "draft save must not move stock"


def test_invoice_update_does_not_duplicate(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    """Editing an existing draft updates the same row (no duplicate)."""
    contact = contact_factory()
    product = product_factory()
    inv = _build_invoice(db_session, contact.tenant_id, contact, product)

    payload = {
        "issue_date": "2026-08-04",
        "due_date": "2026-08-04",
        "line_items": [
            {
                "id": str(inv.lines[0].id),
                "product_id": str(product.id),
                "quantity": "2",
                "rate": "5000",
                "discount": "0",
                "hsn_sac": product.hsn_sac,
                "gst_rate": "18",
            }
        ],
    }
    res = client.put(f"/api/v1/invoices/{inv.id}", headers=combined_headers(), json=payload)
    assert res.status_code == 200
    assert res.json()["issue_date"] == "2026-08-04"

    # Still exactly one invoice in the tenant.
    res2 = client.get("/api/v1/invoices", headers=combined_headers())
    assert res2.json()["total"] == 1
