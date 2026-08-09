"""
PostgreSQL integration test suite fixtures.

These tests exercise the REAL production database path: Alembic migrations
(not Base.metadata.create_all), restricted application roles, Row-Level
Security, accounting triggers and crash-safe idempotency.

Run from backend/:

    TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/postgres \
        .venv314/Scripts/python.exe -m pytest pg_tests -q

When PostgreSQL is unreachable the suite skips (not fails) so it never blocks
the fast SQLite regression suite.  CI and production acceptance set
``REQUIRE_POSTGRES_TESTS=1``, which turns that skip into a hard failure — the
PostgreSQL integration suite is mandatory there and can never be silently
skipped.
"""

import os
import subprocess
import sys
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool

BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, BACKEND_DIR)
sys.path.insert(0, os.path.join(BACKEND_DIR, "src"))

ADMIN_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/postgres",
)
TEST_DB = os.getenv("TEST_PGDATABASE", "apex_books_pgtest")

API_ROLE = "apexbooks_api"
WORKER_ROLE = "apexbooks_worker"
MIGRATOR_ROLE = "apexbooks_migrator"
API_PASSWORD = "apex_api_test_pw"
WORKER_PASSWORD = "apex_worker_test_pw"
MIGRATOR_PASSWORD = "apex_migrator_test_pw"

TENANT_A = uuid.UUID("aaaaaaaa-0000-0000-0000-000000000001")
TENANT_B = uuid.UUID("aaaaaaaa-0000-0000-0000-000000000002")

_roles_created = False


def _replace_credentials(url: str, role: str, password: str) -> str:
    from urllib.parse import quote_plus
    head, _, tail = url.partition("://")
    _, _, hostpart = url.partition("@")
    return f"{head}://{quote_plus(role)}:{quote_plus(password)}@{hostpart.split('/')[0]}/{TEST_DB}"


def _admin_engine(dbname: str):
    from urllib.parse import urlparse, urlunparse
    parsed = urlparse(ADMIN_DATABASE_URL)
    return create_engine(
        urlunparse((parsed.scheme, parsed.netloc, f"/{dbname}", "", "", "")),
        isolation_level="AUTOCOMMIT",
    )


def create_roles_and_grants(dbname: str) -> None:
    """Create the three application roles + schema grants on ``dbname``.

    Mirrors scripts/initdb_roles.sh / scripts/bootstrap_db.py exactly: the
    migrator gets BYPASSRLS + CREATEDB, the API/worker roles are fully
    restricted, and default privileges let the migrator's future objects be
    used by the application roles.
    """
    admin = _admin_engine(dbname)
    with admin.begin() as conn:
        conn.execute(
            text(
                """
                DO $$
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_migrator') THEN
                        CREATE ROLE apexbooks_migrator LOGIN PASSWORD 'apex_migrator_test_pw'
                            BYPASSRLS CREATEDB NOSUPERUSER NOCREATEROLE;
                    ELSE
                        ALTER ROLE apexbooks_migrator WITH LOGIN PASSWORD 'apex_migrator_test_pw'
                            BYPASSRLS CREATEDB NOSUPERUSER NOCREATEROLE;
                    END IF;
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_api') THEN
                        CREATE ROLE apexbooks_api LOGIN PASSWORD 'apex_api_test_pw'
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    ELSE
                        ALTER ROLE apexbooks_api WITH LOGIN PASSWORD 'apex_api_test_pw'
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    END IF;
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'apexbooks_worker') THEN
                        CREATE ROLE apexbooks_worker LOGIN PASSWORD 'apex_worker_test_pw'
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    ELSE
                        ALTER ROLE apexbooks_worker WITH LOGIN PASSWORD 'apex_worker_test_pw'
                            NOBYPASSRLS NOCREATEDB NOCREATEROLE NOSUPERUSER;
                    END IF;
                END
                $$;
                """
            )
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
    admin.dispose()


@pytest.fixture(scope="session")
def pg():
    """Prepare an empty test database via Alembic and create the roles."""
    global _roles_created
    try:
        admin = _admin_engine("postgres")
        with admin.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as exc:  # pragma: no cover - environment dependent
        if os.getenv("REQUIRE_POSTGRES_TESTS") == "1":
            pytest.fail(
                f"REQUIRE_POSTGRES_TESTS=1 but PostgreSQL is unavailable ({exc}). "
                "The PostgreSQL integration suite is mandatory and must not be skipped."
            )
        pytest.skip(f"PostgreSQL unavailable ({exc}); skipping integration suite")

    # Recreate the test database from scratch.
    admin = _admin_engine("postgres")
    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{TEST_DB}"'))
        conn.execute(text(f'CREATE DATABASE "{TEST_DB}"'))
    admin.dispose()

    api_url = _replace_credentials(ADMIN_DATABASE_URL, API_ROLE, API_PASSWORD)
    worker_url = _replace_credentials(ADMIN_DATABASE_URL, WORKER_ROLE, WORKER_PASSWORD)
    migrator_url = _replace_credentials(ADMIN_DATABASE_URL, MIGRATOR_ROLE, MIGRATOR_PASSWORD)

    # Create roles + grants (same SQL the docker-entrypoint bootstrap runs).
    create_roles_and_grants(TEST_DB)

    # Run the full deployment command: alembic upgrade head (fresh-DB
    # bootstrap — the squashed baseline + migrations, no create_all shortcut).
    env = dict(os.environ)
    env["MIGRATION_DATABASE_URL"] = migrator_url
    env["DATABASE_URL"] = migrator_url
    proc = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_DIR,
        env=env,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"alembic upgrade head failed:\n{proc.stdout}\n{proc.stderr}"

    # Migration 20260811_0004 applies the least-privilege revocations; the
    # fresh database has no pre-existing objects, so no blanket re-grant is
    # needed here (a blanket re-grant would UNDO those revocations).

    ctx = {
        "admin_url": _replace_credentials(ADMIN_DATABASE_URL, "postgres", _pw_of_admin()),
        "api_url": api_url,
        "worker_url": worker_url,
        "migrator_url": migrator_url,
    }
    return ctx


def _pw_of_admin() -> str:
    from urllib.parse import unquote
    _, _, creds = ADMIN_DATABASE_URL.partition("://")
    userpass = creds.split("@")[0]
    return unquote(userpass.split(":", 1)[1]) if ":" in userpass else ""


@pytest.fixture(scope="session")
def engine_factories(pg):
    def make(url: str):
        return create_engine(url, poolclass=NullPool)

    return {
        "api": make(pg["api_url"]),
        "worker": make(pg["worker_url"]),
        "admin": make(pg["admin_url"]),
    }


@pytest.fixture()
def db_api(engine_factories):
    session = sessionmaker(bind=engine_factories["api"])()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture()
def db_worker(engine_factories):
    session = sessionmaker(bind=engine_factories["worker"])()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


@pytest.fixture()
def db_admin(engine_factories):
    session = sessionmaker(bind=engine_factories["admin"])()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def set_tenant(db, tenant_id):
    """Set transaction-local RLS tenant context, exactly like production."""
    db.execute(
        text("SET LOCAL app.current_tenant_id = :tid"),
        {"tid": str(tenant_id)},
    )


def clear_tenant(db):
    db.execute(text("SET LOCAL app.current_tenant_id = ''"))
