"""
src/common/audit_log.py
Audit log service for recording significant write operations.
"""
import contextvars
import logging
import threading
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Optional, Dict, Any
from sqlalchemy import event, inspect
from sqlalchemy.orm import Session as OrmSession
from sqlalchemy.orm import Session

from src.core.database import SessionLocal
from src.infrastructure.database.models import AuditLog

logger = logging.getLogger(__name__)

_audit_context: contextvars.ContextVar[Dict[str, Any]] = contextvars.ContextVar(
    "audit_context",
    default={},
)


def set_audit_context(
    *,
    tenant_id: uuid.UUID,
    actor_id: Optional[uuid.UUID],
    actor_email: Optional[str],
    ip_address: Optional[str],
    user_agent: Optional[str],
) -> None:
    _audit_context.set({
        "tenant_id": tenant_id,
        "actor_id": actor_id,
        "actor_email": actor_email,
        "ip_address": ip_address,
        "user_agent": user_agent,
    })


def _json_value(value: Any) -> Any:
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_value(val) for key, val in value.items()}
    if isinstance(value, list):
        return [_json_value(item) for item in value]
    return value


def serialize_model(obj: Any) -> Dict[str, Any]:
    mapper = inspect(obj).mapper
    return {
        column.key: _json_value(getattr(obj, column.key))
        for column in mapper.column_attrs
    }


def _entity_name(obj: Any) -> str:
    return obj.__class__.__name__


def _action_name(obj: Any, operation: str, before_state: Optional[Dict[str, Any]], after_state: Optional[Dict[str, Any]]) -> str:
    entity = _entity_name(obj)
    entity_key = "".join([f"_{char.lower()}" if char.isupper() else char for char in entity]).lstrip("_")

    if operation == "updated" and before_state and after_state:
        old_status = before_state.get("status")
        new_status = after_state.get("status")
        if entity == "Invoice" and old_status == "DRAFT" and new_status == "SENT":
            return "invoice.finalized"
        if new_status == "CANCELLED":
            return f"{entity_key}.cancelled"
        if entity in ("Bill", "CreditNote", "DebitNote") and old_status == "DRAFT" and new_status in ("UNPAID", "ISSUED"):
            return f"{entity_key}.finalized"

        old_e_invoice_status = before_state.get("e_invoice_status")
        new_e_invoice_status = after_state.get("e_invoice_status")
        if old_e_invoice_status != new_e_invoice_status and new_e_invoice_status:
            return f"invoice.e_invoice.{str(new_e_invoice_status).lower()}"

        if before_state.get("deleted_at") is None and after_state.get("deleted_at") is not None:
            return f"{entity_key}.cancelled"

    return f"{entity_key}.{operation}"


def _insert_audit_events(events: list[Dict[str, Any]]) -> None:
    if not events:
        return
    db = SessionLocal()
    try:
        db.add_all([AuditLog(**event) for event in events])
        db.commit()
    except Exception as exc:
        db.rollback()
        logger.warning("Audit log insert failed: %s", exc)
    finally:
        db.close()


def _queue_audit_events(events: list[Dict[str, Any]]) -> None:
    # Run synchronously in dev/test to avoid thread/session conflicts with SQLite
    from src.core.config import settings
    if settings.APP_ENV in ("development",):
        _insert_audit_events(events)
    else:
        thread = threading.Thread(target=_insert_audit_events, args=(events,), daemon=True)
        thread.start()


@event.listens_for(OrmSession, "before_flush")
def collect_audit_events(session: OrmSession, flush_context, instances):
    context = _audit_context.get()
    tenant_id = context.get("tenant_id")
    if not tenant_id:
        return

    events: list[Dict[str, Any]] = session.info.setdefault("audit_events", [])

    for obj in session.new:
        if isinstance(obj, AuditLog):
            continue
        if hasattr(obj, "id") and getattr(obj, "id") is None:
            setattr(obj, "id", uuid.uuid4())
        after_state = serialize_model(obj)
        events.append({
            **context,
            "action": _action_name(obj, "created", None, after_state),
            "entity_type": _entity_name(obj),
            "entity_id": getattr(obj, "id", None),
            "before_state": None,
            "after_state": after_state,
            "timestamp": datetime.now(timezone.utc),
        })

    for obj in session.dirty:
        if isinstance(obj, AuditLog) or not session.is_modified(obj, include_collections=False):
            continue
        state = inspect(obj)
        after_state = serialize_model(obj)
        before_state = dict(after_state)
        changed = False
        for attr in state.mapper.column_attrs:
            history = state.attrs[attr.key].history
            if history.has_changes():
                changed = True
                if history.deleted:
                    before_state[attr.key] = _json_value(history.deleted[0])
        if not changed:
            continue
        events.append({
            **context,
            "action": _action_name(obj, "updated", before_state, after_state),
            "entity_type": _entity_name(obj),
            "entity_id": getattr(obj, "id", None),
            "before_state": before_state,
            "after_state": after_state,
            "timestamp": datetime.now(timezone.utc),
        })

    for obj in session.deleted:
        if isinstance(obj, AuditLog):
            continue
        before_state = serialize_model(obj)
        events.append({
            **context,
            "action": _action_name(obj, "deleted", before_state, None),
            "entity_type": _entity_name(obj),
            "entity_id": getattr(obj, "id", None),
            "before_state": before_state,
            "after_state": None,
            "timestamp": datetime.now(timezone.utc),
        })


@event.listens_for(OrmSession, "after_commit")
def emit_audit_events(session: OrmSession):
    events = session.info.pop("audit_events", [])
    _queue_audit_events(events)


@event.listens_for(OrmSession, "after_rollback")
def discard_audit_events(session: OrmSession):
    session.info.pop("audit_events", None)


def log_event(
    db: Session,
    *,
    tenant_id: uuid.UUID,
    actor_id: Optional[uuid.UUID],
    actor_email: Optional[str],
    action: str,
    entity_type: str,
    entity_id: Optional[uuid.UUID] = None,
    before_state: Optional[Dict[str, Any]] = None,
    after_state: Optional[Dict[str, Any]] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> AuditLog:
    """Records an immutable audit log entry."""
    audit_entry = AuditLog(
        tenant_id=tenant_id,
        actor_id=actor_id,
        actor_email=actor_email,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_state=before_state,
        after_state=after_state,
        ip_address=ip_address,
        user_agent=user_agent,
        timestamp=datetime.now(timezone.utc),
    )
    db.add(audit_entry)
    db.commit()
    return audit_entry
