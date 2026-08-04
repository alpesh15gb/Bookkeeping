"""
ApexBooks offline-first sync layer for Bookkeeping-master.

Provides endpoints that the ApexBooks Flutter client expects:
  - POST /bootstrap       — one-shot tenant+company+user creation
  - POST /auth/token      — simplified JWT login
  - POST /sync/push       — ingest client-generated events
  - GET  /sync/pull       — incremental event pull

The event processor in this module translates ApexBooks event types into
Bookkeeping-master domain operations (Account, Contact, Product, Invoice,
Bill, JournalEntry, etc.) using the existing service layer.
"""

import uuid
import logging
import hmac
from datetime import date, datetime, timezone, timedelta
from decimal import Decimal
from typing import Any, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, EmailStr
from sqlalchemy import select, BigInteger
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError

from src.core.config import settings
from src.core.rate_limiter import limiter
from src.core.database import get_db_session, Base, engine, set_db_tenant_context, tenant_context
from src.core.security import (
    verify_password,
    get_password_hash,
    create_access_token,
    decode_token,
    Permissions,
    ROLE_PERMISSIONS,
)
from src.infrastructure.database.models import (
    Account,
    BankStatement,
    BankTransaction,
    BankingProfile,
    Bill,
    BillLine,
    BillPayment,
    BillPaymentAllocation,
    Branch,
    Contact,
    CreditNote,
    CreditNoteLine,
    DebitNote,
    DebitNoteLine,
    DeliveryChallan,
    DeliveryChallanLine,
    FinancialYear,
    FinancialYearAudit,
    GoodsReceipt,
    GoodsReceiptLine,
    Invoice,
    InvoiceLine,
    InventoryAdjustment,
    InventoryAdjustmentLine,
    JournalEntry,
    JournalLine,
    NumberingSeries,
    OfflineNumberAllocation,
    Payment,
    PaymentAllocation,
    Product,
    PurchaseReturn,
    PurchaseReturnLine,
    SalesOrder,
    SalesOrderLine,
    SalesReturn,
    SalesReturnLine,
    StockLedger,
    SyncEvent,
    Tenant,
    TenantMembership,
    TenantSetting,
    Transfer,
    User,
)
from src.domains.company.provisioning import provision_company_defaults
from src.domains.company.services import (
    NumberingSeriesService,
    detect_tax_mode,
    derive_origin_state_code,
)
from src.domains.accounting.services import (
    AccountResolver,
    JournalEntryDraft,
    JournalLineDraft,
    LedgerPostingEngine,
    commit_ledger_draft,
)
from src.domains.accounting.auto_post import auto_post_invoice

logger = logging.getLogger("apexbooks_sync")

router = APIRouter(prefix="/apexbooks", tags=["ApexBooks Sync"])

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class SyncError(RuntimeError):
    """Raised inside the event processor to reject one event without failing
    the entire push batch.  The message is stored in processing_error."""


# ---------------------------------------------------------------------------
# Schemas — mirror ApexBooks Flutter client request/response types
# ---------------------------------------------------------------------------

class BootstrapRequest(BaseModel):
    tenant_name: str = Field(min_length=2, max_length=200)
    company_name: str = Field(min_length=2, max_length=200)
    company_legal_name: str = Field(min_length=2, max_length=250)
    gstin: str | None = Field(default=None, min_length=15, max_length=15)
    state_code: str = Field(pattern=r"^\d{2}$")
    admin_email: EmailStr
    admin_name: str = Field(min_length=2, max_length=160)
    admin_password: str = Field(min_length=12, max_length=256)


class BootstrapResponse(BaseModel):
    tenant_id: uuid.UUID
    company_id: uuid.UUID
    user_id: uuid.UUID
    financial_year_id: uuid.UUID
    branch_id: uuid.UUID


class LoginRequest(BaseModel):
    tenant_id: uuid.UUID
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int


class SyncEventInput(BaseModel):
    event_id: uuid.UUID
    company_id: uuid.UUID
    device_id: uuid.UUID
    aggregate_type: str = Field(min_length=1, max_length=60)
    aggregate_id: uuid.UUID
    event_type: str = Field(min_length=1, max_length=100)
    event_version: int = Field(ge=1)
    payload: dict[str, Any]
    occurred_at: datetime


class SyncPushRequest(BaseModel):
    events: list[SyncEventInput] = Field(max_length=500)


class SyncAcknowledgement(BaseModel):
    event_id: uuid.UUID
    server_sequence: int
    duplicate: bool
    error: str | None = None


class SyncPushResponse(BaseModel):
    acknowledgements: list[SyncAcknowledgement]


class SyncEventRead(SyncEventInput):
    server_sequence: int


class SyncPullResponse(BaseModel):
    events: list[SyncEventRead]
    next_cursor: int


class NumberAllocationRequest(BaseModel):
    device_id: uuid.UUID
    document_type: str = Field(min_length=1, max_length=50)
    series: str = Field(default="SALES", min_length=1, max_length=50)
    batch_size: int = Field(default=50, ge=5, le=500)
    previous_allocation_id: uuid.UUID | None = None


class NumberAllocationResponse(BaseModel):
    allocation_id: uuid.UUID
    company_id: uuid.UUID
    device_id: uuid.UUID
    financial_year_id: uuid.UUID
    document_type: str
    series: str
    prefix: str
    suffix: str | None
    padding_digits: int
    from_num: int
    to_num: int
    allocated_at: datetime

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_APEXBOOKS_ISS = "apexbooks"


def _tenant_context(tenant_id: uuid.UUID, db: Session | None = None) -> None:
    """Set tenant context for PostgreSQL RLS, including active transactions."""
    if db is not None:
        set_db_tenant_context(db, tenant_id)
    else:
        tenant_context.set(tenant_id)


def _micros_to_decimal(micros: int | None) -> Decimal:
    """Convert integer micros (10 000 = ₹1) to Decimal."""
    if micros is None:
        return Decimal("0")
    return Decimal(micros) / Decimal("10000")


def _basis_points_to_decimal(basis_points: int | None) -> Decimal:
    """Convert basis points (1800 = 18.00%) to Decimal percentage."""
    if basis_points is None:
        return Decimal("0")
    return Decimal(basis_points) / Decimal("100")


def _validated_document_number(
    db: Session,
    tenant_id: uuid.UUID,
    event: "SyncEvent",
    payload: dict[str, Any],
    document_type: str,
) -> str:
    allocation_id = payload.get("allocation_id")
    if not allocation_id:
        return str(
            payload.get("invoice_number")
            or payload.get("document_number")
            or event.aggregate_id
        )[:50].upper()
    try:
        allocation_uuid = uuid.UUID(str(allocation_id))
        raw_number = int(payload["number"])
    except (ValueError, TypeError, KeyError) as exc:
        raise SyncError(f"Invalid number allocation payload: {exc}")
    allocation = (
        db.query(OfflineNumberAllocation)
        .filter(
            OfflineNumberAllocation.id == allocation_uuid,
            OfflineNumberAllocation.tenant_id == tenant_id,
            OfflineNumberAllocation.device_id == event.device_id,
            OfflineNumberAllocation.document_type == document_type,
        )
        .first()
    )
    if allocation is None:
        raise SyncError("Document number allocation is not valid for this device")
    if raw_number < allocation.range_start or raw_number > allocation.range_end:
        raise SyncError("Document number is outside the allocated range")
    formatted = (
        f"{allocation.prefix}"
        f"{str(raw_number).zfill(allocation.padding_digits)}"
        f"{allocation.suffix or ''}"
    )
    supplied = payload.get("invoice_number") or payload.get("document_number")
    if supplied and str(supplied) != formatted:
        raise SyncError("Document number does not match its allocation")
    return formatted[:50].upper()


def _indian_fy_range(today: date | None = None) -> tuple[date, date, str]:
    """Return (start, end, name) for the current Indian financial year."""
    d = today or date.today()
    start_year = d.year if d.month >= 4 else d.year - 1
    start = date(start_year, 4, 1)
    end = date(start_year + 1, 3, 31)
    name = f"{start_year}-{str(start_year + 1)[2:]}"
    return start, end, name

# ---------------------------------------------------------------------------
# Auth dependency for ApexBooks-format JWT tokens
# ---------------------------------------------------------------------------

from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_legacy_bearer = HTTPBearer(auto_error=True)


class ApexBooksPrincipal:
    """Validated principal extracted from an ApexBooks-format JWT."""

    def __init__(self, user_id: uuid.UUID, tenant_id: uuid.UUID, permissions: list[str]) -> None:
        self.user_id = user_id
        self.tenant_id = tenant_id
        self.permissions = permissions

    def require(self, permission: str) -> None:
        if "*" not in self.permissions and permission not in self.permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing permission: {permission}",
            )


def get_legacy_principal(
    credentials: HTTPAuthorizationCredentials = Depends(_legacy_bearer),
    x_tenant_id: str | None = Header(None, alias="X-Tenant-ID"),
    db: Session = Depends(get_db_session),
) -> ApexBooksPrincipal:
    """Validate an ApexBooks-compatible JWT and return the sync principal.

    Offline-first clients created after the sync layer carry tenant_id and
    permissions in the token. The existing ApexBooks UI still signs in through
    the main auth API, whose token carries role scopes and sends X-Tenant-ID via
    the tenant interceptor. Support both shapes so foreground sync works for the
    active app without a separate login path.
    """
    try:
        payload = decode_token(credentials.credentials, expected_type="access")
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id_str = payload.get("sub")
    tenant_id_str = payload.get("tenant_id") or x_tenant_id
    permissions: list[str] = payload.get("permissions") or payload.get("scopes") or []

    if not user_id_str or not tenant_id_str:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing required claims (sub, tenant_id or X-Tenant-ID)",
        )

    try:
        user_id = uuid.UUID(user_id_str)
        tenant_id = uuid.UUID(tenant_id_str)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token contains malformed UUID claims",
        )

    # Verify user exists and is active
    user = db.query(User).filter(
        User.id == user_id,
        User.is_active == True,
    ).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )

    _tenant_context(tenant_id, db)

    # Verify tenant membership
    membership = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == tenant_id,
        TenantMembership.user_id == user_id,
        TenantMembership.is_active == True,
    ).first()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No active membership for this tenant",
        )

    return ApexBooksPrincipal(
        user_id=user_id,
        tenant_id=tenant_id,
        permissions=permissions,
    )

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

