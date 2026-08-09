"""Apply current PostgreSQL RLS and accounting hardening to existing databases."""

from alembic import op

from src.core.postgres_hardening import apply_postgres_hardening


revision = "20260804_0001"
down_revision = "20260731_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    if connection.dialect.name != "postgresql":
        return

    # The old migration made every historical series unique. Keep only the
    # active-series index so deactivated series can remain as audit history.
    connection.exec_driver_sql(
        "ALTER TABLE numbering_series "
        "DROP CONSTRAINT IF EXISTS uq_numbering_series_tenant_doctype"
    )
    apply_postgres_hardening(connection)


def downgrade() -> None:
    # Hardening is intentionally retained on downgrade; removing tenant
    # isolation from a live database is unsafe.
    pass
