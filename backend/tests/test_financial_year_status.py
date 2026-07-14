"""Regression tests for financial year status display."""
from datetime import date

from fastapi.testclient import TestClient

from src.core.database import SessionLocal
from src.infrastructure.database.models import User, TenantMembership, FinancialYear


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

    for start_year in (prev_year, current_start_year, next_year):
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
