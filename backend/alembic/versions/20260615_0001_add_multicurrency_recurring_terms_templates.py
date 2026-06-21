"""Add multi-currency, recurring invoices, terms templates, UPI QR, TDS/TCS, display settings.

Revision ID: 20260615_0001
Revises: 20260609_0002
Create Date: 2026-06-15
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql
from sqlalchemy import inspect

revision = "20260615_0001"
down_revision = "20260609_0002"
branch_labels = None
depends_on = None


def _column_exists(table: str, column: str) -> bool:
    conn = op.get_bind()
    inspector = inspect(conn)
    return column in {c["name"] for c in inspector.get_columns(table)}


def _table_exists(table: str) -> bool:
    conn = op.get_bind()
    inspector = inspect(conn)
    return table in inspector.get_table_names()


def upgrade() -> None:
    # ── Multi-currency on invoices ──
    if not _column_exists("invoices", "currency"):
        op.add_column("invoices", sa.Column("currency", sa.String(10), nullable=False, server_default="INR"))
    if not _column_exists("invoices", "exchange_rate"):
        op.add_column("invoices", sa.Column("exchange_rate", sa.Numeric(15, 6), nullable=False, server_default="1"))

    # ── TDS/TCS on invoices ──
    if not _column_exists("invoices", "tds_rate"):
        op.add_column("invoices", sa.Column("tds_rate", sa.Numeric(5, 2), nullable=False, server_default="0"))
    if not _column_exists("invoices", "tds_amount"):
        op.add_column("invoices", sa.Column("tds_amount", sa.Numeric(15, 4), nullable=False, server_default="0"))
    if not _column_exists("invoices", "tcs_rate"):
        op.add_column("invoices", sa.Column("tcs_rate", sa.Numeric(5, 2), nullable=False, server_default="0"))
    if not _column_exists("invoices", "tcs_amount"):
        op.add_column("invoices", sa.Column("tcs_amount", sa.Numeric(15, 4), nullable=False, server_default="0"))

    # ── UPI + display settings on tenant_settings ──
    if not _column_exists("tenant_settings", "upi_id"):
        op.add_column("tenant_settings", sa.Column("upi_id", sa.String(100), nullable=True))
    if not _column_exists("tenant_settings", "display_settings"):
        op.add_column("tenant_settings", sa.Column("display_settings", sa.JSON(), nullable=False, server_default="{}"))

    # ── Recurring invoices table ──
    if not _table_exists("recurring_invoices"):
        op.create_table(
            "recurring_invoices",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
            sa.Column("contact_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("contacts.id"), nullable=False),
            sa.Column("source_invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("invoices.id"), nullable=True),
            sa.Column("template_name", sa.String(150), nullable=False),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("frequency", sa.String(20), nullable=False, server_default="MONTHLY"),
            sa.Column("interval_count", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("next_date", sa.Date(), nullable=False),
            sa.Column("end_mode", sa.String(20), nullable=False, server_default="NEVER"),
            sa.Column("end_date", sa.Date(), nullable=True),
            sa.Column("max_occurrences", sa.Integer(), nullable=True),
            sa.Column("occurrences_created", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("last_generated", sa.Date(), nullable=True),
            sa.Column("currency", sa.String(10), nullable=False, server_default="INR"),
            sa.Column("exchange_rate", sa.Numeric(15, 6), nullable=False, server_default="1"),
            sa.Column("pos_state_code", sa.String(2), nullable=False),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("terms_and_conditions", sa.Text(), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.create_index("ix_recurring_invoices_tenant_active", "recurring_invoices", ["tenant_id", "is_active"])
        op.create_index("ix_recurring_invoices_next_date", "recurring_invoices", ["next_date"])

    # ── Recurring invoice items table ──
    if not _table_exists("recurring_invoice_items"):
        op.create_table(
            "recurring_invoice_items",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("recurring_invoice_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("recurring_invoices.id"), nullable=False),
            sa.Column("product_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("products.id"), nullable=True),
            sa.Column("description", sa.String(255), nullable=True),
            sa.Column("quantity", sa.Numeric(12, 4), nullable=False),
            sa.Column("rate", sa.Numeric(15, 4), nullable=False),
            sa.Column("discount", sa.Numeric(15, 4), nullable=False, server_default="0"),
            sa.Column("hsn_sac", sa.String(8), nullable=False),
            sa.Column("gst_rate", sa.Numeric(5, 2), nullable=False),
        )
        op.create_index("ix_recurring_invoice_items_template_id", "recurring_invoice_items", ["recurring_invoice_id"])

    # ── Terms templates table ──
    if not _table_exists("terms_templates"):
        op.create_table(
            "terms_templates",
            sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
            sa.Column("tenant_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("tenants.id"), nullable=True),
            sa.Column("name", sa.String(150), nullable=False),
            sa.Column("content", sa.Text(), nullable=False),
            sa.Column("is_preset", sa.Boolean(), nullable=False, server_default=sa.text("false")),
            sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        )
        op.create_index("ix_terms_templates_tenant", "terms_templates", ["tenant_id"])


def downgrade() -> None:
    op.drop_table("terms_templates")
    op.drop_table("recurring_invoice_items")
    op.drop_table("recurring_invoices")
    op.drop_column("tenant_settings", "display_settings")
    op.drop_column("tenant_settings", "upi_id")
    op.drop_column("invoices", "tcs_amount")
    op.drop_column("invoices", "tcs_rate")
    op.drop_column("invoices", "tds_amount")
    op.drop_column("invoices", "tds_rate")
    op.drop_column("invoices", "exchange_rate")
    op.drop_column("invoices", "currency")
