import pytest
from uuid import uuid4
from fastapi import status
from datetime import date
from decimal import Decimal

from src.infrastructure.database.models import Tenant, User, TenantMembership, Account
from src.core.security import create_access_token


@pytest.fixture
def owner_headers(db_session):
    tenant = Tenant(
        id=uuid4(),
        legal_name="Test Co",
        trade_name="Test",
        gstin=f"27{uuid4().hex[:10].upper()}F1ZV",
        pan="AAAAA1234A",
        financial_year_start=date(2026, 4, 1),
    )
    db_session.add(tenant)

    user = User(
        id=uuid4(),
        email=f"owner_{uuid4().hex[:8]}@test.com",
        password_hash="hash",
        full_name="Owner User",
        is_active=True,
    )
    db_session.add(user)

    db_session.add(TenantMembership(
        id=uuid4(),
        tenant_id=tenant.id,
        user_id=user.id,
        role="OWNER",
        is_active=True,
    ))
    db_session.commit()

    token = create_access_token(user_id=str(user.id))
    return {
        "Authorization": f"Bearer {token}",
        "X-Tenant-ID": str(tenant.id),
    }, tenant.id


@pytest.fixture
def two_tenants(db_session):
    def _make(email_slug, gstin_slug, legal_name):
        t = Tenant(
            id=uuid4(),
            legal_name=legal_name,
            trade_name=legal_name,
            gstin=f"27{uuid4().hex[:10].upper()}F1ZV",
            pan=f"{uuid4().hex[:5].upper()}1234A",
            financial_year_start=date(2026, 4, 1),
        )
        db_session.add(t)
        u = User(
            id=uuid4(),
            email=f"{email_slug}@{uuid4().hex[:6]}.com",
            password_hash="hash",
            full_name=legal_name,
            is_active=True,
        )
        db_session.add(u)
        db_session.add(TenantMembership(
            id=uuid4(), tenant_id=t.id, user_id=u.id, role="OWNER", is_active=True,
        ))
        token = create_access_token(user_id=str(u.id))
        return {
            "Authorization": f"Bearer {token}",
            "X-Tenant-ID": str(t.id),
        }, t.id

    ha, ta_id = _make("owner_a", "AAAAA1111A1Z5", "Company A")
    hb, tb_id = _make("owner_b", "BBBBB2222B1Z3", "Company B")
    db_session.commit()
    return ha, hb, ta_id, tb_id


