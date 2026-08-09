"""Add security and feature columns

Revision ID: 0001_security_features
Revises: 20260528_0008
Create Date: 2026-05-30
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = "20260530_0001"
down_revision: Union[str, Sequence[str], None] = "20260528_0008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # User security columns
    op.add_column("users", sa.Column("failed_login_attempts", sa.Integer(), nullable=False, server_default="0"))
    op.add_column("users", sa.Column("locked_until", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("email_verified", sa.Boolean(), nullable=False, server_default="false"))
    op.add_column("users", sa.Column("email_verify_token", sa.String(255), nullable=True))
    op.add_column("users", sa.Column("email_verify_expires", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("totp_secret", sa.String(32), nullable=True))
    op.add_column("users", sa.Column("totp_enabled", sa.Boolean(), nullable=False, server_default="false"))

    # Invoice shipping charges
    op.add_column("invoices", sa.Column("shipping_charges", sa.Numeric(15, 4), nullable=False, server_default="0"))

    # BankReconciliation tenant_id
    op.add_column("bank_reconciliations", sa.Column("tenant_id", sa.dialects.postgresql.UUID(), nullable=True))


def downgrade() -> None:
    op.drop_column("bank_reconciliations", "tenant_id")
    op.drop_column("invoices", "shipping_charges")
    op.drop_column("users", "totp_enabled")
    op.drop_column("users", "totp_secret")
    op.drop_column("users", "email_verify_expires")
    op.drop_column("users", "email_verify_token")
    op.drop_column("users", "email_verified")
    op.drop_column("users", "locked_until")
    op.drop_column("users", "failed_login_attempts")
