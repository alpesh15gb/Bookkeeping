import uuid
from datetime import datetime, timezone

import pyotp
import pytest

from src.core.security import create_access_token, get_password_hash
from src.infrastructure.database.models import Tenant, TenantMembership, User


def _auth_headers(user, tenant):
    token = create_access_token(user_id=str(user.id))
    return {"Authorization": f"Bearer {token}", "X-Tenant-ID": str(tenant.id)}


def _make_user(db_session, email, *, totp_secret=None, totp_enabled=False):
    tenant = Tenant(id=uuid.uuid4(), legal_name=f"2FA {email}", tax_mode="NON_GST")
    db_session.add(tenant)
    user = User(
        id=uuid.uuid4(),
        email=email,
        password_hash=get_password_hash("Secure@123"),
        full_name="2FA User",
        is_active=True,
        email_verified=True,
        totp_secret=totp_secret,
        totp_enabled=totp_enabled,
    )
    db_session.add(user)
    db_session.add(TenantMembership(tenant_id=tenant.id, user_id=user.id, role="owner", is_active=True))
    db_session.commit()
    return user, tenant


def test_2fa_first_time_enable_stages_pending_secret(db_session, client):
    user, tenant = _make_user(db_session, "first@test.com")
    headers = _auth_headers(user, tenant)

    # First-time enable: no body required; secret is staged as pending only,
    # never written to the live secret before verification.
    resp = client.post("/api/v1/auth/2fa/enable", headers=headers)
    assert resp.status_code == 200
    first_secret = resp.json()["secret"]
    db_session.refresh(user)
    assert user.totp_pending_secret == first_secret
    assert user.totp_secret is None
    assert user.totp_enabled is False

    # Verify promotes the pending secret and activates 2FA.
    code = pyotp.TOTP(first_secret).now()
    resp = client.post("/api/v1/auth/2fa/verify", headers=headers, json={"token": code})
    assert resp.status_code == 200
    db_session.refresh(user)
    assert user.totp_secret == first_secret
    assert user.totp_pending_secret is None
    assert user.totp_enabled is True


def test_2fa_rotation_requires_current_code(db_session, client):
    secret = pyotp.random_base32()
    user, tenant = _make_user(db_session, "rotate@test.com", totp_secret=secret, totp_enabled=True)
    headers = _auth_headers(user, tenant)

    # Rotation without a current code is refused.
    resp = client.post("/api/v1/auth/2fa/enable", headers=headers)
    assert resp.status_code == 400
    assert "required" in resp.json()["detail"]

    # Rotation with a wrong code is refused and the live secret survives.
    resp = client.post("/api/v1/auth/2fa/enable", headers=headers, json={"token": "000000"})
    assert resp.status_code == 400
    db_session.refresh(user)
    assert user.totp_secret == secret
    assert user.totp_enabled is True

    # Rotation with the current code stages a pending secret but keeps the
    # live authenticator working until the new code is verified.
    current_code = pyotp.TOTP(secret).now()
    resp = client.post("/api/v1/auth/2fa/enable", headers=headers, json={"token": current_code})
    assert resp.status_code == 200
    second_secret = resp.json()["secret"]
    db_session.refresh(user)
    assert user.totp_secret == secret  # old authenticator still valid
    assert user.totp_pending_secret == second_secret

    # Verifying the new secret promotes it and clears the pending one.
    resp = client.post("/api/v1/auth/2fa/verify", headers=headers, json={"token": pyotp.TOTP(second_secret).now()})
    assert resp.status_code == 200
    db_session.refresh(user)
    assert user.totp_secret == second_secret
    assert user.totp_pending_secret is None


def test_totp_codes_are_single_use(db_session, client):
    secret = pyotp.random_base32()
    user, tenant = _make_user(db_session, "spend@test.com", totp_secret=secret, totp_enabled=True)

    def login():
        return client.post("/api/v1/auth/login", json={"email": "spend@test.com", "password": "Secure@123"})

    # First challenge consumes the code.
    code = pyotp.TOTP(secret).now()
    challenge = login().json()["challenge_token"]
    resp = client.post("/api/v1/auth/2fa/challenge", json={"challenge_token": challenge, "totp_code": code})
    assert resp.status_code == 200

    # The same code cannot be replayed against a fresh challenge.
    challenge2 = login().json()["challenge_token"]
    resp = client.post("/api/v1/auth/2fa/challenge", json={"challenge_token": challenge2, "totp_code": code})
    assert resp.status_code == 401

    # A fresh code in the next window still works.
    next_window_ts = int(datetime.now(timezone.utc).timestamp()) + 30
    next_code = pyotp.TOTP(secret).at(next_window_ts)
    challenge3 = login().json()["challenge_token"]
    resp = client.post("/api/v1/auth/2fa/challenge", json={"challenge_token": challenge3, "totp_code": next_code})
    assert resp.status_code == 200
