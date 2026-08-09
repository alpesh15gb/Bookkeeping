"""Add durable offline document-number allocations.

Revision ID: 20260731_0001
Revises: 20260725_0002
"""

from alembic import op
import sqlalchemy as sa


revision = "20260731_0001"
down_revision = "20260725_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "offline_number_allocations",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("device_id", sa.Uuid(), nullable=False),
        sa.Column("financial_year_id", sa.Uuid(), nullable=False),
        sa.Column("numbering_series_id", sa.Uuid(), nullable=False),
        sa.Column("document_type", sa.String(50), nullable=False),
        sa.Column("series", sa.String(50), nullable=False),
        sa.Column("prefix", sa.String(50), nullable=False, server_default=""),
        sa.Column("suffix", sa.String(50), nullable=True),
        sa.Column(
            "padding_digits",
            sa.Integer(),
            nullable=False,
            server_default="4",
        ),
        sa.Column("range_start", sa.Integer(), nullable=False),
        sa.Column("range_end", sa.Integer(), nullable=False),
        sa.Column(
            "allocated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
        sa.CheckConstraint(
            "range_start > 0 AND range_end >= range_start",
            name="ck_offline_number_allocation_range",
        ),
        sa.ForeignKeyConstraint(["numbering_series_id"], ["numbering_series.id"]),
        sa.ForeignKeyConstraint(["tenant_id"], ["tenants.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "document_type",
            "range_start",
            name="uq_offline_number_allocation_start",
        ),
    )
    op.create_index(
        "ix_offline_number_allocations_device",
        "offline_number_allocations",
        ["tenant_id", "device_id", "document_type"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_offline_number_allocations_device",
        table_name="offline_number_allocations",
    )
    op.drop_table("offline_number_allocations")
