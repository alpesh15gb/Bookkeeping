"""Add Contract v1 order lifecycle state, reservation movements, and audit.

Revision ID: 20260718_0004
Revises: 20260718_0003
"""

from alembic import op
import sqlalchemy as sa


revision = "20260718_0004"
down_revision = "20260718_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "integration_order_state",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("sales_order_id", sa.Uuid(), nullable=False),
        sa.Column("medusa_order_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_order_id", sa.String(150), nullable=False),
        sa.Column("medusa_customer_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_customer_id", sa.String(150), nullable=False),
        sa.Column("accounting_reference", sa.String(50), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("invoice_id", sa.Uuid(), nullable=True),
        sa.Column("apexbooks_invoice_id", sa.String(150), nullable=True),
        sa.Column("captured_amount_minor", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("refunded_amount_minor", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("commercial_snapshot", sa.JSON(), nullable=False),
        sa.Column("cancellation_reason_code", sa.String(30), nullable=True),
        sa.Column("cancellation_reason", sa.Text(), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("status IN ('DRAFT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')", name="ck_integration_order_status"),
        sa.ForeignKeyConstraint(["invoice_id"], ["invoices.id"]),
        sa.ForeignKeyConstraint(["sales_order_id"], ["sales_orders.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("sales_order_id", name="uq_integration_order_sales_order"),
        sa.UniqueConstraint("tenant_id", "apexbooks_order_id", name="uq_integration_order_apexbooks"),
        sa.UniqueConstraint("tenant_id", "medusa_order_id", name="uq_integration_order_medusa"),
    )
    op.create_index("ix_integration_order_tenant_status", "integration_order_state", ["tenant_id", "status"])

    op.create_table(
        "integration_inventory_movement",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("order_state_id", sa.Uuid(), nullable=False),
        sa.Column("sales_order_line_id", sa.Uuid(), nullable=False),
        sa.Column("variant_id", sa.Uuid(), nullable=False),
        sa.Column("warehouse_id", sa.String(150), nullable=False),
        sa.Column("movement_type", sa.String(30), nullable=False),
        sa.Column("quantity_delta", sa.Integer(), nullable=False),
        sa.Column("event_id", sa.String(100), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("movement_type IN ('RESERVATION', 'RESERVATION_RELEASE')", name="ck_integration_inventory_movement_type"),
        sa.CheckConstraint("quantity_delta != 0", name="ck_integration_inventory_movement_quantity"),
        sa.ForeignKeyConstraint(["order_state_id"], ["integration_order_state.id"]),
        sa.ForeignKeyConstraint(["variant_id"], ["integration_synced_product_variants.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_integration_inventory_movement_order", "integration_inventory_movement", ["tenant_id", "order_state_id"])
    op.create_index("ix_integration_inventory_movement_level", "integration_inventory_movement", ["tenant_id", "variant_id", "warehouse_id"])

    op.create_table(
        "integration_order_audit",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("event_name", sa.String(100), nullable=False),
        sa.Column("event_id", sa.String(100), nullable=False),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("medusa_order_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_order_id", sa.String(150), nullable=False),
        sa.Column("medusa_customer_id", sa.String(40), nullable=False),
        sa.Column("apexbooks_customer_id", sa.String(150), nullable=False),
        sa.Column("product_ids", sa.JSON(), nullable=False),
        sa.Column("old_values", sa.JSON(), nullable=True),
        sa.Column("new_values", sa.JSON(), nullable=False),
        sa.Column("execution_time_ms", sa.Integer(), nullable=False),
        sa.Column("result", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("result IN ('CREATED', 'UPDATED', 'CANCELLED')", name="ck_integration_order_audit_result"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_integration_order_audit_event", "integration_order_audit", ["tenant_id", "event_id"])
    op.create_index("ix_integration_order_audit_order", "integration_order_audit", ["tenant_id", "medusa_order_id"])


def downgrade() -> None:
    op.drop_index("ix_integration_order_audit_order", table_name="integration_order_audit")
    op.drop_index("ix_integration_order_audit_event", table_name="integration_order_audit")
    op.drop_table("integration_order_audit")
    op.drop_index("ix_integration_inventory_movement_level", table_name="integration_inventory_movement")
    op.drop_index("ix_integration_inventory_movement_order", table_name="integration_inventory_movement")
    op.drop_table("integration_inventory_movement")
    op.drop_index("ix_integration_order_tenant_status", table_name="integration_order_state")
    op.drop_table("integration_order_state")
