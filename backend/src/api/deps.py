from fastapi import Depends, HTTPException, Header, Request, status
from fastapi.security import OAuth2PasswordBearer
import uuid
from sqlalchemy.orm import Session

from src.core.database import get_db_session, tenant_context
from src.infrastructure.database.models import User, TenantMembership
from src.core.security import decode_token, ROLE_PERMISSIONS
from src.common.audit_log import set_audit_context

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db_session)
) -> User:
    """Validates JWT auth token and returns active User model."""
    try:
        payload = decode_token(token, expected_type="access")
        user_id_str = payload.get("sub")
        if not user_id_str or payload.get("type") != "access":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token type or claims."
            )
        user_id = uuid.UUID(user_id_str)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials."
        )

    user = db.query(User).filter(User.id == user_id, User.deleted_at == None).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User session not found or deactivated."
        )
    return user

def get_tenant_context(
    request: Request,
    x_tenant_id: str = Header(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db_session)
) -> uuid.UUID:
    """
    Enforces tenant context.
    Verifies user has active membership in the target Tenant.
    Sets 'tenant_context' contextvar to configure PostgreSQL RLS session.
    """
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="X-Tenant-ID must be a valid UUID."
        )

    membership = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == tenant_uuid,
        TenantMembership.user_id == current_user.id,
        TenantMembership.is_active == True
    ).first()

    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not have access to this tenant context."
        )

    tenant_context.set(tenant_uuid)
    set_audit_context(
        tenant_id=tenant_uuid,
        actor_id=current_user.id,
        actor_email=current_user.email,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return tenant_uuid

def enforce_permission(required_permission: str):
    """
    FastAPI Route Dependency generator checking scope mappings against
    user role permissions.
    """
    def check_scopes(
        request: Request,
        x_tenant_id: str = Header(...),
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db_session)
    ) -> uuid.UUID:
        try:
            tenant_uuid = uuid.UUID(x_tenant_id)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="X-Tenant-ID must be a valid UUID."
            )

        membership = db.query(TenantMembership).filter(
            TenantMembership.tenant_id == tenant_uuid,
            TenantMembership.user_id == current_user.id,
            TenantMembership.is_active == True
        ).first()

        if not membership:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User does not have access to this tenant context."
            )

        user_permissions = ROLE_PERMISSIONS.get(membership.role.lower(), [])
        if required_permission not in user_permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Operation requires permission scope: {required_permission}"
            )

        tenant_context.set(tenant_uuid)
        set_audit_context(
            tenant_id=tenant_uuid,
            actor_id=current_user.id,
            actor_email=current_user.email,
            ip_address=request.client.host if request.client else None,
            user_agent=request.headers.get("user-agent"),
        )
        return tenant_uuid
    return check_scopes
