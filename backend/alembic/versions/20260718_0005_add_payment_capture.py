"""Add Contract v1 payment capture lifecycle state and audit.

Revision ID: 20260718_0005
Revises: 20260718_0004
"""

from alembic import op
import sqlalchemy as sa


revision = "20260718_0005"
down_revision = "20260718_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "integration_payment_state",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("order_state_id", sa.Uuid(), nullable=False),
        sa.Column("payment_id", sa.Uuid(), nullable=False),
        sa.Column("medusa_payment_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_payment_id", sa.String(150), nullable=False),
        sa.Column("receipt_id", sa.String(150), nullable=False),
        sa.Column("capture_sequence", sa.Integer(), nullable=False),
        sa.Column("currency_code", sa.String(3), nullable=False),
        sa.Column("amount_minor", sa.Integer(), nullable=False),
        sa.Column("provider_id", sa.String(100), nullable=False),
        sa.Column("transaction_id", sa.String(150), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("amount_minor > 0", name="ck_integration_payment_amount"),
        sa.CheckConstraint("status = 'CAPTURED'", name="ck_integration_payment_status"),
        sa.ForeignKeyConstraint(["order_state_id"], ["integration_order_state.id"]),
        sa.ForeignKeyConstraint(["payment_id"], ["payments.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("payment_id", name="uq_integration_payment_receipt"),
        sa.UniqueConstraint("tenant_id", "medusa_payment_id", name="uq_integration_payment_medusa"),
        sa.UniqueConstraint("tenant_id", "order_state_id", "capture_sequence", name="uq_integration_payment_sequence"),
        sa.UniqueConstraint("tenant_id", "provider_id", "transaction_id", name="uq_integration_payment_transaction"),
    )
    op.create_index("ix_integration_payment_order", "integration_payment_state", ["tenant_id", "order_state_id"])

    op.create_table(
        "integration_payment_inventory_movement",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("order_state_id", sa.Uuid(), nullable=False),
        sa.Column("payment_state_id", sa.Uuid(), nullable=False),
        sa.Column("variant_id", sa.Uuid(), nullable=False),
        sa.Column("warehouse_id", sa.String(150), nullable=False),
        sa.Column("movement_type", sa.String(20), nullable=False),
        sa.Column("quantity", sa.Integer(), nullable=False),
        sa.Column("available_before", sa.Integer(), nullable=False),
        sa.Column("available_after", sa.Integer(), nullable=False),
        sa.Column("reserved_before", sa.Integer(), nullable=False),
        sa.Column("reserved_after", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("movement_type = 'SALE_OUT'", name="ck_payment_inventory_type"),
        sa.CheckConstraint("quantity > 0", name="ck_payment_inventory_quantity"),
        sa.ForeignKeyConstraint(["order_state_id"], ["integration_order_state.id"]),
        sa.ForeignKeyConstraint(["payment_state_id"], ["integration_payment_state.id"]),
        sa.ForeignKeyConstraint(["variant_id"], ["integration_synced_product_variants.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_payment_inventory_order", "integration_payment_inventory_movement", ["tenant_id", "order_state_id"])
    op.create_index("ix_payment_inventory_level", "integration_payment_inventory_movement", ["tenant_id", "variant_id", "warehouse_id"])

    op.create_table(
        "integration_invoice_line_map",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("invoice_id", sa.Uuid(), nullable=False),
        sa.Column("invoice_line_id", sa.Uuid(), nullable=False),
        sa.Column("medusa_line_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_invoice_line_id", sa.String(150), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"]),
        sa.ForeignKeyConstraint(["invoice_line_id"], ["invoice_lines.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "apexbooks_invoice_line_id", name="uq_integration_invoice_line_apexbooks"),
        sa.UniqueConstraint("tenant_id", "invoice_id", "medusa_line_id", name="uq_integration_invoice_line_medusa"),
    )

    op.create_table(
        "integration_payment_audit",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("event_id", sa.String(100), nullable=False),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("medusa_payment_id", sa.String(40), nullable=False),
        sa.Column("medusa_order_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_payment_id", sa.String(150), nullable=False),
        sa.Column("apexbooks_invoice_id", sa.String(150), nullable=False),
        sa.Column("capture_sequence", sa.Integer(), nullable=False),
        sa.Column("amount_minor", sa.Integer(), nullable=False),
        sa.Column("old_values", sa.JSON(), nullable=False),
        sa.Column("new_values", sa.JSON(), nullable=False),
        sa.Column("execution_time_ms", sa.Integer(), nullable=False),
        sa.Column("result", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_integration_payment_audit_event", "integration_payment_audit", ["tenant_id", "event_id"])
    op.create_index("ix_integration_payment_audit_order", "integration_payment_audit", ["tenant_id", "medusa_order_id"])


def downgrade() -> None:
    op.drop_index("ix_integration_payment_audit_order", table_name="integration_payment_audit")
    op.drop_index("ix_integration_payment_audit_event", table_name="integration_payment_audit")
    op.drop_table("integration_payment_audit")
    op.drop_table("integration_invoice_line_map")
    op.drop_index("ix_payment_inventory_level", table_name="integration_payment_inventory_movement")
    op.drop_index("ix_payment_inventory_order", table_name="integration_payment_inventory_movement")
    op.drop_table("integration_payment_inventory_movement")
    op.drop_index("ix_integration_payment_order", table_name="integration_payment_state")
    op.drop_table("integration_payment_state")
