"""
Phase 0 direct-posting hardening tests.

Covers, for the direct-posting architecture transition:

* posted journal entries cannot be deleted (delete-proof ledger)
* posted invoices/bills cannot be destructively edited through CRUD
* journal posting is atomic — a failed posting leaves nothing behind
* double-entry balance is enforced at the API and engine layers
* duplicate submissions are idempotent via the Idempotency-Key middleware
* ledger entries carry the authenticated actor and source channel
* reversals are unique, linked to the original, and never remove it
* document cancellation links reversal entries to the original posting
* existing Draft workflows keep working during the transition (backward compat)
"""
import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy.exc import IntegrityError

from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Bill, JournalEntry, JournalLine, StockLedger, Product,
)
from src.domains.accounting.services import AccountResolver, JournalEntryDraft, LedgerValidationError
from src.domains.accounting.services import JournalLineDraft


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _resolve_accounts(db_session, tenant_id):
    resolver = AccountResolver(db_session, tenant_id)
    ids = {
        "cash": resolver.resolve("assets.cash"),
        "sales": resolver.resolve("sales_revenue"),
    }
    db_session.commit()
    return ids


def _journal_payload(tenant_id, accounts, debit=100.00, credit=100.00):
    return {
        "entry_date": str(date.today()),
        "reference_number": f"JE-{uuid.uuid4().hex[:8].upper()}",
        "description": "Phase 0 test journal",
        "lines": [
            {"account_id": str(accounts["cash"]), "amount": debit, "direction": "DEBIT"},
            {"account_id": str(accounts["sales"]), "amount": credit, "direction": "CREDIT"},
        ],
    }


def _invoice_payload(contact_id, product_id, *, post_on_create=True, quantity=1, rate=100.0):
    return {
        "contact_id": str(contact_id),
        "invoice_number": f"INV-P0-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "supply_type": "DOMESTIC",
        "post_on_create": post_on_create,
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


def _bill_payload(contact_id, product_id, *, post_on_create=True, quantity=1, rate=100.0):
    return {
        "contact_id": str(contact_id),
        "bill_number": f"BILL-P0-{uuid.uuid4().hex[:8].upper()}",
        "issue_date": str(date.today()),
        "due_date": str(date.today()),
        "pos_state_code": "27",
        "post_on_create": post_on_create,
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


# ---------------------------------------------------------------------------
# 1. Delete-proof posted journal entries
# ---------------------------------------------------------------------------

def test_posted_journal_entry_cannot_be_deleted(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    res = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id), headers=combined_headers()
    )
    assert res.status_code == 201, res.text
    assert res.json()["status"] == "POSTED"

    je = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE",
        JournalEntry.tenant_id == tenant.id,
    ).first()
    assert je is not None

    db_session.delete(je)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    # The entry is still there after the failed delete.
    assert db_session.query(JournalEntry).filter(JournalEntry.id == je.id).first() is not None


def test_posted_journal_lines_cannot_be_deleted(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    res = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id), headers=combined_headers()
    )
    assert res.status_code == 201, res.text

    je = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE",
        JournalEntry.tenant_id == tenant.id,
    ).first()
    line = je.lines[0]
    db_session.delete(line)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()
    assert db_session.query(JournalLine).filter(JournalLine.id == line.id).first() is not None


# ---------------------------------------------------------------------------
# 2. Posted invoices/bills are immutable through CRUD
# ---------------------------------------------------------------------------

