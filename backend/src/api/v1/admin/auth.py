"""
Super Admin Authentication endpoints.
Separate from tenant-level auth — super admins can access all tenants.
"""
import uuid
import logging
import redis as _redis
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from src.core.config import settings
from src.core.database import get_db_session
from src.core.security import (
    create_access_token,
    create_refresh_token,
    get_password_hash,
    verify_password,
    decode_token,
)
from src.infrastructure.database.models import User, TenantMembership
from src.api.deps import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin", tags=["Admin Auth"])


# ── Redis helpers for refresh-token JTI allow-list ──────────────────────
def _get_redis_client():
    try:
        r = _redis.from_url(settings.REDIS_URL, decode_responses=True, socket_connect_timeout=1)
        r.ping()
        return r
    except Exception:
        return None


def _extract_refresh_jti(token: str) -> Optional[str]:
    try:
        payload = decode_token(token, expected_type="refresh")
        return payload.get("jti")
    except Exception:
        return None


def _register_refresh_jti(user_id: str, token: str):
    jti = _extract_refresh_jti(token)
    if not jti:
        return
    r = _get_redis_client()
    if r:
        try:
            r.sadd(f"refresh_jtis:{user_id}", jti)
            r.expire(f"refresh_jtis:{user_id}", settings.REFRESH_TOKEN_EXPIRE_DAYS * 86400)
        except Exception:
            pass


def _remove_refresh_jti(user_id: str, token: str):
    jti = _extract_refresh_jti(token)
    if not jti:
        return
    r = _get_redis_client()
    if r:
        try:
            r.srem(f"refresh_jtis:{user_id}", jti)
        except Exception:
            pass


def _is_refresh_jti_valid(user_id: str, token: str) -> bool:
    jti = _extract_refresh_jti(token)
    if not jti:
        return False
    r = _get_redis_client()
    if r:
        try:
            return r.sismember(f"refresh_jtis:{user_id}", jti)
        except Exception:
            return False
    return True  # no Redis — fall back to allowing (dev/test)


# ── Admin audit log helper ──────────────────────────────────────────────
def _log_audit(db: Session, action: str, user_id: str = None, request: Request = None, details: dict = None):
    """Lightweight audit entry — no tenant_id for admin actions."""
    from src.infrastructure.database.models import AuditLog
    entry = AuditLog(
        id=str(uuid.uuid4()),
        action=action,
        user_id=user_id,
        details=details or {},
        ip_address=request.client.host if request and request.client else None,
    )
    db.add(entry)


# ── Request / response schemas ──────────────────────────────────────────
class AdminLoginRequest(BaseModel):
    email: EmailStr
    password: str


class AdminLoginResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: dict


class AdminRefreshRequest(BaseModel):
    refresh_token: str


def require_super_admin(user: User = Depends(get_current_user)) -> User:
    """Dependency that requires the user to be a super admin."""
    if not user.is_super_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Super admin access required."
        )
    return user


@router.post("/login", response_model=AdminLoginResponse)
async def admin_login(request: Request, payload: AdminLoginRequest, db: Session = Depends(get_db_session)):
    """Super admin login — requires is_super_admin flag."""
    user = db.query(User).filter(
        User.email == payload.email,
        User.deleted_at == None
    ).first()

    if not user:
        _log_audit(db, "admin.login.failed", details={"email": payload.email}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password."
        )

    if not user.is_super_admin:
        _log_audit(db, "admin.login.denied", user_id=str(user.id), details={"reason": "not_super_admin"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Super admin access required."
        )

    if not user.is_active:
        _log_audit(db, "admin.login.blocked", user_id=str(user.id), details={"reason": "deactivated"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Account is deactivated."
        )

    if not user.email_verified:
        _log_audit(db, "admin.login.denied", user_id=str(user.id), details={"reason": "email_not_verified"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email is not verified."
        )

    # Check account lockout
    if user.locked_until and user.locked_until > datetime.now(timezone.utc):
        _log_audit(db, "admin.login.blocked", user_id=str(user.id), details={"reason": "locked"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Account is temporarily locked due to too many failed login attempts."
        )

    if not verify_password(payload.password, user.password_hash):
        user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
        if user.failed_login_attempts >= 5:
            user.locked_until = datetime.now(timezone.utc) + timedelta(minutes=15)
        db.commit()
        _log_audit(db, "admin.login.failed", user_id=str(user.id), request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password."
        )

    # Success — reset attempts
    user.failed_login_attempts = 0
    user.locked_until = None
    user.last_login_at = datetime.now(timezone.utc)

    # Create tokens — admin uses the same token format, JTI allow-list
    access_token = create_access_token(str(user.id), scopes=["admin", "super_admin"])
    refresh_token = create_refresh_token(str(user.id))
    _register_refresh_jti(str(user.id), refresh_token)

    _log_audit(db, "admin.login.success", user_id=str(user.id), request=request)
    db.commit()

    return AdminLoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        user={
            "id": str(user.id),
            "email": user.email,
            "full_name": user.full_name,
            "is_super_admin": True,
        }
    )


@router.post("/refresh")
async def admin_refresh_token(request: Request, payload: AdminRefreshRequest, db: Session = Depends(get_db_session)):
    """Refresh admin access token — same JTI rotation as tenant auth."""
    token = payload.refresh_token
    if not token:
        raise HTTPException(status_code=400, detail="refresh_token is required.")

    try:
        token_payload = decode_token(token, expected_type="refresh")
        user_id_str = token_payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=401, detail="Invalid token claims.")
        user_id = uuid.UUID(user_id_str)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate refresh credentials."
        )

    if not _is_refresh_jti_valid(user_id_str, token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has been revoked."
        )

    user = db.query(User).filter(User.id == user_id, User.deleted_at == None).first()
    if not user or not user.is_active or not user.is_super_admin:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account is deactivated, not found, or not a super admin."
        )

    # Rotate: drop old JTI, register new token
    new_access_token = create_access_token(str(user.id), scopes=["admin", "super_admin"])
    new_refresh_token = create_refresh_token(str(user.id))

    _remove_refresh_jti(str(user.id), token)
    _register_refresh_jti(str(user.id), new_refresh_token)

    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,
        "token_type": "bearer"
    }


@router.get("/me")
async def admin_me(user: User = Depends(require_super_admin)):
    """Get current admin profile."""
    return {
        "id": str(user.id),
        "email": user.email,
        "full_name": user.full_name,
        "is_super_admin": user.is_super_admin,
        "is_active": user.is_active,
        "last_login_at": user.last_login_at.isoformat() if user.last_login_at else None,
    }
