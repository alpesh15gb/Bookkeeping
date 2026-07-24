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
from src.core.database import get_db_session, Base, engine
from src.core.security import (
    verify_password,
    get_password_hash,
    create_access_token,
    decode_token,
    Permissions,
)
from src.infrastructure.database.models import (
    Account,
    BankingProfile,
    Bill,
    BillLine,
    BillPayment,
    BillPaymentAllocation,
    Branch,
    Contact,
    FinancialYear,
    FinancialYearAudit,
    Invoice,
    InvoiceLine,
    InventoryAdjustment,
    InventoryAdjustmentLine,
    JournalEntry,
    JournalLine,
    NumberingSeries,
    Payment,
    PaymentAllocation,
    Product,
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


class SyncPushResponse(BaseModel):
    acknowledgements: list[SyncAcknowledgement]


class SyncEventRead(SyncEventInput):
    server_sequence: int


class SyncPullResponse(BaseModel):
    events: list[SyncEventRead]
    next_cursor: int

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_APEXBOOKS_ISS = "apexbooks"


def _tenant_context(tenant_id: uuid.UUID) -> None:
    """Import and set the tenant context variable for PostgreSQL RLS."""
    from src.core.database import tenant_context
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
    db: Session = Depends(get_db_session),
) -> ApexBooksPrincipal:
    """Validate an ApexBooks-format JWT and return the principal.

    ApexBooks tokens carry tenant_id and permissions in the JWT payload
    (different from Bookkeeping-master's existing tokens which use scopes).
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
    tenant_id_str = payload.get("tenant_id")
    permissions: list[str] = payload.get("permissions", [])

    if not user_id_str or not tenant_id_str:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token missing required claims (sub, tenant_id)",
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

    # Set tenant context for RLS
    _tenant_context(tenant_id)

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
    if x_bootstrap_key != settings.JWT_SECRET_KEY:
        if not settings.JWT_SECRET_KEY or len(settings.JWT_SECRET_KEY) < 24:
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

# ---------------------------------------------------------------------------
# Auth / Token
# ---------------------------------------------------------------------------

@router.post("/auth/token", response_model=TokenResponse)
def auth_token(
    request: LoginRequest,
    db: Session = Depends(get_db_session),
) -> TokenResponse:
    """Simplified JWT login matching ApexBooks /v1/auth/token.

    The returned token carries tenant_id and permissions claims so the
    ApexBooks client Principal can be reconstructed from the token alone.
    """
    user = db.query(User).filter(
        User.email == request.email.casefold(),
        User.is_active == True,
    ).first()
    if user is None:
        # Timing-safe comparison
        verify_password(request.password, "$2b$12$" + "x" * 53)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect tenant, email, or password",
        )

    if not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect tenant, email, or password",
        )

    # Verify tenant membership
    membership = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == request.tenant_id,
        TenantMembership.user_id == user.id,
        TenantMembership.is_active == True,
    ).first()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not belong to this tenant",
        )

    # Build an ApexBooks-compatible token
    now = datetime.now(timezone.utc)
    lifetime = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    import jwt as pyjwt
    token_payload = {
        "sub": str(user.id),
        "tenant_id": str(request.tenant_id),
        "permissions": ["*"],
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

@router.post("/sync/push", response_model=SyncPushResponse)
def sync_push(
    request: SyncPushRequest,
    principal: ApexBooksPrincipal = Depends(get_legacy_principal),
    db: Session = Depends(get_db_session),
) -> SyncPushResponse:
    """Accept ApexBooks client events, store them idempotently, and process
    each against the Bookkeeping-master domain."""
    principal.require(Permissions.SYNC_WRITE)
    _tenant_context(principal.tenant_id)

    acknowledgements: list[SyncAcknowledgement] = []

    for incoming in request.events:
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

        # Process the event
        try:
            _process_event(db, principal.tenant_id, incoming.company_id, event, principal.user_id)
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

    # Resolve contact (party)
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
            from datetime import date as dt_date
            due_date = dt_date.fromisoformat(due_date_str.replace("Z", "").split("T")[0])
        except (ValueError, TypeError):
            pass

    invoice = Invoice(
        id=event.aggregate_id,
        tenant_id=tenant_id,
        contact_id=contact.id if contact else None,
        invoice_number=(p.get("invoice_number") or str(event.aggregate_id)[:8]).upper(),
        issue_date=issue_date,
        due_date=due_date,
        status="POSTED",
        subtotal=subtotal,
        total=total,
        cgst_amount=tax / 2 if state_code and state_code[:2] != "00" else Decimal("0"),
        sgst_amount=tax / 2 if state_code and state_code[:2] != "00" else Decimal("0"),
        igst_amount=tax if state_code and state_code[:2] == "00" else Decimal("0"),
        pos_state_code=state_code,
        notes=p.get("notes", ""),
        reference_number=(p.get("reference_number") or ""),
    )
    db.add(invoice)
    db.flush()

    # Lines
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

        invoice_line = InvoiceLine(
            invoice_id=invoice.id,
            product_id=product.id if product else None,
            description=product.name if product else "",
            quantity=qty,
            rate=rate,
            subtotal=line_total,
            hsn_sac=product.hsn_sac if product else "00000000",
            gst_rate=gst_rate,
            cgst_rate=gst_rate / 2,
            sgst_rate=gst_rate / 2,
            total=line_total,
        )
        db.add(invoice_line)

    # Payments
    for pay_data in p.get("payments", []):
        method = (pay_data.get("method") or "cash").upper()
        pmt = Payment(
            tenant_id=tenant_id,
            contact_id=contact.id if contact else None,
            payment_number=f"SYNC-{uuid.uuid4().hex[:8].upper()}",
            payment_date=issue_date,
            payment_mode=method,
            amount=_micros_to_decimal(pay_data.get("amount_micros")),
            status="ACTIVE",
        )
        db.add(pmt)
        db.flush()
        allocation = PaymentAllocation(
            payment_id=pmt.id,
            invoice_id=invoice.id,
            amount=pmt.amount,
        )
        db.add(allocation)

    db.flush()

    try:
        auto_post_invoice(db, tenant_id, invoice, allow_negative_stock=True)
    except Exception as exc:
        logger.warning("Auto-post failed for invoice %s: %s. Invoice saved as draft.", invoice.id, exc)
        invoice.status = "DRAFT"


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


def _handle_journal_posted(
    db: Session, tenant_id: uuid.UUID, company_id: uuid.UUID,
    event: SyncEvent, actor_id: uuid.UUID,
) -> None:
    p = event.payload
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

        debit_micros = ld.get("debit_micros", 0) or 0
        credit_micros = ld.get("credit_micros", 0) or 0

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
            narration=ld.get("memo", ""),
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
        reference_number=p.get("voucher_number") or f"J{entry_date.strftime('%Y%m%d')}-{uuid.uuid4().hex[:6].upper()}",
        description=p.get("narration", ""),
        source_type="MANUAL",
        source_id=event.aggregate_id,
        lines=draft_lines,
    )

    try:
        commit_ledger_draft(db, draft)
    except Exception as exc:
        raise SyncError(f"Journal posting failed: {exc}")


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
        account_number="",
        ifsc_code="",
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
    reference = (p.get("reference") or "").strip()
    narration = p.get("narration", "")

    if txn_kind == "receipt":
        dest_id_str = p.get("destination_account_id")
        contact = None
        if dest_id_str:
            try:
                did = uuid.UUID(dest_id_str) if isinstance(dest_id_str, str) else dest_id_str
                contact = db.query(Contact).filter(
                    Contact.id == did,
                    Contact.tenant_id == tenant_id,
                ).first()
            except (ValueError, TypeError):
                pass

        pmt = Payment(
            id=event.aggregate_id,
            tenant_id=tenant_id,
            contact_id=contact.id if contact else None,
            payment_number=f"RCP-{event.aggregate_id.hex[:8].upper()}",
            payment_date=event.occurred_at.date(),
            payment_mode="BANK",
            amount=amount,
            reference_number=reference,
            description=narration,
            status="ACTIVE",
        )
        db.add(pmt)

    elif txn_kind == "payment":
        src_id_str = p.get("source_account_id")
        contact = None
        if src_id_str:
            try:
                sid = uuid.UUID(src_id_str) if isinstance(src_id_str, str) else src_id_str
                contact = db.query(Contact).filter(
                    Contact.id == sid,
                    Contact.tenant_id == tenant_id,
                ).first()
            except (ValueError, TypeError):
                pass

        bpmt = BillPayment(
            id=event.aggregate_id,
            tenant_id=tenant_id,
            contact_id=contact.id if contact else None,
            payment_number=f"PYT-{event.aggregate_id.hex[:8].upper()}",
            payment_date=event.occurred_at.date(),
            payment_mode="BANK",
            amount=amount,
            reference_number=reference,
            description=narration,
            status="ACTIVE",
        )
        db.add(bpmt)

    elif txn_kind == "contra":
        src_id_str = p.get("source_account_id")
        dst_id_str = p.get("destination_account_id")
        if not src_id_str or not dst_id_str:
            raise SyncError("Contra transaction requires source and destination account IDs")

        try:
            src_id = uuid.UUID(src_id_str) if isinstance(src_id_str, str) else src_id_str
            dst_id = uuid.UUID(dst_id_str) if isinstance(dst_id_str, str) else dst_id_str
        except (ValueError, TypeError) as exc:
            raise SyncError(f"Invalid account ID in contra: {exc}")

        resolver = AccountResolver(db, tenant_id)
        src_ledger = resolver.resolve(f"bank.{src_id}")
        dst_ledger = resolver.resolve(f"bank.{dst_id}")

        draft = JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=event.occurred_at.date(),
            reference_number=reference or f"CTR-{event.aggregate_id.hex[:8].upper()}",
            description=narration or "Contra transfer",
            source_type="MANUAL",
            source_id=event.aggregate_id,
            lines=[
                JournalLineDraft(account_id=src_ledger, amount=amount, direction="CREDIT"),
                JournalLineDraft(account_id=dst_ledger, amount=amount, direction="DEBIT"),
            ],
        )
        try:
            commit_ledger_draft(db, draft)
        except Exception as exc:
            raise SyncError(f"Contra journal posting failed: {exc}")

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

    adjustment = InventoryAdjustment(
        tenant_id=tenant_id,
        adjustment_number=f"ADJ-{uuid.uuid4().hex[:8].upper()}",
        adjustment_date=event.occurred_at.date(),
        status="CONFIRMED",
        reason=p.get("reference", ""),
    )
    db.add(adjustment)
    db.flush()

    line = InventoryAdjustmentLine(
        adjustment_id=adjustment.id,
        product_id=product.id,
        quantity_change=quantity_change * sign,
        unit_cost=product.purchase_price or product.sales_price or Decimal("0"),
        total_cost=quantity_change * sign * (product.purchase_price or Decimal("0")),
        reason=p.get("reference", ""),
    )
    db.add(line)

    product.current_stock += quantity_change * sign
    if product.current_stock < 0:
        product.current_stock = Decimal("0")

    stock = StockLedger(
        tenant_id=tenant_id,
        product_id=product.id,
        quantity=quantity_change * sign,
        balance_quantity=product.current_stock,
        reference_type="ADJUSTMENT",
        reference_id=adjustment.id,
    )
    db.add(stock)


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
    "journal.posted": _handle_journal_posted,
    "money_account.created": _handle_money_account_created,
    "money_transaction.posted": _handle_money_transaction_posted,
    "stock.adjusted": _handle_stock_adjusted,
    "stock.transferred": _handle_stock_transferred,
    "company.settings.updated": _handle_company_settings_updated,
}
