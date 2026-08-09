"""Priority 1/4 — Journal balancing, duplicate postings, document-number uniqueness."""

import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import Invoice, JournalEntry, JournalLine

from seed import (
    TENANT_A,
    TENANT_B,
    seed_account,
    seed_contact,
    seed_invoice,
    seed_tenants,
)


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    inv_a = seed_invoice(db_admin, TENANT_A, contact_a, f"INV-A-{token}")
    acc1 = seed_account(db_admin, TENANT_A, f"Bank A {token}", f"10{token[:4]}", "ASSET")
    acc2 = seed_account(db_admin, TENANT_A, f"Rev A {token}", f"40{token[:4]}", "REVENUE")
    db_admin.commit()
    return {"inv_a": inv_a, "acc1": acc1, "acc2": acc2, "contact_a": contact_a}


def _insert_entry(db, tenant_id, entry_id, source_type="INVOICE", source_id=None, lines=()):
    entry = JournalEntry(
        id=entry_id,
        tenant_id=tenant_id,
        entry_date=date.today(),
        reference_number=f"JR-{uuid.uuid4().hex[:8]}",
        source_type=source_type,
        source_id=source_id,
        description="test",
    )
    db.add(entry)
    for account_id, amount, direction in lines:
        db.add(JournalLine(
            tenant_id=tenant_id,
            entry_id=entry_id,
            account_id=account_id,
            amount=amount,
            direction=direction,
            narration="x",
        ))


def test_unbalanced_journal_rejected(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    entry_id = uuid.uuid4()
    _insert_entry(
        db_admin,
        TENANT_A,
        entry_id,
        lines=[(seeded["acc1"].id, Decimal("100.00"), "DEBIT")],
    )
    with pytest.raises(Exception) as excinfo:
        db_admin.commit()
    message = str(excinfo.value).lower()
    assert "balanced" in message


def test_balanced_journal_accepted(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    entry_id = uuid.uuid4()
    _insert_entry(
        db_admin,
        TENANT_A,
        entry_id,
        lines=[
            (seeded["acc1"].id, Decimal("100.00"), "DEBIT"),
            (seeded["acc2"].id, Decimal("100.00"), "CREDIT"),
        ],
    )
    db_admin.commit()


def test_duplicate_source_posting_rejected(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    entry_id = uuid.uuid4()
    _insert_entry(
        db_admin,
        TENANT_A,
        entry_id,
        source_type="INVOICE",
        source_id=seeded["inv_a"].id,
        lines=[
            (seeded["acc1"].id, Decimal("100.00"), "DEBIT"),
            (seeded["acc2"].id, Decimal("100.00"), "CREDIT"),
        ],
    )
    db_admin.commit()

    # Same tenant + same source -> unique constraint violation.
    with pytest.raises(Exception) as excinfo:
        entry_id2 = uuid.uuid4()
        _insert_entry(
            db_admin,
            TENANT_A,
            entry_id2,
            source_type="INVOICE",
            source_id=seeded["inv_a"].id,
            lines=[
                (seeded["acc1"].id, Decimal("100.00"), "DEBIT"),
                (seeded["acc2"].id, Decimal("100.00"), "CREDIT"),
            ],
        )
        db_admin.commit()
    message = str(excinfo.value).lower()
    assert "unique" in message or "duplicate" in message or "journal" in message


def test_duplicate_source_posting_allowed_across_tenants(db_admin, seeded):
    # The same source id may exist per tenant — uniqueness is tenant-scoped.
    set_tenant(db_admin, TENANT_A)
    entry_a = uuid.uuid4()
    _insert_entry(
        db_admin,
        TENANT_A,
        entry_a,
        source_type="INVOICE",
        source_id=seeded["inv_a"].id,
        lines=[
            (seeded["acc1"].id, Decimal("100.00"), "DEBIT"),
            (seeded["acc2"].id, Decimal("100.00"), "CREDIT"),
        ],
    )
    db_admin.commit()

    token = uuid.uuid4().hex[:8]
    seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    db_admin.commit()
    set_tenant(db_admin, TENANT_B)
    acc_b1 = seed_account(db_admin, TENANT_B, f"Bank B {token}", f"10{token[:4]}", "ASSET")
    acc_b2 = seed_account(db_admin, TENANT_B, f"Rev B {token}", f"40{token[:4]}", "REVENUE")
    entry_b = uuid.uuid4()
    _insert_entry(
        db_admin,
        TENANT_B,
        entry_b,
        source_type="INVOICE",
        source_id=seeded["inv_a"].id,
        lines=[
            (acc_b1.id, Decimal("100.00"), "DEBIT"),
            (acc_b2.id, Decimal("100.00"), "CREDIT"),
        ],
    )
    db_admin.commit()


def _insert_numbered_invoice(db, tenant_id, contact_id, number):
    db.add(Invoice(
        tenant_id=tenant_id,
        contact_id=contact_id,
        invoice_number=number,
        issue_date=date.today(),
        due_date=date.today(),
        status="POSTED",
        subtotal=Decimal("0.0000"),
        cgst_amount=Decimal("0.0000"),
        sgst_amount=Decimal("0.0000"),
        igst_amount=Decimal("0.0000"),
        utgst_amount=Decimal("0.0000"),
        cess_amount=Decimal("0.0000"),
        round_off=Decimal("0.0000"),
        shipping_charges=Decimal("0.0000"),
        total=Decimal("0.0000"),
        amount_paid=Decimal("0.0000"),
        e_invoice_status="PENDING",
        pos_state_code="27",
        currency="INR",
        exchange_rate=Decimal("1.000000"),
    ))


def test_active_document_number_duplicate_rejected(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    _insert_numbered_invoice(db_admin, TENANT_A, seeded["contact_a"].id, "DUP-NUM-1")
    db_admin.commit()
    with pytest.raises(Exception) as excinfo:
        _insert_numbered_invoice(db_admin, TENANT_A, seeded["contact_a"].id, "DUP-NUM-1")
        db_admin.commit()
    message = str(excinfo.value).lower()
    assert "unique" in message or "duplicate" in message or "already exists" in message


def test_same_number_allowed_in_different_tenant(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    _insert_numbered_invoice(db_admin, TENANT_A, seeded["contact_a"].id, "SHARED-NUM")
    db_admin.commit()
    set_tenant(db_admin, TENANT_B)
    contact_b = seed_contact(db_admin, TENANT_B, "Cust B shared")
    _insert_numbered_invoice(db_admin, TENANT_B, contact_b.id, "SHARED-NUM")
    db_admin.commit()


def test_soft_deleted_number_still_rejected_by_full_constraint(db_admin, seeded):
    """Documented current behavior: the unconditional (tenant, number) unique
    constraint remains, so even a soft-deleted number cannot be reused.
    Reuse of soft-deleted document numbers is a product decision that is out
    of scope for this hardening sprint."""
    set_tenant(db_admin, TENANT_A)
    _insert_numbered_invoice(db_admin, TENANT_A, seeded["contact_a"].id, "REUSE-NUM")
    db_admin.commit()
    db_admin.execute(
        text("UPDATE invoices SET deleted_at = CURRENT_TIMESTAMP WHERE invoice_number = 'REUSE-NUM'")
    )
    db_admin.commit()
    with pytest.raises(Exception) as excinfo:
        _insert_numbered_invoice(db_admin, TENANT_A, seeded["contact_a"].id, "REUSE-NUM")
        db_admin.commit()
    assert "unique" in str(excinfo.value).lower()
