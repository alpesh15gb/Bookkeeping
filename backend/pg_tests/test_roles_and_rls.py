"""Priority 1 — PostgreSQL application roles and real RLS enforcement."""

import uuid

import pytest
from sqlalchemy import text

from conftest import (
    API_ROLE,
    MIGRATOR_ROLE,
    WORKER_ROLE,
    clear_tenant,
    set_tenant,
)
from src.infrastructure.database.models import Invoice, Tenant

from seed import (
    TENANT_A,
    TENANT_B,
    seed_contact,
    seed_invoice,
    seed_tenants,
    seed_user,
)


@pytest.fixture()
def seeded(db_admin):
    seed_tenants(db_admin)
    token = uuid.uuid4().hex[:8]
    contact_a = seed_contact(db_admin, TENANT_A, f"Cust A {token}")
    contact_b = seed_contact(db_admin, TENANT_B, f"Cust B {token}")
    seed_invoice(db_admin, TENANT_A, contact_a, f"INV-A-{token}")
    seed_invoice(db_admin, TENANT_B, contact_b, f"INV-B-{token}")
    db_admin.commit()
    return {}


def test_roles_have_no_privileged_attributes(engine_factories, db_admin):
    rows = db_admin.execute(
        text(
            "SELECT rolname, rolsuper, rolbypassrls, rolcreatedb, rolcreaterole "
            "FROM pg_roles WHERE rolname IN (:api, :worker, :migrator) ORDER BY rolname"
        ),
        {"api": API_ROLE, "worker": WORKER_ROLE, "migrator": MIGRATOR_ROLE},
    ).mappings().all()
    by_name = {row["rolname"]: row for row in rows}

    for role in (API_ROLE, WORKER_ROLE):
        assert role in by_name, f"role {role} was not created"
        attrs = by_name[role]
        assert attrs["rolsuper"] is False, f"{role} must not be SUPERUSER"
        assert attrs["rolbypassrls"] is False, f"{role} must not have BYPASSRLS"
        assert attrs["rolcreatedb"] is False, f"{role} must not have CREATEDB"
        assert attrs["rolcreaterole"] is False, f"{role} must not have CREATEROLE"

    migrator = by_name[MIGRATOR_ROLE]
    assert migrator["rolsuper"] is False
    assert migrator["rolbypassrls"] is True
    assert migrator["rolcreaterole"] is False


def test_api_role_cannot_disable_row_security(db_api):
    # The GUC can be set by any role, but it only skips RLS on tables the role
    # OWNS.  apexbooks_api owns nothing, so PostgreSQL 16 rejects the query
    # outright instead of letting it bypass tenant isolation.
    db_api.execute(text("SET row_security = off"))
    with pytest.raises(Exception) as excinfo:
        db_api.execute(text("SELECT count(*) FROM invoices"))
        db_api.commit()
    message = str(excinfo.value).lower()
    assert "row-level security" in message
    db_api.rollback()


def test_worker_role_cannot_disable_row_security(db_worker):
    db_worker.execute(text("SET LOCAL row_security = off"))
    with pytest.raises(Exception):
        db_worker.execute(text("SELECT count(*) FROM invoices"))
        db_worker.commit()
    db_worker.rollback()


def test_rls_is_enabled_and_forced_on_tenant_tables(db_admin):
    rows = db_admin.execute(
        text(
            "SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity "
            "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
            "WHERE n.nspname = 'public' AND c.relname IN "
            "('invoices', 'bills', 'payments', 'journal_entries', 'invoice_lines', 'bill_lines', 'journal_lines', 'stock_ledger')"
        )
    ).mappings().all()
    for row in rows:
        assert row["relrowsecurity"] is True, f"{row['relname']} must have RLS enabled"
        assert row["relforcerowsecurity"] is True, f"{row['relname']} must have RLS forced"


def test_missing_tenant_context_exposes_nothing(db_api, seeded):
    # No tenant context set — fail closed.
    count = db_api.execute(text("SELECT count(*) FROM invoices")).scalar()
    assert count == 0


def test_tenant_isolation_select_and_update_delete(db_api, db_admin, seeded):
    set_tenant(db_api, TENANT_A)
    owned_by_a = db_admin.execute(
        text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
        {"t": str(TENANT_A)},
    ).scalar()
    assert db_api.query(Invoice).filter(Invoice.tenant_id == TENANT_A).count() == owned_by_a
    assert db_api.query(Invoice).filter(Invoice.tenant_id == TENANT_B).count() == 0
    assert db_api.execute(text("SELECT count(*) FROM invoices")).scalar() == owned_by_a

    # Cross-tenant UPDATE affects zero rows.
    result = db_api.execute(
        text("UPDATE invoices SET notes = 'x' WHERE tenant_id = :tid"),
        {"tid": str(TENANT_B)},
    )
    assert result.rowcount == 0

    # Same-tenant UPDATE works (affects exactly the tenant-A rows the admin
    # can see — the DB accumulates rows across the session, so compare
    # against the admin count rather than an absolute number).
    result = db_api.execute(
        text("UPDATE invoices SET notes = 'x' WHERE tenant_id = :tid"),
        {"tid": str(TENANT_A)},
    )
    assert result.rowcount == owned_by_a

    # Cross-tenant DELETE affects zero rows.
    result = db_api.execute(
        text("DELETE FROM invoices WHERE tenant_id = :tid"),
        {"tid": str(TENANT_B)},
    )
    assert result.rowcount == 0


