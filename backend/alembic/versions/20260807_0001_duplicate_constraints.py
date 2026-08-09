"""Add partial unique constraints for active document numbers (invoices, bills, POs).

These constraints ensure uniqueness only among non-deleted (active) records,
allowing soft-deleted records to keep their numbers without blocking new ones.
"""

from alembic import op
import sqlalchemy as sa

revision = "20260807_0001"
down_revision = "20260804_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    dialect = connection.dialect.name

    # Tables that need active-number uniqueness
    tables = [
        ("invoices", "invoice_number", "uq_invoices_tenant_number_active"),
        ("bills", "bill_number", "uq_bills_tenant_number_active"),
        ("purchase_orders", "po_number", "uq_purchase_orders_po_number_active"),
        ("credit_notes", "credit_note_number", "uq_credit_notes_tenant_number_active"),
        ("debit_notes", "debit_note_number", "uq_debit_notes_tenant_number_active"),
        ("proforma_invoices", "proforma_number", "uq_proforma_invoices_tenant_number_active"),
        ("sales_orders", "so_number", "uq_sales_orders_tenant_number_active"),
        ("delivery_challans", "challan_number", "uq_delivery_challans_tenant_number_active"),
        ("goods_receipts", "receipt_number", "uq_goods_receipts_tenant_number_active"),
        ("sales_returns", "return_number", "uq_sales_returns_tenant_number_active"),
        ("purchase_returns", "return_number", "uq_purchase_returns_tenant_number_active"),
        ("payments", "payment_number", "uq_payments_tenant_number_active"),
        ("bill_payments", "payment_number", "uq_bill_payments_tenant_number_active"),
        ("expenses", "expense_number", "uq_expenses_tenant_number_active"),
        ("inventory_adjustments", "adjustment_number", "uq_inventory_adjustments_tenant_number_active"),
        ("transfers", "transfer_number", "uq_transfers_tenant_number_active"),
    ]

    if dialect == "postgresql":
        # Use partial unique indexes for PostgreSQL
        for table, col, idx_name in tables:
            op.execute(f"""
                CREATE UNIQUE INDEX IF NOT EXISTS {idx_name}
                ON {table} (tenant_id, {col})
                WHERE deleted_at IS NULL
            """)
    else:
        # For SQLite: Create a unique index on (tenant_id, document_number, is_deleted)
        # where is_deleted is derived from deleted_at IS NOT NULL
        # SQLite doesn't support functional indexes directly, so we add a computed
        # column `is_active` (boolean) and create a unique index on 
        # (tenant_id, document_number, is_active) with a partial filter.
        # Since SQLite doesn't support generated columns in older versions,
        # we add a simple boolean column `is_active` and update it via trigger.
        
        # For now, skip database-level constraints on SQLite and rely on
        # application-level checks. The database-level constraints are
        # primarily for PostgreSQL production environments.
        pass


def downgrade() -> None:
    connection = op.get_bind()
    dialect = connection.dialect.name

    if dialect == "postgresql":
        indexes_to_drop = [
            "uq_invoices_tenant_number_active",
            "uq_bills_tenant_number_active",
            "uq_purchase_orders_po_number_active",
            "uq_credit_notes_tenant_number_active",
            "uq_debit_notes_tenant_number_active",
            "uq_proforma_invoices_tenant_number_active",
            "uq_sales_orders_tenant_number_active",
            "uq_delivery_challans_tenant_number_active",
            "uq_goods_receipts_tenant_number_active",
            "uq_sales_returns_tenant_number_active",
            "uq_purchase_returns_tenant_number_active",
            "uq_payments_tenant_number_active",
            "uq_bill_payments_tenant_number_active",
            "uq_expenses_tenant_number_active",
            "uq_inventory_adjustments_tenant_number_active",
            "uq_transfers_tenant_number_active",
        ]

        for index_name in indexes_to_drop:
            op.execute(f"DROP INDEX IF EXISTS {index_name}")
    else:
        # Nothing to drop for SQLite since we didn't create constraints
        pass