@router.post("/bootstrap", response_model=BootstrapResponse, status_code=201)
def bootstrap(
    request: BootstrapRequest,
    x_bootstrap_key: str = Header(...),
) -> BootstrapResponse:
    """One-shot tenant + company + user + financial-year + branch creation.

    This replicates the ApexBooks /v1/bootstrap endpoint semantics.
    """
    if (
        not settings.JWT_SECRET_KEY
        or len(settings.JWT_SECRET_KEY) < 24
        or not hmac.compare_digest(x_bootstrap_key, settings.JWT_SECRET_KEY)
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid bootstrap key",
        )

    from src.core.database import SessionLocal
    db = SessionLocal()
    try:
        # Check duplicate tenant by name
        existing = db.query(Tenant).filter(
            Tenant.legal_name == request.tenant_name,
        ).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Tenant '{request.tenant_name}' already exists",
            )

        tenant = Tenant(
            legal_name=request.tenant_name,
            trade_name=request.company_name,
            gstin=request.gstin.upper() if request.gstin else None,
            tax_mode=detect_tax_mode(request.gstin, None),
        )
        db.add(tenant)
        db.flush()
        _tenant_context(tenant.id, db)

        # Admin user
        user = User(
            email=request.admin_email.casefold(),
            password_hash=get_password_hash(request.admin_password),
            full_name=request.admin_name,
            is_active=True,
            email_verified=True,
        )
        db.add(user)
        db.flush()

        # Membership (owner role)
        membership = TenantMembership(
            tenant_id=tenant.id,
            user_id=user.id,
            role="owner",
            is_active=True,
        )
        db.add(membership)
        db.flush()

        # Branch "MAIN"
        branch = Branch(
            tenant_id=tenant.id,
            name="Main Branch",
            address={
                "street": "",
                "city": "",
                "state": "",
                "state_code": request.state_code,
                "pincode": "",
                "country": "India",
            },
        )
        db.add(branch)
        db.flush()

        # Financial year
        fy_start, fy_end, fy_name = _indian_fy_range()
        financial_year = FinancialYear(
            tenant_id=tenant.id,
            name=fy_name,
            start_date=fy_start,
            end_date=fy_end,
            status="CURRENT",
            is_current=True,
            created_by=user.id,
        )
        db.add(financial_year)
        db.flush()

        db.add(FinancialYearAudit(
            tenant_id=tenant.id,
            financial_year_id=financial_year.id,
            action="CREATED",
            detail="Financial year created during ApexBooks bootstrap.",
            performed_by=user.id,
        ))

        # Provision standard chart of accounts, numbering series, etc.
        provision_company_defaults(db, tenant, user.id, as_of=fy_start)

        db.commit()

        return BootstrapResponse(
            tenant_id=tenant.id,
            company_id=tenant.id,
            user_id=user.id,
            financial_year_id=financial_year.id,
            branch_id=branch.id,
        )
    except HTTPException:
        db.rollback()
        raise
    except Exception as exc:
        db.rollback()
        logger.error("Bootstrap failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Bootstrap failed: {exc}",
        )
    finally:
        db.close()
        tenant_context.set(None)

# ---------------------------------------------------------------------------
# Auth / Token
# ---------------------------------------------------------------------------

@router.post("/auth/token", response_model=TokenResponse)
@limiter.limit(settings.RATE_LIMIT_LOGIN)
def auth_token(
    request: Request,
    payload: LoginRequest,
    db: Session = Depends(get_db_session),
) -> TokenResponse:
    """Simplified JWT login matching ApexBooks /v1/auth/token.

    The returned token carries tenant_id and permissions claims so the
    ApexBooks client Principal can be reconstructed from the token alone.
    """
    now = datetime.now(timezone.utc)
    user = db.query(User).filter(
        User.email == payload.email.casefold(),
        User.is_active == True,
    ).first()
    if user is None:
        # Timing-safe comparison
        verify_password(payload.password, "$2b$12$" + "x" * 53)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect tenant, email, or password",
        )

    if user.locked_until and user.locked_until > now:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Account is temporarily locked due to too many failed login attempts. Try again later.",
        )

    if not verify_password(payload.password, user.password_hash):
        user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
        if user.failed_login_attempts >= 5:
            user.locked_until = now + timedelta(minutes=15)
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect tenant, email, or password",
        )

    # Verify tenant membership
    membership = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == payload.tenant_id,
        TenantMembership.user_id == user.id,
        TenantMembership.is_active == True,
    ).first()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not belong to this tenant",
        )

    permissions = list(ROLE_PERMISSIONS.get(membership.role.lower(), []))
    if Permissions.SYNC_AUTH not in permissions:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This role is not authorized for offline sync authentication.",
        )
    if user.totp_enabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Two-factor authentication is enabled. Use the primary auth login flow.",
        )

    user.failed_login_attempts = 0
    user.locked_until = None
    db.commit()

    # Build an ApexBooks-compatible token with the membership's actual scopes.
    lifetime = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    import jwt as pyjwt
    token_payload = {
        "sub": str(user.id),
        "tenant_id": str(payload.tenant_id),
        "permissions": permissions,
        "iss": _APEXBOOKS_ISS,
        "iat": now,
        "exp": now + lifetime,
        "type": "access",
    }
    token = pyjwt.encode(
        token_payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    return TokenResponse(
        access_token=token,
        expires_in=int(lifetime.total_seconds()),
    )

# ---------------------------------------------------------------------------
# Sync — Push
# ---------------------------------------------------------------------------

@router.post(
    "/number-allocations",
    response_model=NumberAllocationResponse,
)
def allocate_offline_numbers(
    request: NumberAllocationRequest,
    principal: ApexBooksPrincipal = Depends(get_legacy_principal),
    db: Session = Depends(get_db_session),
) -> NumberAllocationResponse:
    """Lease a collision-free document-number block to one installation."""
    principal.require(Permissions.SYNC_WRITE)
    document_type = request.document_type.strip().upper()
    series_label = request.series.strip().upper()

    financial_year = (
        db.query(FinancialYear)
        .filter(
            FinancialYear.tenant_id == principal.tenant_id,
            FinancialYear.is_current == True,
        )
        .first()
    )
    if financial_year is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No current financial year is configured",
        )
    if financial_year.status in {"LOCKED", "ARCHIVED"}:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The current financial year is locked",
        )

    if request.previous_allocation_id is not None:
        previous = (
            db.query(OfflineNumberAllocation)
            .filter(
                OfflineNumberAllocation.id == request.previous_allocation_id,
                OfflineNumberAllocation.tenant_id == principal.tenant_id,
                OfflineNumberAllocation.device_id == request.device_id,
            )
            .first()
        )
        if previous is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Previous number allocation was not found",
            )
        previous.is_active = False
    else:
        existing = (
            db.query(OfflineNumberAllocation)
            .filter(
                OfflineNumberAllocation.tenant_id == principal.tenant_id,
                OfflineNumberAllocation.device_id == request.device_id,
                OfflineNumberAllocation.financial_year_id == financial_year.id,
                OfflineNumberAllocation.document_type == document_type,
                OfflineNumberAllocation.series == series_label,
                OfflineNumberAllocation.is_active == True,
            )
            .order_by(OfflineNumberAllocation.allocated_at.desc())
            .first()
        )
        if existing is not None:
            return NumberAllocationResponse(
                allocation_id=existing.id,
                company_id=principal.tenant_id,
                device_id=existing.device_id,
                financial_year_id=existing.financial_year_id,
                document_type=existing.document_type,
                series=existing.series,
                prefix=existing.prefix,
                suffix=existing.suffix,
                padding_digits=existing.padding_digits,
                from_num=existing.range_start,
                to_num=existing.range_end,
                allocated_at=existing.allocated_at,
            )

    numbering_series = (
        db.query(NumberingSeries)
        .filter(
            NumberingSeries.tenant_id == principal.tenant_id,
            NumberingSeries.document_type == document_type,
            NumberingSeries.is_active == True,
        )
        .with_for_update()
        .first()
    )
    if numbering_series is None:
        numbering_series = NumberingSeriesService.seed_default_series(
            db,
            principal.tenant_id,
            document_type,
        )
        db.flush()

    range_start = numbering_series.next_number
    range_end = range_start + request.batch_size - 1
    numbering_series.next_number = range_end + 1
    allocation = OfflineNumberAllocation(
        tenant_id=principal.tenant_id,
        device_id=request.device_id,
        financial_year_id=financial_year.id,
        numbering_series_id=numbering_series.id,
        document_type=document_type,
        series=series_label,
        prefix=numbering_series.prefix or "",
        suffix=numbering_series.suffix,
        padding_digits=numbering_series.padding_digits,
        range_start=range_start,
        range_end=range_end,
    )
    db.add(allocation)
    db.commit()
    db.refresh(allocation)
    return NumberAllocationResponse(
        allocation_id=allocation.id,
        company_id=principal.tenant_id,
        device_id=allocation.device_id,
        financial_year_id=allocation.financial_year_id,
        document_type=allocation.document_type,
        series=allocation.series,
        prefix=allocation.prefix,
        suffix=allocation.suffix,
        padding_digits=allocation.padding_digits,
        from_num=allocation.range_start,
        to_num=allocation.range_end,
        allocated_at=allocation.allocated_at,
    )


