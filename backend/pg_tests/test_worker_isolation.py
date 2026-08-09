"""Priority 2 — Workers establish tenant context; one tenant's worker cannot
operate on another tenant's accounting rows."""

import uuid

import pytest
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import Invoice

from seed import (
    TENANT_A,
    TENANT_B,
    seed_contact,
    seed_invoice,
    seed_tenants,
)


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    contact_b = seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    inv_a = seed_invoice(db_admin, TENANT_A, contact_a, f"INV-A-{token}")
    inv_b = seed_invoice(db_admin, TENANT_B, contact_b, f"INV-B-{token}")
    db_admin.commit()
    return {"inv_a": inv_a, "inv_b": inv_b}


def test_worker_task_cannot_resolve_other_tenants_invoice(db_worker, seeded):
    """The tenant-scoped lookup (used by e-invoice/PDF/email tasks) must not
    find another tenant's invoice, even when handed its id."""
    set_tenant(db_worker, TENANT_A)
    found = db_worker.query(Invoice).filter(Invoice.id == seeded["inv_b"].id).first()
    assert found is None

    found = db_worker.query(Invoice).filter(Invoice.id == seeded["inv_a"].id).first()
    assert found is not None
    assert found.tenant_id == TENANT_A


def test_worker_cannot_read_other_tenant_ledger(db_worker, db_admin, seeded):
    from seed import seed_account, seed_journal_entry
    token = uuid.uuid4().hex[:8]
    acc_a = seed_account(db_admin, TENANT_A, f"Bank A {token}", f"10{token[:4]}", "ASSET")
    acc_b = seed_account(db_admin, TENANT_B, f"Bank B {token}", f"11{token[:4]}", "ASSET")
    seed_journal_entry(db_admin, TENANT_A, acc_a, acc_a, "INVOICE", seeded["inv_a"].id)
    seed_journal_entry(db_admin, TENANT_B, acc_b, acc_b, "INVOICE", seeded["inv_b"].id)
    db_admin.commit()

    set_tenant(db_worker, TENANT_A)
    assert db_worker.execute(text("SELECT count(*) FROM journal_entries")).scalar() == 1
    assert db_worker.execute(
        text("SELECT count(*) FROM journal_entries WHERE tenant_id = :t"),
        {"t": str(TENANT_B)},
    ).scalar() == 0


def test_worker_update_other_tenant_row_is_noop(db_worker, seeded):
    set_tenant(db_worker, TENANT_A)
    result = db_worker.execute(
        text("UPDATE invoices SET notes = 'x' WHERE id = :id"),
        {"id": str(seeded["inv_b"].id)},
    )
    assert result.rowcount == 0
    result = db_worker.execute(
        text("UPDATE invoices SET notes = 'x' WHERE id = :id"),
        {"id": str(seeded["inv_a"].id)},
    )
    assert result.rowcount == 1


def test_scheduled_task_enumerates_tenants_without_data(db_worker, seeded):
    """The controlled enumerator returns only ids/names — scheduled tasks can
    iterate tenants but ordinary worker code gets no accounting data from it."""
    rows = db_worker.execute(
        text("SELECT tenant_id, legal_name FROM apex_list_active_tenant_ids() ORDER BY legal_name")
    ).mappings().all()
    assert len(rows) == 2
    assert {r["tenant_id"] for r in rows} == {TENANT_A, TENANT_B}


def test_tenant_scoped_flow_commits_only_own_tenant(db_worker, seeded):
    """A worker operating as tenant A that tries to create a row for tenant B
    is rejected by RLS WITH CHECK."""
    set_tenant(db_worker, TENANT_A)
    with pytest.raises(Exception):
        db_worker.execute(
            text(
                "INSERT INTO invoices "
                "(id, tenant_id, contact_id, invoice_number, issue_date, due_date, status, "
                "subtotal, cgst_amount, sgst_amount, igst_amount, utgst_amount, cess_amount, "
                "round_off, shipping_charges, total, amount_paid, e_invoice_status, pos_state_code, "
                "currency, exchange_rate) "
                "VALUES (:id, :tid, :cid, 'INV-W-1', CURRENT_DATE, CURRENT_DATE, 'POSTED', "
                "0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 'PENDING', '27', 'INR', 1)"
            ),
            {"id": str(uuid.uuid4()), "tid": str(TENANT_B), "cid": str(uuid.uuid4())},
        )
        db_worker.commit()
