import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import pytest
import pyotp
from src.infrastructure.database.models import User, Tenant, TenantMembership, Account, FinancialYear, AccountingPeriod, GSTReturn
from src.core.security import create_access_token, get_password_hash

def _auth_headers(user, tenant):
    token = create_access_token(user_id=str(user.id))
    return {
        "Authorization": f"Bearer {token}",
        "X-Tenant-ID": str(tenant.id)
    }

def test_sprint_2fa_flow(db_session, client):
    # Setup user and tenant
    tenant = Tenant(id=uuid.uuid4(), legal_name="2FA Test Co", tax_mode="NON_GST")
    db_session.add(tenant)
    
    totp_secret = pyotp.random_base32()
    user = User(
        id=uuid.uuid4(),
        email="totp_user@test.com",
        password_hash=get_password_hash("Secure@123"),
        full_name="2FA User",
        is_active=True,
        email_verified=True,
        totp_secret=totp_secret,
        totp_enabled=True
    )
    db_session.add(user)
    
    membership = TenantMembership(tenant_id=tenant.id, user_id=user.id, role="owner", is_active=True)
    db_session.add(membership)
    db_session.commit()
    
    # 1. Login should require 2FA
    resp = client.post("/api/v1/auth/login", json={
        "email": "totp_user@test.com",
        "password": "Secure@123"
    })
    assert resp.status_code == 200
    data = resp.json()
    assert data["requires_2fa"] is True
    assert "challenge_token" in data
    assert "challenge_expiry" in data
    
    challenge_token = data["challenge_token"]
    
    # 2. Challenge with invalid TOTP
    resp = client.post("/api/v1/auth/2fa/challenge", json={
        "challenge_token": challenge_token,
        "totp_code": "000000"
    })
    assert resp.status_code == 401
    
    # 3. Challenge with valid TOTP
    totp = pyotp.TOTP(totp_secret)
    valid_code = totp.now()
    resp = client.post("/api/v1/auth/2fa/challenge", json={
        "challenge_token": challenge_token,
        "totp_code": valid_code
    })
    assert resp.status_code == 200
    tokens = resp.json()
    assert "access_token" in tokens
    assert "refresh_token" in tokens
    
    # 4. Prevent replay attack / already used token
    resp = client.post("/api/v1/auth/2fa/challenge", json={
        "challenge_token": challenge_token,
        "totp_code": valid_code
    })
    assert resp.status_code == 401


