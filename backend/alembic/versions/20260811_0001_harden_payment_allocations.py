"""Explicit tenant ownership + RLS for payment allocation join rows.

Revision ID: 20260811_0001_harden_payment_allocations
Revises: 20260811_0000_squashed_baseline
Create Date: 2026-08-11

payment_allocations (payments <-> invoices) and bill_payment_allocations
(bill_payments <-> bills) previously had NO tenant_id: a foreign key to a
tenant-owned parent provides no RLS protection, so the join rows themselves
were readable/writable by any tenant that knew a parent id.  This migration:

* adds tenant_id (backfilled from the payment / bill_payment side),
* makes it NOT NULL,
* enables RLS + FORCE RLS on both tables,
* adds a database trigger rejecting any allocation whose tenant does not
  match BOTH parents (payment/ bill_payment AND invoice/bill), so a
  cross-tenant allocation link is impossible even with raw SQL,
* adds an index on (tenant_id).

The backfill uses the payment side; if historical data ever contained a row
whose tenant cannot be resolved (orphaned payment FK) or a cross-tenant link
(allocation tenant does not match BOTH the payment and the invoice/bill),
the migration ABORTS and reports the offending row ids instead of silently
deleting or preserving inconsistent financial records.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy import text

from src.core.postgres_hardening import apply_postgres_hardening

revision = "20260811_0001_harden_payment_allocations"
down_revision = "20260811_0000_squashed_baseline"
branch_labels = None
depends_on = None


def _is_postgresql() -> bool:
    return op.get_bind().dialect.name == "postgresql"


def upgrade() -> None:
    if not _is_postgresql():
        return

    bind = op.get_bind()

    def column_exists(table: str, column: str) -> bool:
        return any(
            col["name"] == column
            for col in sa.inspect(bind).get_columns(table)
        )

    for table, payment_fk, document_fk in (
        ("payment_allocations", "payment_id", "invoice_id"),
        ("bill_payment_allocations", "payment_id", "bill_id"),
    ):
        quoted = f'"{table}"'
        if not column_exists(table, "tenant_id"):
            op.add_column(table, sa.Column("tenant_id", sa.UUID(as_uuid=True), nullable=True))
            # Backfill from the payment/bill_payment side (the allocating
            # entity) so every existing row gets a tenant before NOT NULL.
            op.execute(
                text(
                    f"UPDATE {quoted} a SET tenant_id = p.tenant_id "
                    f"FROM {_payment_table(table)} p "
                    f"WHERE a.{payment_fk} = p.id"
                )
            )
            # Rows that could not be backfilled are financial records with an
            # unresolvable owner.  NEVER delete them silently — abort and
            # report the offending ids so an operator can fix the data.
            orphaned = bind.execute(
                text(f"SELECT id FROM {quoted} WHERE tenant_id IS NULL ORDER BY id")
            ).scalars().all()
            if orphaned:
                raise RuntimeError(
                    f"ABORT: {len(orphaned)} {table} row(s) have no resolvable "
                    f"tenant (payment side missing). Fix or remove them first: "
                    f"{', '.join(str(i) for i in orphaned[:50])}"
                )
            # Cross-tenant historical links are also financial integrity
            # violations: the allocation's tenant must match BOTH the
            # payment AND the invoice/bill.  Report, do not silently keep.
            mismatched = bind.execute(
                text(
                    f"SELECT a.id FROM {quoted} a "
                    f"JOIN {_payment_table(table)} p ON p.id = a.{payment_fk} "
                    f"JOIN {_document_table(table)} d ON d.id = a.{document_fk} "
                    f"WHERE a.tenant_id <> p.tenant_id OR a.tenant_id <> d.tenant_id "
                    f"ORDER BY a.id"
                )
            ).scalars().all()
            if mismatched:
                raise RuntimeError(
                    f"ABORT: {len(mismatched)} {table} row(s) link a payment and "
                    f"document from DIFFERENT tenants. Fix them first: "
                    f"{', '.join(str(i) for i in mismatched[:50])}"
                )
            op.alter_column(
                table,
                "tenant_id",
                existing_type=sa.UUID(as_uuid=True),
                nullable=False,
            )
            op.create_index(
                f"ix_{table}_tenant",
                table,
                ["tenant_id"],
                if_not_exists=True,
            )

    # RLS policies + the two-parent tenant-match trigger (idempotent).
    apply_postgres_hardening(bind)


def _payment_table(table: str) -> str:
    return "payments" if table == "payment_allocations" else "bill_payments"


def _document_table(table: str) -> str:
    return "invoices" if table == "payment_allocations" else "bills"


def downgrade() -> None:
    if not _is_postgresql():
        return
    bind = op.get_bind()
    for table in ("payment_allocations", "bill_payment_allocations"):
        quoted = f'"{table}"'
        op.execute(text(f"DROP TRIGGER IF EXISTS ck_{table}_tenant_matches_parents ON {quoted}"))
        op.execute(text(f"DROP POLICY IF EXISTS tenant_isolation ON {quoted}"))
        op.execute(text(f"ALTER TABLE {quoted} NO FORCE ROW LEVEL SECURITY"))
        op.execute(text(f"ALTER TABLE {quoted} DISABLE ROW LEVEL SECURITY"))
        op.drop_index(f"ix_{table}_tenant", table_name=table)
        op.drop_column(table, "tenant_id")
    # Recreate the shared function only if the other allocation table still
    # exists with tenant_id (otherwise leave the function in place; it is
    # idempotent and harmless).
    bind = op.get_bind()
    try:
        apply_postgres_hardening(bind)
    except Exception:
        pass
