from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session, joinedload
import uuid
import re
import logging
import threading
from typing import List, Optional, Union
from datetime import datetime, timedelta, timezone
import redis

from src.core.database import get_db_session, set_db_tenant_context
from src.infrastructure.database.models import User, Tenant, TenantMembership, PasswordResetToken, AuditLog
from src.schemas.auth_schemas import UserRegister, UserLogin, TokenResponse, UserResponse, SchemaBase, Login2FAResponse, TwoFactorChallengeRequest
from src.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    create_2fa_challenge_token,
    ROLE_PERMISSIONS
)
from pydantic import BaseModel
from src.api.deps import get_current_user
from src.core.config import settings
from src.core.rate_limiter import limiter

logger = logging.getLogger(__name__)

# Development/test fallback for replay protection when Redis is unavailable.
# Values expire so a long-running process cannot accumulate hashes forever.
_USED_2FA_CHALLENGE_TOKENS = {}
_USED_2FA_CHALLENGE_TOKENS_LOCK = threading.Lock()

router = APIRouter(prefix="/auth", tags=["Authentication"])


def _validate_password_strength(password: str) -> None:
    """Validates password meets minimum strength requirements. Raises HTTPException on failure."""
    if len(password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters long.")
    if not re.search(r"[A-Z]", password):
        raise HTTPException(status_code=400, detail="Password must contain at least one uppercase letter.")
    if not re.search(r"[a-z]", password):
        raise HTTPException(status_code=400, detail="Password must contain at least one lowercase letter.")
    if not re.search(r"\d", password):
        raise HTTPException(status_code=400, detail="Password must contain at least one digit.")
    if not re.search(r'[!@#$%^&*(),.?":{}|<>\-_=+\[\]\\/]', password):
        raise HTTPException(status_code=400, detail="Password must contain at least one special character.")


class RefreshTokenRequest(BaseModel):
    refresh_token: str


def _get_redis_client():
    try:
        r = redis.from_url(settings.REDIS_URL, decode_responses=True, socket_connect_timeout=1)
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
    """Add a refresh token's jti to the user's allow-list."""
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
    """Remove a refresh token's jti from the user's allow-list."""
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
    """A refresh token is valid only if its jti is on the user's allow-list.

    This fails closed: a token whose jti is unknown (or whose allow-list
    cannot be consulted because Redis is down) is rejected, so a stolen or
    flushed token cannot be replayed. In test/dev without Redis we fall back
    to the JWT signature alone.
    """
    jti = _extract_refresh_jti(token)
    if not jti:
        return False
    r = _get_redis_client()
    if r:
        try:
            return bool(r.sismember(f"refresh_jtis:{user_id}", jti))
        except Exception:
            pass
    if settings.APP_ENV == "production":
        logger.critical("Redis unavailable during refresh jti check — failing closed")
        return False
    return True


def _log_audit(db: Session, action: str, user_id: str = None, tenant_id: str = None, details: dict = None, request: Request = None):
    log = AuditLog(
        action=action,
        actor_id=uuid.UUID(user_id) if user_id else None,
        tenant_id=uuid.UUID(tenant_id) if tenant_id else None,
        entity_type="Auth",
        after_state=details or {},
        ip_address=request.client.host if request and request.client else None,
    )
    db.add(log)


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
    email_verify_token_raw = uuid.uuid4().hex
    email_verify_token_hash = get_password_hash(email_verify_token_raw)
    email_verify_expires = datetime.now(timezone.utc) + timedelta(hours=24)
    user = User(
        email=payload.email,
        password_hash=hashed_password,
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        is_active=True,
        email_verified=False,
        email_verify_token=email_verify_token_hash,
        email_verify_expires=email_verify_expires,
    )
    # Dev/test environments have no SMTP, so there is no way to deliver the
    # verification link; auto-verify there so local registration stays
    # usable. Production always requires the emailed link.
    if not settings.is_production:
        user.email_verified = True
        user.email_verify_token = None
        user.email_verify_expires = None
    db.add(user)
    db.flush() # Flushes to allocate user ID

    # 3. Create Tenant company record
    from src.domains.company.services import detect_tax_mode
    tenant = Tenant(
        legal_name=payload.company_legal_name,
        trade_name=payload.company_legal_name,
        gstin=payload.company_gstin,
        pan=payload.company_pan,
        tax_mode=detect_tax_mode(payload.company_gstin),
    )
    db.add(tenant)
    db.flush() # Flushes to allocate tenant ID
    set_db_tenant_context(db, tenant.id)

    # 4. Set User as Owner of Tenant
    membership = TenantMembership(
        tenant_id=tenant.id,
        user_id=user.id,
        role="owner",
        is_active=True
    )
    db.add(membership)

    from src.domains.company.provisioning import provision_company_defaults
    provision_company_defaults(db, tenant, user.id)

    _log_audit(db, "user.register", user_id=str(user.id), tenant_id=str(tenant.id), request=request)
    db.commit()
    db.refresh(user)

    # 5. Log verification token (dev mode — no real email sent)
    # Verification secrets must never be written to application logs.
    logger.info("Email verification challenge issued for user %s", user.id)

    return user

@router.post("/login", response_model=Union[TokenResponse, Login2FAResponse])
@limiter.limit(settings.RATE_LIMIT_LOGIN)
def login_user(request: Request, payload: UserLogin, db: Session = Depends(get_db_session)):
    # 1. Query user
    user = db.query(User).filter(User.email == payload.email, User.deleted_at == None).first()
    if not user:
        _log_audit(db, "login.failed", details={"email": payload.email}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password."
        )

    # 2. Check account lockout
    if user.locked_until and user.locked_until > datetime.now(timezone.utc):
        _log_audit(db, "login.blocked", user_id=str(user.id), details={"reason": "locked"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Account is temporarily locked due to too many failed login attempts. Try again later."
        )

    # 3. Verify password
    if not verify_password(payload.password, user.password_hash):
        user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
        if user.failed_login_attempts >= 5:
            user.locked_until = datetime.now(timezone.utc) + timedelta(minutes=15)
            _log_audit(db, "login.locked", user_id=str(user.id), details={"attempts": user.failed_login_attempts}, request=request)
        else:
            _log_audit(db, "login.failed", user_id=str(user.id), details={"attempts": user.failed_login_attempts}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password."
        )

    # 4. Reset failed attempts on successful login
    user.failed_login_attempts = 0
    user.locked_until = None

    if not user.is_active:
        _log_audit(db, "login.blocked", user_id=str(user.id), details={"reason": "deactivated"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User account is deactivated."
        )

    if not user.email_verified:
        _log_audit(db, "login.blocked", user_id=str(user.id), details={"reason": "email_unverified"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email is not verified. Please verify your email before signing in."
        )

    # 5. Check if 2FA (TOTP) is enabled
    if user.totp_enabled:
        challenge_token = create_2fa_challenge_token(str(user.id))
        challenge_expiry = datetime.now(timezone.utc) + timedelta(minutes=5)
        _log_audit(db, "login.2fa_required", user_id=str(user.id), request=request)
        db.commit()
        return Login2FAResponse(
            requires_2fa=True,
            challenge_token=challenge_token,
            challenge_expiry=challenge_expiry
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
    _register_refresh_jti(str(user.id), refresh_token)

    _log_audit(db, "login.success", user_id=str(user.id), request=request)
    db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token
    )

@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("30/minute")
def refresh_token(
    request: Request,
    payload: Optional[RefreshTokenRequest] = Body(None),
    db: Session = Depends(get_db_session)
):
    """Receives and validates a refresh token. Accepts from JSON body only."""
    token = payload.refresh_token if payload else None
    if not token:
        raise HTTPException(status_code=400, detail="refresh_token is required in the request body.")
    try:
        payload = decode_token(token, expected_type="refresh")
        user_id_str = payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=401, detail="Invalid token claims.")
        user_id = uuid.UUID(user_id_str)
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

    # Rotate: drop the old jti from the allow-list, register the new one
    _remove_refresh_jti(str(user.id), token)
    _register_refresh_jti(str(user.id), new_refresh_token)

    return TokenResponse(
        access_token=new_access_token,
        refresh_token=new_refresh_token
    )

@router.post("/logout")
def logout_user(
    request: Request,
    payload: Optional[Union[RefreshTokenRequest, str]] = Body(None),
):
    """Revokes a refresh token so it can no longer be used.

    Logout must work even when the access token has expired; the refresh token
    is the credential being revoked here.
    """
    refresh_token_str = (
        payload.refresh_token
        if isinstance(payload, RefreshTokenRequest)
        else payload
    )
    try:
        payload = decode_token(refresh_token_str, expected_type="refresh")
        user_id = payload.get("sub")
        if user_id:
            _remove_refresh_jti(user_id, refresh_token_str)
    except Exception:
        pass
    return {"detail": "Logged out successfully."}


@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user


class MembershipResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    tenant_name: str
    role: str
    is_active: bool


@router.get("/memberships", response_model=List[MembershipResponse])
def get_memberships(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    memberships = db.query(TenantMembership).options(
        joinedload(TenantMembership.tenant)
    ).filter(
        TenantMembership.user_id == current_user.id,
        TenantMembership.is_active == True
    ).all()
    return [
        {
            "id": m.id,
            "tenant_id": m.tenant_id,
            "tenant_name": m.tenant.legal_name if m.tenant else None,
            "role": m.role,
            "is_active": m.is_active,
        }
        for m in memberships
    ]


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@router.post("/change-password")
@limiter.limit("5/minute")
def change_password(
    request: Request,
    payload: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    """Allows an authenticated user to change their own password."""
    # Verify the current password
    if not verify_password(payload.current_password, current_user.password_hash):
        _log_audit(db, "password.change.failed", user_id=str(current_user.id), details={"reason": "wrong_current"}, request=request)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect."
        )

    # Validate new password strength
    _validate_password_strength(payload.new_password)

    # Hash and save the new password
    current_user.password_hash = get_password_hash(payload.new_password)
    _log_audit(db, "password.changed", user_id=str(current_user.id), request=request)
    db.commit()

    return {"detail": "Password changed successfully."}


class ForgotPasswordRequest(BaseModel):
    email: str


@router.post("/forgot-password")
@limiter.limit("3/minute")
def forgot_password(
    request: Request,
    payload: ForgotPasswordRequest,
    db: Session = Depends(get_db_session),
):
    """Sends a password reset link to the user's email."""
    user = db.query(User).filter(
        User.email == payload.email,
        User.deleted_at == None
    ).first()
    if not user:
        return {"detail": "If the email exists, a reset link has been sent."}

    import secrets
    from datetime import timedelta
    token_str = secrets.token_urlsafe(48)
    hashed_token = get_password_hash(token_str)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=1)

    reset = PasswordResetToken(
        user_id=user.id,
        token=hashed_token,
        expires_at=expires_at,
    )
    db.add(reset)

    from src.core.config import settings
    from src.common.email_helper import password_reset_email
    import smtplib
    from email.mime.text import MIMEText

    reset_link = f"{settings.APP_URL}/reset-password?token={token_str}&email={payload.email}"
    subject, html_body = password_reset_email(reset_link, user_name=user.full_name or "User")
    msg = MIMEText(html_body, "html")
    msg["Subject"] = subject
    msg["From"] = settings.EMAIL_FROM
    msg["To"] = payload.email

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                server.starttls()
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.send_message(msg)
    except Exception:
        logger.exception("Failed to send password reset email")

    _log_audit(db, "password.reset.requested", user_id=str(user.id), request=request)
    db.commit()
    return {"detail": "If the email exists, a reset link has been sent."}


class ResetPasswordRequest(BaseModel):
    email: str
    token: str
    new_password: str


@router.post("/reset-password")
@limiter.limit("5/minute")
def reset_password(
    request: Request,
    payload: ResetPasswordRequest,
    db: Session = Depends(get_db_session),
):
    """Resets the password using a valid reset token."""
    user = db.query(User).filter(
        User.email == payload.email,
        User.deleted_at == None
    ).first()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid reset link.")

    reset = db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.used_at == None,
        PasswordResetToken.expires_at > datetime.now(timezone.utc),
    ).order_by(PasswordResetToken.created_at.desc()).first()
    if not reset:
        raise HTTPException(status_code=400, detail="Invalid or expired reset token.")

    if not verify_password(payload.token, reset.token):
        raise HTTPException(status_code=400, detail="Invalid reset token.")

    _validate_password_strength(payload.new_password)

    user.password_hash = get_password_hash(payload.new_password)
    reset.used_at = datetime.now(timezone.utc)
    _log_audit(db, "password.reset.completed", user_id=str(user.id), request=request)
    db.commit()

    return {"detail": "Password reset successfully."}


# ---------------------------------------------------------------------------
# EMAIL VERIFICATION
# ---------------------------------------------------------------------------

@router.post("/verify-email")
@limiter.limit("5/minute")
def verify_email(request: Request, token: str, email: str, db: Session = Depends(get_db_session)):
    # Filter by email to avoid loading all unverified users (prevents DoS)
    user = db.query(User).filter(
        User.email == email,
        User.email_verify_token != None,
    ).first()
    if not user:
        raise HTTPException(status_code=400, detail="Invalid verification token.")
    if not verify_password(token, user.email_verify_token):
        raise HTTPException(status_code=400, detail="Invalid verification token.")
    if user.email_verify_expires and user.email_verify_expires < datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Verification token has expired.")
    user.email_verified = True
    user.email_verify_token = None
    user.email_verify_expires = None
    db.commit()
    return {"detail": "Email verified successfully."}


# ---------------------------------------------------------------------------
# TWO-FACTOR AUTHENTICATION (TOTP)
# ---------------------------------------------------------------------------

class TwoFactorTokenPayload(BaseModel):
    token: str


@router.post("/2fa/enable")
@limiter.limit("3/minute")
def enable_2fa(
    request: Request,
    payload: TwoFactorTokenPayload | None = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    from src.domains.auth.totp_service import generate_totp_secret, get_totp_uri, generate_qr_base64, verify_totp_spend

    # Rotating an already-active 2FA setup requires proof of control of the
    # CURRENT authenticator first; otherwise a stolen access token could
    # silently reset the user's second factor and lock them out.
    if current_user.totp_enabled:
        if not payload or not payload.token:
            raise HTTPException(status_code=400, detail="Current 2FA code is required to rotate the authenticator.")
        if not current_user.totp_secret or not verify_totp_spend(
            current_user.totp_secret, payload.token, str(current_user.id)
        ):
            raise HTTPException(status_code=400, detail="Invalid 2FA token.")

    # Stage the new secret in the pending column; it only becomes live after
    # /2fa/verify succeeds, so an abandoned setup never breaks an active
    # authenticator and first-time enrollment stays safe.
    secret = generate_totp_secret()
    current_user.totp_pending_secret = secret
    db.commit()
    uri = get_totp_uri(secret, current_user.email)
    qr = generate_qr_base64(uri)
    return {"secret": secret, "qr_code": qr, "uri": uri}


@router.post("/2fa/verify")
@limiter.limit("5/minute")
def verify_2fa(
    request: Request,
    payload: TwoFactorTokenPayload,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    from src.domains.auth.totp_service import verify_totp_spend
    pending = current_user.totp_pending_secret or current_user.totp_secret
    if not pending or not verify_totp_spend(pending, payload.token, str(current_user.id)):
        raise HTTPException(status_code=400, detail="Invalid 2FA token.")
    current_user.totp_secret = pending
    current_user.totp_pending_secret = None
    current_user.totp_enabled = True
    db.commit()
    return {"detail": "2FA enabled successfully."}


@router.post("/2fa/disable")
@limiter.limit("3/minute")
def disable_2fa(
    request: Request,
    payload: TwoFactorTokenPayload,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
):
    from src.domains.auth.totp_service import verify_totp_spend
    if not current_user.totp_secret or not verify_totp_spend(
        current_user.totp_secret, payload.token, str(current_user.id)
    ):
        raise HTTPException(status_code=400, detail="Invalid 2FA token.")
    current_user.totp_enabled = False
    current_user.totp_secret = None
    current_user.totp_pending_secret = None
    db.commit()
    return {"detail": "2FA disabled successfully."}


@router.post("/2fa/challenge", response_model=TokenResponse)
@limiter.limit("5/minute")
def verify_2fa_challenge(
    request: Request,
    payload: TwoFactorChallengeRequest,
    db: Session = Depends(get_db_session)
):
    import hashlib
    challenge_token = payload.challenge_token
    totp_code = payload.totp_code

    # 1. Prevent replay attacks by checking if already used
    token_hash = hashlib.sha256(challenge_token.encode()).hexdigest()
    redis_key = f"2fa_used:{token_hash}"

    r = _get_redis_client()
    if r:
        try:
            if r.get(redis_key):
                raise HTTPException(status_code=401, detail="Challenge token has already been used.")
        except HTTPException:
            raise
        except Exception:
            logger.warning("Unable to check 2FA challenge replay key")

    now = datetime.now(timezone.utc)
    with _USED_2FA_CHALLENGE_TOKENS_LOCK:
        expired_hashes = [
            used_hash for used_hash, expires_at in _USED_2FA_CHALLENGE_TOKENS.items()
            if expires_at <= now
        ]
        for used_hash in expired_hashes:
            _USED_2FA_CHALLENGE_TOKENS.pop(used_hash, None)

        if token_hash in _USED_2FA_CHALLENGE_TOKENS:
            raise HTTPException(status_code=401, detail="Challenge token has already been used.")

    # 2. Decode the challenge token
    try:
        token_payload = decode_token(challenge_token, expected_type="2fa_challenge")
        user_id_str = token_payload.get("sub")
        if not user_id_str:
            raise HTTPException(status_code=401, detail="Invalid challenge token.")
        user_id = uuid.UUID(user_id_str)
    except jwt.ExpiredSignatureError:
        _log_audit(db, "login.2fa.failed", details={"reason": "expired"}, request=request)
        db.commit()
        raise HTTPException(status_code=401, detail="Challenge token has expired.")
    except Exception as e:
        _log_audit(db, "login.2fa.failed", details={"reason": "invalid_token", "error": str(e)}, request=request)
        db.commit()
        raise HTTPException(status_code=401, detail="Invalid challenge token.")

    # 3. Load user
    user = db.query(User).filter(User.id == user_id, User.deleted_at == None).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid challenge token or inactive user.")

    # 4. Verify TOTP code (single-use: a captured code cannot be replayed)
    from src.domains.auth.totp_service import verify_totp_spend
    if not user.totp_secret or not verify_totp_spend(user.totp_secret, totp_code, str(user.id)):
        _log_audit(db, "login.2fa.failed", user_id=str(user.id), details={"reason": "invalid_code"}, request=request)
        db.commit()
        raise HTTPException(status_code=401, detail="Invalid 2FA code.")

    # 5. Mark token as used atomically to prevent two concurrent replays.
    if r:
        try:
            if not r.set(redis_key, "1", ex=300, nx=True):
                raise HTTPException(status_code=401, detail="Challenge token has already been used.")
        except HTTPException:
            raise
        except Exception:
            logger.warning("Unable to record 2FA challenge replay key")
    with _USED_2FA_CHALLENGE_TOKENS_LOCK:
        if not r and token_hash in _USED_2FA_CHALLENGE_TOKENS:
            raise HTTPException(status_code=401, detail="Challenge token has already been used.")
        _USED_2FA_CHALLENGE_TOKENS[token_hash] = now + timedelta(minutes=5)

    # 6. Retrieve scopes/memberships
    memberships = db.query(TenantMembership).filter(
        TenantMembership.user_id == user.id,
        TenantMembership.is_active == True
    ).all()
    scopes = []
    for m in memberships:
        role_scopes = ROLE_PERMISSIONS.get(m.role.lower(), [])
        scopes.extend(role_scopes)
    scopes = list(set(scopes))

    # 7. Create access and refresh tokens
    access_token = create_access_token(user_id=str(user.id), scopes=scopes)
    refresh_token = create_refresh_token(user_id=str(user.id))
    _register_refresh_jti(str(user.id), refresh_token)

    _log_audit(db, "login.success", user_id=str(user.id), details={"method": "2fa"}, request=request)
    db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token
    )

