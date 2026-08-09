"""PostgreSQL-level immutability: raw SQL cannot mutate accounting history.

ORM listeners can be bypassed by raw SQL; these tests prove the database
itself refuses to change accounting facts through the normal application role.
The only permitted in-place changes are the explicitly scoped
reversal/correction linkage metadata.

Deletion is NEVER permitted — not for ordinary entries, not for system
YEAR_END / OPENING_BALANCE roll-forward entries, and not even when the
attacker sets ``app.allow_ledger_delete`` (there is deliberately no such
bypass; corrections and year-end reopen create reversal entries).
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


def test_journal_delete_rejected_always(db_api, seeded):
    """Ordinary entries can never be deleted, with or without any GUC."""
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception, match=r"append-only|never"):
        _set_tenant_and_run(
            db_api,
            "DELETE FROM journal_entries WHERE id = :eid",
            {"eid": str(seeded["entry"].id)},
        )
        db_api.commit()
    db_api.rollback()


def test_journal_lines_delete_rejected_always(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    line_id = db_api.execute(
        text("SELECT id FROM journal_lines WHERE entry_id = :eid LIMIT 1"),
        {"eid": str(seeded["entry"].id)},
    ).scalar()
    with pytest.raises(Exception, match=r"append-only|never"):
        _set_tenant_and_run(
            db_api,
            "DELETE FROM journal_lines WHERE id = :lid",
            {"lid": line_id},
        )
        db_api.commit()
    db_api.rollback()


def test_delete_rejected_even_with_forged_guc(db_api, seeded):
    """An attacker who sets ``app.allow_ledger_delete`` can still never delete
    ledger rows: there is no client-settable bypass at the database."""
    set_tenant(db_api, TENANT_A)
    acc1 = db_api.get(__import__("src.infrastructure.database.models", fromlist=["Account"]).Account, seeded["acc1"].id)
    acc2 = db_api.get(__import__("src.infrastructure.database.models", fromlist=["Account"]).Account, seeded["acc2"].id)
    from seed import seed_journal_entry
    year_end = seed_journal_entry(db_api, TENANT_A, acc1, acc2, "YEAR_END", uuid.uuid4())
    # Capture ids BEFORE the commit: SQLAlchemy expires even primary keys on
    # commit, and refreshing them without a live tenant context is invisible
    # to RLS.  Work with plain id strings from here on.
    invoice_entry_id = str(seeded["entry"].id)
    year_end_id = str(year_end.id)
    db_api.commit()
    db_api.expunge(year_end)

    def _forge_guc_and_delete(sql, params):
        # SET LOCAL is transaction-scoped: tenant context + the forged GUC
        # must live in the SAME transaction as the DELETE or RLS hides the
        # row and the trigger never fires.
        set_tenant(db_api, TENANT_A)
        db_api.execute(
            text("SET LOCAL app.allow_ledger_delete = 'INVOICE,YEAR_END,OPENING_BALANCE'")
        )
        with pytest.raises(Exception, match=r"append-only|never"):
            db_api.execute(text(sql), params)
            db_api.commit()
        db_api.rollback()

    # INVOICE entry, YEAR_END entry, and YEAR_END lines — all undeletable
    # even with the GUC naming their exact source types.
    _forge_guc_and_delete(
        "DELETE FROM journal_entries WHERE id = :eid",
        {"eid": invoice_entry_id},
    )
    _forge_guc_and_delete(
        "DELETE FROM journal_entries WHERE id = :eid",
        {"eid": year_end_id},
    )
    _forge_guc_and_delete(
        "DELETE FROM journal_lines WHERE entry_id = :eid",
        {"eid": year_end_id},
    )


def test_reopen_reversal_flow_works_against_db_triggers(db_api, seeded):
    """The append-only reopen strategy — post a reversal entry and mark the
    original reversed — works against the database triggers: the original is
    preserved, the reversal balances, and the original still cannot be
    deleted."""
    from datetime import datetime, timezone
    from src.infrastructure.database.models import JournalEntry, JournalLine

    from src.infrastructure.database.models import Account as _Account
    set_tenant(db_api, TENANT_A)
    acc1 = db_api.get(_Account, seeded["acc1"].id)
    acc2 = db_api.get(_Account, seeded["acc2"].id)
    from seed import seed_journal_entry
    year_end = seed_journal_entry(db_api, TENANT_A, acc1, acc2, "YEAR_END", uuid.uuid4())
    # Capture the id before commit (SQLAlchemy expires even PKs on commit,
    # and a refresh without live tenant context is RLS-invisible).
    original_id = year_end.id
    db_api.commit()
    # SET LOCAL tenant context dies with the committed transaction; re-apply
    # it so the ORM refresh after commit (expire_on_commit) is RLS-visible.
    set_tenant(db_api, TENANT_A)

    original = db_api.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    reversal = JournalEntry(
        tenant_id=TENANT_A,
        entry_date=original.entry_date,
        reference_number=f"REV-{original.reference_number}",
        description=f"Reversal of {original.reference_number}",
        source_type="YEAR_END_REVERSAL",
        source_id=original.id,
        is_locked=True,
        reverses_transaction_id=original.id,
        lines=[
            JournalLine(
                tenant_id=TENANT_A,
                account_id=line.account_id,
                amount=line.amount,
                direction="CREDIT" if line.direction == "DEBIT" else "DEBIT",
                narration="Reversal",
            )
            for line in original.lines
        ],
    )
    db_api.add(reversal)
    db_api.flush()
    original.reversed_by = uuid.uuid4()
    original.reversed_at = datetime.now(timezone.utc)
    original.reversal_transaction_id = reversal.id
    db_api.commit()
    set_tenant(db_api, TENANT_A)

    # Original preserved + marked reversed; reversal present and balanced.
    reloaded = db_api.query(JournalEntry).filter(JournalEntry.id == original_id).one()
    assert reloaded.reversal_transaction_id == reversal.id
    assert db_api.query(JournalEntry).filter(JournalEntry.id == reversal.id).count() == 1
    dr = db_api.execute(
        text("SELECT COALESCE(sum(amount) FILTER (WHERE direction='DEBIT'),0) "
             "FROM journal_lines WHERE entry_id = :rid"),
        {"rid": str(reversal.id)},
    ).scalar()
    cr = db_api.execute(
        text("SELECT COALESCE(sum(amount) FILTER (WHERE direction='CREDIT'),0) "
             "FROM journal_lines WHERE entry_id = :rid"),
        {"rid": str(reversal.id)},
    ).scalar()
    assert dr == cr

    # The original is still undeletable even now that it is reversed.
    with pytest.raises(Exception, match=r"append-only|never"):
        _set_tenant_and_run(
            db_api,
            "DELETE FROM journal_entries WHERE id = :eid",
            {"eid": str(original_id)},
        )
        db_api.commit()
    db_api.rollback()
