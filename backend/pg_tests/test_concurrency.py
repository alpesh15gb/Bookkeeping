"""Priority 4 — Concurrency: no duplicate postings or incorrect stock."""

import threading
import uuid
from datetime import date
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool

from conftest import (
    TENANT_A,
    set_tenant,
)
from src.infrastructure.database.models import Invoice, Product, StockLedger

from seed import (
    seed_account,
    seed_contact,
    seed_product,
    seed_tenants,
    seed_warehouse,
)


@pytest.fixture()
def seeded(db_admin, engine_factories):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    product = seed_product(db_admin, TENANT_A, f"Conc Prod {token}", current_stock=Decimal("10.00"))
    warehouse = seed_warehouse(db_admin, TENANT_A, f"WH {token}")
    acc1 = seed_account(db_admin, TENANT_A, f"Bank {token}", f"10{token[:4]}", "ASSET")
    acc2 = seed_account(db_admin, TENANT_A, f"Rev {token}", f"40{token[:4]}", "REVENUE")
    db_admin.commit()
    return {
        "contact_a": contact_a,
        "product": product,
        "warehouse": warehouse,
        "acc1": acc1,
        "acc2": acc2,
        "engine": engine_factories["api"],
    }


def _run_threads(fn, count=8):
    """Run fn concurrently; unique-violation losers are expected and returned
    separately from unexpected errors."""
    barrier = threading.Barrier(count)
    committed = []
    unique_losers = []
    errors = []

    def worker(i):
        try:
            barrier.wait(timeout=10)
            outcome = fn(i)
            if outcome == "committed":
                committed.append(i)
            elif outcome == "unique-violation":
                unique_losers.append(i)
            else:
                errors.append((i, outcome))
        except Exception as exc:  # pragma: no cover - surfaced below
            errors.append((i, exc))

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(count)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)
    return {"committed": committed, "unique_losers": unique_losers, "errors": errors}


def _expect_exactly_one_winner(results, count):
    assert not results["errors"], f"unexpected thread errors: {results['errors'][:2]}"
    winners = len(results["committed"])
    assert winners == 1, f"expected exactly one winner, got {winners}"
    assert winners + len(results["unique_losers"]) == count


def test_concurrent_invoice_number_generation(seeded):
    """Concurrent inserts with the same active invoice number: exactly one wins."""
    session = __import__("sqlalchemy").orm.sessionmaker(bind=seeded["engine"])
    base = dict(
        tenant_id=TENANT_A,
        contact_id=seeded["contact_a"].id,
        invoice_number="INV-CONC-1",
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

    from sqlalchemy.exc import IntegrityError

    def try_insert(_i):
        s = session()
        try:
            set_tenant(s, TENANT_A)
            s.add(Invoice(**base))
            s.commit()
            return "committed"
        except IntegrityError:
            return "unique-violation"
        finally:
            s.rollback()
            s.close()

    results = _run_threads(try_insert, count=6)
    _expect_exactly_one_winner(results, 6)


def test_concurrent_posting_of_same_document(seeded):
    """Concurrent journal postings for the same source document: one wins."""
    source_id = uuid.uuid4()

    from sqlalchemy.exc import IntegrityError

    def post(_i):
        engine = seeded["engine"]
        conn = engine.connect()
        try:
            conn.execute(text("SET LOCAL app.current_tenant_id = :t"), {"t": str(TENANT_A)})
            entry_id = uuid.uuid4()
            conn.execute(
                text(
                    "INSERT INTO journal_entries "
                    "(id, tenant_id, entry_date, reference_number, source_type, source_id, description, is_locked) "
                    "VALUES (:id, :t, CURRENT_DATE, :ref, 'INVOICE', :sid, 'conc', true)"
                ),
                {"id": str(entry_id), "t": str(TENANT_A), "ref": f"JR-{uuid.uuid4().hex[:8]}", "sid": str(source_id)},
            )
            for account_id, direction in ((seeded["acc1"].id, "DEBIT"), (seeded["acc2"].id, "CREDIT")):
                conn.execute(
                    text(
                        "INSERT INTO journal_lines "
                        "(id, tenant_id, entry_id, account_id, amount, direction, narration) "
                        "VALUES (:id, :t, :eid, :aid, 100, :dir, 'x')"
                    ),
                    {"id": str(uuid.uuid4()), "t": str(TENANT_A), "eid": str(entry_id), "aid": str(account_id), "dir": direction},
                )
            conn.commit()
            return "committed"
        except IntegrityError:
            return "unique-violation"
        finally:
            conn.close()

    results = _run_threads(post, count=6)
    _expect_exactly_one_winner(results, 6)


def test_concurrent_stock_reduction_never_goes_negative(seeded, db_admin):
    """Row-locked stock reductions cannot drive stock below zero."""
    product_id = seeded["product"].id
    db_admin.execute(
        text("UPDATE products SET current_stock = 10 WHERE id = :id"),
        {"id": str(product_id)},
    )
    db_admin.commit()

    def reduce(_i):
        engine = seeded["engine"]
        conn = engine.connect()
        try:
            conn.execute(text("SET LOCAL app.current_tenant_id = :t"), {"t": str(TENANT_A)})
            # Lock the product row so reductions serialize.
            row = conn.execute(
                text("SELECT current_stock FROM products WHERE id = :id FOR UPDATE"),
                {"id": str(product_id)},
            ).mappings().first()
            available = Decimal(row["current_stock"] or 0)
            if available < Decimal("7"):
                conn.rollback()
                return "rejected"
            new_stock = available - Decimal("7")
            conn.execute(
                text("UPDATE products SET current_stock = :v WHERE id = :id"),
                {"v": new_stock, "id": str(product_id)},
            )
            conn.execute(
                text(
                    "INSERT INTO stock_ledger (id, tenant_id, product_id, warehouse_id, reference_type, "
                    "reference_id, quantity, balance_quantity, rate) "
                    "VALUES (:id, :t, :pid, :wid, 'SALE', :rid, -7, :bal, 0)"
                ),
                {
                    "id": str(uuid.uuid4()),
                    "t": str(TENANT_A),
                    "pid": str(product_id),
                    "wid": str(seeded["warehouse"].id),
                    "rid": str(uuid.uuid4()),
                    "bal": new_stock,
                },
            )
            conn.commit()
            return "reduced"
        finally:
            conn.close()

    results = _run_threads(reduce, count=6)
    reduced = [r for r in results["committed"]]
    final = db_admin.execute(
        text("SELECT current_stock FROM products WHERE id = :id"),
        {"id": str(product_id)},
    ).scalar()
    # 10 - 7*n serialized under the row lock; never negative.
    assert final >= 0, f"stock went negative: {final}"
    assert len(reduced) == 1, f"expected exactly one successful reduction, got {len(reduced)}"


def test_concurrent_payment_number_generation(seeded):
    session = __import__("sqlalchemy").orm.sessionmaker(bind=seeded["engine"])
    from src.infrastructure.database.models import Payment

    from sqlalchemy.exc import IntegrityError

    def try_insert(_i):
        s = session()
        try:
            set_tenant(s, TENANT_A)
            s.add(Payment(
                tenant_id=TENANT_A,
                contact_id=seeded["contact_a"].id,
                payment_number="PAY-CONC-1",
                payment_date=date.today(),
                payment_mode="BANK",
                amount=Decimal("10.00"),
                status="ACTIVE",
            ))
            s.commit()
            return "committed"
        except IntegrityError:
            return "unique-violation"
        finally:
            s.rollback()
            s.close()

    results = _run_threads(try_insert, count=6)
    _expect_exactly_one_winner(results, 6)
