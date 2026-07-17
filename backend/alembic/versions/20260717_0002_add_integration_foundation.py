"""Add reusable integration foundation tables.

Revision ID: 20260717_0002
Revises: 20260717_0001
"""

from alembic import op
import sqlalchemy as sa


revision = "20260717_0002"
down_revision = "20260717_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "integration_connections",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("integration_name", sa.String(length=50), nullable=False),
        sa.Column("external_tenant_id", sa.String(length=100), nullable=False),
        sa.Column("api_key_prefix", sa.String(length=20), nullable=False),
        sa.Column("api_key_hash", sa.String(length=64), nullable=False),
        sa.Column("hmac_secret_encrypted", sa.Text(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="ENABLED"),
        sa.Column("clock_skew_seconds", sa.Integer(), nullable=False, server_default="300"),
        sa.Column("replay_retention_days", sa.Integer(), nullable=False, server_default="30"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("status IN ('ENABLED', 'DISABLED')", name="ck_integration_connections_status"),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "integration_name",
            "external_tenant_id",
            name="uq_integration_connection_external_tenant",
        ),
    )
    op.create_index("ix_integration_connections_api_key_hash", "integration_connections", ["api_key_hash"])
    op.create_index(
        "ix_integration_connections_tenant",
        "integration_connections",
        ["tenant_id", "integration_name"],
    )

    op.create_table(
        "integration_entity_map",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("integration_name", sa.String(length=50), nullable=False),
        sa.Column("entity_type", sa.String(length=50), nullable=False),
        sa.Column("external_id", sa.String(length=150), nullable=False),
        sa.Column("internal_id", sa.Uuid(), nullable=False),
        sa.Column("external_version", sa.String(length=100), nullable=True),
        sa.Column("sync_status", sa.String(length=20), nullable=False, server_default="PENDING"),
        sa.Column("last_synced_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "sync_status IN ('PENDING', 'SYNCED', 'FAILED', 'DISABLED')",
            name="ck_integration_entity_map_sync_status",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "integration_name",
            "entity_type",
            "external_id",
            name="uq_integration_entity_map_external",
        ),
        sa.UniqueConstraint(
            "tenant_id",
            "integration_name",
            "entity_type",
            "internal_id",
            name="uq_integration_entity_map_internal",
        ),
    )
    op.create_index(
        "ix_integration_entity_map_lookup",
        "integration_entity_map",
        ["tenant_id", "integration_name", "entity_type"],
    )

    op.create_table(
        "integration_event_log",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("request_id", sa.String(length=30), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=True),
        sa.Column("connection_id", sa.Uuid(), nullable=True),
        sa.Column("integration_name", sa.String(length=50), nullable=False),
        sa.Column("external_tenant_id", sa.String(length=100), nullable=True),
        sa.Column("direction", sa.String(length=10), nullable=False),
        sa.Column("method", sa.String(length=10), nullable=False),
        sa.Column("path", sa.String(length=500), nullable=False),
        sa.Column("event_id", sa.String(length=100), nullable=True),
        sa.Column("idempotency_key", sa.String(length=255), nullable=True),
        sa.Column("event_name", sa.String(length=100), nullable=True),
        sa.Column("source_id", sa.String(length=150), nullable=True),
        sa.Column("signature_hash", sa.String(length=64), nullable=True),
        sa.Column("payload_hash", sa.String(length=64), nullable=False),
        sa.Column("response_hash", sa.String(length=64), nullable=True),
        sa.Column("response_status", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("processing_time_ms", sa.Integer(), nullable=True),
        sa.Column("error_code", sa.String(length=50), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("direction IN ('INBOUND', 'OUTBOUND')", name="ck_integration_event_log_direction"),
        sa.CheckConstraint(
            "status IN ('PROCESSING', 'COMPLETED', 'REPLAYED', 'REJECTED', 'FAILED')",
            name="ck_integration_event_log_status",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("request_id", name="uq_integration_event_log_request_id"),
    )
    op.create_index(
        "ix_integration_event_log_tenant_event",
        "integration_event_log",
        ["tenant_id", "event_id"],
    )
    op.create_index(
        "ix_integration_event_log_status_created",
        "integration_event_log",
        ["status", "created_at"],
    )
    op.create_index(
        "ix_integration_event_log_idempotency",
        "integration_event_log",
        ["integration_name", "idempotency_key"],
    )

    op.create_table(
        "integration_replay_cache",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("connection_id", sa.Uuid(), nullable=False),
        sa.Column("integration_name", sa.String(length=50), nullable=False),
        sa.Column("event_id", sa.String(length=100), nullable=False),
        sa.Column("idempotency_key", sa.String(length=255), nullable=False),
        sa.Column("event_name", sa.String(length=100), nullable=False),
        sa.Column("source_id", sa.String(length=150), nullable=False),
        sa.Column("method", sa.String(length=10), nullable=False),
        sa.Column("path", sa.String(length=500), nullable=False),
        sa.Column("signature_hash", sa.String(length=64), nullable=False),
        sa.Column("request_hash", sa.String(length=64), nullable=False),
        sa.Column("response_hash", sa.String(length=64), nullable=True),
        sa.Column("response_status", sa.Integer(), nullable=True),
        sa.Column("response_body_encrypted", sa.Text(), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="PROCESSING"),
        sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("status IN ('PROCESSING', 'COMPLETED')", name="ck_integration_replay_status"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "integration_name",
            "event_id",
            name="uq_integration_replay_event",
        ),
        sa.UniqueConstraint(
            "tenant_id",
            "integration_name",
            "idempotency_key",
            name="uq_integration_replay_idempotency",
        ),
    )
    op.create_index("ix_integration_replay_expires", "integration_replay_cache", ["expires_at"])

    op.create_table(
        "integration_dead_letter",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("connection_id", sa.Uuid(), nullable=False),
        sa.Column("integration_name", sa.String(length=50), nullable=False),
        sa.Column("direction", sa.String(length=10), nullable=False),
        sa.Column("event_id", sa.String(length=100), nullable=True),
        sa.Column("event_name", sa.String(length=100), nullable=False),
        sa.Column("payload_encrypted", sa.Text(), nullable=False),
        sa.Column("payload_hash", sa.String(length=64), nullable=False),
        sa.Column("failure_code", sa.String(length=50), nullable=False),
        sa.Column("failure_message", sa.Text(), nullable=False),
        sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("next_retry_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="OPEN"),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("direction IN ('INBOUND', 'OUTBOUND')", name="ck_integration_dead_letter_direction"),
        sa.CheckConstraint(
            "status IN ('OPEN', 'RETRYING', 'RESOLVED', 'DISCARDED')",
            name="ck_integration_dead_letter_status",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_integration_dead_letter_status_created",
        "integration_dead_letter",
        ["status", "created_at"],
    )
    op.create_index(
        "ix_integration_dead_letter_tenant",
        "integration_dead_letter",
        ["tenant_id", "integration_name"],
    )


def downgrade() -> None:
    op.drop_index("ix_integration_dead_letter_tenant", table_name="integration_dead_letter")
    op.drop_index("ix_integration_dead_letter_status_created", table_name="integration_dead_letter")
    op.drop_table("integration_dead_letter")
    op.drop_index("ix_integration_replay_expires", table_name="integration_replay_cache")
    op.drop_table("integration_replay_cache")
    op.drop_index("ix_integration_event_log_idempotency", table_name="integration_event_log")
    op.drop_index("ix_integration_event_log_status_created", table_name="integration_event_log")
    op.drop_index("ix_integration_event_log_tenant_event", table_name="integration_event_log")
    op.drop_table("integration_event_log")
    op.drop_index("ix_integration_entity_map_lookup", table_name="integration_entity_map")
    op.drop_table("integration_entity_map")
    op.drop_index("ix_integration_connections_tenant", table_name="integration_connections")
    op.drop_index("ix_integration_connections_api_key_hash", table_name="integration_connections")
    op.drop_table("integration_connections")
