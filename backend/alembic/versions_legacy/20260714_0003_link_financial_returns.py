"""Link sales and purchase returns to their source documents.

Revision ID: 20260714_0003
Revises: 20260714_0002
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa


revision = "20260714_0003"
down_revision = "20260714_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Existing unlinked returns remain readable for audit/history. New API
    # writes always supply these fields; nullable migration avoids inventing
    # source documents for historical financial records.
    op.add_column("sales_returns", sa.Column("invoice_id", sa.Uuid()))
    op.add_column("sales_return_lines", sa.Column("invoice_line_id", sa.Uuid()))
    op.add_column("purchase_returns", sa.Column("bill_id", sa.Uuid()))
    op.add_column("purchase_return_lines", sa.Column("bill_line_id", sa.Uuid()))
    op.create_index("ix_sales_returns_invoice", "sales_returns", ["tenant_id", "invoice_id"])
    op.create_index("ix_purchase_returns_bill", "purchase_returns", ["tenant_id", "bill_id"])
    if op.get_bind().dialect.name == "postgresql":
        op.create_foreign_key("fk_sales_returns_invoice", "sales_returns", "invoices", ["invoice_id"], ["id"])
        op.create_foreign_key("fk_sales_return_lines_invoice_line", "sales_return_lines", "invoice_lines", ["invoice_line_id"], ["id"])
        op.create_foreign_key("fk_purchase_returns_bill", "purchase_returns", "bills", ["bill_id"], ["id"])
        op.create_foreign_key("fk_purchase_return_lines_bill_line", "purchase_return_lines", "bill_lines", ["bill_line_id"], ["id"])


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.drop_constraint("fk_purchase_return_lines_bill_line", "purchase_return_lines", type_="foreignkey")
        op.drop_constraint("fk_purchase_returns_bill", "purchase_returns", type_="foreignkey")
        op.drop_constraint("fk_sales_return_lines_invoice_line", "sales_return_lines", type_="foreignkey")
        op.drop_constraint("fk_sales_returns_invoice", "sales_returns", type_="foreignkey")
    op.drop_index("ix_purchase_returns_bill", table_name="purchase_returns")
    op.drop_index("ix_sales_returns_invoice", table_name="sales_returns")
    op.drop_column("purchase_return_lines", "bill_line_id")
    op.drop_column("purchase_returns", "bill_id")
    op.drop_column("sales_return_lines", "invoice_line_id")
    op.drop_column("sales_returns", "invoice_id")
