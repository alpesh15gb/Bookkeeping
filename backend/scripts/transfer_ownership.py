#!/usr/bin/env python3
"""Transfer ownership of an existing deployment's schema to apexbooks_migrator.

Existing ApexBooks deployments created their schema while the API connected
as the PostgreSQL ``postgres`` superuser, so every table/sequence/view/function
is owned by ``postgres``.  That breaks the restricted-migration architecture:
the migration role (apexbooks_migrator) cannot ALTER or own objects it does
not own, and the application roles cannot be properly isolated.

Run this ONCE against an existing database, as a superuser, AFTER creating the
application roles (scripts/bootstrap_db.py or the docker initdb script):

    DATABASE_URL=postgresql://postgres:PASS@db:5432/bookkeeping \
        python scripts/transfer_ownership.py

What it does
------------
* Transfers ownership of every non-extension table, sequence, view,
  materialized view and function in the ``public`` schema to
  ``apexbooks_migrator`` (the role must exist).
* Leaves extension-owned objects untouched.
* Does NOT touch the ``public`` schema's own owner (still the default
  database owner), and does NOT change any grants — existing ACLs survive
  the transfer, and the migrator role's default privileges keep granting
  future objects to the restricted application roles.

After the transfer, ``alembic upgrade head`` (running as apexbooks_migrator)
owns the schema evolution: the new squashed-baseline chain stamps the legacy
head and continues with normal migrations.
"""

import os
import sys

from sqlalchemy import create_engine, text

MIGRATOR_ROLE = "apexbooks_migrator"


def main() -> int:
    admin_url = os.getenv("DATABASE_URL")
    if not admin_url:
        print("transfer_ownership.py: DATABASE_URL (superuser) is not set", file=sys.stderr)
        return 1

    engine = create_engine(admin_url)
    with engine.begin() as conn:
        conn.execute(
            text(
                """
                DO $$
                DECLARE
                    r record;
                    target text := 'apexbooks_migrator';
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = target) THEN
                        RAISE EXCEPTION 'role % does not exist; run scripts/bootstrap_db.py first', target;
                    END IF;

                    -- Tables, views, materialized views, sequences (skip
                    -- objects owned by extensions such as pgcrypto, and skip
                    -- identity sequences whose ownership is tied to their
                    -- table — they follow the table's owner automatically).
                    FOR r IN
                        SELECT c.oid, c.relname, c.relkind
                          FROM pg_class c
                          JOIN pg_namespace n ON n.oid = c.relnamespace
                         WHERE n.nspname = 'public'
                           AND c.relkind IN ('r', 'v', 'S', 'm')
                           AND NOT EXISTS (
                               SELECT 1 FROM pg_depend d
                                WHERE d.classid = 'pg_class'::regclass
                                  AND d.objid = c.oid
                                  AND d.deptype = 'e'
                           )
                           AND NOT EXISTS (
                               SELECT 1 FROM pg_depend d
                                WHERE d.classid = 'pg_class'::regclass
                                  AND d.objid = c.oid
                                  AND d.refclassid = 'pg_class'::regclass
                                  AND d.refobjsubid > 0
                                  AND d.deptype = 'i'
                           )
                    LOOP
                        EXECUTE format(
                            'ALTER %s %I.%I OWNER TO %I',
                            CASE r.relkind
                                WHEN 'r' THEN 'TABLE'
                                WHEN 'v' THEN 'VIEW'
                                WHEN 'm' THEN 'MATERIALIZED VIEW'
                                WHEN 'S' THEN 'SEQUENCE'
                            END,
                            'public', r.relname, target
                        );
                    END LOOP;

                    -- Functions / procedures (skip extension members).
                    FOR r IN
                        SELECT p.oid, p.proname,
                               pg_get_function_identity_arguments(p.oid) AS args
                          FROM pg_proc p
                          JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public'
                           AND p.prokind IN ('f', 'p')
                           AND NOT EXISTS (
                               SELECT 1 FROM pg_depend d
                                WHERE d.classid = 'pg_proc'::regclass
                                  AND d.objid = p.oid
                                  AND d.deptype = 'e'
                           )
                    LOOP
                        EXECUTE format(
                            'ALTER FUNCTION %I.%I(%s) OWNER TO %I',
                            'public', r.proname, r.args, target
                        );
                    END LOOP;
                END
                $$;
                """
            )
        )
    engine.dispose()
    print("transfer_ownership.py: schema ownership moved to apexbooks_migrator.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
