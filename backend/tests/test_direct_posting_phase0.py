"""Direct-posting accounting contract tests.

Create posts immediately unless post_on_create is false. Edit of a posted
document creates a linked reversal + replacement; draft edits stay in place.
Delete reverses posted documents and hides the business record.
"""
import json
import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from src.main import app
from src.infrastructure.database.models import (
    Bill,
    Expense,
    ExpenseCategory,
    Invoice,
    JournalEntry,
    JournalLine,
    Product,
    StockLedger,
)
from src.domains.accounting.services import (
    AccountResolver,
    JournalEntryDraft,
    JournalLineDraft,
    LedgerValidationError,
)


def _resolve_accounts(db_session, tenant_id):
    resolver = AccountResolver(db_session, tenant_id)
    ids = {
        "cash": resolver.resolve("assets.cash"),
        "sales": resolver.resolve("sales_revenue"),
    }
    db_session.commit()
    return ids


def _journal_payload(accounts, debit=100.00, credit=100.00):
    return {
        "entry_date": str(date.today()),
        "reference_number": f"JE-{uuid.uuid4().hex[:8].upper()}",
        "description": "Direct contract test journal",
        "lines": [
            {"account_id": str(accounts["cash"]), "amount": debit, "direction": "DEBIT"},
            {"account_id": str(accounts["sales"]), "amount": credit, "direction": "CREDIT"},
        ],
    }


