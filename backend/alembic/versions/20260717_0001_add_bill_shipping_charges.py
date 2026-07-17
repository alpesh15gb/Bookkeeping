"""Persist vendor-bill shipping charges.

Revision ID: 20260717_0001
Revises: 20260715_0001
"""
from alembic import op
import sqlalchemy as sa


revision = "20260717_0001"
down_revision = "20260715_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("bills") as batch_op:
        batch_op.add_column(sa.Column(
            "shipping_charges",
            sa.Numeric(15, 4),
            nullable=False,
            server_default="0",
        ))
        batch_op.drop_constraint("ck_bills_total_balance", type_="check")
        batch_op.create_check_constraint(
            "ck_bills_total_balance",
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + "
            "igst_amount + utgst_amount + cess_amount + round_off - "
            "discount_total + shipping_charges, 2)",
        )


def downgrade() -> None:
    with op.batch_alter_table("bills") as batch_op:
        batch_op.drop_constraint("ck_bills_total_balance", type_="check")
        batch_op.create_check_constraint(
            "ck_bills_total_balance",
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + "
            "igst_amount + utgst_amount + cess_amount + round_off - discount_total, 2)",
        )
        batch_op.drop_column("shipping_charges")
