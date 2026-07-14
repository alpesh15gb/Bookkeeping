from sqlalchemy import Column, String, DateTime, Boolean, UUID, Index, UniqueConstraint, Integer, Text
from sqlalchemy.sql import func
import uuid

from src.core.database import Base


class IdempotencyRecord(Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (
        UniqueConstraint("idempotency_key", "tenant_id", "method", "path", name="uq_idempotency_key_tenant_method_path"),
        Index("ix_idempotency_created", "created_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    idempotency_key = Column(String(255), nullable=False)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    method = Column(String(10), nullable=False)
    path = Column(String(500), nullable=False)
    is_processed = Column(Boolean, default=True)
    request_hash = Column(String(64))
    status = Column(String(20), nullable=False, default="PROCESSING")
    response_status = Column(Integer)
    response_body = Column(Text)
    response_content_type = Column(String(100))
    created_at = Column(DateTime(timezone=True), nullable=False, default=func.now())
