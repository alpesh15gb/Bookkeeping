"""Priority 1/5 — Tenant isolation across parent and child tables."""

import uuid
from decimal import Decimal

import pytest
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import (
    Bill,
    Invoice,
    JournalEntry,
    Payment,
    StockLedger,
)

from seed import (
    TENANT_A,
    TENANT_B,
    seed_account,
    seed_bill,
    seed_contact,
    seed_invoice,
    seed_journal_entry,
    seed_payment,
    seed_product,
    seed_stock_ledger,
    seed_tenants,
    seed_warehouse,
)

TABLES = [
    "invoices",
    "bills",
    "payments",
    "journal_entries",
    "stock_ledger",
    "invoice_lines",
    "bill_lines",
    "journal_lines",
]


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    contact_b = seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    product_a = seed_product(db_admin, TENANT_A, f"Prod A {token}")
    product_b = seed_product(db_admin, TENANT_B, f"Prod B {token}")
    wh_a = seed_warehouse(db_admin, TENANT_A, f"WH A {token}")
    wh_b = seed_warehouse(db_admin, TENANT_B, f"WH B {token}")
    inv_a = seed_invoice(db_admin, TENANT_A, contact_a, f"INV-A-{token}")
    inv_b = seed_invoice(db_admin, TENANT_B, contact_b, f"INV-B-{token}")
    bill_a = seed_bill(db_admin, TENANT_A, contact_a, f"BILL-A-{token}")
    bill_b = seed_bill(db_admin, TENANT_B, contact_b, f"BILL-B-{token}")
    pay_a = seed_payment(db_admin, TENANT_A, contact_a, f"PAY-A-{token}")
    pay_b = seed_payment(db_admin, TENANT_B, contact_b, f"PAY-B-{token}")
    acc_a = seed_account(db_admin, TENANT_A, f"Rev A {token}", f"40{token[:4]}", "REVENUE")
    acc_b = seed_account(db_admin, TENANT_B, f"Rev B {token}", f"41{token[:4]}", "REVENUE")
    seed_journal_entry(db_admin, TENANT_A, acc_a, acc_a, "INVOICE", inv_a.id)
    seed_journal_entry(db_admin, TENANT_B, acc_b, acc_b, "INVOICE", inv_b.id)
    seed_stock_ledger(db_admin, TENANT_A, product_a, wh_a.id, Decimal("5"), Decimal("5"))
    seed_stock_ledger(db_admin, TENANT_B, product_b, wh_b.id, Decimal("9"), Decimal("9"))
    db_admin.commit()
    return {
        "contact_a": contact_a, "contact_b": contact_b,
        "inv_a": inv_a, "inv_b": inv_b,
        "bill_a": bill_a, "bill_b": bill_b,
        "pay_a": pay_a, "pay_b": pay_b,
        "acc_a": acc_a, "acc_b": acc_b,
    }


def _count(db, table, tenant_id):
    return db.execute(
        text(f"SELECT count(*) FROM {table} WHERE tenant_id = :tid"),
        {"tid": str(tenant_id)},
    ).scalar()


def test_tenant_a_cannot_read_tenant_b_accounting_data(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    for table in TABLES:
        assert _count(db_api, table, TENANT_A) > 0, f"{table} should have tenant A rows"
        assert _count(db_api, table, TENANT_B) == 0, f"{table} leaked tenant B rows"


def test_tenant_b_cannot_read_tenant_a_accounting_data(db_api, seeded):
    set_tenant(db_api, TENANT_B)
    for table in TABLES:
        assert _count(db_api, table, TENANT_B) > 0
        assert _count(db_api, table, TENANT_A) == 0


def test_direct_child_table_access_blocked(db_api, seeded):
    """A direct query on child tables must not return other tenants' rows."""
    set_tenant(db_api, TENANT_A)
    assert db_api.execute(text("SELECT count(*) FROM invoice_lines")).scalar() == 1
    assert db_api.execute(text("SELECT count(*) FROM bill_lines")).scalar() == 1
    assert db_api.execute(text("SELECT count(*) FROM journal_lines")).scalar() == 2
    assert _count(db_api, "invoice_lines", TENANT_B) == 0
    assert _count(db_api, "bill_lines", TENANT_B) == 0
    assert _count(db_api, "journal_lines", TENANT_B) == 0


def test_child_tenant_must_match_parent(db_admin, db_api, seeded):
    """The DB trigger rejects a child row whose tenant differs from its parent."""
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        db_api.execute(
            text(
                "INSERT INTO invoice_lines (id, tenant_id, invoice_id, description, quantity, rate, "
                "discount, subtotal, hsn_sac, gst_rate, cgst_rate, cgst_amount, sgst_rate, sgst_amount, "
                "igst_rate, igst_amount, utgst_rate, utgst_amount, cess_rate, cess_amount, total) "
                "VALUES (:id, :tid, :inv, 'bad', 1, 1, 0, 1, '9983', 18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)"
            ),
            {
                "id": str(uuid.uuid4()),
                "tid": str(TENANT_B),
                "inv": str(seeded["inv_a"].id),
            },
        )
        db_api.commit()
    assert "tenant" in str(excinfo.value).lower()


def test_update_and_delete_other_tenant_rows_are_noops(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    result = db_api.execute(
        text("UPDATE bills SET notes = 'x' WHERE tenant_id = :tid"),
        {"tid": str(TENANT_B)},
    )
    assert result.rowcount == 0
    result = db_api.execute(
        text("DELETE FROM payments WHERE tenant_id = :tid"),
        {"tid": str(TENANT_B)},
    )
    assert result.rowcount == 0
    result = db_api.execute(
        text("DELETE FROM journal_lines WHERE tenant_id = :tid"),
        {"tid": str(TENANT_B)},
    )
    assert result.rowcount == 0


def test_orm_queries_respect_rls(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    invoices = db_api.query(Invoice).all()
    assert [i.id for i in invoices] == [seeded["inv_a"].id]
    bills = db_api.query(Bill).all()
    assert [b.id for b in bills] == [seeded["bill_a"].id]
    payments = db_api.query(Payment).all()
    assert [p.id for p in payments] == [seeded["pay_a"].id]
    entries = db_api.query(JournalEntry).all()
    assert all(e.tenant_id == TENANT_A for e in entries)
    moves = db_api.query(StockLedger).all()
    assert all(m.tenant_id == TENANT_A for m in moves)


def test_child_tenant_propagated_via_orm(db_api, seeded):
    """ORM-created child rows inherit tenant_id from their parent."""
    set_tenant(db_api, TENANT_A)
    rows = db_api.execute(
        text("SELECT tenant_id FROM invoice_lines WHERE invoice_id = :inv"),
        {"inv": str(seeded["inv_a"].id)},
    ).scalars().all()
    assert rows and all(str(r) == str(TENANT_A) for r in rows)