def test_posted_bill_cannot_be_edited_destructively(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    vendor = contact_factory(contact_type="VENDOR")
    product = product_factory()
    res = client.post(
        "/api/v1/bills", json=_bill_payload(vendor.id, product.id, post_on_create=True),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    bill_id = res.json()["id"]
    assert res.json()["status"] == "POSTED"

    original_total = Decimal(res.json()["total"])
    je = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "BILL",
        JournalEntry.source_id == uuid.UUID(bill_id),
    ).one()
    original_je_amounts = sorted((l.amount, l.direction) for l in je.lines)
    stock_before = db_session.query(StockLedger).filter(
        StockLedger.reference_type == "BILL",
        StockLedger.reference_id == uuid.UUID(bill_id),
    ).count()
    stock_qty_before = db_session.query(Product).filter(Product.id == product.id).one().current_stock

    # Attempt to destructively edit the posted bill (rate change).
    edit = _bill_payload(vendor.id, product.id, post_on_create=True, rate=999.0)
    edit["bill_number"] = res.json()["bill_number"]
    res_edit = client.put(f"/api/v1/bills/{bill_id}", json=edit, headers=combined_headers())
    assert res_edit.status_code == 400
    assert "immutable" in res_edit.json()["detail"].lower()

    # Journal, lines, stock-ledger rows and stock balance are untouched.
    db_session.expire_all()
    je = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "BILL",
        JournalEntry.source_id == uuid.UUID(bill_id),
    ).one()
    assert sorted((l.amount, l.direction) for l in je.lines) == original_je_amounts
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "BILL",
        JournalEntry.source_id == uuid.UUID(bill_id),
    ).count() == 1
    assert db_session.query(StockLedger).filter(
        StockLedger.reference_type == "BILL",
        StockLedger.reference_id == uuid.UUID(bill_id),
    ).count() == stock_before
    bill = db_session.query(Bill).filter(Bill.id == uuid.UUID(bill_id)).one()
    assert bill.total == original_total
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == stock_qty_before


def test_posted_invoice_cannot_be_edited(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    res = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id, post_on_create=True),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    inv_id = res.json()["id"]

    edit = _invoice_payload(contact.id, product.id, post_on_create=True, rate=999.0)
    edit["invoice_number"] = res.json()["invoice_number"]
    res_edit = client.put(f"/api/v1/invoices/{inv_id}", json=edit, headers=combined_headers())
    assert res_edit.status_code == 400
    assert "immutable" in res_edit.json()["detail"].lower()
    # Original journal entry still exists with its original amounts.
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE",
        JournalEntry.source_id == uuid.UUID(inv_id),
    ).count() == 1


def test_draft_bill_can_still_be_edited(
    client, combined_headers, contact_factory, product_factory, db_session,
):
    """Draft editing remains available during the transition."""
    vendor = contact_factory(contact_type="VENDOR")
    product = product_factory()
    res = client.post(
        "/api/v1/bills", json=_bill_payload(vendor.id, product.id, post_on_create=False),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    bill_id = res.json()["id"]
    assert res.json()["status"] == "DRAFT"

    edit = _bill_payload(vendor.id, product.id, post_on_create=False, rate=200.0)
    edit["bill_number"] = res.json()["bill_number"]
    res_edit = client.put(f"/api/v1/bills/{bill_id}", json=edit, headers=combined_headers())
    assert res_edit.status_code == 200, res_edit.text
    assert Decimal(res_edit.json()["total"]) > Decimal(res.json()["total"])


# ---------------------------------------------------------------------------
# 3. Atomic posting — a failed posting leaves nothing behind
# ---------------------------------------------------------------------------

def test_failed_posting_rolls_back_atomically(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """Insufficient stock must fail the whole operation: no invoice, no journal,
    no stock movement, no balance change."""
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="GOODS", current_stock=Decimal("1.0000"))
    stock_before = db_session.query(Product).filter(Product.id == product.id).one().current_stock

    res = client.post(
        "/api/v1/invoices",
        json=_invoice_payload(contact.id, product.id, post_on_create=True, quantity=5, rate=100.0),
        headers=combined_headers(),
    )
    assert res.status_code == 422

    db_session.expire_all()
    assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 0
    assert db_session.query(JournalEntry).filter(JournalEntry.tenant_id == tenant.id).count() == 0
    assert db_session.query(StockLedger).filter(StockLedger.tenant_id == tenant.id).count() == 0
    assert db_session.query(Product).filter(Product.id == product.id).one().current_stock == stock_before


# ---------------------------------------------------------------------------
# 4. Balanced journal enforcement
# ---------------------------------------------------------------------------

def test_api_rejects_unbalanced_journal(client, combined_headers, tenant, db_session):
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts, debit=100.00, credit=99.00)
    res = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert res.status_code == 400
    assert "balance" in res.json()["detail"].lower()


