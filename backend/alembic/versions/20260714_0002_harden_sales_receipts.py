"""Harden customer receipt accounting invariants.

Revision ID: 20260714_0002
Revises: 20260714_0001
Create Date: 2026-07-14
"""
from alembic import op
import sqlalchemy as sa


revision = "20260714_0002"
down_revision = "20260714_0001"
branch_labels = None
depends_on = None


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def upgrade() -> None:
    op.add_column("payments", sa.Column("cancelled_at", sa.DateTime(timezone=True)))
    op.add_column("payments", sa.Column("cancellation_reason", sa.Text()))
    op.add_column("payments", sa.Column("advance_supply_type", sa.String(10)))
    op.create_index(
        "ix_payments_tenant_contact_date", "payments", ["tenant_id", "contact_id", "payment_date"]
    )
    op.create_index(
        "ix_payments_tenant_status_date", "payments", ["tenant_id", "status", "payment_date"]
    )
    op.add_column("invoices", sa.Column("source_document_type", sa.String(30)))
    op.add_column("invoices", sa.Column("source_document_id", sa.Uuid()))
    op.add_column("sales_orders", sa.Column("source_proforma_id", sa.Uuid()))
    op.add_column("sales_orders", sa.Column("converted_to_invoice_id", sa.Uuid()))
    op.add_column("delivery_challans", sa.Column("source_sales_order_id", sa.Uuid()))
    op.add_column("delivery_challans", sa.Column("converted_to_invoice_id", sa.Uuid()))
    op.add_column("proforma_invoices", sa.Column("converted_to_sales_order_id", sa.Uuid()))
    op.add_column("credit_notes", sa.Column("restock_items", sa.Boolean(), nullable=False, server_default=sa.true()))
    op.add_column("idempotency_keys", sa.Column("request_hash", sa.String(64)))
    op.add_column("idempotency_keys", sa.Column("status", sa.String(20), nullable=False, server_default="COMPLETED"))
    op.add_column("idempotency_keys", sa.Column("response_status", sa.Integer()))
    op.add_column("idempotency_keys", sa.Column("response_body", sa.Text()))
    op.add_column("idempotency_keys", sa.Column("response_content_type", sa.String(100)))
    if not _is_postgresql():
        return
    op.create_foreign_key("fk_sales_orders_source_proforma", "sales_orders", "proforma_invoices", ["source_proforma_id"], ["id"])
    op.create_foreign_key("fk_sales_orders_invoice", "sales_orders", "invoices", ["converted_to_invoice_id"], ["id"])
    op.create_foreign_key("fk_delivery_challans_sales_order", "delivery_challans", "sales_orders", ["source_sales_order_id"], ["id"])
    op.create_foreign_key("fk_delivery_challans_invoice", "delivery_challans", "invoices", ["converted_to_invoice_id"], ["id"])
    op.drop_constraint("ck_payments_payment_mode", "payments", type_="check")
    op.create_check_constraint(
        "ck_payments_payment_mode",
        "payments",
        "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'CHEQUE', 'NEFT_RTGS', 'OTHER')",
    )
    op.create_check_constraint("ck_payments_amount_positive", "payments", "amount > 0")
    op.create_check_constraint(
        "ck_payments_status", "payments", "status IN ('ACTIVE', 'CANCELLED')"
    )
    op.create_unique_constraint(
        "uq_payment_allocations_payment_invoice",
        "payment_allocations",
        ["payment_id", "invoice_id"],
    )
    op.create_check_constraint(
        "ck_invoices_amount_paid_nonnegative", "invoices", "amount_paid >= 0"
    )
    op.create_check_constraint(
        "ck_invoices_due_date", "invoices", "due_date >= issue_date"
    )
    op.create_unique_constraint(
        "uq_invoices_source_document", "invoices",
        ["tenant_id", "source_document_type", "source_document_id"],
    )


def downgrade() -> None:
    if _is_postgresql():
        op.drop_constraint("uq_invoices_source_document", "invoices", type_="unique")
        op.drop_constraint("ck_invoices_due_date", "invoices", type_="check")
        op.drop_constraint(
            "ck_invoices_amount_paid_nonnegative", "invoices", type_="check"
        )
        op.drop_constraint(
            "uq_payment_allocations_payment_invoice",
            "payment_allocations",
            type_="unique",
        )
        op.drop_constraint("ck_payments_status", "payments", type_="check")
        op.drop_constraint("ck_payments_amount_positive", "payments", type_="check")
        op.drop_constraint("ck_payments_payment_mode", "payments", type_="check")
        op.create_check_constraint(
            "ck_payments_payment_mode",
            "payments",
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'OTHER')",
        )
        op.drop_constraint("fk_delivery_challans_invoice", "delivery_challans", type_="foreignkey")
        op.drop_constraint("fk_delivery_challans_sales_order", "delivery_challans", type_="foreignkey")
        op.drop_constraint("fk_sales_orders_invoice", "sales_orders", type_="foreignkey")
        op.drop_constraint("fk_sales_orders_source_proforma", "sales_orders", type_="foreignkey")
    op.drop_column("proforma_invoices", "converted_to_sales_order_id")
    op.drop_column("idempotency_keys", "response_content_type")
    op.drop_column("idempotency_keys", "response_body")
    op.drop_column("idempotency_keys", "response_status")
    op.drop_column("idempotency_keys", "status")
    op.drop_column("idempotency_keys", "request_hash")
    op.drop_column("credit_notes", "restock_items")
    op.drop_column("delivery_challans", "converted_to_invoice_id")
    op.drop_column("delivery_challans", "source_sales_order_id")
    op.drop_column("sales_orders", "converted_to_invoice_id")
    op.drop_column("sales_orders", "source_proforma_id")
    op.drop_column("invoices", "source_document_id")
    op.drop_column("invoices", "source_document_type")
    op.drop_column("payments", "cancellation_reason")
    op.drop_index("ix_payments_tenant_status_date", table_name="payments")
    op.drop_index("ix_payments_tenant_contact_date", table_name="payments")
    op.drop_column("payments", "advance_supply_type")
    op.drop_column("payments", "cancelled_at")