def test_sprint_team_management(db_session, client):
    # Setup owner user and company
    tenant = Tenant(id=uuid.uuid4(), legal_name="Team Test Co", tax_mode="NON_GST")
    db_session.add(tenant)
    
    owner = User(id=uuid.uuid4(), email="owner@team.com", password_hash=get_password_hash("Password123!"), full_name="Owner User", is_active=True)
    db_session.add(owner)
    
    membership = TenantMembership(tenant_id=tenant.id, user_id=owner.id, role="owner", is_active=True)
    db_session.add(membership)
    db_session.commit()
    
    headers = _auth_headers(owner, tenant)
    
    # 1. Invite a member
    invite_email = "invitee@team.com"
    resp = client.post(f"/api/v1/companies/{tenant.id}/invite", json={
        "email": invite_email,
        "role": "accountant"
    }, headers=headers)
    assert resp.status_code == 200
    invite_data = resp.json()
    assert invite_data["email"] == invite_email
    assert invite_data["status"] == "PENDING"
    token = invite_data["token"]
    
    # 2. Get members
    resp = client.get(f"/api/v1/companies/{tenant.id}/members", headers=headers)
    assert resp.status_code == 200
    members = resp.json()
    assert len(members) == 1
    assert members[0]["email"] == "owner@team.com"
    
    # 3. Accept invitation
    # Register and login invitee
    invitee = User(id=uuid.uuid4(), email=invite_email, password_hash=get_password_hash("Password123!"), full_name="Invitee User", is_active=True)
    db_session.add(invitee)
    db_session.commit()
    
    invitee_headers = _auth_headers(invitee, tenant)
    
    resp = client.post("/api/v1/companies/invitations/accept", json={
        "token": token
    }, headers=invitee_headers)
    assert resp.status_code == 200
    
    # Verify member is added
    resp = client.get(f"/api/v1/companies/{tenant.id}/members", headers=headers)
    assert resp.status_code == 200
    members = resp.json()
    assert len(members) == 2
    
    # 4. Update member role
    resp = client.put(f"/api/v1/companies/{tenant.id}/members/{invitee.id}", json={
        "role": "salesperson",
        "is_active": True
    }, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["role"] == "salesperson"
    
    # 5. Delete member
    resp = client.delete(f"/api/v1/companies/{tenant.id}/members/{invitee.id}", headers=headers)
    assert resp.status_code == 204
    
    # Verify member is gone
    resp = client.get(f"/api/v1/companies/{tenant.id}/members", headers=headers)
    members = resp.json()
    assert len(members) == 1


def test_sprint_period_lock_management(db_session, client):
    tenant = Tenant(id=uuid.uuid4(), legal_name="Period Test Co", tax_mode="NON_GST")
    db_session.add(tenant)
    user = User(id=uuid.uuid4(), email="lock@test.com", password_hash=get_password_hash("Password123!"), full_name="Lock User", is_active=True)
    db_session.add(user)
    membership = TenantMembership(tenant_id=tenant.id, user_id=user.id, role="owner", is_active=True)
    db_session.add(membership)
    db_session.commit()
    
    headers = _auth_headers(user, tenant)
    
    # 1. Lock current period
    resp = client.post("/api/v1/accounting/periods/lock", json={
        "period_date": "2025-04-15",
        "note": "Locking April"
    }, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_closed"] is True
    
    # 2. Cannot lock future period
    future_date = date.today() + timedelta(days=60)
    resp = client.post("/api/v1/accounting/periods/lock", json={
        "period_date": str(future_date)
    }, headers=headers)
    assert resp.status_code == 400
    
    # 3. List periods
    resp = client.get("/api/v1/accounting/periods", headers=headers)
    assert resp.status_code == 200
    periods = resp.json()
    assert len(periods) >= 1
    
    # 4. Unlock period
    resp = client.post("/api/v1/accounting/periods/unlock", json={
        "period_date": "2025-04-15",
        "note": "Unlocking April"
    }, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["is_closed"] is False
    
    # 5. Lock containing FY and try to unlock
    fy = FinancialYear(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name="FY 2025-26",
        start_date=date(2025, 4, 1),
        end_date=date(2026, 3, 31),
        status="LOCKED",
        is_current=True
    )
    db_session.add(fy)
    db_session.commit()
    
    resp = client.post("/api/v1/accounting/periods/unlock", json={
        "period_date": "2025-04-15"
    }, headers=headers)
    assert resp.status_code == 400


def test_sprint_contra_entry(db_session, client):
    tenant = Tenant(id=uuid.uuid4(), legal_name="Contra Test Co", tax_mode="NON_GST")
    db_session.add(tenant)
    user = User(id=uuid.uuid4(), email="contra@test.com", password_hash=get_password_hash("Password123!"), full_name="Contra User", is_active=True)
    db_session.add(user)
    membership = TenantMembership(tenant_id=tenant.id, user_id=user.id, role="owner", is_active=True)
    db_session.add(membership)
    
    # Cash and Bank accounts
    cash_acc = Account(id=uuid.uuid4(), tenant_id=tenant.id, name="Cash in Hand", code="1001", account_type="ASSET", account_group="Cash & Bank", opening_balance=Decimal("1000.00"), current_balance=Decimal("1000.00"), is_active=True)
    bank_acc = Account(id=uuid.uuid4(), tenant_id=tenant.id, name="Bank Account", code="1002", account_type="ASSET", account_group="Cash & Bank", opening_balance=Decimal("5000.00"), current_balance=Decimal("5000.00"), is_active=True)
    # Expense account for invalid validation test
    exp_acc = Account(id=uuid.uuid4(), tenant_id=tenant.id, name="Rent Expense", code="5001", account_type="EXPENSE", account_group="Expenses", is_active=True)
    
    db_session.add_all([cash_acc, bank_acc, exp_acc])
    db_session.commit()
    
    headers = _auth_headers(user, tenant)
    
    # 1. Invalid accounts (not Cash/Bank)
    resp = client.post("/api/v1/accounting/contra", json={
        "entry_date": "2026-04-15",
        "debit_account_id": str(bank_acc.id),
        "credit_account_id": str(exp_acc.id),
        "amount": "500.00",
        "description": "Withdraw cash"
    }, headers=headers)
    assert resp.status_code == 400
    
    # 2. Valid Contra Entry
    resp = client.post("/api/v1/accounting/contra", json={
        "entry_date": "2026-04-15",
        "debit_account_id": str(cash_acc.id),
        "credit_account_id": str(bank_acc.id),
        "amount": "500.00",
        "description": "Withdraw cash"
    }, headers=headers)
    assert resp.status_code == 201
    
    # Verify account balances updated
    db_session.expire_all()
    assert cash_acc.current_balance == Decimal("1500.00")
    assert bank_acc.current_balance == Decimal("4500.00")


def test_sprint_opening_balances(db_session, client):
    tenant = Tenant(id=uuid.uuid4(), legal_name="Open Bal Co", tax_mode="NON_GST")
    db_session.add(tenant)
    user = User(id=uuid.uuid4(), email="open@test.com", password_hash=get_password_hash("Password123!"), full_name="Open User", is_active=True)
    db_session.add(user)
    membership = TenantMembership(tenant_id=tenant.id, user_id=user.id, role="owner", is_active=True)
    db_session.add(membership)

    today = date.today()
    fy_start = date(today.year if today.month >= 4 else today.year - 1, 4, 1)
    fy_end = date(fy_start.year + 1, 3, 31)
    fy = FinancialYear(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        name=f"FY {fy_start.year}-{str(fy_end.year)[2:]}",
        start_date=fy_start,
        end_date=fy_end,
        status="CURRENT",
        is_current=True
    )
    db_session.add(fy)

    acc = Account(id=uuid.uuid4(), tenant_id=tenant.id, name="Cash", code="1001", account_type="ASSET", account_group="Cash & Bank", opening_balance=Decimal("100.00"), current_balance=Decimal("100.00"), is_active=True)
    db_session.add(acc)
    db_session.commit()

    headers = _auth_headers(user, tenant)

    # Bulk update opening balance
    resp = client.post("/api/v1/accounting/opening-balances", json={
        "balances": [
            {
                "account_id": str(acc.id),
                "opening_balance": "1000.00"
            }
        ]
    }, headers=headers)
    assert resp.status_code == 200

    db_session.expire_all()
    assert acc.opening_balance == Decimal("1000.00")
    assert acc.current_balance == Decimal("1000.00")


def test_sprint_gst_return_status(db_session, client):
    tenant = Tenant(id=uuid.uuid4(), legal_name="GST Status Co", tax_mode="GST_REGULAR")
    db_session.add(tenant)
    user = User(id=uuid.uuid4(), email="gst_status@test.com", password_hash=get_password_hash("Password123!"), full_name="GST User", is_active=True)
    db_session.add(user)
    membership = TenantMembership(tenant_id=tenant.id, user_id=user.id, role="owner", is_active=True)
    db_session.add(membership)
    db_session.commit()

    headers = _auth_headers(user, tenant)

    # 1. Create a return status
    resp = client.post("/api/v1/gst/returns", json={
        "return_type": "GSTR1",
        "period_start": "2026-04-01",
        "period_end": "2026-04-30",
        "status": "DRAFT",
        "arn": "ARN1111"
    }, headers=headers)
    assert resp.status_code == 201
    ret_id = resp.json()["id"]

    # 2. Get returns
    resp = client.get("/api/v1/gst/returns", headers=headers)
    assert resp.status_code == 200
    assert len(resp.json()) == 1

    # 3. Update return status to FILED
    resp = client.put(f"/api/v1/gst/returns/{ret_id}", json={
        "status": "FILED",
        "arn": "ARN123456789"
    }, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["status"] == "FILED"
    assert resp.json()["arn"] == "ARN123456789"
    assert resp.json()["filed_at"] is not None
