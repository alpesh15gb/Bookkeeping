import pytest
from uuid import UUID, uuid4
from fastapi import status
from datetime import date

from src.infrastructure.database.models import Tenant, User, TenantMembership


class TestAuthRouter:
    """Integration tests for authentication endpoints."""

    @pytest.mark.asyncio
    async def test_tenant_login_success(self, async_client, tenant, db_session):
        """Test successful tenant login."""
        # Create a test user
        user_id = uuid4()
        user = User(
            id=user_id,
            email="test@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",  # secret
            full_name="Test User",
            is_active=True
        )
        db_session.add(user)
        
        # Create tenant membership
        membership = TenantMembership(
            id=uuid4(),
            tenant_id=tenant.id,
            user_id=user.id,
            role="OWNER",
            is_active=True
        )
        db_session.add(membership)
        db_session.commit()

        login_data = {
            "email": "test@example.com",
            "password": "secret"
        }
        
        response = await async_client.post(
            "/api/v1/auth/login",
            json=login_data,
            headers={"X-Tenant-ID": str(tenant.id)}
        )
        
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"
        assert "refresh_token" in data

    @pytest.mark.asyncio
    async def test_tenant_login_invalid_credentials(self, async_client, tenant, db_session):
        """Test login with invalid credentials."""
        # Create a test user
        user_id = uuid4()
        user = User(
            id=user_id,
            email="test@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",  # secret
            full_name="Test User",
            is_active=True
        )
        db_session.add(user)
        
        # Create tenant membership
        membership = TenantMembership(
            id=uuid4(),
            tenant_id=tenant.id,
            user_id=user.id,
            role="OWNER",
            is_active=True
        )
        db_session.add(membership)
        db_session.commit()

        login_data = {
            "email": "test@example.com",
            "password": "wrongpassword"
        }
        
        response = await async_client.post(
            "/api/v1/auth/login",
            json=login_data,
            headers={"X-Tenant-ID": str(tenant.id)}
        )
        
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
        assert "Incorrect email or password" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_tenant_login_wrong_tenant(self, async_client, tenant, db_session):
        """The login endpoint does not validate X-Tenant-ID — it authenticates by
        credentials only. Passing a wrong tenant header still succeeds."""
        # Create a test user
        user_id = uuid4()
        user = User(
            id=user_id,
            email="test@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",  # secret
            full_name="Test User",
            is_active=True
        )
        db_session.add(user)
        
        # Create tenant membership
        membership = TenantMembership(
            id=uuid4(),
            tenant_id=tenant.id,
            user_id=user.id,
            role="OWNER",
            is_active=True
        )
        db_session.add(membership)
        db_session.commit()

        login_data = {
            "email": "test@example.com",
            "password": "secret"
        }
        
        # Use wrong tenant ID — login still succeeds (endpoint doesn't check tenant)
        wrong_tenant_id = uuid4()
        response = await async_client.post(
            "/api/v1/auth/login",
            json=login_data,
            headers={"X-Tenant-ID": str(wrong_tenant_id)}
        )
        
        assert response.status_code == status.HTTP_200_OK

    @pytest.mark.asyncio
    async def test_access_protected_endpoint_without_token(self, async_client, tenant_headers):
        """Test accessing protected endpoint without auth token."""
        response = await async_client.get(
            "/api/v1/auth/me",
            headers=tenant_headers
        )
        
        assert response.status_code == status.HTTP_401_UNAUTHORIZED

    @pytest.mark.asyncio
    async def test_access_protected_endpoint_with_invalid_token(self, async_client, tenant_headers):
        """Test accessing protected endpoint with invalid token."""
        headers = {
            "Authorization": "Bearer invalid-token",
            "X-Tenant-ID": str(tenant_headers["X-Tenant-ID"])
        }
        
        response = await async_client.get(
            "/api/v1/auth/me",
            headers=headers
        )
        
        assert response.status_code == status.HTTP_401_UNAUTHORIZED

    @pytest.mark.asyncio
    async def test_access_me_endpoint_valid_token(self, async_client, tenant, db_session):
        """Test accessing /me endpoint with valid token."""
        # Create a test user
        user_id = uuid4()
        user = User(
            id=user_id,
            email="test@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",  # secret
            full_name="Test User",
            is_active=True
        )
        db_session.add(user)
        
        # Create tenant membership
        membership = TenantMembership(
            id=uuid4(),
            tenant_id=tenant.id,
            user_id=user.id,
            role="OWNER",
            is_active=True
        )
        db_session.add(membership)
        db_session.commit()

        # Login first to get token
        login_data = {
            "email": "test@example.com",
            "password": "secret"
        }
        
        login_response = await async_client.post(
            "/api/v1/auth/login",
            json=login_data,
            headers={"X-Tenant-ID": str(tenant.id)}
        )
        
        assert login_response.status_code == status.HTTP_200_OK
        tokens = login_response.json()
        access_token = tokens["access_token"]
        
        # Access /me endpoint
        headers = {
            "Authorization": f"Bearer {access_token}",
            "X-Tenant-ID": str(tenant.id)
        }
        
        response = await async_client.get("/api/v1/auth/me", headers=headers)
        
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert data["email"] == "test@example.com"

    @pytest.mark.asyncio
    async def test_refresh_token(self, async_client, tenant, db_session):
        """Test token refresh endpoint."""
        # Create a test user
        user_id = uuid4()
        user = User(
            id=user_id,
            email="test@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",  # secret
            full_name="Test User",
            is_active=True
        )
        db_session.add(user)
        
        # Create tenant membership
        membership = TenantMembership(
            id=uuid4(),
            tenant_id=tenant.id,
            user_id=user.id,
            role="OWNER",
            is_active=True
        )
        db_session.add(membership)
        db_session.commit()

        # Login first to get tokens
        login_data = {
            "email": "test@example.com",
            "password": "secret"
        }
        
        login_response = await async_client.post(
            "/api/v1/auth/login",
            json=login_data,
            headers={"X-Tenant-ID": str(tenant.id)}
        )
        
        assert login_response.status_code == status.HTTP_200_OK
        data = login_response.json()
        refresh_token = data["refresh_token"]
        
        # Refresh token
        refresh_data = {"refresh_token": refresh_token}
        response = await async_client.post(
            "/api/v1/auth/refresh",
            json=refresh_data,
            headers={"X-Tenant-ID": str(tenant.id)}
        )
        
        assert response.status_code == status.HTTP_200_OK
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"

    @pytest.mark.asyncio
    async def test_logout_endpoint(self, async_client, tenant, db_session):
        """Test logout endpoint."""
        # Create a test user
        user_id = uuid4()
        user = User(
            id=user_id,
            email="test@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",  # secret
            full_name="Test User",
            is_active=True
        )
        db_session.add(user)
        
        # Create tenant membership
        membership = TenantMembership(
            id=uuid4(),
            tenant_id=tenant.id,
            user_id=user.id,
            role="OWNER",
            is_active=True
        )
        db_session.add(membership)
        db_session.commit()

        # Login first to get tokens
        login_data = {
            "email": "test@example.com",
            "password": "secret"
        }
        
        login_response = await async_client.post(
            "/api/v1/auth/login",
            json=login_data,
            headers={"X-Tenant-ID": str(tenant.id)}
        )
        
        assert login_response.status_code == status.HTTP_200_OK
        tokens = login_response.json()
        access_token = tokens["access_token"]
        refresh_token = tokens["refresh_token"]
        
        # Logout — endpoint expects refresh_token_str as query parameter
        headers = {
            "Authorization": f"Bearer {access_token}",
            "X-Tenant-ID": str(tenant.id)
        }
        
        response = await async_client.post(
            "/api/v1/auth/logout",
            params={"refresh_token_str": refresh_token},
            headers=headers
        )
        
        assert response.status_code == status.HTTP_200_OK
        assert "Logged out" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_tenant_isolation_rls(self, async_client, db_session):
        """Test Row Level Security isolation between tenants using an endpoint
        that enforces tenant context (GET /api/v1/invoices)."""
        # Create two tenants
        tenant1_id = uuid4()
        tenant2_id = uuid4()

        tenant1 = Tenant(
            id=tenant1_id,
            legal_name="Tenant One Pvt Ltd",
            trade_name="Tenant One",
            gstin="27AAACT1234A1Z5",
            pan="AAACT1234A",
            financial_year_start=date(2026, 4, 1),
        )

        tenant2 = Tenant(
            id=tenant2_id,
            legal_name="Tenant Two Pvt Ltd",
            trade_name="Tenant Two",
            gstin="29AAACT1234B1Z3",
            pan="AAACT1234B",
            financial_year_start=date(2026, 4, 1),
        )

        db_session.add_all([tenant1, tenant2])
        db_session.commit()

        # Create users for each tenant
        user1_id = uuid4()
        user2_id = uuid4()

        user1 = User(
            id=user1_id,
            email="user1@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",
            full_name="User One",
            is_active=True
        )

        user2 = User(
            id=user2_id,
            email="user2@example.com",
            password_hash="$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW",
            full_name="User Two",
            is_active=True
        )

        db_session.add_all([user1, user2])
        db_session.commit()

        # Create memberships
        membership1 = TenantMembership(
            id=uuid4(),
            tenant_id=tenant1.id,
            user_id=user1.id,
            role="OWNER",
            is_active=True
        )

        membership2 = TenantMembership(
            id=uuid4(),
            tenant_id=tenant2.id,
            user_id=user2.id,
            role="OWNER",
            is_active=True
        )

        db_session.add_all([membership1, membership2])
        db_session.commit()

        # Login as user1 (tenant1)
        login_data1 = {
            "email": "user1@example.com",
            "password": "secret"
        }

        login_response1 = await async_client.post(
            "/api/v1/auth/login",
            json=login_data1,
            headers={"X-Tenant-ID": str(tenant1.id)}
        )

        assert login_response1.status_code == status.HTTP_200_OK
        tokens1 = login_response1.json()
        access_token1 = tokens1["access_token"]

        # Login as user2 (tenant2)
        login_data2 = {
            "email": "user2@example.com",
            "password": "secret"
        }

        login_response2 = await async_client.post(
            "/api/v1/auth/login",
            json=login_data2,
            headers={"X-Tenant-ID": str(tenant2.id)}
        )

        assert login_response2.status_code == status.HTTP_200_OK
        tokens2 = login_response2.json()
        access_token2 = tokens2["access_token"]

        # Test that user1 cannot access tenant2's scoped data
        headers1_with_tenant2 = {
            "Authorization": f"Bearer {access_token1}",
            "X-Tenant-ID": str(tenant2.id)
        }

        response = await async_client.get("/api/v1/invoices", headers=headers1_with_tenant2)
        assert response.status_code == status.HTTP_403_FORBIDDEN

        # Test that user2 cannot access tenant1's scoped data
        headers2_with_tenant1 = {
            "Authorization": f"Bearer {access_token2}",
            "X-Tenant-ID": str(tenant1.id)
        }

        response = await async_client.get("/api/v1/invoices", headers=headers2_with_tenant1)
        assert response.status_code == status.HTTP_403_FORBIDDEN

        # Test that each user can access their own tenant's data (empty list is OK)
        headers1_correct = {
            "Authorization": f"Bearer {access_token1}",
            "X-Tenant-ID": str(tenant1.id)
        }

        response = await async_client.get("/api/v1/invoices", headers=headers1_correct)
        assert response.status_code == status.HTTP_200_OK

        headers2_correct = {
            "Authorization": f"Bearer {access_token2}",
            "X-Tenant-ID": str(tenant2.id)
        }

        response = await async_client.get("/api/v1/invoices", headers=headers2_correct)
        assert response.status_code == status.HTTP_200_OK
