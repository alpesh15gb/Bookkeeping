"""
src/core/posting_context.py

Authoritative source-channel for ledger postings.

Every journal entry records where it came from so the audit trail can answer
"how did this transaction get into the ledger?" The default is the REST API
(UI and direct API clients both arrive through it). Offline sync, batch
imports and recurring processes explicitly stamp their own channel on the
request's SQLAlchemy session.

Single mechanism: the channel lives in ``session.info["posting_channel"]``.
FastAPI resolves dependencies and runs sync endpoints in different
threads/contexts, so a plain contextvar set in a dependency is invisible in
the endpoint's thread — the session-scoped value survives that boundary and is
the one source of truth. When no channel was stamped (plain API requests) the
constant DEFAULT_CHANNEL ("API") applies.

The value is derived from backend context only — clients cannot influence it.
"""
from typing import Optional

DEFAULT_CHANNEL = "API"
VALID_CHANNELS = {"UI", "API", "IMPORT", "RECURRING", "SYNC"}

_SESSION_KEY = "posting_channel"


def _normalize(channel: str) -> str:
    normalized = channel.upper()
    return normalized if normalized in VALID_CHANNELS else DEFAULT_CHANNEL


def set_session_posting_channel(db, channel: str) -> None:
    """Stamp the source channel onto the SQLAlchemy session.

    Session-scoped state survives the threadpool boundary that separates
    FastAPI dependencies from sync endpoints, so this is the reliable way to
    mark postings from sync/import/recurring flows.
    """
    db.info[_SESSION_KEY] = _normalize(channel)


def get_posting_channel(db: Optional[object] = None) -> str:
    """Return the effective source channel for postings on this session.

    Prefers the session-stamped value (set by sync/import/recurring flows),
    otherwise the API default.
    """
    if db is not None:
        channel = db.info.get(_SESSION_KEY)
        if channel:
            return channel
    return DEFAULT_CHANNEL
