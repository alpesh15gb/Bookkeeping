"""
src/domains/accounting/ledger_guards.py

The single, explicitly-scoped exception to the append-only ledger.

Journal entries and lines are immutable accounting history. The ONLY place in
the codebase permitted to delete them is the financial-year reopen flow, which
rolls back system-generated roll-forward entries (``YEAR_END`` closing and
``OPENING_BALANCE`` carry-forward) that the close flow itself created moments
earlier. Reopening is a permission-gated (``accounts:manage``), audited action
that already records actor + reason via ``_log_audit``.

That exception is exposed ONLY through :func:`system_ledger_rollback_scope`,
a context manager that:

* must be entered from inside the authorized service (never from a request
  parameter or client input);
* stores the authorization in the request-scoped SQLAlchemy ``session.info``
  (server-side execution context only);
* records the exact set of ``JournalEntry.source_type`` values eligible for
  deletion, so the DB guard can refuse anything else — normal invoice, bill,
  payment, manual-journal, expense, etc. history can never be deleted, even
  while the scope is active;
* always clears the flag in ``finally``, even when the flow raises.

The flag value is a frozenset of allowed source types, not a boolean, so a
future caller that merely sets ``session.info["ALLOW_LEDGER_DELETE"] = True``
(the naive misuse) is *rejected* by the guard in ``models.py``.
"""
from __future__ import annotations

from contextlib import contextmanager
from typing import Collection

from src.infrastructure.database.models import ALLOW_LEDGER_DELETE_KEY

# The only JournalEntry.source_type values that are system-generated during
# year-end close and legitimately rolled back by reopen. Anything else is
# real accounting history and must never be deletable.
SYSTEM_ROLLFORWARD_SOURCE_TYPES = frozenset({"YEAR_END", "OPENING_BALANCE"})


@contextmanager
def system_ledger_rollback_scope(
    db,
    source_types: Collection[str] = SYSTEM_ROLLFORWARD_SOURCE_TYPES,
):
    """Allow deletion of ONLY the given system-generated journal source types.

    Intended exclusively for the financial-year reopen service. The caller is
    responsible for having performed authorization (the reopen endpoint's
    ``enforce_permission("accounts:manage")`` dependency) and for recording an
    audit event (``_log_audit(..., "REOPENED", actor, reason)``).
    """
    allowed = frozenset(source_types)
    if not allowed <= SYSTEM_ROLLFORWARD_SOURCE_TYPES:
        raise ValueError(
            "system_ledger_rollback_scope may only authorize the system "
            "roll-forward source types; got %r" % (sorted(allowed),)
        )
    previous = db.info.get(ALLOW_LEDGER_DELETE_KEY)
    db.info[ALLOW_LEDGER_DELETE_KEY] = allowed
    # Mirror the authorization into the database: the PostgreSQL-level
    # immutability triggers (see postgres_hardening.py) refuse to delete
    # journal rows unless this transaction-scoped GUC lists the entry's
    # source_type.  SET LOCAL is transaction-scoped, so the authorization
    # dies with the transaction and can never leak into a pooled connection.
    # Skipped on SQLite (unit-test convenience; the triggers only exist on
    # PostgreSQL).
    is_postgresql = db.get_bind().dialect.name == "postgresql"
    if is_postgresql:
        from sqlalchemy import text
        db.execute(
            text("SET LOCAL app.allow_ledger_delete = :allowed"),
            {"allowed": ",".join(sorted(allowed))},
        )
    try:
        yield
    finally:
        if is_postgresql:
            db.execute(text("SET LOCAL app.allow_ledger_delete = ''"))
        if previous is None:
            db.info.pop(ALLOW_LEDGER_DELETE_KEY, None)
        else:
            db.info[ALLOW_LEDGER_DELETE_KEY] = previous
