"""Add product barcodes and warehouse-aware stock movements.

Revision ID: 20260714_0007
Revises: 20260714_0006
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "20260714_0007"
down_revision = "20260714_0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    uuid_type = postgresql.UUID(as_uuid=True) if bind.dialect.name == "postgresql" else sa.String(36)

    op.add_column("products", sa.Column("barcode", sa.String(length=64), nullable=True))
    if bind.dialect.name == "postgresql":
        op.execute(sa.text("""
            WITH duplicates AS (
                SELECT id,
                       row_number() OVER (
                           PARTITION BY tenant_id, transfer_number
                           ORDER BY created_at, id
                       ) AS occurrence
                  FROM transfers
                 WHERE transfer_number IS NOT NULL
            )
            UPDATE transfers AS t
               SET transfer_number = left(t.transfer_number, 36) || '-DUP-' || left(t.id::text, 8)
              FROM duplicates AS d
             WHERE t.id = d.id
               AND d.occurrence > 1
        """))
    op.create_unique_constraint(
        "uq_transfers_tenant_number",
        "transfers",
        ["tenant_id", "transfer_number"],
    )
    op.add_column("stock_ledger", sa.Column("warehouse_id", uuid_type, nullable=True))
    op.create_foreign_key(
        "fk_stock_ledger_warehouse_id_branches",
        "stock_ledger",
        "branches",
        ["warehouse_id"],
        ["id"],
    )
    op.create_index(
        "ix_stock_ledger_tenant_warehouse_product",
        "stock_ledger",
        ["tenant_id", "warehouse_id", "product_id"],
    )

    if bind.dialect.name == "postgresql":
        op.create_index(
            "uq_products_tenant_barcode",
            "products",
            ["tenant_id", "barcode"],
            unique=True,
            postgresql_where=sa.text("barcode IS NOT NULL AND deleted_at IS NULL"),
        )
        # Existing unallocated movements belong to the company's first active
        # warehouse. This preserves total stock while making location balances
        # usable immediately after deployment.
        op.execute(sa.text("""
            UPDATE stock_ledger AS sl
               SET warehouse_id = (
                    SELECT b.id
                      FROM branches AS b
                     WHERE b.tenant_id = sl.tenant_id
                       AND b.deleted_at IS NULL
                       AND b.is_active = true
                     ORDER BY b.created_at, b.id
                     LIMIT 1
               )
             WHERE sl.warehouse_id IS NULL
               AND EXISTS (
                    SELECT 1
                      FROM branches AS b
                     WHERE b.tenant_id = sl.tenant_id
                       AND b.deleted_at IS NULL
                       AND b.is_active = true
               )
        """))
        # Older product creation stored opening/current stock only on Product.
        # Add one auditable reconciliation movement so the stock register and
        # warehouse views agree with the established product balance.
        op.execute(sa.text("""
            INSERT INTO stock_ledger (
                id, tenant_id, product_id, warehouse_id, quantity,
                balance_quantity, reference_type, reference_id, rate, created_at
            )
            SELECT md5(p.id::text || '-warehouse-reconcile')::uuid,
                   p.tenant_id,
                   p.id,
                   (
                       SELECT b.id
                         FROM branches AS b
                        WHERE b.tenant_id = p.tenant_id
                          AND b.deleted_at IS NULL
                          AND b.is_active = true
                        ORDER BY b.created_at, b.id
                        LIMIT 1
                   ),
                   coalesce(p.current_stock, 0) - coalesce(m.movement_total, 0),
                   coalesce(p.current_stock, 0),
                   'MIGRATION_RECONCILE',
                   p.id,
                   p.purchase_price,
                   now()
              FROM products AS p
              LEFT JOIN (
                    SELECT tenant_id, product_id, sum(quantity) AS movement_total
                      FROM stock_ledger
                     GROUP BY tenant_id, product_id
              ) AS m
                ON m.tenant_id = p.tenant_id
               AND m.product_id = p.id
             WHERE p.deleted_at IS NULL
               AND p.product_type = 'GOODS'
               AND abs(coalesce(p.current_stock, 0) - coalesce(m.movement_total, 0)) > 0.00005
        """))
    else:
        op.create_index(
            "uq_products_tenant_barcode",
            "products",
            ["tenant_id", "barcode"],
            unique=True,
        )


def downgrade() -> None:
    op.drop_index("uq_products_tenant_barcode", table_name="products")
    op.drop_index("ix_stock_ledger_tenant_warehouse_product", table_name="stock_ledger")
    op.drop_constraint(
        "fk_stock_ledger_warehouse_id_branches",
        "stock_ledger",
        type_="foreignkey",
    )
    op.drop_column("stock_ledger", "warehouse_id")
    op.drop_constraint("uq_transfers_tenant_number", "transfers", type_="unique")
    op.drop_column("products", "barcode")