class TestAccountsCrud:
    """Integration tests for Chart of Accounts CRUD at /api/v1/masters/accounts."""

    # ── CREATE ──────────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_create_account(self, async_client, owner_headers):
        headers, _ = owner_headers
        payload = {
            "name": "Cash in Hand",
            "code": "1200",
            "account_type": "ASSET",
            "opening_balance": 0.0,
        }
        resp = await async_client.post("/api/v1/masters/accounts", json=payload, headers=headers)
        assert resp.status_code == status.HTTP_201_CREATED
        data = resp.json()
        assert data["name"] == "Cash in Hand"
        assert data["code"] == "1200"
        assert data["account_type"] == "ASSET"
        assert float(data["opening_balance"]) == 0.0
        assert float(data["current_balance"]) == 0.0
        assert data["is_active"] is True
        assert "id" in data

    @pytest.mark.asyncio
    async def test_create_account_invalid_type(self, async_client, owner_headers):
        headers, _ = owner_headers
        resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Bad", "code": "9999", "account_type": "BALANCE", "opening_balance": 0.0,
        }, headers=headers)
        assert resp.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

    @pytest.mark.asyncio
    async def test_create_account_duplicate_code(self, async_client, owner_headers):
        headers, _ = owner_headers
        payload = {"name": "Bank A", "code": "1201", "account_type": "ASSET", "opening_balance": 0.0}
        await async_client.post("/api/v1/masters/accounts", json=payload, headers=headers)

        resp = await async_client.post("/api/v1/masters/accounts", json=payload, headers=headers)
        assert resp.status_code == status.HTTP_400_BAD_REQUEST
        assert "already exists" in resp.json()["detail"]

    @pytest.mark.asyncio
    async def test_create_account_same_code_different_tenant(self, async_client, owner_headers, db_session):
        headers_a, _ = owner_headers
        payload = {"name": "Bank", "code": "1201", "account_type": "ASSET", "opening_balance": 0.0}
        await async_client.post("/api/v1/masters/accounts", json=payload, headers=headers_a)

        # Create tenant B user + membership
        tenant = Tenant(
            id=uuid4(), legal_name="Company B", trade_name="B",
            gstin=f"29{uuid4().hex[:10].upper()}F1ZV", pan="BBBBB1234B",
            financial_year_start=date(2026, 4, 1),
        )
        db_session.add(tenant)
        user = User(
            id=uuid4(), email=f"b_{uuid4().hex[:8]}@test.com",
            password_hash="hash", full_name="User B", is_active=True,
        )
        db_session.add(user)
        db_session.add(TenantMembership(
            id=uuid4(), tenant_id=tenant.id, user_id=user.id, role="OWNER", is_active=True,
        ))
        db_session.commit()

        token = create_access_token(user_id=str(user.id))
        headers_b = {
            "Authorization": f"Bearer {token}",
            "X-Tenant-ID": str(tenant.id),
        }
        resp = await async_client.post("/api/v1/masters/accounts", json=payload, headers=headers_b)
        assert resp.status_code == status.HTTP_201_CREATED

    @pytest.mark.asyncio
    async def test_create_account_with_parent(self, async_client, owner_headers):
        headers, _ = owner_headers
        parent_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Current Assets", "code": "1000", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        parent_id = parent_resp.json()["id"]

        resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "HDFC Bank", "code": "1001", "account_type": "ASSET",
            "parent_id": parent_id, "opening_balance": 50000.0,
        }, headers=headers)
        assert resp.status_code == status.HTTP_201_CREATED
        assert resp.json()["parent_id"] == parent_id
        assert float(resp.json()["current_balance"]) == 50000.0

    @pytest.mark.asyncio
    async def test_create_account_parent_not_found(self, async_client, owner_headers):
        headers, _ = owner_headers
        resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Orphan", "code": "1999", "account_type": "ASSET",
            "parent_id": str(uuid4()), "opening_balance": 0.0,
        }, headers=headers)
        assert resp.status_code == status.HTTP_400_BAD_REQUEST
        assert "Parent account not found" in resp.json()["detail"]

    # ── LIST ────────────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_list_accounts(self, async_client, owner_headers):
        headers, _ = owner_headers
        await async_client.post("/api/v1/masters/accounts", json={
            "name": "Cash", "code": "1200", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        await async_client.post("/api/v1/masters/accounts", json={
            "name": "Bank", "code": "1201", "account_type": "ASSET", "opening_balance": 1000.0,
        }, headers=headers)

        resp = await async_client.get("/api/v1/masters/accounts", headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        data = resp.json()
        assert len(data) == 2
        assert data[0]["code"] == "1200"
        assert data[1]["code"] == "1201"

    @pytest.mark.asyncio
    async def test_list_accounts_empty_tenant(self, async_client, owner_headers):
        headers, _ = owner_headers
        resp = await async_client.get("/api/v1/masters/accounts", headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        assert resp.json() == []

    @pytest.mark.asyncio
    async def test_list_accounts_tenant_isolation(self, async_client, two_tenants):
        ha, hb, ta_id, tb_id = two_tenants
        # Tenant A creates an account
        await async_client.post("/api/v1/masters/accounts", json={
            "name": "Tenant A Bank", "code": "1201", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=ha)

        resp_b = await async_client.get("/api/v1/masters/accounts", headers=hb)
        assert resp_b.status_code == 200
        assert resp_b.json() == []

    # ── GET ─────────────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_get_account(self, async_client, owner_headers):
        headers, _ = owner_headers
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Petty Cash", "code": "1202", "account_type": "ASSET", "opening_balance": 5000.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]

        resp = await async_client.get(f"/api/v1/masters/accounts/{account_id}", headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        data = resp.json()
        assert data["name"] == "Petty Cash"
        assert data["code"] == "1202"
        assert float(data["opening_balance"]) == 5000.0

    @pytest.mark.asyncio
    async def test_get_account_not_found(self, async_client, owner_headers):
        headers, _ = owner_headers
        resp = await async_client.get(f"/api/v1/masters/accounts/{uuid4()}", headers=headers)
        assert resp.status_code == status.HTTP_404_NOT_FOUND

    @pytest.mark.asyncio
    async def test_get_account_tenant_isolation(self, async_client, two_tenants):
        ha, hb, ta_id, tb_id = two_tenants
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Secret Asset", "code": "1300", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=ha)
        account_id = create_resp.json()["id"]

        resp = await async_client.get(f"/api/v1/masters/accounts/{account_id}", headers=hb)
        assert resp.status_code == status.HTTP_404_NOT_FOUND

    # ── UPDATE ──────────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_update_account(self, async_client, owner_headers):
        headers, _ = owner_headers
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Old Name", "code": "1400", "account_type": "LIABILITY", "opening_balance": 0.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]

        resp = await async_client.put(f"/api/v1/masters/accounts/{account_id}", json={
            "name": "New Name", "code": "1401",
        }, headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        assert resp.json()["name"] == "New Name"
        assert resp.json()["code"] == "1401"

    @pytest.mark.asyncio
    async def test_update_account_self_parent(self, async_client, owner_headers):
        headers, _ = owner_headers
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Self", "code": "1500", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]

        resp = await async_client.put(f"/api/v1/masters/accounts/{account_id}", json={
            "parent_id": account_id,
        }, headers=headers)
        assert resp.status_code == status.HTTP_400_BAD_REQUEST
        assert "own parent" in resp.json()["detail"]

    @pytest.mark.asyncio
    async def test_update_account_invalid_parent(self, async_client, owner_headers):
        headers, _ = owner_headers
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Orphan", "code": "1501", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]

        resp = await async_client.put(f"/api/v1/masters/accounts/{account_id}", json={
            "parent_id": str(uuid4()),
        }, headers=headers)
        assert resp.status_code == status.HTTP_400_BAD_REQUEST
        assert "Parent account not found" in resp.json()["detail"]

    @pytest.mark.asyncio
    async def test_update_account_duplicate_code(self, async_client, owner_headers):
        headers, _ = owner_headers
        await async_client.post("/api/v1/masters/accounts", json={
            "name": "Existing", "code": "1600", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "To Rename", "code": "1601", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]

        resp = await async_client.put(f"/api/v1/masters/accounts/{account_id}", json={
            "code": "1600",
        }, headers=headers)
        assert resp.status_code == status.HTTP_400_BAD_REQUEST
        assert "already exists" in resp.json()["detail"]

    @pytest.mark.asyncio
    async def test_update_account_opening_balance(self, async_client, owner_headers):
        headers, _ = owner_headers
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Balanced", "code": "1700", "account_type": "ASSET", "opening_balance": 1000.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]
        assert float(create_resp.json()["current_balance"]) == 1000.0

        resp = await async_client.put(f"/api/v1/masters/accounts/{account_id}", json={
            "opening_balance": 2000.0,
        }, headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        assert float(resp.json()["opening_balance"]) == 2000.0
        assert float(resp.json()["current_balance"]) == 2000.0

    @pytest.mark.asyncio
    async def test_update_account_inactivate(self, async_client, owner_headers):
        headers, _ = owner_headers
        create_resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Active Now", "code": "1800", "account_type": "EQUITY", "opening_balance": 0.0,
        }, headers=headers)
        account_id = create_resp.json()["id"]
        assert create_resp.json()["is_active"] is True

        resp = await async_client.put(f"/api/v1/masters/accounts/{account_id}", json={
            "is_active": False,
        }, headers=headers)
        assert resp.status_code == status.HTTP_200_OK
        assert resp.json()["is_active"] is False

    @pytest.mark.asyncio
    async def test_update_account_not_found(self, async_client, owner_headers):
        headers, _ = owner_headers
        resp = await async_client.put(f"/api/v1/masters/accounts/{uuid4()}", json={"name": "Nope"}, headers=headers)
        assert resp.status_code == status.HTTP_404_NOT_FOUND

    # ── EDGE: non-OWNER role cannot create accounts ─────────────────────

    @pytest.mark.asyncio
    async def test_create_account_requires_accounts_manage(self, async_client, db_session):
        tenant = Tenant(
            id=uuid4(), legal_name="X", trade_name="X",
            gstin=f"27{uuid4().hex[:10].upper()}F1ZV", pan="CCCCC1234C",
            financial_year_start=date(2026, 4, 1),
        )
        db_session.add(tenant)
        auditor = User(
            id=uuid4(), email=f"auditor_{uuid4().hex[:8]}@x.com",
            password_hash="hash", full_name="Auditor", is_active=True,
        )
        db_session.add(auditor)
        db_session.add(TenantMembership(
            id=uuid4(), tenant_id=tenant.id, user_id=auditor.id, role="AUDITOR", is_active=True,
        ))
        db_session.commit()

        token = create_access_token(user_id=str(auditor.id))
        headers = {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant.id)}
        resp = await async_client.post("/api/v1/masters/accounts", json={
            "name": "Should Fail", "code": "9999", "account_type": "ASSET", "opening_balance": 0.0,
        }, headers=headers)
        assert resp.status_code == status.HTTP_403_FORBIDDEN
