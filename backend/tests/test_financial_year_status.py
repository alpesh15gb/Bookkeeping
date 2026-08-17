"""Regression tests for financial year status display."""
import uuid
from datetime import date

from fastapi.testclient import TestClient

from src.core.database import SessionLocal
from src.infrastructure.database.models import User, TenantMembership, FinancialYear
from src.api.v1.financial_years import _compute_status


def _auth(client: TestClient, email: str = "fy_status@test.com"):
    client.post("/api/v1/auth/register", json={
        "email": email,
        "password": "Passw0rd!",
        "full_name": "FY Status User",
        "company_legal_name": "FY Status Co",
    })
    login = client.post("/api/v1/auth/login", json={"email": email, "password": "Passw0rd!"})
    assert login.status_code == 200

    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        membership = db.query(TenantMembership).filter(TenantMembership.user_id == user.id).first()
        tenant_id = membership.tenant_id
    finally:
        db.close()

    return {"Authorization": f"Bearer {login.json()['access_token']}", "X-Tenant-ID": str(tenant_id)}, tenant_id


def _create_fy(client: TestClient, headers: dict, start_year: int):
    return client.post("/api/v1/financial-years", json={
        "name": f"{start_year}-{((start_year + 1) % 100):02d}",
        "start_date": f"{start_year}-04-01",
        "end_date": f"{start_year + 1}-03-31",
    }, headers=headers)


def test_list_normalizes_single_current_and_marks_future_upcoming(client: TestClient):
    headers, tenant_id = _auth(client)

    today = date.today()
    current_start_year = today.year if today.month >= 4 else today.year - 1
    prev_year = current_start_year - 1
    next_year = current_start_year + 1

    # Signup provisions the current FY; only create the surrounding years.
    for start_year in (prev_year, next_year):
        res = _create_fy(client, headers, start_year)
        assert res.status_code == 201, res.json()

    # Simulate recoverable legacy data with no selected current FY. The database
    # now prevents multiple current years, so normalization only needs to recover
    # the missing-current case by selecting the date-matching FY.
    db = SessionLocal()
    try:
        db.query(FinancialYear).filter(FinancialYear.tenant_id == tenant_id).update({
            "is_current": False,
            "status": "CURRENT",
        })
        db.commit()
    finally:
        db.close()

    res = client.get("/api/v1/financial-years", headers=headers)
    assert res.status_code == 200
    years = {fy["name"]: fy for fy in res.json()}

    assert years[f"{prev_year}-{((prev_year + 1) % 100):02d}"]["status"] == "READY_TO_CLOSE"
    assert years[f"{prev_year}-{((prev_year + 1) % 100):02d}"]["is_current"] is False

    assert years[f"{current_start_year}-{((current_start_year + 1) % 100):02d}"]["status"] == "CURRENT"
    assert years[f"{current_start_year}-{((current_start_year + 1) % 100):02d}"]["is_current"] is True

    assert years[f"{next_year}-{((next_year + 1) % 100):02d}"]["status"] == "UPCOMING"
    assert years[f"{next_year}-{((next_year + 1) % 100):02d}"]["is_current"] is False


def test_list_reports_open_for_in_range_year_that_is_not_current(client: TestClient):
    """Regression: when a different FY is the designated current one, an
    in-range year must NOT also read CURRENT (that made two years look
    current at once). It should read OPEN."""
    headers, tenant_id = _auth(client)

    today = date.today()
    current_start_year = today.year if today.month >= 4 else today.year - 1
    prev_year = current_start_year - 1

    res = _create_fy(client, headers, prev_year)
    assert res.status_code == 201, res.json()

    # The books are explicitly in the PREVIOUS year, even though today falls
    # inside the current-year FY's range.
    db = SessionLocal()
    try:
        db.query(FinancialYear).filter(
            FinancialYear.tenant_id == tenant_id,
            FinancialYear.start_date >= date(prev_year, 4, 1),
            FinancialYear.start_date <= date(current_start_year, 12, 31),
        ).update({"is_current": False})
        prev = db.query(FinancialYear).filter(
            FinancialYear.tenant_id == tenant_id,
            FinancialYear.start_date == date(prev_year, 4, 1),
        ).first()
        prev.is_current = True
        db.commit()
    finally:
        db.close()

    res = client.get("/api/v1/financial-years", headers=headers)
    assert res.status_code == 200
    years = {fy["name"]: fy for fy in res.json()}
    cur = years[f"{prev_year}-{((prev_year + 1) % 100):02d}"]
    in_range = years[f"{current_start_year}-{((current_start_year + 1) % 100):02d}"]

    assert cur["is_current"] is True
    assert cur["status"] == "CURRENT"
    assert in_range["is_current"] is False
    assert in_range["status"] != "CURRENT"


def _fy(status="CURRENT", is_current=False, start=None, end=None):
    return FinancialYear(
        id=uuid.uuid4(),
        tenant_id=uuid.uuid4(),
        name="TEST",
        start_date=start or date(2025, 4, 1),
        end_date=end or date(2026, 3, 31),
        status=status,
        is_current=is_current,
    )


def test_compute_status_designated_current_is_current():
    fy = _fy(is_current=True)
    assert _compute_status(fy, date(2026, 8, 17)) == "CURRENT"


def test_compute_status_in_range_not_current_is_open():
    fy = _fy(is_current=False, start=date(2026, 4, 1), end=date(2027, 3, 31))
    assert _compute_status(fy, date(2026, 8, 17)) == "OPEN"


def test_compute_status_future_year_is_upcoming():
    fy = _fy(is_current=False, start=date(2027, 4, 1), end=date(2028, 3, 31))
    assert _compute_status(fy, date(2026, 8, 17)) == "UPCOMING"


def test_compute_status_past_year_is_ready_to_close():
    fy = _fy(is_current=False, start=date(2024, 4, 1), end=date(2025, 3, 31))
    assert _compute_status(fy, date(2026, 8, 17)) == "READY_TO_CLOSE"


def test_compute_status_locked_status_is_never_overridden():
    for stored in ("LOCKED", "ARCHIVED", "READY_TO_CLOSE"):
        fy = _fy(status=stored, is_current=True)
        assert _compute_status(fy, date(2026, 8, 17)) == stored
