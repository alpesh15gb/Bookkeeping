"""Existing-deployment ownership migration (postgres-owned -> apexbooks_migrator).

Simulates a production database created the OLD way (schema owned by the
``postgres`` superuser), then runs the documented upgrade path:

1. Schema is built as ``postgres`` (an older deployment).
2. scripts/transfer_ownership.py moves ownership to ``apexbooks_migrator``.
3. An Alembic schema change runs as ``apexbooks_migrator`` and succeeds.
4. apexbooks_api / apexbooks_worker still own nothing and cannot bypass RLS.
"""

import os
import subprocess
import sys

import pytest
from sqlalchemy import create_engine, text

from conftest import (
    API_ROLE,
    ADMIN_DATABASE_URL,
    BACKEND_DIR,
    MIGRATOR_ROLE,
    WORKER_ROLE,
    _admin_engine,
    create_roles_and_grants,
)

OWN_TEST_DB = "apex_books_owntest"
BASELINE_REVISION = "20260811_0000_squashed_baseline"


@pytest.fixture(scope="module")
def owntest(pg):
    """Build an 'old deployment' DB, transfer ownership, upgrade as migrator."""
    admin = _admin_engine("postgres")
    with admin.connect() as conn:
        conn.execute(text(f'DROP DATABASE IF EXISTS "{OWN_TEST_DB}"'))
        conn.execute(text(f'CREATE DATABASE "{OWN_TEST_DB}"'))
    admin.dispose()

    create_roles_and_grants(OWN_TEST_DB)

    postgres_url = _url("postgres", _pw_of_admin())
    migrator_url = _url(MIGRATOR_ROLE, "apex_migrator_test_pw")

    # Step 1: build the schema as postgres (old deployment).  Only the
    # baseline revision, so the new-chain migrations (0001..0004) remain to be
    # applied later by the migration role.
    env = dict(os.environ)
    env["DATABASE_URL"] = postgres_url
    env["MIGRATION_DATABASE_URL"] = postgres_url
    proc = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", BASELINE_REVISION],
        cwd=BACKEND_DIR,
        env=env,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"baseline upgrade as postgres failed:\n{proc.stdout}\n{proc.stderr}"

    # Step 2: transfer ownership to apexbooks_migrator (superuser script).
    env["DATABASE_URL"] = postgres_url
    proc = subprocess.run(
        [sys.executable, "scripts/transfer_ownership.py"],
        cwd=BACKEND_DIR,
        env=env,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"transfer_ownership failed:\n{proc.stdout}\n{proc.stderr}"

    # Step 3: run an Alembic schema change (0001..0004) AS apexbooks_migrator.
    env["DATABASE_URL"] = migrator_url
    env["MIGRATION_DATABASE_URL"] = migrator_url
    proc = subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=BACKEND_DIR,
        env=env,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, f"migrator upgrade failed:\n{proc.stdout}\n{proc.stderr}"

    return {
        "admin_url": _url("postgres", _pw_of_admin()),
        "api_url": _url(API_ROLE, "apex_api_test_pw"),
        "worker_url": _url(WORKER_ROLE, "apex_worker_test_pw"),
        "migrator_url": migrator_url,
    }


def _pw_of_admin():
    from urllib.parse import unquote
    _, _, creds = ADMIN_DATABASE_URL.partition("://")
    userpass = creds.split("@")[0]
    return unquote(userpass.split(":", 1)[1]) if ":" in userpass else ""


def _url(role: str, password: str) -> str:
    """Build a URL against the OWNERSHIP test database (not the main one)."""
    from urllib.parse import quote_plus
    head, _, tail = ADMIN_DATABASE_URL.partition("://")
    _, _, hostpart = tail.partition("@")
    return f"{head}://{quote_plus(role)}:{quote_plus(password)}@{hostpart.split('/')[0]}/{OWN_TEST_DB}"


def test_schema_objects_owned_by_migrator(owntest):
    engine = create_engine(owntest["admin_url"])
    with engine.connect() as conn:
        tables = conn.execute(
            text(
                "SELECT c.relname FROM pg_class c "
                "JOIN pg_namespace n ON n.oid = c.relnamespace "
                "JOIN pg_roles r ON r.oid = c.relowner "
                "WHERE n.nspname = 'public' AND c.relkind = 'r' "
                "AND r.rolname <> :owner"
            ),
            {"owner": MIGRATOR_ROLE},
        ).scalars().all()
        engine.dispose()
    # alembic_version may still be owned by the original creator (postgres)
    # depending on the order of operations; everything else must be migrator.
    assert set(tables) <= {"alembic_version"}, f"tables not owned by migrator: {tables[:10]}"


def test_all_new_chain_migrations_applied(owntest):
    engine = create_engine(owntest["admin_url"])
    with engine.connect() as conn:
        version = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
        columns = {
            c["name"] for c in __import__("sqlalchemy").inspect(conn).get_columns("idempotency_keys")
        }
        engine.dispose()
    assert version == "20260811_0004_least_privilege_grants", version
    # The migrator-applied 0003 migration added the resource columns.
    assert "resource_type" in columns
    assert "resource_id" in columns


def test_api_and_worker_own_no_tables(owntest):
    engine = create_engine(owntest["admin_url"])
    with engine.connect() as conn:
        for role in (API_ROLE, WORKER_ROLE):
            owned = conn.execute(
                text(
                    "SELECT c.relname FROM pg_class c "
                    "JOIN pg_namespace n ON n.oid = c.relnamespace "
                    "JOIN pg_roles r ON r.oid = c.relowner "
                    "WHERE n.nspname = 'public' AND r.rolname = :role"
                ),
                {"role": role},
            ).scalars().all()
            assert owned == [], f"{role} owns tables: {owned[:5]}"
    engine.dispose()


def test_api_role_cannot_bypass_rls_after_upgrade(owntest):
    engine = create_engine(owntest["api_url"])
    with engine.connect() as conn:
        conn.execute(text("SET row_security = off"))
        with pytest.raises(Exception) as excinfo:
            conn.execute(text("SELECT count(*) FROM invoices"))
            conn.commit()
        assert "row-level security" in str(excinfo.value).lower()
        conn.rollback()
        # Missing tenant context fails closed.
        assert conn.execute(text("SELECT count(*) FROM invoices")).scalar() == 0
    engine.dispose()


def test_worker_role_isolated_after_upgrade(owntest):
    engine = create_engine(owntest["worker_url"])
    with engine.connect() as conn:
        conn.execute(text("SET LOCAL app.current_tenant_id = 'aaaaaaaa-0000-0000-0000-000000000001'"))
        assert conn.execute(text("SELECT count(*) FROM invoices")).scalar() == 0
        conn.rollback()
    engine.dispose()


def test_migrator_can_run_further_ddl_after_transfer(owntest):
    """The migrator (not postgres) now owns DDL: create + drop a probe table."""
    engine = create_engine(owntest["migrator_url"])
    with engine.begin() as conn:
        conn.execute(text("CREATE TABLE ownership_probe (id int)"))
        conn.execute(text("DROP TABLE ownership_probe"))
    engine.dispose()
