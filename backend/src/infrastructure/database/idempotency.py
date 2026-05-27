from sqlalchemy import Column, String, DateTime, Boolean, UUID, Index
from sqlalchemy.sql import func
import uuid

from src.core.database import Base


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (
        Index("ix_idempotency_created", "created_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    idempotency_key = Column(String(255), nullable=False)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    method = Column(String(10), nullable=False)
    path = Column(String(500), nullable=False)
    is_processed = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