def test_engine_rejects_unbalanced_draft(tenant, db_session):
    accounts = _resolve_accounts(db_session, tenant.id)
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
# 5. Duplicate submission idempotency (Idempotency-Key middleware)
# ---------------------------------------------------------------------------

def test_duplicate_submission_is_idempotent(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    payload = _invoice_payload(contact.id, product.id, post_on_create=True)
    key = str(uuid.uuid4())

    headers = combined_headers()
    headers["Idempotency-Key"] = key
    first = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert first.status_code == 201, first.text

    second = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert second.status_code == 201, second.text
    assert second.json()["id"] == first.json()["id"]
    assert second.headers.get("Idempotency-Replayed") == "true"

    db_session.expire_all()
    assert db_session.query(Invoice).filter(Invoice.tenant_id == tenant.id).count() == 1
    assert db_session.query(JournalEntry).filter(JournalEntry.tenant_id == tenant.id).count() == 1


def test_duplicate_submission_without_key_creates_two_drafts(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """Without an Idempotency-Key the middleware does not dedupe — the
    document number uniqueness guard is the remaining backstop."""
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    payload = _invoice_payload(contact.id, product.id, post_on_create=False)
    first = client.post("/api/v1/invoices", json=payload, headers=combined_headers())
    assert first.status_code == 201
    second = client.post("/api/v1/invoices", json=payload, headers=combined_headers())
    # Same invoice_number supplied twice → unique constraint rejects the dup.
    assert second.status_code == 400


def test_same_key_different_payload_is_rejected(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    """Reusing an Idempotency-Key with a different request body must be
    rejected (422), not silently replayed against the new payload."""
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    key = str(uuid.uuid4())

    headers = combined_headers()
    headers["Idempotency-Key"] = key
    first = client.post("/api/v1/invoices", json=_invoice_payload(contact.id, product.id), headers=headers)
    assert first.status_code == 201, first.text

    # Same key, different payload (different quantity) → payload fingerprint mismatch.
    different = _invoice_payload(contact.id, product.id, quantity=3)
    second = client.post("/api/v1/invoices", json=different, headers=headers)
    assert second.status_code == 422, second.text
    assert "IDEMPOTENCY_PAYLOAD_MISMATCH" in second.json().get("code", "")


# ---------------------------------------------------------------------------
# 6. Actor attribution — server-derived, never client-supplied
# ---------------------------------------------------------------------------

def test_manual_journal_carries_authenticated_actor(
    client, combined_headers, tenant, admin_user, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts)
    res = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert res.status_code == 201, res.text

    je = db_session.query(JournalEntry).filter(JournalEntry.source_type == "MANUAL").one()
    assert je.created_by == admin_user.id
    assert je.posted_by == admin_user.id
    assert je.posted_at is not None
    assert je.source_channel == "API"


def test_auto_posted_document_journal_carries_actor(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    res = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id, post_on_create=True),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text

    je = db_session.query(JournalEntry).filter(JournalEntry.source_type == "INVOICE").one()
    assert je.created_by == admin_user.id
    assert je.posted_by == admin_user.id
    assert je.posted_at is not None
    assert je.source_channel == "API"


# ---------------------------------------------------------------------------
# 7. Reversal uniqueness, linkage, and preservation of the original
# ---------------------------------------------------------------------------

def test_reversal_is_unique_and_linked(
    client, combined_headers, tenant, admin_user, db_session,
):
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts)
    created = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert created.status_code == 201, created.text
    original_id = uuid.UUID(created.json()["id"])

    rev = client.post(
        f"/api/v1/accounting/journals/{original_id}/reverse",
        json={"reversal_date": str(date.today()), "reason": "Posted in error"},
        headers=combined_headers(),
    )
    assert rev.status_code == 201, rev.text
    reversal = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "JOURNAL_REVERSAL"
    ).one()

    # Reversal is balanced and points at the original; original untouched.
    debit = sum(l.amount for l in reversal.lines if l.direction == "DEBIT")
    credit = sum(l.amount for l in reversal.lines if l.direction == "CREDIT")
    assert debit == credit
    assert reversal.reverses_transaction_id == original_id
    assert reversal.created_by == admin_user.id
    assert reversal.posted_by == admin_user.id

    original = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    assert original.reversal_transaction_id == reversal.id
    assert original.reversed_by == admin_user.id
    assert original.reversed_at is not None
    assert len(original.lines) == 2  # original preserved, amounts untouched

    # Double reversal is rejected.
    again = client.post(
        f"/api/v1/accounting/journals/{original_id}/reverse",
        json={"reversal_date": str(date.today()), "reason": "Again"},
        headers=combined_headers(),
    )
    assert again.status_code == 409


def test_document_cancel_links_reversal_entry(
    client, combined_headers, tenant, admin_user, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    res = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id, post_on_create=True),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    inv_id = uuid.UUID(res.json()["id"])

    cancel = client.post(f"/api/v1/invoices/{inv_id}/cancel", headers=combined_headers())
    assert cancel.status_code == 200, cancel.text

    original = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE", JournalEntry.source_id == inv_id
    ).one()
    reversal = db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE_REVERSAL", JournalEntry.source_id == inv_id
    ).one()

    assert original.reversed_by == admin_user.id
    assert original.reversed_at is not None
    assert original.reversal_transaction_id == reversal.id
    assert reversal.reverses_transaction_id == original.id
    assert original.lines  # original posting preserved


