#!/bin/sh
# Creates the PostgreSQL application roles and grants for ApexBooks.
#
# Mounted at /docker-entrypoint-initdb.d/01-roles.sh in docker-compose, this
# runs as the bootstrap superuser on the FIRST initialization of the data
# volume only.  For existing deployments, run scripts/bootstrap_db.py instead.
#
# Role model:
#   apexbooks_migrator — runs Alembic.  BYPASSRLS (migrations backfill across
#       tenants) + CREATEDB (CI/test database creation).  NEVER used by the
#       API or workers at runtime.
#   apexbooks_api      — FastAPI application traffic.  No superuser, no
#       BYPASSRLS, no CREATEDB, no CREATEROLE.  RLS fully enforced.
#   apexbooks_worker   — Celery worker traffic.  Same restrictions as API.
#
# Passwords come from the container environment (DB_MIGRATOR_PASSWORD,
# DB_API_PASSWORD, DB_WORKER_PASSWORD).

set -e

MIGRATOR_PASSWORD="${DB_MIGRATOR_PASSWORD:-}"
API_PASSWORD="${DB_API_PASSWORD:-}"
WORKER_PASSWORD="${DB_WORKER_PASSWORD:-}"

if [ -z "$MIGRATOR_PASSWORD" ] || [ -z "$API_PASSWORD" ] || [ -z "$WORKER_PASSWORD" ]; then
    echo "initdb_roles.sh: DB_MIGRATOR_PASSWORD, DB_API_PASSWORD and DB_WORKER_PASSWORD must all be set." >&2
    exit 1
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
-- Roles (idempotent)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_migrator') THEN
        CREATE ROLE apexbooks_migrator LOGIN PASSWORD '$MIGRATOR_PASSWORD'
            BYPASSRLS CREATEDB NOSUPERUSER NOCREATEROLE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_api') THEN
        CREATE ROLE apexbooks_api LOGIN PASSWORD '$API_PASSWORD'
            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_worker') THEN
        CREATE ROLE apexbooks_worker LOGIN PASSWORD '$WORKER_PASSWORD'
            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
    END IF;
END
\$\$;

-- Schema access
GRANT ALL ON SCHEMA public TO apexbooks_migrator;
GRANT USAGE ON SCHEMA public TO apexbooks_api, apexbooks_worker;

-- Default privileges: everything the migrator creates going forward (all
-- migration DDL) is readable/writable by the restricted application roles.
-- Sequences: USAGE only (least privilege; nextval/currval/setval all work
-- with USAGE and the application never needs SELECT on a sequence).
ALTER DEFAULT PRIVILEGES FOR ROLE apexbooks_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO apexbooks_api, apexbooks_worker;
ALTER DEFAULT PRIVILEGES FOR ROLE apexbooks_migrator IN SCHEMA public
    GRANT USAGE ON SEQUENCES TO apexbooks_api, apexbooks_worker;

-- Also cover objects that pre-date the default-privilege statement.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO apexbooks_api, apexbooks_worker;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO apexbooks_api, apexbooks_worker;

-- Least privilege (kept in sync with migration 20260811_0004).  These run
-- before migrations create the objects, so each statement is guarded: apply
-- now when the object exists, otherwise the migration (20260811_0004) and
-- bootstrap_db.py apply the same policy later.
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname = 'audit_logs') THEN
        EXECUTE 'REVOKE UPDATE, DELETE ON TABLE public.audit_logs FROM apexbooks_api, apexbooks_worker';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname = 'alembic_version') THEN
        EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON TABLE public.alembic_version FROM apexbooks_api, apexbooks_worker';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'apex_list_active_tenant_ids') THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.apex_list_active_tenant_ids() FROM PUBLIC';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.apex_list_active_tenant_ids() TO apexbooks_api, apexbooks_worker';
    END IF;
    -- Security-sensitive tables: the worker never writes user / membership /
    -- password-reset rows (it only reads the owner email), and never needs
    -- password-reset data at all.  tenant_memberships is RLS-exempt, so its
    -- access must be narrowed at the privilege layer.
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname IN ('users', 'tenant_memberships')) THEN
        EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON TABLE public.users, public.tenant_memberships FROM apexbooks_worker';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname = 'password_reset_tokens') THEN
        EXECUTE 'REVOKE ALL ON TABLE public.password_reset_tokens FROM apexbooks_worker';
    END IF;
END
\$\$;
SQL

echo "initdb_roles.sh: roles apexbooks_migrator / apexbooks_api / apexbooks_worker ready."
