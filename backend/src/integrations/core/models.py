from __future__ import annotations

import uuid

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID

from src.core.database import Base
from src.integrations.core.utils import (
    api_key_prefix,
    decrypt_text,
    encrypt_text,
    sha256_hex,
    utc_now,
)


class IntegrationConnection(Base):
    __tablename__ = "integration_connections"
    __table_args__ = (
        UniqueConstraint(
            "integration_name",
            "external_tenant_id",
            name="uq_integration_connection_external_tenant",
        ),
        Index("ix_integration_connections_api_key_hash", "api_key_hash"),
        Index("ix_integration_connections_tenant", "tenant_id", "integration_name"),
        CheckConstraint("status IN ('ENABLED', 'DISABLED')", name="ck_integration_connections_status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    integration_name = Column(String(50), nullable=False)
    external_tenant_id = Column(String(100), nullable=False)
    api_key_prefix = Column(String(20), nullable=False)
    api_key_hash = Column(String(64), nullable=False)
    hmac_secret_encrypted = Column(Text, nullable=False)
    status = Column(String(20), nullable=False, default="ENABLED")
    clock_skew_seconds = Column(Integer, nullable=False, default=300)
    replay_retention_days = Column(Integer, nullable=False, default=30)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)
    disabled_at = Column(DateTime(timezone=True))

    def set_api_key(self, api_key: str) -> None:
        if not 32 <= len(api_key) <= 256:
            raise ValueError("Integration API keys must contain 32 to 256 characters.")
        self.api_key_prefix = api_key_prefix(api_key)
        self.api_key_hash = sha256_hex(api_key)

    def matches_api_key(self, api_key: str) -> bool:
        import secrets

        return secrets.compare_digest(self.api_key_hash, sha256_hex(api_key))

    def set_hmac_secret(self, secret: str) -> None:
        if len(secret.encode("utf-8")) < 32:
            raise ValueError("Integration HMAC secrets must contain at least 256 bits.")
        self.hmac_secret_encrypted = encrypt_text(secret)

    def get_hmac_secret(self) -> str:
        return decrypt_text(self.hmac_secret_encrypted)


class IntegrationEntityMap(Base):
    __tablename__ = "integration_entity_map"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "integration_name",
            "entity_type",
            "external_id",
            name="uq_integration_entity_map_external",
        ),
        UniqueConstraint(
            "tenant_id",
            "integration_name",
            "entity_type",
            "internal_id",
            name="uq_integration_entity_map_internal",
        ),
        Index("ix_integration_entity_map_lookup", "tenant_id", "integration_name", "entity_type"),
        CheckConstraint(
            "sync_status IN ('PENDING', 'SYNCED', 'FAILED', 'DISABLED')",
            name="ck_integration_entity_map_sync_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    integration_name = Column(String(50), nullable=False)
    entity_type = Column(String(50), nullable=False)
    external_id = Column(String(150), nullable=False)
    internal_id = Column(UUID(as_uuid=True), nullable=False)
    external_version = Column(String(100))
    sync_status = Column(String(20), nullable=False, default="PENDING")
    last_synced_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)


class IntegrationEventLog(Base):
    __tablename__ = "integration_event_log"
    __table_args__ = (
        UniqueConstraint("request_id", name="uq_integration_event_log_request_id"),
        Index("ix_integration_event_log_tenant_event", "tenant_id", "event_id"),
        Index("ix_integration_event_log_status_created", "status", "created_at"),
        Index("ix_integration_event_log_idempotency", "integration_name", "idempotency_key"),
        CheckConstraint(
            "direction IN ('INBOUND', 'OUTBOUND')",
            name="ck_integration_event_log_direction",
        ),
        CheckConstraint(
            "status IN ('PROCESSING', 'COMPLETED', 'REPLAYED', 'REJECTED', 'FAILED')",
            name="ck_integration_event_log_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    request_id = Column(String(30), nullable=False)
    tenant_id = Column(UUID(as_uuid=True))
    connection_id = Column(UUID(as_uuid=True))
    integration_name = Column(String(50), nullable=False)
    external_tenant_id = Column(String(100))
    direction = Column(String(10), nullable=False)
    method = Column(String(10), nullable=False)
    path = Column(String(500), nullable=False)
    event_id = Column(String(100))
    idempotency_key = Column(String(255))
    event_name = Column(String(100))
    source_id = Column(String(150))
    signature_hash = Column(String(64))
    payload_hash = Column(String(64), nullable=False)
    response_hash = Column(String(64))
    response_status = Column(Integer)
    status = Column(String(20), nullable=False)
    processing_time_ms = Column(Integer)
    error_code = Column(String(50))
    started_at = Column(DateTime(timezone=True), nullable=False)
    processed_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class IntegrationReplayCache(Base):
    __tablename__ = "integration_replay_cache"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "integration_name",
            "event_id",
            name="uq_integration_replay_event",
        ),
        UniqueConstraint(
            "tenant_id",
            "integration_name",
            "idempotency_key",
            name="uq_integration_replay_idempotency",
        ),
        Index("ix_integration_replay_expires", "expires_at"),
        CheckConstraint(
            "status IN ('PROCESSING', 'COMPLETED')",
            name="ck_integration_replay_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    connection_id = Column(UUID(as_uuid=True), nullable=False)
    integration_name = Column(String(50), nullable=False)
    event_id = Column(String(100), nullable=False)
    idempotency_key = Column(String(255), nullable=False)
    event_name = Column(String(100), nullable=False)
    source_id = Column(String(150), nullable=False)
    method = Column(String(10), nullable=False)
    path = Column(String(500), nullable=False)
    signature_hash = Column(String(64), nullable=False)
    request_hash = Column(String(64), nullable=False)
    response_hash = Column(String(64))
    response_status = Column(Integer)
    response_body_encrypted = Column(Text)
    status = Column(String(20), nullable=False, default="PROCESSING")
    processed_at = Column(DateTime(timezone=True))
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)

    def set_response_body(self, body: str) -> None:
        self.response_body_encrypted = encrypt_text(body)

    def get_response_body(self) -> str | None:
        if self.response_body_encrypted is None:
            return None
        return decrypt_text(self.response_body_encrypted)


class IntegrationDeadLetter(Base):
    __tablename__ = "integration_dead_letter"
    __table_args__ = (
        Index("ix_integration_dead_letter_status_created", "status", "created_at"),
        Index("ix_integration_dead_letter_tenant", "tenant_id", "integration_name"),
        CheckConstraint(
            "direction IN ('INBOUND', 'OUTBOUND')",
            name="ck_integration_dead_letter_direction",
        ),
        CheckConstraint(
            "status IN ('OPEN', 'RETRYING', 'RESOLVED', 'DISCARDED')",
            name="ck_integration_dead_letter_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    connection_id = Column(UUID(as_uuid=True), nullable=False)
    integration_name = Column(String(50), nullable=False)
    direction = Column(String(10), nullable=False)
    event_id = Column(String(100))
    event_name = Column(String(100), nullable=False)
    payload_encrypted = Column(Text, nullable=False)
    payload_hash = Column(String(64), nullable=False)
    failure_code = Column(String(50), nullable=False)
    failure_message = Column(Text, nullable=False)
    retry_count = Column(Integer, nullable=False, default=0)
    next_retry_at = Column(DateTime(timezone=True))
    status = Column(String(20), nullable=False, default="OPEN")
    resolved_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)