def _invoice_payload(contact_id, product_id, *, quantity=1, rate=100.0):
    return {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-DP-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "supply_type": "DOMESTIC",
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


def _bill_payload(contact_id, product_id, *, quantity=1, rate=100.0):
    return {
        "contact_id": str(contact_id),
        "bill_number": f"BILL-DP-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
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


def _expense_category(db_session, tenant):
    linked = AccountResolver(db_session, tenant.id).resolve("expense.misc")
    category = ExpenseCategory(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="Direct Contract Expense",
        linked_account_id=linked,
    )
    db_session.add(category)
    db_session.commit()
    return category


# ---------------------------------------------------------------------------
# Public API shape
# ---------------------------------------------------------------------------

def test_public_contract_keeps_draft_finalize_and_cancel_routes():
    # FastAPI 0.141 exposes included routers through lazy `_IncludedRouter`
    # placeholders in `app.routes`, so reflecting over `app.routes` cannot see
    # the registered paths (the app itself serves them fine). The OpenAPI
    # schema materializes the full route table, so assert against it — the
    # same source the sibling schema tests use below.
    schema = app.openapi()
    paths = schema.get("paths", {})
    required = {
        ("/api/v1/invoices/{id}/finalize", "POST"),
        ("/api/v1/invoices/{id}/cancel", "POST"),
        ("/api/v1/bills/{id}/finalize", "POST"),
        ("/api/v1/bills/{id}/cancel", "POST"),
        ("/api/v1/expenses/{id}/post", "POST"),
        ("/api/v1/expenses/{id}/cancel", "POST"),
        ("/api/v1/accounting/journals/{id}/reverse", "POST"),
        ("/api/v1/payments/receipts/{id}/cancel", "POST"),
        ("/api/v1/payments/disbursements/{id}/cancel", "POST"),
        ("/api/v1/returns/sales/{id}/cancel", "POST"),
        ("/api/v1/returns/purchase/{id}/cancel", "POST"),
    }
    missing = {f"{method} {path}" for path, method in required if method.lower() not in paths.get(path, {})}
    assert not missing, missing


def test_public_create_schemas_expose_optional_post_on_create_and_bill_number():
    schema = app.openapi()
    invoice_ref = schema["paths"]["/api/v1/invoices"]["post"]["requestBody"]["content"]["application/json"]["schema"]["$ref"]
    invoice_name = invoice_ref.rsplit("/", 1)[-1]
    invoice_schema = schema["components"]["schemas"][invoice_name]
    assert "post_on_create" in invoice_schema.get("properties", {})

    bill_ref = schema["paths"]["/api/v1/bills"]["post"]["requestBody"]["content"]["application/json"]["schema"]["$ref"]
    bill_name = bill_ref.rsplit("/", 1)[-1]
    bill_schema = schema["components"]["schemas"][bill_name]
    assert "post_on_create" in bill_schema.get("properties", {})
    assert "bill_number" not in bill_schema.get("required", [])


# ---------------------------------------------------------------------------
# Save always posts
# ---------------------------------------------------------------------------

def test_invoice_save_posts_immediately(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    response = client.post(
        "/api/v1/invoices",
        json=_invoice_payload(contact.id, product.id),
        headers=combined_headers(),
    )
    assert response.status_code == 201, response.text
    invoice_id = uuid.UUID(response.json()["id"])
    assert response.json()["status"] == "POSTED"
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE",
        JournalEntry.source_id == invoice_id,
    ).count() == 1


def test_post_on_create_false_creates_a_draft(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    payload = _invoice_payload(contact.id, product.id)
    payload["post_on_create"] = False
    response = client.post("/api/v1/invoices", json=payload, headers=combined_headers())
    assert response.status_code == 201, response.text
    assert response.json()["status"] == "DRAFT"
    invoice_id = uuid.UUID(response.json()["id"])
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE",
        JournalEntry.source_id == invoice_id,
    ).count() == 0


def test_bill_save_posts_immediately_and_number_can_be_generated(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    vendor = contact_factory(contact_type="VENDOR")
    product = product_factory(product_type="SERVICE")
    payload = _bill_payload(vendor.id, product.id)
    payload.pop("bill_number")
    response = client.post("/api/v1/bills", json=payload, headers=combined_headers())
    assert response.status_code == 201, response.text
    assert response.json()["status"] == "POSTED"
    assert response.json()["bill_number"]
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "BILL",
        JournalEntry.source_id == uuid.UUID(response.json()["id"]),
    ).count() == 1


def test_expense_save_posts_immediately(client, combined_headers, tenant, db_session):
    category = _expense_category(db_session, tenant)
    response = client.post(
        "/api/v1/expenses",
        json={
            "expense_category_id": str(category.id),
            "expense_date": str(date.today()),
            "amount": 1000.0,
            "description": "Direct expense",
            "vendor_name": "Vendor",
            "place_of_supply_state_code": "27",
        },
        headers=combined_headers(),
    )
    assert response.status_code == 201, response.text
    assert response.json()["status"] == "POSTED"
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "EXPENSE",
        JournalEntry.source_id == uuid.UUID(response.json()["id"]),
    ).count() == 1


# ---------------------------------------------------------------------------
# Edit = reversal + replacement; original history survives
# ---------------------------------------------------------------------------

def test_invoice_edit_reverses_and_replaces(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    created = client.post(
        "/api/v1/invoices",
        json=_invoice_payload(contact.id, product.id, rate=100),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    original_id = uuid.UUID(created.json()["id"])

    edited = client.put(
        f"/api/v1/invoices/{original_id}",
        json={"line_items": _invoice_payload(contact.id, product.id, rate=250)["line_items"]},
        headers=combined_headers(),
    )
    assert edited.status_code == 200, edited.text
    replacement_id = uuid.UUID(edited.json()["id"])
    assert replacement_id != original_id
    assert Decimal(edited.json()["total"]) > Decimal(created.json()["total"])

    db_session.expire_all()
    original = db_session.query(Invoice).filter(Invoice.id == original_id).one()
    replacement = db_session.query(Invoice).filter(Invoice.id == replacement_id).one()
    assert original.deleted_at is not None
    assert original.replaced_by_id == replacement_id
    assert replacement.replaces_id == original_id

    original_je = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE", JournalEntry.source_id == original_id
    ).one()
    reversal = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE_REVERSAL", JournalEntry.source_id == original_id
    ).one()
    replacement_je = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE", JournalEntry.source_id == replacement_id
    ).one()
    assert original_je.reversal_transaction_id == reversal.id
    assert reversal.reverses_transaction_id == original_je.id
    assert original_je.reversed_by == admin_user.id
    assert replacement_je.id != original_je.id

    hidden = client.get(f"/api/v1/invoices/{original_id}", headers=combined_headers())
    assert hidden.status_code == 404


def test_bill_edit_reverses_and_replaces(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    vendor = contact_factory(contact_type="VENDOR")
    product = product_factory(product_type="SERVICE")
    created = client.post(
        "/api/v1/bills", json=_bill_payload(vendor.id, product.id, rate=100),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    original_id = uuid.UUID(created.json()["id"])

    edited = client.put(
        f"/api/v1/bills/{original_id}",
        json={"line_items": _bill_payload(vendor.id, product.id, rate=300)["line_items"]},
        headers=combined_headers(),
    )
    assert edited.status_code == 200, edited.text
    replacement_id = uuid.UUID(edited.json()["id"])
    assert replacement_id != original_id

    db_session.expire_all()
    original = db_session.query(Bill).filter(Bill.id == original_id).one()
    replacement = db_session.query(Bill).filter(Bill.id == replacement_id).one()
    assert original.deleted_at is not None
    assert original.replaced_by_id == replacement_id
    assert replacement.replaces_id == original_id
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "BILL_REVERSAL", JournalEntry.source_id == original_id
    ).count() == 1
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "BILL", JournalEntry.source_id == replacement_id
    ).count() == 1


