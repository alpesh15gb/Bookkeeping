"""Add goods receipt persistence.

Revision ID: 20260731_0002
Revises: 20260731_0001
"""

from alembic import op
import sqlalchemy as sa


revision = "20260731_0002"
down_revision = "20260731_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "goods_receipts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_order_id", sa.Uuid(), nullable=True),
        sa.Column("contact_id", sa.Uuid(), nullable=True),
        sa.Column("receipt_number", sa.String(50), nullable=False),
        sa.Column("receipt_date", sa.Date(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="DRAFT"),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "status IN ('DRAFT', 'CONFIRMED', 'CANCELLED')",
            name="ck_goods_receipts_status",
        ),
        sa.ForeignKeyConstraint(["contact_id"], ["contacts.id"]),
        sa.ForeignKeyConstraint(["purchase_order_id"], ["purchase_orders.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tenant_id",
            "receipt_number",
            name="uq_goods_receipts_tenant_number",
        ),
    )
    op.create_index(
        "ix_goods_receipts_tenant_date",
        "goods_receipts",
        ["tenant_id", "receipt_date"],
    )
    op.create_index(
        "ix_goods_receipts_tenant_status",
        "goods_receipts",
        ["tenant_id", "status"],
    )
    op.create_table(
        "goods_receipt_lines",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("goods_receipt_id", sa.Uuid(), nullable=False),
        sa.Column("purchase_order_line_id", sa.Uuid(), nullable=True),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("quantity_ordered", sa.Numeric(12, 4), nullable=False),
        sa.Column("quantity_received", sa.Numeric(12, 4), nullable=False),
        sa.Column("warehouse_id", sa.Uuid(), nullable=True),
        sa.Column("lot_number", sa.String(100), nullable=True),
        sa.Column("batch_number", sa.String(100), nullable=True),
        sa.ForeignKeyConstraint(
            ["goods_receipt_id"],
            ["goods_receipts.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["purchase_order_line_id"],
            ["purchase_order_lines.id"],
        ),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"]),
        sa.ForeignKeyConstraint(["warehouse_id"], ["branches.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_goods_receipt_lines_receipt",
        "goods_receipt_lines",
        ["goods_receipt_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_goods_receipt_lines_receipt",
        table_name="goods_receipt_lines",
    )
    op.drop_table("goods_receipt_lines")
    op.drop_index(
        "ix_goods_receipts_tenant_status",
        table_name="goods_receipts",
    )
    op.drop_index(
        "ix_goods_receipts_tenant_date",
        table_name="goods_receipts",
    )
    op.drop_table("goods_receipts")
