"""normalize status names and add payment status columns

Revision ID: 20260528_0006
Revises: 20260528_0005
Create Date: 2026-05-28

Standardizes the posted/finalized status to 'POSTED' across all document types:
  Invoice SENT -> POSTED
  Bill UNPAID -> POSTED
  CreditNote ISSUED -> POSTED
  DebitNote ISSUED -> POSTED

Also adds a real status column to Payment and BillPayment tables.
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260528_0006"
down_revision: Union[str, Sequence[str], None] = "20260528_0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()

    # 1. Drop old CHECK constraints
    for tbl in ["invoices", "bills", "expenses", "credit_notes", "debit_notes"]:
        try:
            conn.execute(sa.text(f"ALTER TABLE {tbl} DROP CONSTRAINT IF EXISTS ck_{tbl}_status"))
        except Exception:
            pass
        try:
            conn.execute(sa.text(f"ALTER TABLE {tbl} DROP CONSTRAINT IF EXISTS {tbl}_status_check"))
        except Exception:
            pass

    # 2. Update status values
    conn.execute(sa.text("UPDATE invoices SET status = 'POSTED' WHERE status = 'SENT'"))
    conn.execute(sa.text("UPDATE bills SET status = 'POSTED' WHERE status = 'UNPAID'"))
    conn.execute(sa.text("UPDATE credit_notes SET status = 'POSTED' WHERE status = 'ISSUED'"))
    conn.execute(sa.text("UPDATE debit_notes SET status = 'POSTED' WHERE status = 'ISSUED'"))

    # 3. Re-add CHECK constraints with normalized values
    conn.execute(sa.text(
        "ALTER TABLE invoices ADD CONSTRAINT ck_invoices_status "
        "CHECK (status IN ('DRAFT','POSTED','PARTIALLY_PAID','PAID','CANCELLED'))"
    ))
    conn.execute(sa.text(
        "ALTER TABLE bills ADD CONSTRAINT ck_bills_status "
        "CHECK (status IN ('DRAFT','POSTED','PARTIALLY_PAID','PAID','CANCELLED'))"
    ))
    conn.execute(sa.text(
        "ALTER TABLE expenses ADD CONSTRAINT ck_expenses_status "
        "CHECK (status IN ('DRAFT','POSTED','CANCELLED'))"
    ))
    conn.execute(sa.text(
        "ALTER TABLE credit_notes ADD CONSTRAINT ck_credit_notes_status "
        "CHECK (status IN ('DRAFT','POSTED','CANCELLED'))"
    ))
    conn.execute(sa.text(
        "ALTER TABLE debit_notes ADD CONSTRAINT ck_debit_notes_status "
        "CHECK (status IN ('DRAFT','POSTED','CANCELLED'))"
    ))

    # 4. Add status column to Payment and BillPayment tables
    try:
        op.add_column("payments", sa.Column("status", sa.String(20), nullable=False, server_default="ACTIVE"))
        conn.execute(sa.text(
            "ALTER TABLE payments ADD CONSTRAINT ck_payments_status "
            "CHECK (status IN ('ACTIVE','CANCELLED'))"
        ))
    except Exception:
        pass
    try:
        op.add_column("bill_payments", sa.Column("status", sa.String(20), nullable=False, server_default="ACTIVE"))
        conn.execute(sa.text(
            "ALTER TABLE bill_payments ADD CONSTRAINT ck_bill_payments_status "
            "CHECK (status IN ('ACTIVE','CANCELLED'))"
        ))
    except Exception:
        pass

    # 5. Sync payment status from deleted_at
    conn.execute(sa.text("UPDATE payments SET status = 'CANCELLED' WHERE deleted_at IS NOT NULL"))
    conn.execute(sa.text("UPDATE bill_payments SET status = 'CANCELLED' WHERE deleted_at IS NOT NULL"))


def downgrade() -> None:
    conn = op.get_bind()

    for tbl in ["invoices", "bills", "expenses", "credit_notes", "debit_notes"]:
        try:
            conn.execute(sa.text(f"ALTER TABLE {tbl} DROP CONSTRAINT IF EXISTS ck_{tbl}_status"))
        except Exception:
            pass

    conn.execute(sa.text("UPDATE invoices SET status = 'SENT' WHERE status = 'POSTED'"))
    conn.execute(sa.text("UPDATE bills SET status = 'UNPAID' WHERE status = 'POSTED'"))
    conn.execute(sa.text("UPDATE credit_notes SET status = 'ISSUED' WHERE status = 'POSTED'"))
    conn.execute(sa.text("UPDATE debit_notes SET status = 'ISSUED' WHERE status = 'POSTED'"))

    for tbl in ["payments", "bill_payments"]:
        try:
            conn.execute(sa.text(f"ALTER TABLE {tbl} DROP CONSTRAINT IF EXISTS ck_{tbl}_status"))
        except Exception:
            pass
    try:
        op.drop_column("payments", "status")
    except Exception:
        pass
    try:
        op.drop_column("bill_payments", "status")
    except Exception:
        pass
