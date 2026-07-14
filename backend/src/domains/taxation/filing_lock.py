"""GST filing immutability guards for outward-supply documents."""
from datetime import date
import uuid

from sqlalchemy.orm import Session

from src.infrastructure.database.models import GSTReturn


class GSTPeriodFiledError(ValueError):
    pass


def ensure_outward_period_mutable(
    db: Session,
    tenant_id: uuid.UUID,
    document_date: date,
) -> None:
    ensure_gst_period_mutable(db, tenant_id, document_date, ("GSTR1", "GSTR3B"))


def ensure_gst_period_mutable(
    db: Session,
    tenant_id: uuid.UUID,
    document_date: date,
    return_types: tuple[str, ...] = ("GSTR3B",),
) -> None:
    filed = db.query(GSTReturn.id).filter(
        GSTReturn.tenant_id == tenant_id,
        GSTReturn.return_type.in_(return_types),
        GSTReturn.status.in_(("FILED", "ACKNOWLEDGED")),
        GSTReturn.period_start <= document_date,
        GSTReturn.period_end >= document_date,
    ).first()
    if filed:
        raise GSTPeriodFiledError(
            "This document is included in a filed GST return. Record an adjustment in an open period instead."
        )
