"""Add Phase 2 master-data synchronization projections and audit.

Revision ID: 20260718_0003
Revises: 20260717_0002
"""

from alembic import op
import sqlalchemy as sa


revision = "20260718_0003"
down_revision = "20260717_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "integration_synced_products",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("apexbooks_product_id", sa.String(150), nullable=False),
        sa.Column("medusa_product_id", sa.String(40), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("categories", sa.JSON(), nullable=False),
        sa.Column("images", sa.JSON(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("hsn_sac", sa.String(8), nullable=False),
        sa.Column("gst_rate_bps", sa.Integer(), nullable=False),
        sa.Column("source_updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "apexbooks_product_id", name="uq_synced_product_external"),
        sa.UniqueConstraint("tenant_id", "medusa_product_id", name="uq_synced_product_medusa"),
    )
    op.create_index("ix_synced_products_tenant", "integration_synced_products", ["tenant_id"])

    op.create_table(
        "integration_synced_product_variants",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("apexbooks_variant_id", sa.String(150), nullable=False),
        sa.Column("medusa_variant_id", sa.String(40), nullable=False),
        sa.Column("sku", sa.String(64), nullable=False),
        sa.Column("title", sa.String(150), nullable=False),
        sa.Column("product_type", sa.String(10), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(["product_id"], ["integration_synced_products.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "apexbooks_variant_id", name="uq_synced_variant_external"),
        sa.UniqueConstraint("tenant_id", "medusa_variant_id", name="uq_synced_variant_medusa"),
    )
    op.create_index("ix_synced_variants_product", "integration_synced_product_variants", ["product_id"])

    op.create_table(
        "integration_synced_prices",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("variant_id", sa.Uuid(), nullable=False),
        sa.Column("amount_minor", sa.Integer(), nullable=False),
        sa.Column("currency_code", sa.String(3), nullable=False),
        sa.Column("tax_inclusive", sa.Boolean(), nullable=False),
        sa.Column("price_list_id", sa.String(100), nullable=True),
        sa.Column("valid_from", sa.DateTime(timezone=True), nullable=True),
        sa.Column("valid_to", sa.DateTime(timezone=True), nullable=True),
        sa.Column("source_updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("amount_minor >= 0", name="ck_synced_price_amount"),
        sa.ForeignKeyConstraint(["product_id"], ["integration_synced_products.id"]),
        sa.ForeignKeyConstraint(["variant_id"], ["integration_synced_product_variants.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_synced_prices_product", "integration_synced_prices", ["tenant_id", "product_id"])

    op.create_table(
        "integration_synced_inventory_levels",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("product_id", sa.Uuid(), nullable=False),
        sa.Column("variant_id", sa.Uuid(), nullable=False),
        sa.Column("warehouse_id", sa.String(150), nullable=False),
        sa.Column("available_quantity", sa.Integer(), nullable=False),
        sa.Column("reserved_quantity", sa.Integer(), nullable=False),
        sa.Column("source_updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("available_quantity >= 0", name="ck_synced_inventory_available"),
        sa.CheckConstraint("reserved_quantity >= 0", name="ck_synced_inventory_reserved"),
        sa.ForeignKeyConstraint(["product_id"], ["integration_synced_products.id"]),
        sa.ForeignKeyConstraint(["variant_id"], ["integration_synced_product_variants.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "variant_id", "warehouse_id", name="uq_synced_inventory_scope"),
    )
    op.create_index("ix_synced_inventory_product", "integration_synced_inventory_levels", ["tenant_id", "product_id"])

    op.create_table(
        "integration_synced_customers",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("apexbooks_customer_id", sa.String(150), nullable=False),
        sa.Column("medusa_customer_id", sa.String(40), nullable=False),
        sa.Column("first_name", sa.String(75), nullable=False),
        sa.Column("last_name", sa.String(75), nullable=False),
        sa.Column("phone", sa.String(16), nullable=False),
        sa.Column("accounting_email", sa.String(255), nullable=False),
        sa.Column("gstin", sa.String(15), nullable=True),
        sa.Column("gst_type", sa.String(20), nullable=False),
        sa.Column("billing_address", sa.JSON(), nullable=False),
        sa.Column("shipping_address", sa.JSON(), nullable=False),
        sa.Column("state_code", sa.String(2), nullable=False),
        sa.Column("credit_terms_days", sa.Integer(), nullable=False),
        sa.Column("active", sa.Boolean(), nullable=False),
        sa.Column("source_updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("tenant_id", "apexbooks_customer_id", name="uq_synced_customer_external"),
        sa.UniqueConstraint("tenant_id", "medusa_customer_id", name="uq_synced_customer_medusa"),
    )
    op.create_index("ix_synced_customers_tenant", "integration_synced_customers", ["tenant_id"])

    op.create_table(
        "integration_master_sync_audit",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("tenant_id", sa.Uuid(), nullable=False),
        sa.Column("integration_name", sa.String(50), nullable=False),
        sa.Column("event_name", sa.String(100), nullable=False),
        sa.Column("event_id", sa.String(100), nullable=False),
        sa.Column("idempotency_key", sa.String(255), nullable=False),
        sa.Column("entity_type", sa.String(50), nullable=False),
        sa.Column("external_id", sa.String(150), nullable=False),
        sa.Column("old_values", sa.JSON(), nullable=True),
        sa.Column("new_values", sa.JSON(), nullable=False),
        sa.Column("processing_time_ms", sa.Integer(), nullable=False),
        sa.Column("result", sa.String(20), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("result IN ('CREATED', 'UPDATED')", name="ck_master_sync_audit_result"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_master_sync_audit_event", "integration_master_sync_audit", ["tenant_id", "event_id"])
    op.create_index("ix_master_sync_audit_entity", "integration_master_sync_audit", ["tenant_id", "entity_type", "external_id"])


def downgrade() -> None:
    op.drop_index("ix_master_sync_audit_entity", table_name="integration_master_sync_audit")
    op.drop_index("ix_master_sync_audit_event", table_name="integration_master_sync_audit")
    op.drop_table("integration_master_sync_audit")
    op.drop_index("ix_synced_customers_tenant", table_name="integration_synced_customers")
    op.drop_table("integration_synced_customers")
    op.drop_index("ix_synced_inventory_product", table_name="integration_synced_inventory_levels")
    op.drop_table("integration_synced_inventory_levels")
    op.drop_index("ix_synced_prices_product", table_name="integration_synced_prices")
    op.drop_table("integration_synced_prices")
    op.drop_index("ix_synced_variants_product", table_name="integration_synced_product_variants")
    op.drop_table("integration_synced_product_variants")
    op.drop_index("ix_synced_products_tenant", table_name="integration_synced_products")
    op.drop_table("integration_synced_products")
