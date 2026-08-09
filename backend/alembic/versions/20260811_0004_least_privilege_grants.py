"""Least-privilege revocations for the restricted application roles.

Revision ID: 20260811_0004_least_privilege_grants
Revises: 20260811_0003_idempotency_resource_recovery
Create Date: 2026-08-11

The role bootstrap grants CRUD on all tables + USAGE/SELECT on all sequences
to apexbooks_api / apexbooks_worker.  This migration tightens that to
least privilege (mirrored in scripts/bootstrap_db.py, scripts/initdb_roles.sh
and the docker entrypoint):

* sequences      — USAGE only (nextval/currval/setval all work with USAGE;
                    SELECT on a sequence is never needed by the app).
* audit_logs     — no UPDATE/DELETE (immutable by trigger as well; this
                    removes even the attempt for raw SQL).
* alembic_version— SELECT only (the API health/readiness probe reads the
                    revision; it never writes schema bookkeeping).
* users / tenant_memberships / password_reset_tokens — the CELERY WORKER
                    gets no INSERT/UPDATE/DELETE on users and memberships
                    (it only reads the owner's email), and NO access at all to
                    password_reset_tokens.  tenant_memberships is deliberately
                    RLS-exempt, so its access is narrowed at the privilege
                    layer instead.

Revocations are applied when the roles exist (plain developer databases
without the role bootstrap are skipped).  The owner of the objects is the
migration role, so ownership-based REVOKE works here; superuser bootstrap
scripts re-apply the same policy on existing deployments.
"""

from alembic import op
from sqlalchemy import text

revision = "20260811_0004_least_privilege_grants"
down_revision = "20260811_0003_idempotency_resource_recovery"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    conn = bind
    for role in ("apexbooks_api", "apexbooks_worker"):
        conn.execute(
            text(
                "DO $$ "
                "BEGIN "
                "IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :role) THEN "
                "   EXECUTE format('REVOKE SELECT ON ALL SEQUENCES IN SCHEMA public FROM %I', :role); "
                "   EXECUTE format('REVOKE UPDATE, DELETE ON TABLE audit_logs FROM %I', :role); "
                "   EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON TABLE alembic_version FROM %I', :role); "
                "   EXECUTE format('REVOKE EXECUTE ON FUNCTION apex_list_active_tenant_ids() FROM PUBLIC'); "
                "   EXECUTE format('GRANT EXECUTE ON FUNCTION apex_list_active_tenant_ids() TO %I', :role); "
                "END IF; "
                "END $$;"
            ),
            {"role": role},
        )
        if role == "apexbooks_worker":
            conn.execute(
                text(
                    "DO $$ "
                    "BEGIN "
                    "IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_worker') THEN "
                    "   REVOKE INSERT, UPDATE, DELETE ON TABLE users, tenant_memberships "
                    "       FROM apexbooks_worker; "
                    "   REVOKE ALL ON TABLE password_reset_tokens FROM apexbooks_worker; "
                    "END IF; "
                    "END $$;"
                )
            )


def downgrade() -> None:
    """Re-grant the broad privileges (the bootstrap defaults)."""
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    conn = bind
    for role in ("apexbooks_api", "apexbooks_worker"):
        conn.execute(
            text(
                "DO $$ "
                "BEGIN "
                "IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :role) THEN "
                "   EXECUTE format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO %I', :role); "
                "   EXECUTE format('GRANT UPDATE, DELETE ON TABLE audit_logs TO %I', :role); "
                "   EXECUTE format('GRANT INSERT, UPDATE, DELETE ON TABLE alembic_version TO %I', :role); "
                "END IF; "
                "END $$;"
            ),
            {"role": role},
        )