@router.get("/reference-snapshot")
def reference_snapshot(
    principal: ApexBooksPrincipal = Depends(get_legacy_principal),
    db: Session = Depends(get_db_session),
) -> dict[str, Any]:
    """Return the tenant reference data required for safe offline posting.

    The incremental event stream only contains changes submitted through the
    sync API. Existing master data and changes made through normal CRUD routes
    must therefore be bootstrapped explicitly on every installation.
    """
    principal.require(Permissions.SYNC_READ)
    tenant_id = principal.tenant_id
    resolver = AccountResolver(db, tenant_id)
    for account_key in (
        "assets.cash",
        "assets.bank",
        "assets.upi",
        "assets.pos",
        "assets.inventory",
        "liability.grir",
        "sales_revenue",
        "purchases",
        "cogs",
        "cgst_output",
        "sgst_output",
        "igst_output",
        "utgst_output",
        "cess_output",
        "cgst_input",
        "sgst_input",
        "igst_input",
        "utgst_input",
        "cess_input",
        "inventory_adjustment",
        "round_off",
    ):
        resolver.resolve(account_key)
    contacts = (
        db.query(Contact)
        .filter(Contact.tenant_id == tenant_id, Contact.deleted_at == None)
        .order_by(Contact.name, Contact.id)
        .all()
    )
    control_accounts: dict[uuid.UUID, dict[str, uuid.UUID | None]] = {}
    for contact in contacts:
        contact_type = (contact.contact_type or "").upper()
        receivable = (
            resolver.resolve(f"customer.{contact.id}")
            if contact_type in {"CUSTOMER", "BOTH"}
            else None
        )
        payable = (
            resolver.resolve(f"vendor.{contact.id}")
            if contact_type in {"VENDOR", "BOTH"}
            else None
        )
        control_accounts[contact.id] = {
            "receivable": receivable,
            "payable": payable,
        }

    # AccountResolver may provision deterministic control accounts. Persist
    # them before returning their IDs, then query the complete account list.
    db.commit()
    accounts = (
        db.query(Account)
        .filter(Account.tenant_id == tenant_id, Account.deleted_at == None)
        .order_by(Account.code, Account.id)
        .all()
    )
    products = (
        db.query(Product)
        .filter(Product.tenant_id == tenant_id, Product.deleted_at == None)
        .order_by(Product.name, Product.id)
        .all()
    )

    return {
        "company_id": str(tenant_id),
        "origin_state_code": derive_origin_state_code(
            db.query(Tenant).filter(Tenant.id == tenant_id).one().gstin,
        ),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "accounts": [
            {
                "id": str(account.id),
                "code": account.code,
                "name": account.name,
                "account_type": account.account_type,
                "account_group": account.account_group,
                "parent_id": str(account.parent_id) if account.parent_id else None,
                "opening_balance": str(account.opening_balance or 0),
                "is_active": account.is_active,
                "updated_at": account.updated_at.isoformat(),
            }
            for account in accounts
        ],
        "contacts": [
            {
                "id": str(contact.id),
                "name": contact.name,
                "email": contact.email,
                "phone": contact.phone,
                "contact_type": contact.contact_type,
                "gstin": contact.gstin,
                "state_code": contact.state_code,
                "opening_balance": str(contact.opening_balance or 0),
                "receivable_account_id": (
                    str(control_accounts[contact.id]["receivable"])
                    if control_accounts[contact.id]["receivable"]
                    else None
                ),
                "payable_account_id": (
                    str(control_accounts[contact.id]["payable"])
                    if control_accounts[contact.id]["payable"]
                    else None
                ),
                "is_active": contact.is_active,
                "updated_at": contact.updated_at.isoformat(),
            }
            for contact in contacts
        ],
        "products": [
            {
                "id": str(product.id),
                "name": product.name,
                "sku": product.sku,
                "uom": product.uom,
                "hsn_sac": product.hsn_sac,
                "sales_price": str(product.sales_price or 0),
                "purchase_price": str(product.purchase_price or 0),
                "gst_rate": str(product.gst_rate or 0),
                "current_stock": str(product.current_stock or 0),
                "is_active": product.is_active,
                "updated_at": product.updated_at.isoformat(),
            }
            for product in products
        ],
    }


@router.post("/sync/push", response_model=SyncPushResponse)
def sync_push(
    request: SyncPushRequest,
    principal: ApexBooksPrincipal = Depends(get_legacy_principal),
    db: Session = Depends(get_db_session),
) -> SyncPushResponse:
    """Accept ApexBooks client events, store them idempotently, and process
    each against the Bookkeeping-master domain."""
    principal.require(Permissions.SYNC_WRITE)
    _tenant_context(principal.tenant_id, db)

    acknowledgements: list[SyncAcknowledgement] = []

    for incoming in request.events:
        # The client contract uses the tenant id as its company id. Reject an
        # arbitrary client-supplied scope before it can enter this tenant's
        # event stream and advance the pull cursor.
        if incoming.company_id != principal.tenant_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Event company does not match the authenticated tenant",
            )

        # Idempotency check
        existing = db.query(SyncEvent).filter(
            SyncEvent.tenant_id == principal.tenant_id,
            SyncEvent.event_id == incoming.event_id,
        ).first()
        if existing is not None:
            acknowledgements.append(SyncAcknowledgement(
                event_id=existing.event_id,
                server_sequence=existing.server_sequence,
                duplicate=True,
                error=existing.processing_error,
            ))
            continue

        event = SyncEvent(
            event_id=incoming.event_id,
            tenant_id=principal.tenant_id,
            company_id=incoming.company_id,
            device_id=incoming.device_id,
            aggregate_type=incoming.aggregate_type,
            aggregate_id=incoming.aggregate_id,
            event_type=incoming.event_type,
            event_version=incoming.event_version,
            payload=incoming.payload,
            occurred_at=incoming.occurred_at,
        )
        db.add(event)
        # Allocate the durable pull sequence before processing.  This keeps
        # even rejected events returnable as structured acknowledgements.
        db.flush()

        # Process the event
        try:
            # A malformed event must not roll back the surrounding push batch
            # or leave the SQLAlchemy session unusable for its acknowledgement.
            with db.begin_nested():
                _process_event(
                    db,
                    principal.tenant_id,
                    incoming.company_id,
                    event,
                    principal.user_id,
                )
                event.processed = True
        except SyncError as exc:
            event.processed = False
            event.processing_error = str(exc)
            logger.warning("Sync event %s not processed: %s", incoming.event_id, exc)
        except Exception as exc:
            event.processed = False
            event.processing_error = f"{type(exc).__name__}: {exc}"
            logger.error("Sync event %s failed", incoming.event_id, exc_info=True)

        db.flush()
        acknowledgements.append(SyncAcknowledgement(
            event_id=event.event_id,
            server_sequence=event.server_sequence,
            duplicate=False,
            error=event.processing_error,
        ))

    db.commit()
    return SyncPushResponse(acknowledgements=acknowledgements)


@router.get("/sync/pull", response_model=SyncPullResponse)
def sync_pull(
    after: int = Query(default=0, ge=0),
    limit: int = Query(default=500, ge=1, le=1000),
    principal: ApexBooksPrincipal = Depends(get_legacy_principal),
    db: Session = Depends(get_db_session),
) -> SyncPullResponse:
    """Return events with server_sequence > after, ordered ascending.

    The client uses next_cursor as the 'after' value for the next pull.
    """
    principal.require(Permissions.SYNC_READ)
    events = (
        db.query(SyncEvent)
        .filter(
            SyncEvent.tenant_id == principal.tenant_id,
            SyncEvent.server_sequence > after,
            SyncEvent.processed == True,
        )
        .order_by(SyncEvent.server_sequence)
        .limit(limit)
        .all()
    )
    result = [
        SyncEventRead(
            event_id=e.event_id,
            company_id=e.company_id,
            device_id=e.device_id,
            aggregate_type=e.aggregate_type,
            aggregate_id=e.aggregate_id,
            event_type=e.event_type,
            event_version=e.event_version,
            payload=e.payload,
            occurred_at=e.occurred_at,
            server_sequence=e.server_sequence,
        )
        for e in events
    ]
    return SyncPullResponse(
        events=result,
        next_cursor=result[-1].server_sequence if result else after,
    )

# ---------------------------------------------------------------------------
# Event Processor
# ---------------------------------------------------------------------------

def _process_event(
    db: Session,
    tenant_id: uuid.UUID,
    company_id: uuid.UUID,
    event: SyncEvent,
    actor_id: uuid.UUID,
) -> None:
    """Dispatch one ApexBooks event to the appropriate handler."""
    handler = _EVENT_HANDLERS.get(event.event_type)
    if handler is None:
        raise SyncError(f"Unknown event type: {event.event_type}")
    handler(db, tenant_id, company_id, event, actor_id)


