"""
Audit Log API Router
GET /api/v1/audit-logs — List audit log entries with pagination and filtering.
"""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
import uuid
from typing import Optional

from src.core.database import get_db_session
from src.infrastructure.database.models import AuditLog
from src.api.deps import enforce_permission

router = APIRouter(prefix="/audit-logs", tags=["Audit Logs"])


@router.get("")
def list_audit_logs(
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=50, ge=1, le=200),
    entity_type: Optional[str] = None,
    action: Optional[str] = None,
    actor_id: Optional[uuid.UUID] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("audit:view")),
):
    """Lists audit log entries for the active tenant with pagination."""
    offset = (page - 1) * limit
    q = db.query(AuditLog).filter(AuditLog.tenant_id == tenant_id)

    if entity_type:
        q = q.filter(AuditLog.entity_type == entity_type)
    if action:
        q = q.filter(AuditLog.action == action)
    if actor_id:
        q = q.filter(AuditLog.actor_id == actor_id)

    total = q.count()
    items = q.order_by(AuditLog.timestamp.desc()).offset(offset).limit(limit).all()

    return {"total": total, "page": page, "limit": limit, "items": items}
