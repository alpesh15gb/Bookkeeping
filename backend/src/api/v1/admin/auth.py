"""
Super Admin Authentication endpoints.
Separate from tenant-level auth — super admins can access all tenants.
"""
import uuid
import logging
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
    decode_token,
    get_password_hash,
    verify_password,
)
from src.api.v1.auth import _is_refresh_jti_valid, _register_refresh_jti, _remove_refresh_jti
from src.infrastructure.database.models import User, TenantMembership
from src.api.deps import get_current_user
from src.common.audit_log import _log_audit

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin", tags=["Admin Auth"])


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

    # Create tokens with admin and super-admin scopes, then allow-list the refresh JTI.
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
    """Rotate a refresh token while preserving the super-admin boundary."""
    try:
        token_payload = decode_token(payload.refresh_token, expected_type="refresh")
        user_id = token_payload.get("sub")
        if not user_id or not _is_refresh_jti_valid(user_id, payload.refresh_token):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")
        user = db.query(User).filter(
            User.id == uuid.UUID(user_id),
            User.deleted_at == None,
            User.is_active == True,
            User.is_super_admin == True,
        ).first()
        if not user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")
        access_token = create_access_token(str(user.id), scopes=["admin", "super_admin"])
        refresh_token = create_refresh_token(str(user.id))
        _remove_refresh_jti(str(user.id), payload.refresh_token)
        _register_refresh_jti(str(user.id), refresh_token)
        return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer"}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")


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