def test_expense_edit_reverses_and_replaces(
    client, combined_headers, tenant, db_session,
):
    category = _expense_category(db_session, tenant)
    created = client.post(
        "/api/v1/expenses",
        json={
            "expense_category_id": str(category.id),
            "expense_date": str(date.today()),
            "amount": 100.0,
            "place_of_supply_state_code": "27",
        },
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    original_id = uuid.UUID(created.json()["id"])
    edited = client.put(
        f"/api/v1/expenses/{original_id}",
        json={"amount": 250.0},
        headers=combined_headers(),
    )
    assert edited.status_code == 200, edited.text
    replacement_id = uuid.UUID(edited.json()["id"])
    assert replacement_id != original_id
    original = db_session.query(Expense).filter(Expense.id == original_id).one()
    replacement = db_session.query(Expense).filter(Expense.id == replacement_id).one()
    assert original.deleted_at is not None
    assert original.replaced_by_id == replacement_id
    assert replacement.replaces_id == original_id
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "EXPENSE_REVERSAL", JournalEntry.source_id == original_id
    ).count() == 1


# ---------------------------------------------------------------------------
# Delete = reversal + hidden document; accounting history remains
# ---------------------------------------------------------------------------

def test_invoice_delete_reverses_and_keeps_history(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    created = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id),
        headers=combined_headers(),
    )
    original_id = uuid.UUID(created.json()["id"])
    deleted = client.delete(f"/api/v1/invoices/{original_id}", headers=combined_headers())
    assert deleted.status_code == 204, deleted.text
    assert client.get(f"/api/v1/invoices/{original_id}", headers=combined_headers()).status_code == 404

    original = db_session.query(Invoice).filter(Invoice.id == original_id).one()
    assert original.deleted_at is not None
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE", JournalEntry.source_id == original_id
    ).count() == 1
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE_REVERSAL", JournalEntry.source_id == original_id
    ).count() == 1


# ---------------------------------------------------------------------------
# Ledger immutability, atomic posting and double-entry rules
# ---------------------------------------------------------------------------

def test_posted_journal_entry_and_lines_cannot_be_deleted(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    response = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id),
        headers=combined_headers(),
    )
    invoice_id = uuid.UUID(response.json()["id"])
    entry = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE", JournalEntry.source_id == invoice_id
    ).one()
    line_id = entry.lines[0].id

    db_session.delete(entry.lines[0])
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    assert db_session.query(JournalLine).filter(JournalLine.id == line_id).one()

    entry = db_session.query(JournalEntry).filter(JournalEntry.id == entry.id).one()
    db_session.delete(entry)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    assert db_session.query(JournalEntry).filter(JournalEntry.id == entry.id).one()


def test_failed_posting_rolls_back_atomically(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("1.0000"))
    stock_before = db_session.query(Product).filter(Product.id == product.id).one().current_stock
    response = client.post(
        "/api/v1/invoices",
        json=_invoice_payload(contact.id, product.id, quantity=5),
        headers=combined_headers(),
    )
    assert response.status_code == 422
    db_session.expire_all()
    assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 0
    assert db_session.query(JournalEntry).filter(JournalEntry.tenant_id == tenant.id).count() == 0
    assert db_session.query(StockLedger).filter(StockLedger.tenant_id == tenant.id).count() == 0
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == stock_before


