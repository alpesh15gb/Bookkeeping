#!/usr/bin/env python3
"""CI helper: build a schema from an EMPTY PostgreSQL database using only
Alembic migrations (no create_all, no stamp shortcuts at the shell level).

Runs from backend/.  Uses CI_ADMIN_DATABASE_URL (superuser, defaults to the
local postgres:postgres) to create a throwaway database, runs
``alembic upgrade head`` against it, then verifies the version table records
exactly one revision.
"""

import os
import subprocess
import sys
from urllib.parse import urlparse, urlunparse

from sqlalchemy import create_engine, text

ADMIN_DATABASE_URL = os.getenv(
    "CI_ADMIN_DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/postgres",
)
FRESH_DB = os.getenv("CI_FRESH_DATABASE", "ci_fresh_migration")


def main() -> int:
    admin = create_engine(ADMIN_DATABASE_URL, isolation_level="AUTOCOMMIT")
    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{FRESH_DB}"'))
        conn.execute(text(f'CREATE DATABASE "{FRESH_DB}"'))
    admin.dispose()

    parsed = urlparse(ADMIN_DATABASE_URL)
    fresh_url = urlunparse((parsed.scheme, parsed.netloc, f"/{FRESH_DB}", "", "", ""))

    env = dict(os.environ)
    env["DATABASE_URL"] = fresh_url
    env["MIGRATION_DATABASE_URL"] = fresh_url
    proc = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode:
        print(proc.stdout + proc.stderr, file=sys.stderr)
        print("FAIL: alembic upgrade head on an empty database errored", file=sys.stderr)
        return 1

    engine = create_engine(fresh_url)
    try:
        with engine.connect() as conn:
            rows = conn.execute(text("SELECT version_num FROM alembic_version")).fetchall()
            if len(rows) != 1:
                print(f"FAIL: expected 1 alembic_version row, found {len(rows)}: {rows}", file=sys.stderr)
                return 1
            print("alembic_version:", rows[0][0])
            # Spot-check a core accounting table exists.
            count = conn.execute(
                text("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
            ).scalar()
            print(f"tables in public schema: {count}")
    finally:
        engine.dispose()

    print("OK: fresh empty-database migration succeeded")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