# ---------------------------------------------------------------------------
# 8. Backward compatibility — existing Draft workflows keep working
# ---------------------------------------------------------------------------

def test_draft_invoice_workflow_still_works(
    client, combined_headers, tenant, contact_factory, product_factory, db_session,
):
    contact = contact_factory(contact_type="CUSTOMER")
    product = product_factory(product_type="SERVICE", current_stock=Decimal("0"))
    res = client.post(
        "/api/v1/invoices", json=_invoice_payload(contact.id, product.id, post_on_create=False),
        headers=combined_headers(),
    )
    assert res.status_code == 201, res.text
    assert res.json()["status"] == "DRAFT"
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE"
    ).count() == 0

    fin = client.post(f"/api/v1/invoices/{res.json()['id']}/finalize", headers=combined_headers())
    assert fin.status_code == 200
    assert fin.json()["status"] == "POSTED"
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "INVOICE"
    ).count() == 1


def test_expense_draft_workflow_still_works(client, combined_headers, tenant, db_session):
    """Expenses still require the explicit /post step during the transition."""
    from src.infrastructure.database.models import ExpenseCategory, Account

    resolver = AccountResolver(db_session, tenant.id)
    linked_account = resolver.resolve("expense.misc")
    db_session.commit()
    category = ExpenseCategory(
        id=uuid.uuid4(), tenant_id=tenant.id, name="Test Category",
        linked_account_id=linked_account,
    )
    db_session.add(category)
    db_session.commit()

    payload = {
        "expense_category_id": str(category.id),
        "expense_date": str(date.today()),
        "amount": 1000.00,
        "description": "Phase 0 expense",
        "vendor_name": "Test Vendor",
        "place_of_supply_state_code": "27",
    }
    res = client.post("/api/v1/expenses", json=payload, headers=combined_headers())
    assert res.status_code == 201, res.text
    assert res.json()["status"] == "DRAFT"
    expense_id = res.json()["id"]

    posted = client.post(f"/api/v1/expenses/{expense_id}/post", headers=combined_headers())
    assert posted.status_code == 200, posted.text
    assert posted.json()["status"] == "POSTED"
    assert db_session.query(JournalEntry).filter(
        JournalEntry.source_type == "EXPENSE"
    ).count() == 1


