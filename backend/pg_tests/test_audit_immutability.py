"""Priority 1/8 — Audit records are immutable and commit atomically with
financial changes."""

import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import AuditLog, Invoice

from seed import (
    TENANT_A,
    seed_audit_log,
    seed_contact,
    seed_tenants,
)


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    contact = seed_contact(db_admin, TENANT_A, "Cust A")
    audit = seed_audit_log(db_admin, TENANT_A)
    db_admin.commit()
    return {"contact": contact, "audit": audit}


def test_audit_log_update_blocked(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        db_admin.execute(
            text("UPDATE audit_logs SET action = 'tampered' WHERE id = :id"),
            {"id": str(seeded["audit"].id)},
        )
        db_admin.commit()
    assert "immutable" in str(excinfo.value).lower()


def test_audit_log_delete_blocked(db_admin, seeded):
    set_tenant(db_admin, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        db_admin.execute(
            text("DELETE FROM audit_logs WHERE id = :id"),
            {"id": str(seeded["audit"].id)},
        )
        db_admin.commit()
    assert "immutable" in str(excinfo.value).lower()


def test_audit_log_blocks_admin_too(db_admin, seeded):
    """FORCE ROW LEVEL SECURITY is not the immutability mechanism — the trigger
    protects audit rows even from the superuser."""
    with pytest.raises(Exception):
        db_admin.execute(
            text("UPDATE audit_logs SET actor_email = 'hacker@evil.example' WHERE id = :id"),
            {"id": str(seeded["audit"].id)},
        )
        db_admin.commit()


def test_audit_and_financial_change_commit_atomically(db_admin, seeded):
    """A financial mutation and its audit row are all-or-nothing."""
    set_tenant(db_admin, TENANT_A)

    def do_insert(commit: bool):
        inv = Invoice(
            tenant_id=TENANT_A,
            contact_id=seeded["contact"].id,
            invoice_number=f"ATOM-{uuid.uuid4().hex[:6]}",
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
        )
        db_admin.add(inv)
        db_admin.flush()
        db_admin.add(AuditLog(
            tenant_id=TENANT_A,
            actor_id=uuid.uuid4(),
            actor_email="actor@test.local",
            action="invoice.created",
            entity_type="Invoice",
            entity_id=inv.id,
            after_state={"number": inv.invoice_number},
            timestamp=date.today(),
        ))
        if commit:
            db_admin.commit()
        else:
            db_admin.rollback()
        return inv.invoice_number

    number = do_insert(commit=True)
    count = db_admin.execute(
        text("SELECT count(*) FROM invoices WHERE invoice_number = :n"),
        {"n": number},
    ).scalar()
    assert count == 1
    audit_count = db_admin.execute(
        text("SELECT count(*) FROM audit_logs WHERE action = 'invoice.created'"),
    ).scalar()
    assert audit_count == 1

    # Rollback removes both the invoice and its audit row.
    number2 = do_insert(commit=False)
    count = db_admin.execute(
        text("SELECT count(*) FROM invoices WHERE invoice_number = :n"),
        {"n": number2},
    ).scalar()
    assert count == 0
