"""Prevent duplicate inventory adjustment numbers.

Revision ID: 20260714_0006
Revises: 20260714_0005
"""
from alembic import op


revision = "20260714_0006"
down_revision = "20260714_0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.create_unique_constraint(
            "uq_inventory_adjustments_tenant_number",
            "inventory_adjustments",
            ["tenant_id", "adjustment_number"],
        )


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.drop_constraint(
            "uq_inventory_adjustments_tenant_number",
            "inventory_adjustments",
            type_="unique",
        )
