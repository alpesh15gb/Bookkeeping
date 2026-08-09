"""Payment allocation tenant integrity — both sides of every link must match.

payment_allocations:  allocation.tenant_id == payment.tenant_id == invoice.tenant_id
bill_payment_allocations: allocation.tenant_id == bill_payment.tenant_id == bill.tenant_id

Cross-tenant allocation links must be rejected by PostgreSQL itself, and the
allocation rows must be protected by RLS like every other tenant-owned table.
"""

import uuid
from decimal import Decimal

import pytest
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import (
    BillPaymentAllocation,
    PaymentAllocation,
)

from seed import (
    TENANT_A,
    TENANT_B,
    seed_bill,
    seed_bill_payment,
    seed_bill_payment_allocation,
    seed_contact,
    seed_invoice,
    seed_payment,
    seed_payment_allocation,
    seed_tenants,
)

ALLOCATION_TABLES = ["payment_allocations", "bill_payment_allocations"]


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    contact_b = seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    inv_a = seed_invoice(db_admin, TENANT_A, contact_a, f"INV-A-{token}")
    inv_b = seed_invoice(db_admin, TENANT_B, contact_b, f"INV-B-{token}")
    bill_a = seed_bill(db_admin, TENANT_A, contact_a, f"BILL-A-{token}")
    bill_b = seed_bill(db_admin, TENANT_B, contact_b, f"BILL-B-{token}")
    pay_a = seed_payment(db_admin, TENANT_A, contact_a, f"PAY-A-{token}")
    pay_b = seed_payment(db_admin, TENANT_B, contact_b, f"PAY-B-{token}")
    bp_a = seed_bill_payment(db_admin, TENANT_A, contact_a, f"BP-A-{token}")
    bp_b = seed_bill_payment(db_admin, TENANT_B, contact_b, f"BP-B-{token}")
    alloc_a = seed_payment_allocation(db_admin, TENANT_A, pay_a, inv_a)
    balloc_a = seed_bill_payment_allocation(db_admin, TENANT_A, bp_a, bill_a)
    db_admin.commit()
    return {
        "contact_a": contact_a,
        "inv_a": inv_a, "inv_b": inv_b,
        "bill_a": bill_a, "bill_b": bill_b,
        "pay_a": pay_a, "pay_b": pay_b,
        "bp_a": bp_a, "bp_b": bp_b,
        "alloc_a": alloc_a, "balloc_a": balloc_a,
    }


def test_rls_enforced_on_allocation_tables(db_admin):
    rows = db_admin.execute(
        text(
            "SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity "
            "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
            "WHERE n.nspname = 'public' AND c.relname IN "
            "('payment_allocations', 'bill_payment_allocations')"
        )
    ).mappings().all()
    assert len(rows) == 2
    for row in rows:
        assert row["relrowsecurity"] is True, f"{row['relname']} RLS must be enabled"
        assert row["relforcerowsecurity"] is True, f"{row['relname']} RLS must be forced"


def test_tenant_a_cannot_see_tenant_b_allocations(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    # Tenant A sees its own allocations…
    assert db_api.query(PaymentAllocation).filter(
        PaymentAllocation.invoice_id == seeded["inv_a"].id
    ).count() == 1
    assert db_api.query(BillPaymentAllocation).filter(
        BillPaymentAllocation.bill_id == seeded["bill_a"].id
    ).count() == 1
    # …and nothing from Tenant B.
    for table in ALLOCATION_TABLES:
        n = db_api.execute(
            text(f"SELECT count(*) FROM {table} WHERE tenant_id = :t"),
            {"t": str(TENANT_B)},
        ).scalar()
        assert n == 0, f"{table} leaked tenant B rows"


def test_cross_tenant_payment_allocation_rejected(db_api, seeded):
    """payment A + invoice B must be rejected by PostgreSQL itself."""
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        db_api.execute(
            text(
                "INSERT INTO payment_allocations (id, tenant_id, payment_id, invoice_id, amount) "
                "VALUES (:id, :tid, :pid, :iid, 10)"
            ),
            {
                "id": str(uuid.uuid4()),
                "tid": str(TENANT_A),
                "pid": str(seeded["pay_a"].id),
                "iid": str(seeded["inv_b"].id),
            },
        )
        db_api.commit()
    message = str(excinfo.value).lower()
    assert "tenant" in message


def test_cross_tenant_bill_payment_allocation_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        db_api.execute(
            text(
                "INSERT INTO bill_payment_allocations (id, tenant_id, payment_id, bill_id, amount) "
                "VALUES (:id, :tid, :pid, :bid, 10)"
            ),
            {
                "id": str(uuid.uuid4()),
                "tid": str(TENANT_A),
                "pid": str(seeded["bp_a"].id),
                "bid": str(seeded["bill_b"].id),
            },
        )
        db_api.commit()
    message = str(excinfo.value).lower()
    assert "tenant" in message


def test_allocation_tenant_must_match_payment_side(db_api, seeded):
    """An allocation whose tenant_id matches the invoice but NOT the payment
    is still rejected (both sides are enforced)."""
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        db_api.execute(
            text(
                "INSERT INTO payment_allocations (id, tenant_id, payment_id, invoice_id, amount) "
                "VALUES (:id, :tid, :pid, :iid, 10)"
            ),
            {
                "id": str(uuid.uuid4()),
                "tid": str(TENANT_B),
                "pid": str(seeded["pay_a"].id),
                "iid": str(seeded["inv_a"].id),
            },
        )
        db_api.commit()
    message = str(excinfo.value).lower()
    assert "tenant" in message


def test_orm_created_allocation_inherits_tenant(db_api, seeded):
    """ORM-created allocations inherit tenant_id from the payment (listener)
    and pass the database trigger."""
    set_tenant(db_api, TENANT_A)
    # Use a fresh payment/invoice pair: the unique (payment_id, invoice_id)
    # constraint forbids a second allocation between the seeded pair.
    fresh_pay = seed_payment(db_api, TENANT_A, seeded["contact_a"], f"PAY-NEW-{uuid.uuid4().hex[:6]}")
    fresh_inv = seed_invoice(db_api, TENANT_A, seeded["contact_a"], f"INV-NEW-{uuid.uuid4().hex[:6]}")
    db_api.add(PaymentAllocation(
        payment_id=fresh_pay.id,
        invoice_id=fresh_inv.id,
        amount=Decimal("10.00"),
    ))
    db_api.flush()
    row = db_api.execute(
        text(
            "SELECT tenant_id FROM payment_allocations "
            "WHERE payment_id = :pid AND invoice_id = :iid"
        ),
        {"pid": str(fresh_pay.id), "iid": str(fresh_inv.id)},
    ).scalar()
    assert str(row) == str(TENANT_A)


def test_cross_tenant_orm_allocation_rejected(db_api, seeded):
    """ORM-created allocation with an explicit mismatched tenant is rejected."""
    set_tenant(db_api, TENANT_A)
    db_api.add(PaymentAllocation(
        tenant_id=TENANT_B,
        payment_id=seeded["pay_a"].id,
        invoice_id=seeded["inv_a"].id,
        amount=Decimal("10.00"),
    ))
    with pytest.raises(Exception) as excinfo:
        db_api.commit()
    assert "tenant" in str(excinfo.value).lower()