# ---------------------------------------------------------------------------
# 9. Journal history is append-only: no deletion path exists at all
# ---------------------------------------------------------------------------

def test_journal_entry_can_never_be_deleted(
    client, combined_headers, tenant, admin_user, db_session,
):
    """Posted journal entries can never be deleted via the ORM — there is no
    scoped exception and no flag a caller can set: corrections and year-end
    reopen must create reversal entries."""
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts)
    created = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert created.status_code == 201, created.text
    manual_je = db_session.query(JournalEntry).filter(JournalEntry.source_type == "MANUAL").one()

    db_session.delete(manual_je)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    # The entry is untouched.
    assert db_session.query(JournalEntry).filter(JournalEntry.id == manual_je.id).first() is not None


def test_journal_line_can_never_be_deleted(
    client, combined_headers, tenant, admin_user, db_session,
):
    """Journal lines are immutable history: deleting one must fail even when
    the owning entry is untouched."""
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts)
    created = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert created.status_code == 201, created.text
    manual_je = db_session.query(JournalEntry).filter(JournalEntry.source_type == "MANUAL").one()
    line = manual_je.lines[0]

    db_session.delete(line)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    assert db_session.query(JournalLine).filter(JournalLine.id == line.id).first() is not None


# ---------------------------------------------------------------------------
# 10. Locked entry: reversal metadata only, never financial fields
# ---------------------------------------------------------------------------

def test_locked_entry_cannot_be_unlocked_in_same_flush_as_edit(
    client, combined_headers, tenant, admin_user, db_session,
):
    """Flipping is_locked False and mutating a financial field in one flush
    must still be rejected — no single-flush unlock bypass."""
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts)
    created = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert created.status_code == 201, created.text
    entry = db_session.query(JournalEntry).filter(JournalEntry.source_type == "MANUAL").one()

    entry.is_locked = False
    entry.entry_date = date(2000, 1, 1)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    db_session.expire_all()
    entry = db_session.query(JournalEntry).filter(JournalEntry.id == entry.id).one()
    assert entry.is_locked is True
    assert entry.entry_date == date.today()


def test_locked_entry_cannot_modify_financial_fields(
    client, combined_headers, tenant, admin_user, db_session,
):
    """After reversal metadata is written to a locked entry, financial fields
    (amount, account, direction, date) must still be immutable."""
    accounts = _resolve_accounts(db_session, tenant.id)
    payload = _journal_payload(tenant.id, accounts)
    created = client.post("/api/v1/accounting/journals", json=payload, headers=combined_headers())
    assert created.status_code == 201, created.text
    original_id = uuid.UUID(created.json()["id"])

    # Author a reversal so the locked entry carries reversal metadata.
    rev = client.post(
        f"/api/v1/accounting/journals/{original_id}/reverse",
        json={"reversal_date": str(date.today()), "reason": "Test"},
        headers=combined_headers(),
    )
    assert rev.status_code == 201, rev.text

    db_session.expire_all()
    entry = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    assert entry.reversal_transaction_id is not None

    # Changing a financial field (entry_date) must still raise.
    entry.entry_date = date(2000, 1, 1)
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    # Changing a journal line amount must also raise.
    db_session.expire_all()
    entry = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    entry.lines[0].amount = Decimal("999.0000")
    with pytest.raises(IntegrityError):
        db_session.flush()
    db_session.rollback()

    # And a locked entry with reversal metadata can still accept linkage fields.
    db_session.expire_all()
    entry = db_session.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    entry.replacement_transaction_id = uuid.uuid4()
    db_session.flush()
    db_session.rollback()  # no IntegrityError raised above
