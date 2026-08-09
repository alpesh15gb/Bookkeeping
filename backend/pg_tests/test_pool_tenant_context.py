"""Connection-pool tenant-context isolation.

The application sets tenant context with ``SET LOCAL app.current_tenant_id``
— transaction-scoped by definition.  These tests prove that with a REAL
connection pool (QueuePool, connections reused), a tenant context set inside
one transaction can never be observed by the next user of the same physical
connection, and that concurrent pooled connections never see each other's
tenants.
"""

import threading
import uuid

import pytest
from sqlalchemy import create_engine, event, text
from sqlalchemy.pool import QueuePool

from conftest import TENANT_A, TENANT_B, set_tenant

from seed import (
    seed_contact,
    seed_invoice,
    seed_tenants,
)


@pytest.fixture()
def pooled(pg, db_admin):
    """An API-role engine with a REAL pool (connections reused)."""
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    contact_b = seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    inv_a_number = f"INV-A-{token}"
    inv_b_number = f"INV-B-{token}"
    seed_invoice(db_admin, TENANT_A, contact_a, inv_a_number)
    seed_invoice(db_admin, TENANT_B, contact_b, inv_b_number)
    db_admin.commit()

    engine = create_engine(
        pg["api_url"],
        poolclass=QueuePool,
        pool_size=1,
        max_overflow=0,
        pool_timeout=5,
    )
    created = {"count": 0}
    lock = threading.Lock()

    @event.listens_for(engine, "connect")
    def _count_connections(dbapi_conn, record):
        with lock:
            created["count"] += 1

    yield {"engine": engine, "created": created, "inv_a_number": inv_a_number, "inv_b_number": inv_b_number}
    engine.dispose()


def _count_by_number(conn, number):
    return conn.execute(
        text("SELECT count(*) FROM invoices WHERE invoice_number = :num"),
        {"num": number},
    ).scalar()


def _count_any_tenant_a(conn):
    return conn.execute(
        text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
        {"t": str(TENANT_A)},
    ).scalar()


def test_set_local_never_leaks_into_next_pooled_use(pooled):
    engine = pooled["engine"]
    num_a, num_b = pooled["inv_a_number"], pooled["inv_b_number"]

    # First user: tenant A context inside a transaction.
    with engine.connect() as conn:
        set_tenant(conn, TENANT_A)
        assert _count_by_number(conn, num_a) == 1
        assert _count_by_number(conn, num_b) == 0
        # commit ends the transaction; connection returns to the pool.

    # Second user (same physical connection, pool_size=1): no tenant context
    # set — must fail closed and see NOTHING, not tenant A's rows.
    with engine.connect() as conn:
        assert _count_any_tenant_a(conn) == 0, "tenant context leaked into the pooled connection"

    # Third user: sets tenant B, sees only B, commits.
    with engine.connect() as conn:
        set_tenant(conn, TENANT_B)
        assert _count_by_number(conn, num_b) == 1
        assert _count_by_number(conn, num_a) == 0

    # Fourth user: again no context — nothing leaks after tenant B either.
    with engine.connect() as conn:
        assert _count_any_tenant_a(conn) == 0
        assert _count_any_tenant_b(conn) == 0

    # Exactly ONE physical connection was ever opened (pool_size=1 reuse).
    assert pooled["created"]["count"] == 1


def test_rollback_does_not_leave_tenant_context(pooled):
    engine = pooled["engine"]
    with engine.connect() as conn:
        set_tenant(conn, TENANT_A)
        assert _count_by_number(conn, pooled["inv_a_number"]) == 1
        conn.rollback()  # aborted transaction; GUC dies with it
    with engine.connect() as conn:
        assert _count_any_tenant_a(conn) == 0


def _count_any_tenant_b(conn):
    return conn.execute(
        text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
        {"t": str(TENANT_B)},
    ).scalar()


def test_concurrent_pooled_connections_see_only_their_tenant(pg, db_admin):
    """Two pooled connections used simultaneously by different tenants never
    observe each other's rows — even though both share the pool."""
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    contact_b = seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    inv_a_number = f"INV-A-{token}"
    inv_b_number = f"INV-B-{token}"
    seed_invoice(db_admin, TENANT_A, contact_a, inv_a_number)
    seed_invoice(db_admin, TENANT_B, contact_b, inv_b_number)
    db_admin.commit()

    engine = create_engine(
        pg["api_url"],
        poolclass=QueuePool,
        pool_size=2,
        max_overflow=0,
        pool_timeout=5,
    )
    results = {}
    barrier = threading.Barrier(2)

    def tenant_worker(name, tenant_id, own_number, other_tenant):
        barrier.wait(timeout=10)
        with engine.connect() as conn:
            set_tenant(conn, tenant_id)
            own = _count_by_number(conn, own_number)
            other = conn.execute(
                text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
                {"t": str(other_tenant)},
            ).scalar()
            conn.rollback()
            results[name] = (own, other)

    threads = [
        threading.Thread(target=tenant_worker, args=("a", TENANT_A, inv_a_number, TENANT_B)),
        threading.Thread(target=tenant_worker, args=("b", TENANT_B, inv_b_number, TENANT_A)),
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=30)

    assert results["a"] == (1, 0), f"tenant A saw wrong rows: {results['a']}"
    assert results["b"] == (1, 0), f"tenant B saw wrong rows: {results['b']}"
    engine.dispose()


def test_pooled_connection_cannot_access_other_tenant_even_with_known_id(pooled):
    """Knowing another tenant's invoice id is useless: RLS still filters."""
    engine = pooled["engine"]
    other_id = None
    with engine.connect() as conn:
        set_tenant(conn, TENANT_B)
        other_id = conn.execute(
            text("SELECT id FROM invoices WHERE tenant_id = :t"),
            {"t": str(TENANT_B)},
        ).scalar()
        conn.commit()  # SET LOCAL dies with the transaction
    assert other_id is not None

    with engine.connect() as conn:
        set_tenant(conn, TENANT_A)
        seen = conn.execute(
            text("SELECT count(*) FROM invoices WHERE id = :iid"),
            {"iid": other_id},
        ).scalar()
        assert seen == 0
        conn.rollback()
