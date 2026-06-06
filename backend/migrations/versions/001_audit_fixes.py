"""Add new columns for audit findings fixes

Revision ID: 001_audit_fixes
Revises: 
Create Date: 2026-06-07

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '001_audit_fixes'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add supply_type to invoices (GST-3.9 Export/SEZ support)
    op.add_column('invoices', sa.Column('supply_type', sa.String(20), nullable=False, server_default='DOMESTIC'))
    
    # Add is_rcm to invoices (C8 RCM segregation)
    op.add_column('invoices', sa.Column('is_rcm', sa.Boolean(), nullable=False, server_default='0'))
    
    # Add itc_eligible to bills (C6 GSTR-3B ITC filter)
    op.add_column('bills', sa.Column('itc_eligible', sa.Boolean(), nullable=False, server_default='1'))
    
    # Create period_lock_audits table (FY-4.4)
    op.create_table('period_lock_audits',
        sa.Column('id', sa.UUID(), nullable=False),
        sa.Column('tenant_id', sa.UUID(), nullable=False),
        sa.Column('period_date', sa.Date(), nullable=False),
        sa.Column('action', sa.String(10), nullable=False),
        sa.Column('locked_by', sa.UUID(), nullable=False),
        sa.Column('locked_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('note', sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_pla_tenant_date', 'period_lock_audits', ['tenant_id', 'period_date'])


def downgrade() -> None:
    op.drop_index('ix_pla_tenant_date', table_name='period_lock_audits')
    op.drop_table('period_lock_audits')
    op.drop_column('bills', 'itc_eligible')
    op.drop_column('invoices', 'is_rcm')
    op.drop_column('invoices', 'supply_type')
