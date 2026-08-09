"""
Crash-safe idempotency coordination for financial mutations.

The middleware owns a PROCESSING claim in a separate transaction.  The
business transaction flips that claim to COMMITTED before its own commit, so a
response-loss retry can never execute the financial mutation twice.
"""

import contextvars
from typing import Any, Dict, Optional

from sqlalchemy import event, text
from sqlalchemy.orm import Session

_inflight_claim: contextvars.ContextVar[Optional[Dict[str, Any]]] = (
    contextvars.ContextVar("idempotency_inflight_claim", default=None)
)


class IdempotencyClaimLostError(RuntimeError):
    """The claim disappeared before the business transaction could commit."""


def set_inflight_claim(claim: Dict[str, Any]) -> contextvars.Token:
    return _inflight_claim.set(claim)


def clear_inflight_claim(token: contextvars.Token) -> None:
    _inflight_claim.reset(token)


def get_inflight_claim() -> Optional[Dict[str, Any]]:
    return _inflight_claim.get()


@event.listens_for(Session, "after_flush")
def _mark_idempotency_committed_atomically(session: Session, flush_context) -> None:
    """Mark the request committed inside the financial SQL transaction.

    A direct Edit may flush its reversal before its replacement exists.  Such
    handlers set ``_defer_idempotency_mark`` until the replacement is added;
    the replacement adapter then stores the preferred user-visible resource in
    ``_idempotency_resource``.  Ordinary creates retain the original behavior
    of selecting the first tenant-owned object from ``session.new``.
    """
    claim = _inflight_claim.get()
    if not claim:
        return
    if session.get_bind().dialect.name != "postgresql":
        return
    if session.info.get("_idem_marked"):
        return
    if session.info.get("_defer_idempotency_mark"):
        return

    resource_type = None
    resource_id = None
    preferred = session.info.get("_idempotency_resource")
    if preferred is not None and hasattr(preferred, "id"):
        pk = getattr(preferred, "id", None)
        if pk is not None:
            resource_type = type(preferred).__name__
            resource_id = str(pk)

    if resource_id is None:
        for obj in session.new:
            cls = type(obj)
            if cls.__name__ == "IdempotencyRecord":
                continue
            if hasattr(obj, "id") and hasattr(obj, "tenant_id"):
                pk = getattr(obj, "id", None)
                if pk is not None:
                    resource_type = cls.__name__
                    resource_id = str(pk)
                    break

    result = session.execute(
        text(
            "UPDATE idempotency_keys "
            "SET status='COMMITTED', is_processed=true, "
            "resource_type=COALESCE(:resource_type, resource_type), "
            "resource_id=COALESCE(CAST(:resource_id AS uuid), resource_id) "
            "WHERE idempotency_key=:key AND tenant_id=:tenant "
            "AND method=:method AND path=:path"
        ),
        {
            "key": claim["key"],
            "tenant": claim["tenant"],
            "method": claim["method"],
            "path": claim["path"],
            "resource_type": resource_type,
            "resource_id": resource_id,
        },
    )
    if result.rowcount == 0:
        raise IdempotencyClaimLostError(
            "Idempotency claim row is no longer present; aborting commit to "
            "prevent duplicate financial execution."
        )
    session.info["_idem_marked"] = True