def test_api_and_engine_reject_unbalanced_journals(
    client, combined_headers, tenant, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    response = client.post(
        "/api/v1/accounting/journals",
        json=_journal_payload(accounts, debit=100, credit=99),
        headers=combined_headers(),
    )
    assert response.status_code == 400
    with pytest.raises(LedgerValidationError):
        JournalEntryDraft(
            tenant_id=tenant.id,
            entry_date=date.today(),
            reference_number="X",
            description="unbalanced",
            source_type="MANUAL",
            source_id=uuid.uuid4(),
            lines=[
                JournalLineDraft(accounts["cash"], Decimal("100"), "DEBIT"),
                JournalLineDraft(accounts["sales"], Decimal("99"), "CREDIT"),
            ],
        )


# ---------------------------------------------------------------------------
# Idempotency and actor attribution
# ---------------------------------------------------------------------------

def test_duplicate_submission_is_idempotent(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    payload = _invoice_payload(contact.id, product.id)
    headers = combined_headers()
    headers["Idempotency-Key"] = str(uuid.uuid4())
    first = client.post("/api/v1/invoices", json=payload, headers=headers)
    second = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert first.status_code == 201, first.text
    assert second.status_code == 201, second.text
    assert second.json()["id"] == first.json()["id"]
    assert second.headers.get("Idempotency-Replayed") == "true"
    assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 1


def test_same_key_different_payload_is_rejected(
    client, combined_headers, contact_factory, product_factory,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    headers = combined_headers()
    headers["Idempotency-Key"] = str(uuid.uuid4())
    first_payload = _invoice_payload(contact.id, product.id)
    first = client.post("/api/v1/invoices", json=first_payload, headers=headers)
    assert first.status_code == 201
    changed = dict(first_payload)
    changed["notes"] = "different"
    second = client.post("/api/v1/invoices", json=changed, headers=headers)
    assert second.status_code == 422
    assert second.json()["code"] == "IDEMPOTENCY_PAYLOAD_MISMATCH"


def test_manual_journal_carries_actor(
    client, combined_headers, tenant, admin_user, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    response = client.post(
        "/api/v1/accounting/journals",
        json=_journal_payload(accounts),
        headers=combined_headers(),
    )
    assert response.status_code == 201, response.text
    entry = db_session.query(JournalEntry).filter(JournalEntry.source_type == "MANUAL").one()
    assert entry.created_by == admin_user.id
    assert entry.posted_by == admin_user.id
    assert entry.posted_at is not None
    assert entry.source_channel == "API"


# ---------------------------------------------------------------------------
# Manual journal correction is reversal-based, never destructive
# ---------------------------------------------------------------------------

def test_manual_journal_edit_creates_reversal_and_replacement(
    client, combined_headers, tenant, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    created = client.post(
        "/api/v1/accounting/journals",
        json=_journal_payload(accounts),
        headers=combined_headers(),
    )
    assert created.status_code == 201, created.text
    original_id = uuid.UUID(created.json()["id"])

    replacement_payload = _journal_payload(accounts, debit=250, credit=250)
    edited = client.put(
        f"/api/v1/accounting/journals/{original_id}",
        json=replacement_payload,
        headers=combined_headers(),
    )
    assert edited.status_code == 200, edited.text
    replacement_id = uuid.UUID(edited.json()["id"])
    assert replacement_id != original_id

    original = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    replacement = db_session.query(JournalEntry).filter(JournalEntry.id == replacement_id).one()
    reversal = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "JOURNAL_REVERSAL",
        JournalEntry.source_id == original_id,
    ).one()
    assert original.reversal_transaction_id == reversal.id
    assert reversal.reverses_transaction_id == original_id
    assert original.replacement_transaction_id == replacement_id
    assert replacement.original_transaction_id == original_id
    assert len(original.lines) == 2


def test_manual_journal_delete_is_a_reversal_not_a_delete(
    client, combined_headers, tenant, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    created = client.post(
        "/api/v1/accounting/journals",
        json=_journal_payload(accounts),
        headers=combined_headers(),
    )
    original_id = uuid.UUID(created.json()["id"])
    deleted = client.delete(
        f"/api/v1/accounting/journals/{original_id}", headers=combined_headers()
    )
    assert deleted.status_code == 204
    assert db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "JOURNAL_REVERSAL",
        JournalEntry.source_id == original_id,
    ).count() == 1


# ---------------------------------------------------------------------------
# Locked journal financial fields remain immutable after reversal metadata
# ---------------------------------------------------------------------------

def test_locked_entry_cannot_modify_financial_fields_after_reversal(
    client, combined_headers, tenant, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    created = client.post(
        "/api/v1/accounting/journals",
        json=_journal_payload(accounts),
        headers=combined_headers(),
    )
    original_id = uuid.UUID(created.json()["id"])
    deleted = client.delete(
        f"/api/v1/accounting/journals/{original_id}", headers=combined_headers()
    )
    assert deleted.status_code == 204

    db_session.expire_all()
    entry = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    assert entry.reversal_transaction_id is not None
    entry.entry_date = date(2000, 1, 1)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    entry = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    entry.lines[0].amount = Decimal("999")
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
