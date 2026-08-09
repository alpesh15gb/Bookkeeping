"""
src/core/idempotency.py
Crash-safe idempotency coordination.

The idempotency claim (status PROCESSING) is committed up front to protect
against concurrent duplicate requests.  The business transaction that performs
the financial mutation is a *separate* transaction, so the naive design leaves
a crash window: financial commit -> process dies -> response never stored ->
client retries -> mutation runs twice.

This module closes that window with an atomic marker: while a request owns an
in-flight idempotency claim, the first commit of any session in that request
flips the claim row from PROCESSING to COMMITTED *in the same transaction* as
the business mutation.  A retry that finds COMMITTED replays instead of
re-executing, so a duplicate invoice/payment/bill/journal/stock movement is
impossible once the financial transaction has committed — even if the API
process dies before sending its response.

If the claim row has vanished (e.g. a stale-timeout cleanup deleted it while
the original request was still running), the commit is aborted rather than
risking double execution.
"""

import contextvars
from typing import Any, Dict, Optional

from sqlalchemy import event, text
from sqlalchemy.orm import Session

# In-flight idempotency claim owned by the current request.  Set by the
# middleware before the endpoint runs; visible inside the endpoint because
# Starlette/anyio copy contextvars into the downstream task.
_inflight_claim: contextvars.ContextVar[Optional[Dict[str, Any]]] = (
    contextvars.ContextVar("idempotency_inflight_claim", default=None)
)


class IdempotencyClaimLostError(RuntimeError):
    """The claim row disappeared before the business commit could mark it."""


def set_inflight_claim(claim: Dict[str, Any]) -> contextvars.Token:
    return _inflight_claim.set(claim)


def clear_inflight_claim(token: contextvars.Token) -> None:
    _inflight_claim.reset(token)


def get_inflight_claim() -> Optional[Dict[str, Any]]:
    return _inflight_claim.get()


@event.listens_for(Session, "before_commit")
def _mark_idempotency_committed_atomically(session: Session) -> None:
    """Flip the claim to COMMITTED inside the business transaction.

    Runs on the first commit of any session while this request owns an
    in-flight claim.  Skipped on SQLite (unit-test convenience; PostgreSQL is
    the production enforcement point).
    """
    claim = _inflight_claim.get()
    if not claim:
        return
    if session.get_bind().dialect.name != "postgresql":
        return
    result = session.execute(
        text(
            "UPDATE idempotency_keys "
            "SET status = 'COMMITTED', is_processed = true "
            "WHERE idempotency_key = :key AND tenant_id = :tenant "
            "AND method = :method AND path = :path"
        ),
        {
            "key": claim["key"],
            "tenant": claim["tenant"],
            "method": claim["method"],
            "path": claim["path"],
        },
    )
    if result.rowcount == 0:
        raise IdempotencyClaimLostError(
            "Idempotency claim row is no longer present; aborting commit to "
            "prevent duplicate financial execution."
        )
