"""Add sync_events table for ApexBooks offline-first sync.

Revision ID: 20260725_0001
Revises: 20260718_0005
"""

from alembic import op
import sqlalchemy as sa


revision = "20260725_0001"
down_revision = "20260718_0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "sync_events",
        sa.Column("server_sequence", sa.BigInteger(), autoincrement=True, nullable=False),
        sa.Column("event_id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("company_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False),
        sa.Column("aggregate_type", sa.String(60), nullable=False),
        sa.Column("aggregate_id", sa.Uuid(), nullable=False),
        sa.Column("event_type", sa.String(100), nullable=False),
        sa.Column("event_version", sa.Integer(), nullable=False),
        sa.Column("payload", sa.JSON(), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
        sa.Column("processed", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("processing_error", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("server_sequence"),
        sa.UniqueConstraint("tenant_id", "event_id", name="uq_sync_event_tenant_event"),
    )
    op.create_index("ix_sync_pull", "sync_events", ["tenant_id", "server_sequence"])
    op.create_index("ix_sync_tenant_processed", "sync_events", ["tenant_id", "processed"])
    op.create_index("ix_sync_tenant_event_type", "sync_events", ["tenant_id", "event_type"])


def downgrade() -> None:
    op.drop_index("ix_sync_tenant_event_type", table_name="sync_events")
    op.drop_index("ix_sync_tenant_processed", table_name="sync_events")
    op.drop_index("ix_sync_pull", table_name="sync_events")
    op.drop_table("sync_events")
