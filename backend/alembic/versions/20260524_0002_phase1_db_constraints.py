"""phase1 db constraints

Revision ID: 20260524_0002
Revises: 20260524_0001
Create Date: 2026-05-24

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = "20260524_0002"
down_revision: Union[str, Sequence[str], None] = "20260524_0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_unique_constraint("uq_tenants_gstin", "tenants", ["gstin"])
    op.create_unique_constraint("uq_invoices_irn", "invoices", ["irn"])

    op.create_check_constraint(
        "ck_invoices_status",
        "invoices",
        "status IN ('DRAFT', 'SENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
    )
    op.create_check_constraint(
        "ck_invoices_e_invoice_status",
        "invoices",
        "e_invoice_status IN ('PENDING', 'GENERATED', 'CANCELLED', 'FAILED')",
    )
    op.create_check_constraint(
        "ck_payments_payment_mode",
        "payments",
        "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'OTHER')",
    )
    op.create_check_constraint(
        "ck_bill_payments_payment_mode",
        "bill_payments",
        "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'OTHER')",
    )
    op.create_check_constraint(
        "ck_bills_status",
        "bills",
        "status IN ('DRAFT', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
    )
    op.create_check_constraint(
        "ck_journal_lines_direction",
        "journal_lines",
        "direction IN ('DEBIT', 'CREDIT')",
    )
    op.create_check_constraint(
        "ck_credit_notes_status",
        "credit_notes",
        "status IN ('DRAFT', 'ISSUED', 'CANCELLED')",
    )
    op.create_check_constraint(
        "ck_debit_notes_status",
        "debit_notes",
        "status IN ('DRAFT', 'ISSUED', 'CANCELLED')",
    )
    op.create_check_constraint(
        "ck_eway_bills_status",
        "eway_bills",
        "status IN ('GENERATED', 'CANCELLED')",
    )
    op.create_check_constraint(
        "ck_gst_returns_status",
        "gst_returns",
        "status IN ('COMPUTED', 'READY_TO_FILE', 'FILED', 'ACKNOWLEDGED')",
    )
    op.create_check_constraint(
        "ck_webhook_events_status",
        "webhook_events",
        "status IN ('PENDING', 'DELIVERED', 'FAILED')",
    )
    op.create_check_constraint(
        "ck_tenant_invitations_status",
        "tenant_invitations",
        "status IN ('PENDING', 'ACCEPTED', 'EXPIRED')",
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_constraint("ck_tenant_invitations_status", "tenant_invitations", type_="check")
    op.drop_constraint("ck_webhook_events_status", "webhook_events", type_="check")
    op.drop_constraint("ck_gst_returns_status", "gst_returns", type_="check")
    op.drop_constraint("ck_eway_bills_status", "eway_bills", type_="check")
    op.drop_constraint("ck_debit_notes_status", "debit_notes", type_="check")
    op.drop_constraint("ck_credit_notes_status", "credit_notes", type_="check")
    op.drop_constraint("ck_journal_lines_direction", "journal_lines", type_="check")
    op.drop_constraint("ck_bills_status", "bills", type_="check")
    op.drop_constraint("ck_bill_payments_payment_mode", "bill_payments", type_="check")
    op.drop_constraint("ck_payments_payment_mode", "payments", type_="check")
    op.drop_constraint("ck_invoices_e_invoice_status", "invoices", type_="check")
    op.drop_constraint("ck_invoices_status", "invoices", type_="check")

    op.drop_constraint("uq_invoices_irn", "invoices", type_="unique")
    op.drop_constraint("uq_tenants_gstin", "tenants", type_="unique")
