"""PostgreSQL-level immutability: raw SQL cannot mutate accounting history.

ORM listeners can be bypassed by raw SQL; these tests prove the database
itself refuses to change accounting facts through the normal application role.
The only permitted in-place changes are the explicitly scoped
reversal/correction linkage metadata, and the only permitted deletions are the
system-generated YEAR_END / OPENING_BALANCE roll-forward entries under the
tightly-scoped GUC set by the authorized reopen flow.
"""

import uuid
from decimal import Decimal

import pytest
from sqlalchemy import text

from conftest import set_tenant
from src.infrastructure.database.models import JournalEntry

from seed import (
    TENANT_A,
    seed_account,
    seed_contact,
    seed_journal_entry,
    seed_product,
    seed_stock_ledger,
    seed_tenants,
    seed_warehouse,
)


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact = seed_contact(db_admin, TENANT_A, f"Cust {token}")
    acc1 = seed_account(db_admin, TENANT_A, f"Bank {token}", f"10{token[:4]}", "ASSET")
    acc2 = seed_account(db_admin, TENANT_A, f"Rev {token}", f"40{token[:4]}", "REVENUE")
    entry = seed_journal_entry(db_admin, TENANT_A, acc1, acc2, "INVOICE", uuid.uuid4())
    product = seed_product(db_admin, TENANT_A, f"Prod {token}")
    warehouse = seed_warehouse(db_admin, TENANT_A, f"WH {token}")
    move = seed_stock_ledger(db_admin, TENANT_A, product, warehouse.id, Decimal("5"), Decimal("5"))
    db_admin.commit()
    return {"entry": entry, "move": move, "acc1": acc1, "acc2": acc2}


def _set_tenant_and_run(db, sql, params):
    set_tenant(db, TENANT_A)
    return db.execute(text(sql), params)


def test_journal_line_update_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    line_id = db_api.execute(
        text("SELECT id FROM journal_lines WHERE entry_id = :eid LIMIT 1"),
        {"eid": str(seeded["entry"].id)},
    ).scalar()
    with pytest.raises(Exception) as excinfo:
        _set_tenant_and_run(
            db_api,
            "UPDATE journal_lines SET amount = 999 WHERE id = :lid",
            {"lid": line_id},
        )
        db_api.commit()
    assert "append-only" in str(excinfo.value).lower() or "immutable" in str(excinfo.value).lower()


def test_journal_entry_financial_update_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        _set_tenant_and_run(
            db_api,
            "UPDATE journal_entries SET source_id = :sid WHERE id = :eid",
            {"sid": str(uuid.uuid4()), "eid": str(seeded["entry"].id)},
        )
        db_api.commit()
    assert "append-only" in str(excinfo.value).lower()


def test_journal_entry_lock_state_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception) as excinfo:
        _set_tenant_and_run(
            db_api,
            "UPDATE journal_entries SET is_locked = false WHERE id = :eid",
            {"eid": str(seeded["entry"].id)},
        )
        db_api.commit()
    assert "append-only" in str(excinfo.value).lower()


def test_journal_entry_reversal_metadata_allowed(db_api, seeded):
    """The explicitly scoped reversal/correction metadata MAY change."""
    set_tenant(db_api, TENANT_A)
    result = _set_tenant_and_run(
        db_api,
        "UPDATE journal_entries SET reversed_at = CURRENT_TIMESTAMP, reversed_by = :uid "
        "WHERE id = :eid",
        {"uid": str(uuid.uuid4()), "eid": str(seeded["entry"].id)},
    )
    db_api.commit()
    assert result.rowcount == 1


def test_stock_ledger_update_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    for column, value in (("quantity", -999), ("balance_quantity", 0), ("rate", 1000), ("product_id", str(uuid.uuid4()))):
        with pytest.raises(Exception, match=r"append-only|immutable"):
            _set_tenant_and_run(
                db_api,
                f"UPDATE stock_ledger SET {column} = :v WHERE id = :mid",
                {"v": value, "mid": str(seeded["move"].id)},
            )
            db_api.commit()
        db_api.rollback()


def test_stock_ledger_reversal_metadata_allowed(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    result = _set_tenant_and_run(
        db_api,
        "UPDATE stock_ledger SET reversed_at = CURRENT_TIMESTAMP, reversed_by = :uid "
        "WHERE id = :mid",
        {"uid": str(uuid.uuid4()), "mid": str(seeded["move"].id)},
    )
    db_api.commit()
    assert result.rowcount == 1


def test_stock_ledger_delete_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception, match=r"append-only|immutable"):
        _set_tenant_and_run(
            db_api,
            "DELETE FROM stock_ledger WHERE id = :mid",
            {"mid": str(seeded["move"].id)},
        )
        db_api.commit()
    db_api.rollback()


