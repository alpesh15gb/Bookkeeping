from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session
import uuid
from typing import List, Optional
import redis

from src.core.database import get_db_session
from src.infrastructure.database.models import User, Tenant, TenantMembership
from src.schemas.auth_schemas import UserRegister, UserLogin, TokenResponse, UserResponse, SchemaBase
from src.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    ROLE_PERMISSIONS
)
from pydantic import BaseModel
from src.api.deps import get_current_user
from src.core.config import settings
from src.core.rate_limiter import limiter

router = APIRouter(prefix="/auth", tags=["Authentication"])


class RefreshTokenRequest(BaseModel):
    refresh_token: str


def _get_redis_client():
    try:
        r = redis.from_url(settings.REDIS_URL, decode_responses=True, socket_connect_timeout=1)
        r.ping()
        return r
    except Exception:
        return None


def _revoke_refresh_token(user_id: str, token: str):
    r = _get_redis_client()
    if r:
        try:
            r.sadd(f"refresh_tokens:{user_id}", token)
            r.expire(f"refresh_tokens:{user_id}", settings.REFRESH_TOKEN_EXPIRE_DAYS * 86400)
        except Exception:
            pass


def _is_refresh_token_revoked(user_id: str, token: str) -> bool:
    r = _get_redis_client()
    if r:
        try:
            return bool(r.sismember(f"refresh_tokens:{user_id}", token))
        except Exception:
            pass
    return False


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_REGISTER)
def register_user(request: Request, payload: UserRegister, db: Session = Depends(get_db_session)):
    # 1. Verify user doesn't already exist
    existing_user = db.query(User).filter(User.email == payload.email).first()
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A user with this email address already exists."
        )

    # 2. Create User record
    hashed_password = get_password_hash(payload.password)
    user = User(
        email=payload.email,
        password_hash=hashed_password,
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        is_active=True
    )
    db.add(user)
    db.flush() # Flushes to allocate user ID

    # 3. Create Tenant company record
    tenant = Tenant(
        legal_name=payload.company_legal_name,
        trade_name=payload.company_legal_name,
        gstin=payload.company_gstin,
        pan=payload.company_pan
    )
    db.add(tenant)
    db.flush() # Flushes to allocate tenant ID

    # 4. Set User as Owner of Tenant
    membership = TenantMembership(
        tenant_id=tenant.id,
        user_id=user.id,
        role="owner",
        is_active=True
    )
    db.add(membership)
    db.commit()
    db.refresh(user)
    return user

@router.post("/login", response_model=TokenResponse)
@limiter.limit(settings.RATE_LIMIT_LOGIN)
def login_user(request: Request, payload: UserLogin, db: Session = Depends(get_db_session)):
    # 1. Query user
    user = db.query(User).filter(User.email == payload.email, User.deleted_at == None).first()
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password."
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account is deactivated."
        )

    # 2. Query memberships to define scopes
    memberships = db.query(TenantMembership).filter(
        TenantMembership.user_id == user.id,
        TenantMembership.is_active == True
    ).all()

    # Map user roles scopes
    scopes = []
    for m in memberships:
        role_scopes = ROLE_PERMISSIONS.get(m.role.lower(), [])
        scopes.extend(role_scopes)
    scopes = list(set(scopes)) # Unique permissions

    # 3. Create session tokens
    access_token = create_access_token(user_id=str(user.id), scopes=scopes)
    refresh_token = create_refresh_token(user_id=str(user.id))

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token
    )

@router.post("/refresh", response_model=TokenResponse)
def refresh_token(
    request: Request,
    payload: Optional[RefreshTokenRequest] = Body(None),
    refresh_token: Optional[str] = Query(None),
    db: Session = Depends(get_db_session)
):
    """Receives and validates a refresh token. Accepts from JSON body or query parameter."""
    token = payload.refresh_token if payload else None
    token = token or refresh_token
    if not token:
        raise HTTPException(status_code=400, detail="refresh_token is required.")
    try:
        payload = decode_token(token)
        if payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type.")
        user_id_str = payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=401, detail="Invalid token claims.")
        user_id = uuid.UUID(user_id_str)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate refresh credentials."
        )

    if _is_refresh_token_revoked(user_id_str, refresh_token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has been revoked."
        )

    user = db.query(User).filter(User.id == user_id, User.deleted_at == None).first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account is deactivated or not found."
        )

    # Re-evaluate memberships to define scopes
    memberships = db.query(TenantMembership).filter(
        TenantMembership.user_id == user.id,
        TenantMembership.is_active == True
    ).all()

    scopes = []
    for m in memberships:
        role_scopes = ROLE_PERMISSIONS.get(m.role.lower(), [])
        scopes.extend(role_scopes)
    scopes = list(set(scopes))

    new_access_token = create_access_token(user_id=str(user.id), scopes=scopes)
    new_refresh_token = create_refresh_token(user_id=str(user.id))

    # Revoke the old refresh token on rotation
    _revoke_refresh_token(str(user.id), refresh_token)

    return TokenResponse(
        access_token=new_access_token,
        refresh_token=new_refresh_token
    )

@router.post("/logout")
def logout_user(request: Request, refresh_token_str: str):
    """Revokes a refresh token so it can no longer be used."""
    try:
        payload = decode_token(refresh_token_str)
        user_id = payload.get("sub")
        if user_id:
            _revoke_refresh_token(user_id, refresh_token_str)
    except Exception:
        pass
    return {"detail": "Logged out successfully."}


@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user


class MembershipResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    role: str
    is_active: bool


@router.get("/memberships", response_model=List[MembershipResponse])
def get_memberships(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    memberships = db.query(TenantMembership).filter(
        TenantMembership.user_id == current_user.id,
        TenantMembership.is_active == True
    ).all()
    return memberships


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@router.post("/change-password")
def change_password(
    payload: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    """Allows an authenticated user to change their own password."""
    # Verify the current password
    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect."
        )

    # Validate new password length
    if len(payload.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 8 characters long."
        )

    # Hash and save the new password
    current_user.password_hash = get_password_hash(payload.new_password)
    db.commit()

    return {"detail": "Password changed successfully."}