def test_insert_with_other_tenants_tenant_id_rejected(db_api, seeded):
    set_tenant(db_api, TENANT_A)
    with pytest.raises(Exception):
        db_api.execute(
            text(
                "INSERT INTO invoices "
                "(id, tenant_id, contact_id, invoice_number, issue_date, due_date, status, "
                "subtotal, cgst_amount, sgst_amount, igst_amount, utgst_amount, cess_amount, "
                "round_off, shipping_charges, total, amount_paid, e_invoice_status, pos_state_code, "
                "currency, exchange_rate) "
                "VALUES (:id, :tid, :cid, 'INV-X', CURRENT_DATE, CURRENT_DATE, 'POSTED', "
                "0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 'PENDING', '27', 'INR', 1)"
            ),
            {"id": str(uuid.uuid4()), "tid": str(TENANT_B), "cid": str(uuid.uuid4())},
        )
        db_api.commit()


def test_worker_role_isolated_like_api(db_worker, db_admin, seeded):
    set_tenant(db_worker, TENANT_A)
    seen_by_worker = db_worker.execute(text("SELECT count(*) FROM invoices")).scalar()
    owned_by_a = db_admin.execute(
        text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
        {"t": str(TENANT_A)},
    ).scalar()
    assert seen_by_worker == owned_by_a
    assert db_worker.execute(
        text("SELECT count(*) FROM invoices WHERE tenant_id = :t"),
        {"t": str(TENANT_B)},
    ).scalar() == 0
    assert db_worker.query(Invoice).filter(Invoice.tenant_id == TENANT_B).count() == 0


def test_tenant_enumerator_returns_ids_only(db_api, seeded):
    # The controlled enumerator is callable by the restricted role and exposes
    # only tenant ids/names — not accounting data.
    rows = db_api.execute(
        text("SELECT tenant_id, legal_name FROM apex_list_active_tenant_ids() ORDER BY legal_name")
    ).mappings().all()
    ids = {row["tenant_id"] for row in rows}
    assert TENANT_A in ids
    assert TENANT_B in ids
    names = {row["legal_name"] for row in rows}
    assert "Tenant A Ltd" in names


def test_global_templates_visible_to_all_tenants(db_api, db_admin, seeded):
    # Global tax templates (tenant_id NULL) must remain readable by the
    # restricted API role under any tenant context.
    from src.infrastructure.database.models import TaxTemplate
    db_admin.add(TaxTemplate(name="GST 18%", rate="18.00"))
    db_admin.commit()

    set_tenant(db_api, TENANT_A)
    rates = db_api.execute(text("SELECT rate FROM tax_templates")).scalars().all()
    assert "18.00" in rates or 18.00 in rates


def test_least_privilege_audit_logs_not_writable(db_api, db_admin):
    """The API role must not be able to UPDATE or DELETE audit_logs even with
    raw SQL — the least-privilege grant model forbids it (defense in depth
    on top of the immutability trigger)."""
    for priv in ("UPDATE", "DELETE"):
        assert db_admin.execute(
            text("SELECT has_table_privilege(:role, 'audit_logs', :priv)"),
            {"role": API_ROLE, "priv": priv},
        ).scalar() is False
    assert db_admin.execute(
        text("SELECT has_table_privilege(:role, 'audit_logs', 'INSERT')"),
        {"role": API_ROLE},
    ).scalar() is True


def test_least_privilege_alembic_version_read_only(db_api, db_admin):
    for priv in ("INSERT", "UPDATE", "DELETE"):
        assert db_admin.execute(
            text("SELECT has_table_privilege(:role, 'alembic_version', :priv)"),
            {"role": API_ROLE, "priv": priv},
        ).scalar() is False
    # The readiness probe reads it.
    assert db_admin.execute(
        text("SELECT has_table_privilege(:role, 'alembic_version', 'SELECT')"),
        {"role": API_ROLE},
    ).scalar() is True


def test_least_privilege_sequence_usage_only(db_admin):
    """Sequences grant USAGE only — nextval/currval/setval all work with
    USAGE and the application never needs SELECT on a sequence."""
    seq = db_admin.execute(
        text(
            "SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace "
            "WHERE n.nspname = 'public' AND c.relkind = 'S' LIMIT 1"
        )
    ).scalar()
    if not seq:
        pytest.skip("no sequences in public schema")
    assert db_admin.execute(
        text("SELECT has_sequence_privilege(:role, :seq, 'USAGE')"),
        {"role": API_ROLE, "seq": seq},
    ).scalar() is True
    assert db_admin.execute(
        text("SELECT has_sequence_privilege(:role, :seq, 'SELECT')"),
        {"role": API_ROLE, "seq": seq},
    ).scalar() is False


def test_tenant_enumerator_not_public(db_admin):
    """The controlled tenant enumerator is callable by the restricted roles
    but never by arbitrary PUBLIC."""
    public_ok = db_admin.execute(
        text(
            "SELECT has_function_privilege('public', 'apex_list_active_tenant_ids()', 'EXECUTE')"
        )
    ).scalar()
    assert public_ok is False
    assert db_admin.execute(
        text("SELECT has_function_privilege(:role, 'apex_list_active_tenant_ids()', 'EXECUTE')"),
        {"role": API_ROLE},
    ).scalar() is True