def _handle_account_created(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    type_map = {
        "asset": "ASSET", "liability": "LIABILITY", "equity": "EQUITY",
        "income": "REVENUE", "expense": "EXPENSE",
    }
    acct_type = type_map.get(p.get("account_type", ""))
    if not acct_type:
        raise SyncError(f"Unsupported account_type: {p.get('account_type')}")

    account = Account(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        name=p.get("name", ""),
        code=p.get("code", "").upper(),
        account_type=acct_type,
    )
    try:
        db.add(account)
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = db.query(Account).filter(
            Account.tenant_id == tenant_id,
            Account.code == account.code,
        ).first()
        if existing:
            return
        raise SyncError("Account code already exists")


def _handle_party_created(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    kind = p.get("kind", "customer")
    contact_type = "CUSTOMER" if kind == "customer" else ("VENDOR" if kind == "supplier" else "BOTH")

    gstin = (p.get("gstin") or "").strip().upper() or None
    pan = (p.get("pan") or "").strip().upper() or None
    state_code = (p.get("state_code") or "").strip() or None
    reg_type = "REGULAR" if gstin else "CONSUMER"

    billing_address = {
        "street": p.get("billing_address") or "",
        "city": "",
        "state": "",
        "state_code": state_code or "",
        "pincode": "",
        "country": "India",
    }

    contact = Contact(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        name=(p.get("name") or "").strip(),
        email=(p.get("email") or "").strip() or None,
        phone=(p.get("phone") or "").strip() or None,
        contact_type=contact_type,
        gstin=gstin,
        pan=pan,
        registration_type=reg_type,
        billing_address=billing_address,
        shipping_address=billing_address,
        state_code=state_code,
    )
    try:
        db.add(contact)
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            Contact.name == contact.name,
        ).first()
        if existing:
            return
        raise SyncError("Contact creation failed")


def _handle_item_created(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    unit = (p.get("unit") or "PCS").strip().upper()
    product_type = "SERVICE" if unit == "HRS" else "GOODS"

    hsn = (p.get("hsn") or "").strip()
    if not hsn:
        hsn = "00000000"

    quantity = _micros_to_decimal(p.get("opening_quantity_micros"))
    sale_price = _micros_to_decimal(p.get("sale_price_micros"))
    purchase_price = _micros_to_decimal(p.get("purchase_price_micros"))
    gst_rate = _basis_points_to_decimal(p.get("default_tax_rate_basis_points"))

    product = Product(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        name=(p.get("name") or "").strip(),
        sku=(p.get("sku") or "").strip().upper(),
        barcode=(p.get("barcode") or "").strip() or None,
        hsn_sac=hsn,
        product_type=product_type,
        uom=unit,
        sales_price=sale_price,
        purchase_price=purchase_price,
        gst_rate=gst_rate,
        opening_stock=quantity,
        current_stock=quantity,
        reorder_level=_micros_to_decimal(p.get("reorder_quantity_micros")),
    )
    for field in ("description", "category", "brand"):
        val = p.get(field)
        if val:
            setattr(product, field, val)
    try:
        db.add(product)
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = db.query(Product).filter(
            Product.tenant_id == tenant_id,
            Product.sku == product.sku,
        ).first()
        if existing:
            return
        raise SyncError("Product creation failed")


def _handle_branch_created(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    branch = Branch(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        name=(p.get("name") or "").strip(),
        address={"street": "", "city": "", "state": "", "state_code": "", "pincode": "", "country": "India"},
    )
    try:
        db.add(branch)
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = db.query(Branch).filter(
            Branch.tenant_id == tenant_id,
            Branch.name == branch.name,
        ).first()
        if existing:
            return
        raise SyncError("Branch creation failed")


def _handle_warehouse_created(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    warehouse = Branch(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        name=(p.get("name") or "").strip(),
        address={
            "street": "",
            "city": "",
            "state": "",
            "state_code": "",
            "pincode": "",
            "country": "India",
            "warehouse_kind": p.get("kind", "standard"),
        },
    )
    try:
        db.add(warehouse)
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = db.query(Branch).filter(
            Branch.tenant_id == tenant_id,
            Branch.name == warehouse.name,
        ).first()
        if existing:
            return
        raise SyncError("Warehouse creation failed")


def _handle_invoice_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    kind = event.payload.get("kind", "sale")
    if kind == "sale":
        _handle_sale_invoice(db, tenant_id, company_id, event, actor_id)
    elif kind == "purchase":
        _handle_purchase_invoice(db, tenant_id, company_id, event, actor_id)
    else:
        raise SyncError(f"Unsupported invoice kind: {kind}")


def _handle_sale_invoice(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    invoice_number = _validated_document_number(
        db,
        tenant_id,
        event,
        p,
        "INVOICE",
    )

    try:
        party_id = uuid.UUID(str(p.get("party_id")))
    except (ValueError, TypeError):
        raise SyncError("Invoice requires a valid party_id")
    contact = db.query(Contact).filter(
        Contact.id == party_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
        Contact.is_active == True,
    ).first()
    if contact is None:
        raise SyncError("Invoice customer was not found in this company")

    lines_data = p.get("lines") or []
    if not lines_data:
        raise SyncError("Invoice requires at least one line")
    if p.get("payments"):
        raise SyncError(
            "Embedded invoice payments are unsupported; queue a separate receipt",
        )

    issue_date = event.occurred_at.date()
    if p.get("invoice_date"):
        try:
            issue_date = date.fromisoformat(
                str(p["invoice_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            raise SyncError("Invoice date is invalid")
    due_date = issue_date
    if p.get("due_date"):
        try:
            due_date = date.fromisoformat(
                str(p["due_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            raise SyncError("Invoice due date is invalid")
    if due_date < issue_date:
        raise SyncError("Invoice due date cannot be before invoice date")

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).one()
    origin_state_code = derive_origin_state_code(tenant.gstin)
    state_code = (
        p.get("place_of_supply_state_code")
        or contact.state_code
        or origin_state_code
        or "00"
    )
    intra_state = (
        origin_state_code is not None and state_code == origin_state_code
    )
    computed_subtotal = Decimal("0")
    computed_tax = Decimal("0")
    prepared_lines: list[tuple[Product, Decimal, Decimal, Decimal, Decimal]] = []
    for line_data in lines_data:
        try:
            product_id = uuid.UUID(str(line_data.get("item_id")))
        except (ValueError, TypeError):
            raise SyncError("Every invoice line requires a valid item_id")
        product = db.query(Product).filter(
            Product.id == product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
            Product.is_active == True,
        ).first()
        if product is None:
            raise SyncError(f"Invoice product {product_id} was not found")
        quantity = _micros_to_decimal(line_data.get("quantity_micros"))
        rate = _micros_to_decimal(line_data.get("rate_micros"))
        discount = _micros_to_decimal(line_data.get("discount_micros"))
        if quantity <= 0 or rate <= 0:
            raise SyncError("Invoice quantity and rate must be positive")
        gross = quantity * rate
        if discount < 0 or discount > gross:
            raise SyncError("Invoice line discount is invalid")
        taxable = gross - discount
        gst_rate = _basis_points_to_decimal(
            line_data.get("tax_rate_basis_points"),
        )
        if gst_rate < 0 or gst_rate > 100:
            raise SyncError("Invoice line GST rate is invalid")
        line_tax = taxable * gst_rate / Decimal("100")
        computed_subtotal += taxable
        computed_tax += line_tax
        prepared_lines.append(
            (product, quantity, rate, discount, gst_rate),
        )

    declared_subtotal = _micros_to_decimal(p.get("subtotal_micros"))
    declared_tax = _micros_to_decimal(p.get("tax_micros"))
    declared_total = _micros_to_decimal(p.get("total_micros"))
    computed_total = computed_subtotal + computed_tax
    tolerance = Decimal("0.01")
    if (
        abs(declared_subtotal - computed_subtotal) > tolerance
        or abs(declared_tax - computed_tax) > tolerance
        or abs(declared_total - computed_total) > tolerance
    ):
        raise SyncError("Invoice totals do not match the line calculations")

    invoice = Invoice(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=contact.id,
        invoice_number=invoice_number,
        issue_date=issue_date,
        due_date=due_date,
        status="POSTED",
        subtotal=computed_subtotal,
        total=computed_total,
        cgst_amount=computed_tax / 2 if intra_state else Decimal("0"),
        sgst_amount=computed_tax / 2 if intra_state else Decimal("0"),
        igst_amount=computed_tax if not intra_state else Decimal("0"),
        pos_state_code=state_code,
        notes=p.get("notes", ""),
        reference_number=(p.get("reference_number") or ""),
    )
    db.add(invoice)
    db.flush()

    for product, quantity, rate, discount, gst_rate in prepared_lines:
        gross = quantity * rate
        taxable = gross - discount
        line_tax = taxable * gst_rate / Decimal("100")
        invoice_line = InvoiceLine(
            invoice_id=invoice.id,
            product_id=product.id,
            description=product.name,
            quantity=quantity,
            rate=rate,
            discount=discount,
            subtotal=taxable,
            hsn_sac=product.hsn_sac,
            gst_rate=gst_rate,
            cgst_rate=gst_rate / 2 if intra_state else Decimal("0"),
            cgst_amount=line_tax / 2 if intra_state else Decimal("0"),
            sgst_rate=gst_rate / 2 if intra_state else Decimal("0"),
            sgst_amount=line_tax / 2 if intra_state else Decimal("0"),
            igst_rate=gst_rate if not intra_state else Decimal("0"),
            igst_amount=line_tax if not intra_state else Decimal("0"),
            total=taxable + line_tax,
        )
        db.add(invoice_line)

    db.flush()
    try:
        auto_post_invoice(db, tenant_id, invoice, allow_negative_stock=True)
    except Exception as exc:
        raise SyncError(f"Invoice ledger posting failed: {exc}")


def _handle_purchase_invoice(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload

    party_id_str = p.get("party_id")
    contact = None
    if party_id_str:
        try:
            pid = uuid.UUID(party_id_str) if isinstance(party_id_str, str) else party_id_str
            contact = db.query(Contact).filter(
                Contact.id == pid,
                Contact.tenant_id == tenant_id,
            ).first()
        except (ValueError, TypeError):
            pass

    subtotal = _micros_to_decimal(p.get("subtotal_micros"))
    tax = _micros_to_decimal(p.get("tax_micros"))
    total = _micros_to_decimal(p.get("total_micros"))
    state_code = p.get("place_of_supply_state_code") or "00"
    due_date_str = p.get("due_date")

    issue_date = event.occurred_at.date()
    due_date = issue_date
    if due_date_str:
        try:
            due_date = date.fromisoformat(due_date_str.replace("Z", "").split("T")[0])
        except (ValueError, TypeError):
            pass

    bill = Bill(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=contact.id if contact else None,
        bill_number=(p.get("invoice_number") or str(event.aggregate_id)[:8]).upper(),
        issue_date=issue_date,
        due_date=due_date,
        status="POSTED",
        subtotal=subtotal,
        total=total,
        cgst_amount=tax / 2 if state_code[:2] != "00" else Decimal("0"),
        sgst_amount=tax / 2 if state_code[:2] != "00" else Decimal("0"),
        igst_amount=tax if state_code[:2] == "00" else Decimal("0"),
        pos_state_code=state_code,
        notes=p.get("notes", ""),
        reference_number=(p.get("reference_number") or ""),
        itc_eligible=True,
    )
    db.add(bill)
    db.flush()

    for line_data in p.get("lines", []):
        item_id_str = line_data.get("item_id")
        product = None
        if item_id_str:
            try:
                pid = uuid.UUID(item_id_str) if isinstance(item_id_str, str) else item_id_str
                product = db.query(Product).filter(
                    Product.id == pid,
                    Product.tenant_id == tenant_id,
                ).first()
            except (ValueError, TypeError):
                pass

        qty = _micros_to_decimal(line_data.get("quantity_micros"))
        rate = _micros_to_decimal(line_data.get("rate_micros"))
        line_total = qty * rate if rate else Decimal("0")
        gst_rate = _basis_points_to_decimal(line_data.get("tax_rate_basis_points"))

        bill_line = BillLine(
            bill_id=bill.id,
            product_id=product.id if product else None,
            description=product.name if product else "",
            quantity=qty,
            rate=rate,
            subtotal=line_total,
            hsn_sac=product.hsn_sac if product else "00000000",
            gst_rate=gst_rate,
            total=line_total,
        )
        db.add(bill_line)

    for pay_data in p.get("payments", []):
        method = (pay_data.get("method") or "cash").upper()
        bpmt = BillPayment(
            tenant_id=tenant_id,
            contact_id=contact.id if contact else None,
            payment_number=f"SYNC-{uuid.uuid4().hex[:8].upper()}",
            payment_date=issue_date,
            payment_mode=method,
            amount=_micros_to_decimal(pay_data.get("amount_micros")),
            status="ACTIVE",
        )
        db.add(bpmt)
        db.flush()
        balloc = BillPaymentAllocation(
            payment_id=bpmt.id,
            bill_id=bill.id,
            amount=bpmt.amount,
        )
        db.add(balloc)

    db.flush()
    try:
        from src.domains.accounting.auto_post import auto_post_bill
        auto_post_bill(db, tenant_id, bill)
    except Exception as exc:
        raise SyncError(f"Purchase invoice ledger posting failed: {exc}")


def _handle_journal_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    source_type = p.get("source_type") or "MANUAL"
    source_id = uuid.UUID(p["reversed_journal_id"]) if p.get("reversed_journal_id") else event.aggregate_id

    # A posted event may be replayed with a new transport event id (for
    # example after a client retry).  The ledger source identity is the
    # business idempotency key, so never post the same journal twice.
    existing = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == source_type,
        JournalEntry.source_id == source_id,
    ).first()
    if existing is not None:
        return

    entry_date_str = p.get("entry_date")

    lines_data = p.get("lines", [])
    if len(lines_data) < 2:
        raise SyncError("A journal entry requires at least two lines")

    total_debit = Decimal("0")
    total_credit = Decimal("0")
    draft_lines: list[JournalLineDraft] = []

    for ld in lines_data:
        account_id_str = ld.get("account_id")
        try:
            account_id = uuid.UUID(account_id_str) if isinstance(account_id_str, str) else account_id_str
        except (ValueError, TypeError):
            raise SyncError(f"Invalid account_id in journal line: {account_id_str}")

        debit_micros = int(ld.get("debit_micros", 0) or 0)
        credit_micros = int(ld.get("credit_micros", 0) or 0)
        if debit_micros == 0 and credit_micros == 0:
            direction_hint = (ld.get("direction") or "").upper()
            amount_micros = int(ld.get("amount_micros", 0) or 0)
            if direction_hint == "DEBIT":
                debit_micros = amount_micros
            elif direction_hint == "CREDIT":
                credit_micros = amount_micros

        if debit_micros > 0 and credit_micros > 0:
            raise SyncError("Each line must have exactly one non-zero side")

        if debit_micros > 0:
            amount = _micros_to_decimal(debit_micros)
            direction = "DEBIT"
            total_debit += amount
        elif credit_micros > 0:
            amount = _micros_to_decimal(credit_micros)
            direction = "CREDIT"
            total_credit += amount
        else:
            raise SyncError("Each line must have a non-zero amount")

        draft_lines.append(JournalLineDraft(
            account_id=account_id,
            amount=amount,
            direction=direction,
            narration=ld.get("narration") or ld.get("memo", ""),
        ))

    if total_debit != total_credit:
        raise SyncError(
            f"Journal entry is unbalanced: debit={total_debit} credit={total_credit}"
        )

    entry_date = event.occurred_at.date()
    if entry_date_str:
        try:
            entry_date = date.fromisoformat(entry_date_str.split("T")[0])
        except (ValueError, TypeError):
            pass

    fy = (
        db.query(FinancialYear)
        .filter(
            FinancialYear.tenant_id == tenant_id,
            FinancialYear.start_date <= entry_date,
            FinancialYear.end_date >= entry_date,
            FinancialYear.status.in_(["CURRENT", "READY_TO_CLOSE"]),
        )
        .first()
    )
    if not fy:
        raise SyncError(f"No active financial year found for date {entry_date}")

    draft = JournalEntryDraft(
        tenant_id=tenant_id,
        entry_date=entry_date,
        reference_number=(
            (
                f"REV-{p.get('voucher_number') or p.get('reference_number')}"
                if source_type == "JOURNAL_REVERSAL" and (
                    p.get("voucher_number") or p.get("reference_number")
                )
                else p.get("voucher_number") or p.get("reference_number")
            )
            or f"J{entry_date.strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}"
        )[:50],
        description=p.get("narration") or p.get("description", ""),
        source_type=source_type,
        source_id=source_id,
        lines=draft_lines,
    )

    try:
        commit_ledger_draft(db, tenant_id, draft)
    except Exception as exc:
        raise SyncError(f"Journal posting failed: {exc}")


def _handle_journal_draft(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    """Accept a draft/update without touching the immutable ledger.

    Drafts are intentionally represented by the durable sync event stream
    until the client posts them.  This keeps draft editing offline-safe while
    ensuring the server never creates a ledger entry before the explicit
    ``journal.posted`` transition.
    """
    payload = event.payload
    lines = payload.get("lines") or []
    if len(lines) < 2:
        raise SyncError("A journal entry requires at least two lines")

    debit = Decimal("0")
    credit = Decimal("0")
    for line in lines:
        try:
            account_id = uuid.UUID(str(line.get("account_id")))
        except (ValueError, TypeError, AttributeError):
            raise SyncError("Each journal line requires a valid account_id")
        if db.query(Account.id).filter(
            Account.id == account_id,
            Account.tenant_id == tenant_id,
        ).first() is None:
            raise SyncError(f"Unknown account: {account_id}")

        debit_micros = int(line.get("debit_micros") or 0)
        credit_micros = int(line.get("credit_micros") or 0)
        if debit_micros > 0 and credit_micros > 0:
            raise SyncError("Each line must have exactly one non-zero side")
        if debit_micros <= 0 and credit_micros <= 0:
            raise SyncError("Each line must have a non-zero amount")
        debit += _micros_to_decimal(debit_micros)
        credit += _micros_to_decimal(credit_micros)

    # A draft may be unbalanced; posting is the transition that enforces
    # double-entry balance.  Once posted, updates are immutable.
    posted = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.source_type == "MANUAL",
        JournalEntry.source_id == event.aggregate_id,
    ).first()
    if posted is not None:
        raise SyncError("Posted journals are immutable; use reversal")


def _handle_money_account_created(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    name = (p.get("name") or "").strip()
    kind = (p.get("kind") or "cash").strip().lower()

    bank_name = "Cash" if kind == "cash" else name
    profile = BankingProfile(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        bank_name=bank_name,
        account_number=p.get("account_number", ""),
        ifsc_code=p.get("ifsc", ""),
        account_holder_name=name,
    )
    try:
        db.add(profile)
        db.flush()
    except IntegrityError:
        db.rollback()
        existing = db.query(BankingProfile).filter(
            BankingProfile.id == event.aggregate_id,
            BankingProfile.tenant_id == tenant_id,
        ).first()
        if existing:
            return
        raise SyncError("Money account creation failed")


def _handle_money_transaction_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    txn_kind = p.get("kind", "receipt")
    amount = _micros_to_decimal(p.get("amount_micros"))
    if amount <= 0:
        raise SyncError("Payment amount must be greater than zero")
    reference = (p.get("reference") or "").strip()
    narration = p.get("narration", "")
    payment_mode = (p.get("payment_mode") or "BANK").strip().upper()
    if payment_mode == "CARD":
        payment_mode = "POS"
    if payment_mode not in {
        "CASH", "BANK", "UPI", "POS", "CHEQUE", "NEFT_RTGS", "OTHER",
    }:
        raise SyncError(f"Unsupported payment mode: {payment_mode}")

    payment_date = event.occurred_at.date()
    if p.get("payment_date"):
        try:
            payment_date = date.fromisoformat(
                str(p["payment_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            raise SyncError("Payment date is invalid")

    if txn_kind == "contra":
        try:
            source_id = uuid.UUID(str(p.get("source_account_id")))
            destination_id = uuid.UUID(str(p.get("destination_account_id")))
        except (ValueError, TypeError):
            raise SyncError(
                "Contra transaction requires valid source and destination account IDs",
            )
        if source_id == destination_id:
            raise SyncError("Contra source and destination accounts must differ")
        accounts = db.query(Account).filter(
            Account.tenant_id == tenant_id,
            Account.id.in_([source_id, destination_id]),
            Account.deleted_at == None,
            Account.is_active == True,
            Account.account_type == "ASSET",
        ).all()
        by_id = {account.id: account for account in accounts}
        if source_id not in by_id or destination_id not in by_id:
            raise SyncError("Contra accounts were not found in this company")
        draft = JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=payment_date,
            reference_number=(
                reference or f"CTR-{event.aggregate_id.hex[:8].upper()}"
            ),
            description=narration or "Contra transfer",
            source_type="MANUAL",
            source_id=event.aggregate_id,
            lines=[
                JournalLineDraft(
                    account_id=source_id,
                    amount=amount,
                    direction="CREDIT",
                ),
                JournalLineDraft(
                    account_id=destination_id,
                    amount=amount,
                    direction="DEBIT",
                ),
            ],
        )
        try:
            commit_ledger_draft(db, tenant_id, draft)
        except Exception as exc:
            raise SyncError(f"Contra journal posting failed: {exc}")
        return

    contact_id_str = p.get("contact_id")
    try:
        contact_id = (
            uuid.UUID(contact_id_str)
            if isinstance(contact_id_str, str)
            else contact_id_str
        )
    except (ValueError, TypeError):
        raise SyncError("Payment requires a valid contact_id")
    contact = db.query(Contact).filter(
        Contact.id == contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
        Contact.is_active == True,
    ).first()
    if contact is None:
        raise SyncError("Payment contact was not found in this company")

    account_id_str = p.get("account_id")
    try:
        account_id = (
            uuid.UUID(account_id_str)
            if isinstance(account_id_str, str)
            else account_id_str
        )
    except (ValueError, TypeError):
        raise SyncError("Payment requires a valid cash or bank account_id")
    money_account = db.query(Account).filter(
        Account.id == account_id,
        Account.tenant_id == tenant_id,
        Account.deleted_at == None,
        Account.is_active == True,
        Account.account_type == "ASSET",
    ).first()
    if money_account is None:
        raise SyncError("Cash or bank account was not found in this company")

    if txn_kind == "receipt":
        pmt = Payment(
            id=event.aggregate_id,
            tenant_id=tenant_id,
            contact_id=contact.id,
            payment_number=f"RCP-{event.aggregate_id.hex[:8].upper()}",
            payment_date=payment_date,
            payment_mode=payment_mode,
            amount=amount,
            reference_number=reference,
            description=narration,
            status="ACTIVE",
        )
        db.add(pmt)
        db.flush()
        resolver = AccountResolver(db, tenant_id)
        customer_account_id = resolver.resolve(f"customer.{contact.id}")
        draft = LedgerPostingEngine.create_payment_receipt_posting(
            tenant_id=tenant_id,
            payment_id=pmt.id,
            payment_number=pmt.payment_number,
            payment_date=pmt.payment_date,
            bank_or_cash_account_id=money_account.id,
            customer_account_id=customer_account_id,
            amount=amount,
        )
        commit_ledger_draft(db, tenant_id, draft)

    elif txn_kind == "payment":
        bpmt = BillPayment(
            id=event.aggregate_id,
            tenant_id=tenant_id,
            contact_id=contact.id,
            payment_number=f"PYT-{event.aggregate_id.hex[:8].upper()}",
            payment_date=payment_date,
            payment_mode=payment_mode,
            amount=amount,
            reference_number=reference,
            description=narration,
            status="ACTIVE",
        )
        db.add(bpmt)
        db.flush()
        resolver = AccountResolver(db, tenant_id)
        vendor_account_id = resolver.resolve(f"vendor.{contact.id}")
        draft = LedgerPostingEngine.create_payment_out_posting(
            tenant_id=tenant_id,
            payment_id=bpmt.id,
            payment_number=bpmt.payment_number,
            payment_date=bpmt.payment_date,
            bank_or_cash_account_id=money_account.id,
            vendor_account_id=vendor_account_id,
            amount=amount,
        )
        commit_ledger_draft(db, tenant_id, draft)

    else:
        raise SyncError(f"Unsupported money transaction kind: {txn_kind}")


def _handle_stock_adjusted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    quantity_micros = p.get("quantity_micros", 0) or 0
    if quantity_micros == 0:
        raise SyncError("Stock adjustment quantity cannot be zero")

    item_id_str = p.get("item_id")
    try:
        item_id = uuid.UUID(item_id_str) if isinstance(item_id_str, str) else item_id_str
    except (ValueError, TypeError):
        raise SyncError(f"Invalid item_id: {item_id_str}")

    product = db.query(Product).filter(
        Product.id == item_id,
        Product.tenant_id == tenant_id,
    ).first()
    if not product:
        raise SyncError(f"Product {item_id} not found")

    quantity_change = _micros_to_decimal(abs(quantity_micros))
    is_positive = quantity_micros > 0
    sign = Decimal("1") if is_positive else Decimal("-1")

    movement_date = event.occurred_at.date()
    if p.get("movement_date"):
        try:
            movement_date = date.fromisoformat(
                str(p["movement_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            raise SyncError("Stock movement date is invalid")
    unit_cost = _micros_to_decimal(p.get("unit_cost_micros"))
    if unit_cost <= 0:
        unit_cost = product.purchase_price or product.sales_price or Decimal("0")

    adjustment = InventoryAdjustment(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        adjustment_number=f"ADJ-{uuid.uuid4().hex[:8].upper()}",
        adjustment_date=movement_date,
        status="CONFIRMED",
        reason=p.get("reference", ""),
    )
    db.add(adjustment)
    db.flush()

    line = InventoryAdjustmentLine(
        adjustment_id=adjustment.id,
        product_id=product.id,
        quantity_change=quantity_change * sign,
        unit_cost=unit_cost,
        total_cost=quantity_change * sign * unit_cost,
        reason=p.get("reference", ""),
    )
    db.add(line)

    new_quantity = product.current_stock + (quantity_change * sign)
    if new_quantity < 0:
        raise SyncError("Stock adjustment would make quantity negative")
    product.current_stock = new_quantity

    stock = StockLedger(
        tenant_id=tenant_id,
        product_id=product.id,
        quantity=quantity_change * sign,
        balance_quantity=product.current_stock,
        reference_type="ADJUSTMENT",
        reference_id=adjustment.id,
    )
    db.add(stock)
    event.payload = {
        **p,
        "item_id": str(product.id),
        "quantity_micros": int(quantity_change * sign * Decimal("10000")),
        "unit_cost_micros": int(unit_cost * Decimal("10000")),
        "server_balance_micros": int(
            product.current_stock * Decimal("10000"),
        ),
        "product_name": product.name,
    }


def _handle_stock_transferred(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    quantity_micros = p.get("quantity_micros", 0) or 0
    if quantity_micros <= 0:
        raise SyncError("Transfer quantity must be positive")

    item_id_str = p.get("item_id")
    from_str = p.get("from_warehouse_id")
    to_str = p.get("to_warehouse_id")

    try:
        item_id = uuid.UUID(item_id_str) if isinstance(item_id_str, str) else item_id_str
        from_id = uuid.UUID(from_str) if isinstance(from_str, str) else from_str
        to_id = uuid.UUID(to_str) if isinstance(to_str, str) else to_str
    except (ValueError, TypeError) as exc:
        raise SyncError(f"Invalid UUID in transfer: {exc}")

    product = db.query(Product).filter(
        Product.id == item_id,
        Product.tenant_id == tenant_id,
    ).first()
    if not product:
        raise SyncError(f"Product {item_id} not found")

    qty = _micros_to_decimal(quantity_micros)

    transfer = Transfer(
        tenant_id=tenant_id,
        transfer_number=f"TRF-{uuid.uuid4().hex[:8].upper()}",
        transfer_date=event.occurred_at.date().isoformat(),
        from_warehouse_id=from_id,
        from_warehouse_name="",
        to_warehouse_id=to_id,
        to_warehouse_name="",
        status="COMPLETED",
        lines=[{"product_id": str(item_id), "quantity": str(qty)}],
        notes=p.get("reference", ""),
    )
    db.add(transfer)
    db.flush()

    out = StockLedger(
        tenant_id=tenant_id,
        product_id=product.id,
        quantity=-qty,
        balance_quantity=product.current_stock - qty,
        reference_type="TRANSFER_OUT",
        reference_id=transfer.id,
    )
    db.add(out)

    inp = StockLedger(
        tenant_id=tenant_id,
        product_id=product.id,
        quantity=qty,
        balance_quantity=product.current_stock,
        reference_type="TRANSFER_IN",
        reference_id=transfer.id,
    )
    db.add(inp)


def _handle_company_settings_updated(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    state_code = p.get("state_code")

    tsetting = db.query(TenantSetting).filter(
        TenantSetting.tenant_id == tenant_id,
    ).first()
    if tsetting:
        if state_code:
            tsetting.origin_state_code = state_code
    else:
        tsetting = TenantSetting(
            tenant_id=tenant_id,
            origin_state_code=state_code or "",
        )
        db.add(tsetting)

    prefix_map = {
        "INVOICE": p.get("sales_prefix"),
        "BILL": p.get("purchase_prefix"),
    }
    for doc_type, prefix in prefix_map.items():
        if not prefix:
            continue
        series = db.query(NumberingSeries).filter(
            NumberingSeries.tenant_id == tenant_id,
            NumberingSeries.document_type == doc_type,
            NumberingSeries.is_active == True,
        ).first()
        if series:
            series.prefix = prefix.strip().upper()


def _handle_bank_statement_imported(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    try:
        profile_id = uuid.UUID(str(p.get("bank_account_id")))
    except (ValueError, TypeError):
        raise SyncError("Bank statement requires a valid bank_account_id")
    profile = db.query(BankingProfile).filter(
        BankingProfile.id == profile_id,
        BankingProfile.tenant_id == tenant_id,
        BankingProfile.is_active == True,
    ).first()
    if profile is None:
        raise SyncError("Bank account was not found in this company")
    try:
        statement_date = date.fromisoformat(str(p.get("statement_date")))
    except ValueError:
        raise SyncError("Bank statement date is invalid")
    lines = p.get("lines") or []
    if not lines:
        raise SyncError("Bank statement must contain at least one transaction")

    statement = BankStatement(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        banking_profile_id=profile.id,
        statement_date=statement_date,
        starting_balance=_micros_to_decimal(p.get("opening_balance_micros")),
        ending_balance=_micros_to_decimal(p.get("closing_balance_micros")),
        currency="INR",
        status="IMPORTED",
    )
    db.add(statement)
    db.flush()
    for line in lines:
        try:
            transaction_date = date.fromisoformat(
                str(line.get("transaction_date")),
            )
        except ValueError:
            raise SyncError("Bank transaction date is invalid")
        amount = _micros_to_decimal(line.get("amount_micros"))
        if amount == 0:
            raise SyncError("Bank transaction amount cannot be zero")
        db.add(
            BankTransaction(
                bank_statement_id=statement.id,
                transaction_date=transaction_date,
                amount=amount,
                description=(line.get("description") or "").strip(),
                reference_number=(
                    line.get("reference_number")
                    or line.get("external_id")
                    or None
                ),
                status="PENDING",
            ),
        )


def _handle_purchase_receipt_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
    try:
        supplier_id = uuid.UUID(str(p.get("supplier_id")))
    except (ValueError, TypeError):
        raise SyncError("Goods receipt requires a valid supplier_id")
    supplier = db.query(Contact).filter(
        Contact.id == supplier_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
        Contact.is_active == True,
    ).first()
    if supplier is None or (supplier.contact_type or "").upper() not in {
        "VENDOR",
        "BOTH",
    }:
        raise SyncError("Goods receipt supplier was not found in this company")
    try:
        receipt_date = date.fromisoformat(str(p.get("receipt_date")))
    except ValueError:
        raise SyncError("Goods receipt date is invalid")
    lines_data = p.get("lines") or []
    if not lines_data:
        raise SyncError("Goods receipt requires at least one line")

    receipt = GoodsReceipt(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=supplier.id,
        receipt_number=f"GRN-{event.aggregate_id.hex[:10].upper()}",
        receipt_date=receipt_date,
        status="CONFIRMED",
        notes=(p.get("notes") or p.get("reference_number") or ""),
        confirmed_at=datetime.now(timezone.utc),
    )
    db.add(receipt)
    db.flush()

    receipt_value = Decimal("0")
    enriched_lines: list[dict[str, Any]] = []
    for line_data in lines_data:
        try:
            product_id = uuid.UUID(str(line_data.get("item_id")))
        except (ValueError, TypeError):
            raise SyncError("Every goods receipt line requires a valid item_id")
        product = db.query(Product).filter(
            Product.id == product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
            Product.is_active == True,
        ).first()
        if product is None:
            raise SyncError(f"Goods receipt product {product_id} was not found")
        quantity = _micros_to_decimal(line_data.get("quantity_micros"))
        unit_cost = _micros_to_decimal(line_data.get("unit_cost_micros"))
        if quantity <= 0 or unit_cost < 0:
            raise SyncError(
                "Goods receipt quantity must be positive and cost non-negative",
            )
        product.current_stock += quantity
        receipt_value += quantity * unit_cost
        db.add(GoodsReceiptLine(
            goods_receipt_id=receipt.id,
            product_id=product.id,
            quantity_ordered=quantity,
            quantity_received=quantity,
        ))
        db.add(StockLedger(
            tenant_id=tenant_id,
            product_id=product.id,
            quantity=quantity,
            balance_quantity=product.current_stock,
            reference_type="GOODS_RECEIPT",
            reference_id=receipt.id,
            rate=unit_cost,
        ))
        enriched_lines.append({
            **line_data,
            "item_id": str(product.id),
            "server_balance_micros": int(
                product.current_stock * Decimal("10000"),
            ),
        })

    if receipt_value > 0:
        resolver = AccountResolver(db, tenant_id)
        draft = JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=receipt_date,
            reference_number=receipt.receipt_number,
            description=f"Goods receipt {receipt.receipt_number}",
            source_type="GOODS_RECEIPT",
            source_id=receipt.id,
            lines=[
                JournalLineDraft(
                    account_id=resolver.resolve("assets.inventory"),
                    amount=receipt_value,
                    direction="DEBIT",
                ),
                JournalLineDraft(
                    account_id=resolver.resolve("liability.grir"),
                    amount=receipt_value,
                    direction="CREDIT",
                ),
            ],
        )
        commit_ledger_draft(db, tenant_id, draft)

    event.payload = {
        **p,
        "supplier_id": str(supplier.id),
        "receipt_number": receipt.receipt_number,
        "lines": enriched_lines,
    }


def _handle_purchase_invoice_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    _handle_purchase_invoice(db, tenant_id, company_id, event, actor_id)


def _resolve_product_for_line(
    db: Session, tenant_id: uuid.UUID, line_data: dict[str, Any],
):
    """Resolve a Product from an event line by item_id (UUID) then product_name."""
    item_id = line_data.get("item_id")
    if item_id:
        try:
            product = db.query(Product).filter(
                Product.id == uuid.UUID(str(item_id)),
                Product.tenant_id == tenant_id,
            ).first()
            if product:
                return product
        except (ValueError, TypeError):
            pass
    product_name = line_data.get("product_name")
    if product_name:
        return db.query(Product).filter(
            Product.name == product_name,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
    return None


def _handle_sales_delivery_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload

    so_id_str = p.get("sales_order_id")
    if not so_id_str:
        raise SyncError("Delivery requires a valid sales_order_id")
    try:
        so_id = uuid.UUID(str(so_id_str))
    except ValueError:
        raise SyncError(f"Invalid sales_order_id: {so_id_str}")

    sales_order = db.query(SalesOrder).filter(
        SalesOrder.id == so_id,
        SalesOrder.tenant_id == tenant_id,
    ).first()
    if not sales_order:
        raise SyncError(f"Sales order {so_id} was not found")

    customer_id = sales_order.contact_id
    if not customer_id:
        contact_name = p.get("customer_name")
        if contact_name:
            contact = db.query(Contact).filter(
                Contact.name == contact_name,
                Contact.tenant_id == tenant_id,
                Contact.deleted_at == None,
            ).first()
            if contact:
                customer_id = contact.id

    delivery_date = event.occurred_at.date()
    if p.get("delivery_date"):
        try:
            delivery_date = date.fromisoformat(
                str(p["delivery_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            pass

    challan = DeliveryChallan(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=customer_id,
        source_sales_order_id=sales_order.id,
        challan_number=f"DC-{event.aggregate_id.hex[:10].upper()}",
        challan_date=delivery_date,
        due_date=delivery_date,
        status="ISSUED",
        pos_state_code=sales_order.pos_state_code or "00",
        total=Decimal("0"),
        subtotal=Decimal("0"),
    )
    db.add(challan)
    db.flush()

    total_cogs = Decimal("0")
    challan_subtotal = Decimal("0")

    from src.domains.inventory.services import resolve_default_warehouse_id
    warehouse_id = resolve_default_warehouse_id(db, tenant_id)

    for line_data in p.get("lines", []):
        product_name = line_data.get("product_name")
        product = db.query(Product).filter(
            Product.name == product_name,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if not product:
            raise SyncError(f"Product not found by name: {product_name}")

        qty = Decimal(str(line_data.get("quantity", 0)))
        unit_price = Decimal(str(line_data.get("unit_price_paise", 0))) / Decimal("100")
        line_total = qty * unit_price
        challan_subtotal += line_total

        challan_line = DeliveryChallanLine(
            delivery_challan_id=challan.id,
            product_id=product.id,
            description=product.name,
            quantity=qty,
            rate=unit_price,
            discount=Decimal("0"),
            subtotal=line_total,
            hsn_sac=product.hsn_sac or "00000000",
            gst_rate=product.gst_rate or Decimal("0"),
            total=line_total,
        )
        db.add(challan_line)

        if product.product_type == "GOODS" and qty > 0:
            product.current_stock = (product.current_stock or Decimal("0")) - qty

            unit_cost = product.purchase_price or Decimal("0")
            from src.domains.accounting.auto_post import get_stock_balance_after
            balance_after = get_stock_balance_after(
                db, tenant_id, warehouse_id, product.id,
                -qty, product.current_stock,
            )

            db.add(StockLedger(
                tenant_id=tenant_id,
                product_id=product.id,
                warehouse_id=warehouse_id,
                quantity=-qty,
                balance_quantity=balance_after,
                reference_type="DELIVERY",
                reference_id=challan.id,
                rate=unit_cost,
            ))

            line_cogs = qty * unit_cost
            total_cogs += line_cogs

    challan.subtotal = challan_subtotal
    challan.total = challan_subtotal

    total_cogs_paise = p.get("total_cogs_paise")
    if total_cogs_paise:
        total_cogs = Decimal(total_cogs_paise) / Decimal("100")

    if total_cogs > 0:
        resolver = AccountResolver(db, tenant_id)
        cogs_account_id = resolver.resolve("cogs")
        inventory_account_id = resolver.resolve("assets.inventory")

        draft = JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=delivery_date,
            reference_number=challan.challan_number,
            description=f"COGS: {challan.challan_number} delivery",
            source_type="AUTO",
            source_id=challan.id,
            lines=[
                JournalLineDraft(
                    account_id=cogs_account_id,
                    amount=total_cogs,
                    direction="DEBIT",
                ),
                JournalLineDraft(
                    account_id=inventory_account_id,
                    amount=total_cogs,
                    direction="CREDIT",
                ),
            ],
        )
        commit_ledger_draft(db, tenant_id, draft)

    # Recompute delivered quantities from all issued challans for this SO so a
    # partial delivery does not prematurely mark the order as fully delivered.
    delivered_by_product: dict[uuid.UUID, Decimal] = {}
    for prior in db.query(DeliveryChallan).filter(
        DeliveryChallan.source_sales_order_id == sales_order.id,
        DeliveryChallan.status == "ISSUED",
        DeliveryChallan.deleted_at == None,
    ):
        for line in prior.lines:
            if line.product_id:
                delivered_by_product[line.product_id] = (
                    delivered_by_product.get(line.product_id, Decimal("0"))
                    + line.quantity
                )

    all_delivered = True
    for so_line in sales_order.lines:
        if so_line.product_id:
            delivered = delivered_by_product.get(so_line.product_id, Decimal("0"))
            if delivered < so_line.quantity - Decimal("0.0001"):
                all_delivered = False
                break

    if all_delivered:
        sales_order.status = "DELIVERED"


def _handle_sales_return_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload

    invoice_id_str = p.get("invoice_id")
    if not invoice_id_str:
        raise SyncError("Sales return requires a valid invoice_id")
    try:
        invoice_id = uuid.UUID(str(invoice_id_str))
    except ValueError:
        raise SyncError(f"Invalid invoice_id: {invoice_id_str}")

    invoice = db.query(Invoice).filter(
        Invoice.id == invoice_id,
        Invoice.tenant_id == tenant_id,
    ).first()
    if not invoice:
        raise SyncError(f"Invoice {invoice_id} was not found")

    customer_id = invoice.contact_id
    total_val = Decimal(str(p.get("total_paise", 0))) / Decimal("100")

    return_date = event.occurred_at.date()
    if p.get("return_date"):
        try:
            return_date = date.fromisoformat(
                str(p["return_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            pass

    sales_return = SalesReturn(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=customer_id,
        invoice_id=invoice.id,
        return_number=f"SRN-{event.aggregate_id.hex[:10].upper()}",
        issue_date=return_date,
        status="DRAFT",
        subtotal=total_val,
        total=total_val,
        pos_state_code=invoice.pos_state_code or "00",
        notes=p.get("description", ""),
    )
    db.add(sales_return)
    db.flush()

    for line_data in p.get("lines", []):
        product_name = line_data.get("product_name")
        product = db.query(Product).filter(
            Product.name == product_name,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if not product:
            raise SyncError(f"Product not found by name: {product_name}")

        qty = Decimal(str(line_data.get("quantity", 0)))
        unit_price = Decimal(str(line_data.get("unit_price_paise", 0))) / Decimal("100")
        line_total = qty * unit_price

        invoice_line = db.query(InvoiceLine).filter(
            InvoiceLine.invoice_id == invoice.id,
            InvoiceLine.product_id == product.id,
        ).first()
        if not invoice_line:
            raise SyncError(f"Product {product_name} is not on the original invoice")

        return_line = SalesReturnLine(
            sales_return_id=sales_return.id,
            invoice_line_id=invoice_line.id,
            product_id=product.id,
            description=product.name,
            quantity=qty,
            rate=unit_price,
            subtotal=line_total,
            hsn_sac=product.hsn_sac or "00000000",
            gst_rate=product.gst_rate or Decimal("0"),
            total=line_total,
        )
        db.add(return_line)

    db.flush()

    try:
        from src.domains.accounting.auto_post import auto_post_sales_return
        auto_post_sales_return(db, tenant_id, sales_return)
    except Exception as exc:
        raise SyncError(f"Sales return auto posting failed: {exc}")


def _handle_purchase_return_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload

    bill_id_str = p.get("bill_id")
    if not bill_id_str:
        raise SyncError("Purchase return requires a valid bill_id")
    try:
        bill_id = uuid.UUID(str(bill_id_str))
    except ValueError:
        raise SyncError(f"Invalid bill_id: {bill_id_str}")

    bill = db.query(Bill).filter(
        Bill.id == bill_id,
        Bill.tenant_id == tenant_id,
    ).first()
    if not bill:
        raise SyncError(f"Bill {bill_id} was not found")

    supplier_id = bill.contact_id
    total_val = Decimal(str(p.get("total_paise", 0))) / Decimal("100")

    return_date = event.occurred_at.date()
    if p.get("return_date"):
        try:
            return_date = date.fromisoformat(
                str(p["return_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            pass

    purchase_return = PurchaseReturn(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=supplier_id,
        bill_id=bill.id,
        return_number=f"PRN-{event.aggregate_id.hex[:10].upper()}",
        issue_date=return_date,
        status="DRAFT",
        subtotal=total_val,
        total=total_val,
        pos_state_code=bill.pos_state_code or "00",
        notes=p.get("description", ""),
    )
    db.add(purchase_return)
    db.flush()

    for line_data in p.get("lines", []):
        product_name = line_data.get("product_name")
        product = db.query(Product).filter(
            Product.name == product_name,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None,
        ).first()
        if not product:
            raise SyncError(f"Product not found by name: {product_name}")

        qty = Decimal(str(line_data.get("quantity", 0)))
        unit_cost = Decimal(str(line_data.get("unit_cost_paise", 0))) / Decimal("100")
        line_total = qty * unit_cost

        bill_line = db.query(BillLine).filter(
            BillLine.bill_id == bill.id,
            BillLine.product_id == product.id,
        ).first()
        if not bill_line:
            raise SyncError(f"Product {product_name} is not on the original bill")

        return_line = PurchaseReturnLine(
            purchase_return_id=purchase_return.id,
            bill_line_id=bill_line.id,
            product_id=product.id,
            description=product.name,
            quantity=qty,
            rate=unit_cost,
            subtotal=line_total,
            hsn_sac=product.hsn_sac or "00000000",
            gst_rate=product.gst_rate or Decimal("0"),
            total=line_total,
        )
        db.add(return_line)

    db.flush()

    try:
        from src.domains.accounting.auto_post import auto_post_purchase_return
        auto_post_purchase_return(db, tenant_id, purchase_return)
    except Exception as exc:
        raise SyncError(f"Purchase return auto posting failed: {exc}")


def _handle_credit_note_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload

    invoice = None
    invoice_id_str = p.get("invoice_id")
    if invoice_id_str:
        try:
            invoice_uuid = uuid.UUID(str(invoice_id_str))
            invoice = db.query(Invoice).filter(
                Invoice.id == invoice_uuid,
                Invoice.tenant_id == tenant_id,
            ).first()
        except ValueError:
            pass

    cust_name = p.get("customer_name")
    contact = None
    if invoice and invoice.contact_id:
        contact = db.query(Contact).filter(Contact.id == invoice.contact_id).first()
    elif cust_name:
        contact = db.query(Contact).filter(
            Contact.name == cust_name,
            Contact.tenant_id == tenant_id,
            Contact.deleted_at == None,
        ).first()

    total_val = Decimal(str(p.get("total_paise", 0))) / Decimal("100")
    subtotal_val = Decimal(str(p.get("subtotal_paise", p.get("total_paise", 0)))) / Decimal("100")
    tax_val = Decimal(str(p.get("tax_paise", 0))) / Decimal("100")

    cn_date = event.occurred_at.date()
    if p.get("credit_note_date"):
        try:
            cn_date = date.fromisoformat(
                str(p["credit_note_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            pass

    number = int(p.get("number", 0))
    display_number = str(p.get("number", f"CN-{number}"))

    cn = CreditNote(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        invoice_id=invoice.id if invoice else None,
        credit_note_number=display_number,
        issue_date=cn_date,
        reason=p.get("description", "Sales Return Credit Note"),
        status="DRAFT",
        subtotal=subtotal_val,
        cgst_amount=tax_val / 2 if (invoice and invoice.cgst_amount > 0) else Decimal("0"),
        sgst_amount=tax_val / 2 if (invoice and invoice.sgst_amount > 0) else Decimal("0"),
        igst_amount=tax_val if (invoice and invoice.igst_amount > 0) else Decimal("0"),
        total=total_val,
        pos_state_code=invoice.pos_state_code if invoice else "00",
    )
    db.add(cn)
    db.flush()

    # Parse provided line items; a credit note without itemized lines is a valid
    # journal-only note, so unresolvable lines are skipped rather than assigned
    # to an arbitrary product (which would corrupt that product's attribution).
    for line_data in p.get("lines", []):
        product = _resolve_product_for_line(db, tenant_id, line_data)
        if product is None:
            continue
        qty = Decimal(str(line_data.get("quantity", 1)))
        rate = Decimal(str(line_data.get("unit_price_paise", 0))) / Decimal("100")
        line_total = qty * rate
        db.add(CreditNoteLine(
            credit_note_id=cn.id,
            product_id=product.id,
            quantity=qty,
            rate=rate,
            subtotal=line_total,
            hsn_sac=product.hsn_sac or "00000000",
            gst_rate=product.gst_rate or Decimal("0"),
            total=line_total,
        ))

    db.flush()

    try:
        from src.domains.accounting.auto_post import auto_post_credit_note
        auto_post_credit_note(db, tenant_id, cn)
    except Exception as exc:
        raise SyncError(f"Credit note auto posting failed: {exc}")


def _handle_debit_note_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload

    bill = None
    bill_id_str = p.get("bill_id") or p.get("invoice_id")
    if bill_id_str:
        try:
            bill_uuid = uuid.UUID(str(bill_id_str))
            bill = db.query(Bill).filter(
                Bill.id == bill_uuid,
                Bill.tenant_id == tenant_id,
            ).first()
        except ValueError:
            pass

    supp_name = p.get("supplier_name")
    contact = None
    if bill and bill.contact_id:
        contact = db.query(Contact).filter(Contact.id == bill.contact_id).first()
    elif supp_name:
        contact = db.query(Contact).filter(
            Contact.name == supp_name,
            Contact.tenant_id == tenant_id,
            Contact.deleted_at == None,
        ).first()

    total_val = Decimal(str(p.get("total_paise", 0))) / Decimal("100")
    subtotal_val = Decimal(str(p.get("subtotal_paise", p.get("total_paise", 0)))) / Decimal("100")
    tax_val = Decimal(str(p.get("tax_paise", 0))) / Decimal("100")

    dn_date = event.occurred_at.date()
    if p.get("debit_note_date"):
        try:
            dn_date = date.fromisoformat(
                str(p["debit_note_date"]).replace("Z", "").split("T")[0],
            )
        except ValueError:
            pass

    number = int(p.get("number", 0))
    display_number = str(p.get("number", f"DN-{number}"))

    dn = DebitNote(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        invoice_id=bill.id if bill else None,
        debit_note_number=display_number,
        issue_date=dn_date,
        reason=p.get("description", "Purchase Return Debit Note"),
        status="DRAFT",
        subtotal=subtotal_val,
        cgst_amount=tax_val / 2 if (bill and bill.cgst_amount > 0) else Decimal("0"),
        sgst_amount=tax_val / 2 if (bill and bill.sgst_amount > 0) else Decimal("0"),
        igst_amount=tax_val if (bill and bill.igst_amount > 0) else Decimal("0"),
        total=total_val,
        pos_state_code=bill.pos_state_code if bill else "00",
    )
    db.add(dn)
    db.flush()

    # Parse provided line items; a debit note without itemized lines is a valid
    # journal-only note, so unresolvable lines are skipped rather than assigned
    # to an arbitrary product (which would corrupt that product's attribution).
    for line_data in p.get("lines", []):
        product = _resolve_product_for_line(db, tenant_id, line_data)
        if product is None:
            continue
        qty = Decimal(str(line_data.get("quantity", 1)))
        rate = Decimal(str(line_data.get("unit_price_paise", 0))) / Decimal("100")
        line_total = qty * rate
        db.add(DebitNoteLine(
            debit_note_id=dn.id,
            product_id=product.id,
            quantity=qty,
            rate=rate,
            subtotal=line_total,
            hsn_sac=product.hsn_sac or "00000000",
            gst_rate=product.gst_rate or Decimal("0"),
            total=line_total,
        ))

    db.flush()

    try:
        from src.domains.accounting.auto_post import auto_post_debit_note
        auto_post_debit_note(db, tenant_id, dn)
    except Exception as exc:
        raise SyncError(f"Debit note auto posting failed: {exc}")


# ---------------------------------------------------------------------------
# Event type to handler mapping
# ---------------------------------------------------------------------------

_EVENT_HANDLERS: dict[str, Any] = {
    "account.created": _handle_account_created,
    "party.created": _handle_party_created,
    "item.created": _handle_item_created,
    "branch.created": _handle_branch_created,
    "warehouse.created": _handle_warehouse_created,
    "invoice.posted": _handle_invoice_posted,
    "journal.created": _handle_journal_draft,
    "journal.updated": _handle_journal_draft,
    "journal.posted": _handle_journal_posted,
    "journal.reversed": _handle_journal_posted,
    "money_account.created": _handle_money_account_created,
    "money_transaction.posted": _handle_money_transaction_posted,
    "stock.adjusted": _handle_stock_adjusted,
    "stock.transferred": _handle_stock_transferred,
    "bank_statement.imported": _handle_bank_statement_imported,
    "purchase_receipt.posted": _handle_purchase_receipt_posted,
    "company.settings.updated": _handle_company_settings_updated,
    "purchase_invoice.posted": _handle_purchase_invoice_posted,
    "sales_delivery.posted": _handle_sales_delivery_posted,
    "sales_return.posted": _handle_sales_return_posted,
    "purchase_return.posted": _handle_purchase_return_posted,
    "credit_note.posted": _handle_credit_note_posted,
    "debit_note.posted": _handle_debit_note_posted,
}