def test_journal_delete_rejected_without_scope(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception, match=r"append-only|scoped"):
        _set_tenant_and_run(
            db_api,
            "DELETE FROM journal_entries WHERE id = :eid",
            {"eid": str(seeded["entry"].id)},
        )
        db_api.commit()
    db_api.rollback()


def test_ordinary_journal_delete_rejected_even_with_scope(db_api, seeded):
    """Setting the roll-back GUC does NOT authorize deleting an INVOICE entry."""
    set_tenant(db_api, TENANT_A)
    db_api.execute(text("SET LOCAL app.allow_ledger_delete = 'YEAR_END'"))
    with pytest.raises(Exception, match=r"not eligible|append-only"):
        db_api.execute(
            text("DELETE FROM journal_entries WHERE id = :eid"),
            {"eid": str(seeded["entry"].id)},
        )
        db_api.commit()
    db_api.rollback()


def test_system_rollforward_delete_allowed_under_scope(db_api, seeded):
    """A system YEAR_END entry (and its lines) may be rolled back when the
    transaction-scoped GUC names that source type — exactly what the reopen
    flow does.  The delete must remove lines + entry in one transaction so
    the deferred balance check sees the entry disappear."""
    set_tenant(db_api, TENANT_A)
    acc1 = db_api.get(__import__("src.infrastructure.database.models", fromlist=["Account"]).Account, seeded["acc1"].id)
    acc2 = db_api.get(__import__("src.infrastructure.database.models", fromlist=["Account"]).Account, seeded["acc2"].id)
    from seed import seed_journal_entry
    year_end = seed_journal_entry(db_api, TENANT_A, acc1, acc2, "YEAR_END", uuid.uuid4())
    db_api.commit()
    year_end_id = year_end.id
    # Detach the object so the raw deletes below never touch the ORM identity
    # map (a reconciled/deleted persistent object would trigger lazy loads).
    db_api.expunge(year_end)

    db_api.execute(text("SET LOCAL app.allow_ledger_delete = 'YEAR_END,OPENING_BALANCE'"))
    db_api.execute(
        text("DELETE FROM journal_lines WHERE entry_id = :eid"),
        {"eid": str(year_end_id)},
    )
    db_api.execute(
        text("DELETE FROM journal_entries WHERE id = :eid"),
        {"eid": str(year_end_id)},
    )
    db_api.commit()
    assert db_api.execute(
        text("SELECT count(*) FROM journal_entries WHERE id = :eid"),
        {"eid": str(year_end_id)},
    ).scalar() == 0
    db_api.rollback()


def test_reopen_orm_flow_honors_db_triggers(db_api, db_admin, seeded):
    """The ORM reopen flow (system_ledger_rollback_scope) works against the
    database triggers: YEAR_END entries delete, ordinary entries do not."""
    from seed import seed_journal_entry as _seed_journal_entry
    acc1 = db_api.get(__import__("src.infrastructure.database.models", fromlist=["Account"]).Account, seeded["acc1"].id)
    acc2 = db_api.get(__import__("src.infrastructure.database.models", fromlist=["Account"]).Account, seeded["acc2"].id)
    set_tenant(db_api, TENANT_A)
    year_end = _seed_journal_entry(db_api, TENANT_A, acc1, acc2, "YEAR_END", uuid.uuid4())
    db_api.commit()

    from src.domains.accounting.ledger_guards import system_ledger_rollback_scope
    with system_ledger_rollback_scope(db_api):
        db_api.query(JournalEntry).filter(JournalEntry.id == year_end.id).delete()
        db_api.flush()
    db_api.expire_all()
    db_api.commit()
    assert db_api.query(JournalEntry).filter(JournalEntry.id == year_end.id).count() == 0

    # Ordinary entries are still protected even while a scope is active.
    from sqlalchemy.orm import Session
    db_api.rollback()
    with pytest.raises(Exception):
        with system_ledger_rollback_scope(db_api):
            db_api.query(JournalEntry).filter(JournalEntry.id == seeded["entry"].id).delete()
            db_api.flush()
        db_api.commit()
    db_api.rollback()
