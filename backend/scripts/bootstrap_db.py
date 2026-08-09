#!/usr/bin/env python3
"""Bootstrap the ApexBooks PostgreSQL application roles and privileges.

Idempotent.  Connect as a superuser (typically ``postgres``) and run:

    DATABASE_URL=postgresql://postgres:PASS@db:5432/bookkeeping \
    DB_MIGRATOR_PASSWORD=... DB_API_PASSWORD=... DB_WORKER_PASSWORD=... \
    python scripts/bootstrap_db.py

On a fresh docker-compose deployment this is unnecessary — the container's
``/docker-entrypoint-initdb.d/01-roles.sh`` runs automatically.  Use this
script for existing deployments (or after restoring a backup) so the API and
worker never connect as the PostgreSQL superuser.

Role model
----------
* apexbooks_migrator — Alembic only.  BYPASSRLS + CREATEDB, never used by the
  API or workers at runtime.
* apexbooks_api      — FastAPI traffic.  NO superuser / BYPASSRLS / CREATEDB /
  CREATEROLE; RLS fully enforced.
* apexbooks_worker   — Celery traffic.  Same restrictions as the API role.
"""

import os
import sys

from sqlalchemy import create_engine, text

REQUIRED_ENV = ("DB_MIGRATOR_PASSWORD", "DB_API_PASSWORD", "DB_WORKER_PASSWORD")


def main() -> int:
    for var in REQUIRED_ENV:
        if not os.getenv(var):
            print(f"bootstrap_db.py: {var} is not set", file=sys.stderr)
            return 1

    admin_url = os.getenv("DATABASE_URL")
    if not admin_url:
        print("bootstrap_db.py: DATABASE_URL (superuser) is not set", file=sys.stderr)
        return 1

    migrator_pw = os.getenv("DB_MIGRATOR_PASSWORD")
    api_pw = os.getenv("DB_API_PASSWORD")
    worker_pw = os.getenv("DB_WORKER_PASSWORD")

    engine = create_engine(admin_url)
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                DO $$
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_migrator') THEN
                        CREATE ROLE apexbooks_migrator LOGIN PASSWORD :migrator_pw
                            BYPASSRLS CREATEDB NOSUPERUSER NOCREATEROLE;
                    ELSE
                        ALTER ROLE apexbooks_migrator WITH LOGIN PASSWORD :migrator_pw
                            BYPASSRLS CREATEDB NOSUPERUSER NOCREATEROLE;
                    END IF;
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_api') THEN
                        CREATE ROLE apexbooks_api LOGIN PASSWORD :api_pw
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    ELSE
                        ALTER ROLE apexbooks_api WITH LOGIN PASSWORD :api_pw
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    END IF;
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_worker') THEN
                        CREATE ROLE apexbooks_worker LOGIN PASSWORD :worker_pw
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    ELSE
                        ALTER ROLE apexbooks_worker WITH LOGIN PASSWORD :worker_pw
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    END IF;
                END
                $$;
                """
            ),
            {
                "migrator_pw": migrator_pw,
                "api_pw": api_pw,
                "worker_pw": worker_pw,
            },
        )
        conn.execute(text("GRANT ALL ON SCHEMA public TO apexbooks_migrator"))
        conn.execute(text("GRANT USAGE ON SCHEMA public TO apexbooks_api, apexbooks_worker"))
        conn.execute(
            text(
                "ALTER DEFAULT PRIVILEGES FOR ROLE apexbooks_migrator IN SCHEMA public "
                "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO apexbooks_api, apexbooks_worker"
            )
        )
        conn.execute(
            text(
                "ALTER DEFAULT PRIVILEGES FOR ROLE apexbooks_migrator IN SCHEMA public "
                "GRANT USAGE ON SEQUENCES TO apexbooks_api, apexbooks_worker"
            )
        )
        conn.execute(
            text(
                "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public "
                "TO apexbooks_api, apexbooks_worker"
            )
        )
        conn.execute(
            text(
                "GRANT USAGE ON ALL SEQUENCES IN SCHEMA public "
                "TO apexbooks_api, apexbooks_worker"
            )
        )
        # ---- Least privilege (kept in sync with migration 20260811_0004) ----
        # audit_logs is append-only: the application never updates/deletes it.
        conn.execute(
            text(
                "REVOKE UPDATE, DELETE ON TABLE audit_logs "
                "FROM apexbooks_api, apexbooks_worker"
            )
        )
        # alembic_version is schema bookkeeping: the API only reads it for the
        # readiness probe and must never write it.
        conn.execute(
            text(
                "REVOKE INSERT, UPDATE, DELETE ON TABLE alembic_version "
                "FROM apexbooks_api, apexbooks_worker"
            )
        )
        # Security-sensitive tables: the CELERY WORKER never writes user,
        # membership or password-reset rows (it only reads the owner's email
        # via users/tenant_memberships), and never needs password-reset data
        # at all.  tenant_memberships is intentionally RLS-exempt, so its
        # access must be narrowed at the privilege layer.
        conn.execute(
            text(
                "REVOKE INSERT, UPDATE, DELETE ON TABLE users, tenant_memberships "
                "FROM apexbooks_worker"
            )
        )
        conn.execute(
            text(
                "REVOKE ALL ON TABLE password_reset_tokens "
                "FROM apexbooks_worker"
            )
        )
        # The controlled tenant enumerator is callable only by the restricted
        # application roles, never by arbitrary PUBLIC.
        conn.execute(
            text(
                "DO $$ "
                "BEGIN "
                "IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace "
                "          WHERE n.nspname = 'public' AND p.proname = 'apex_list_active_tenant_ids') THEN "
                "   REVOKE EXECUTE ON FUNCTION public.apex_list_active_tenant_ids() FROM PUBLIC; "
                "   GRANT EXECUTE ON FUNCTION public.apex_list_active_tenant_ids() "
                "       TO apexbooks_api, apexbooks_worker; "
                "END IF; "
                "END $$;"
            )
        )
    engine.dispose()
    print("bootstrap_db.py: roles and least-privilege grants applied.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
