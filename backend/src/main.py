"""
src/main.py
FastAPI application entry point.

Production hardening applied:
  - Lifespan context manager for startup/shutdown (not global scope)
  - Seed data guarded by SEED_ON_STARTUP env flag
  - Security headers middleware (HSTS, X-Frame, CSP, X-Content-Type-Options)
  - Global exception handler (no stack trace leakage to clients)
  - Rate limiting via slowapi
  - Deep health check endpoint (DB + Redis ping)
  - CORS restricted from settings
"""
import logging
import uuid
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import List, Optional

from fastapi import Depends, FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
import json
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, NoResultFound, OperationalError
from sqlalchemy.orm import Session

from src.core.config import settings
from src.core.database import engine, Base, SessionLocal, get_db_session
from src.core.rate_limiter import limiter, rate_limiter_exceeded_handler
from src.domains.accounting.services import LedgerValidationError

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("bookkeeping")

# ---------------------------------------------------------------------------
# Routers
# ---------------------------------------------------------------------------
from src.api.v1.auth import router as auth_router
from src.api.v1.invoices import router as invoices_router
from src.api.v1.sales import router as sales_router
from src.api.v1.bills import router as bills_router
from src.api.v1.purchase_orders import router as purchase_orders_router
from src.api.v1.sales_orders import router as sales_orders_router
from src.api.v1.delivery_challans import router as delivery_challans_router
from src.api.v1.proforma_invoices import router as proforma_invoices_router
from src.api.v1.inventory_adjustments import router as inventory_adjustments_router
from src.api.v1.bank_reconciliation import router as bank_reconciliation_router
from src.api.v1.companies import router as companies_router
from src.api.v1.masters import router as masters_router
from src.api.v1.payments import router as payments_router
from src.api.v1.accounting import router as accounting_router
from src.api.v1.gst import router as gst_router
from src.api.v1.eway_bills import router as eway_bills_router
from src.api.v1.reports import router as reports_router
from src.api.v1.audit import router as audit_router
from src.api.v1.expenses import router as expenses_router
from src.api.v1.gstr2a import router as gstr2a_router
from src.schemas.document import ContactResponse, ProductResponse
from src.infrastructure.database.models import Contact, Product
from src.api.deps import enforce_permission


# ---------------------------------------------------------------------------
# Lifespan — startup & shutdown (replaces deprecated @app.on_event)
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan context manager.
    Runs once on startup, then yields (application runs), then shuts down.
    """
    logger.info("Starting Indian Accounting & GST Platform...")

    # Create tables only if they don't exist (dev/test only; production uses Alembic)
    if not settings.is_production:
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables verified (create_all — non-production only).")

    # Seed demo data only when explicitly requested via env flag
    if settings.SEED_ON_STARTUP and not settings.is_production:
        _seed_demo_data()

    yield

    # ---- Shutdown ----
    logger.info("Shutting down application...")
    engine.dispose()


def _seed_demo_data():
    """Seeds master data for demo / development environments only."""
    from src.infrastructure.database.models import Contact, Product, TaxTemplate, PaymentTerm

    db = SessionLocal()
    try:
        DEMO_TENANT = uuid.UUID("0aa85f64-5717-4562-b3fc-2c963f66b110")

        if db.query(TaxTemplate).filter(TaxTemplate.tenant_id.is_(None)).count() == 0:
            db.add_all([
                TaxTemplate(name="GST 0%",  rate=Decimal("0.00")),
                TaxTemplate(name="GST 5%",  rate=Decimal("5.00")),
                TaxTemplate(name="GST 12%", rate=Decimal("12.00")),
                TaxTemplate(name="GST 18%", rate=Decimal("18.00")),
                TaxTemplate(name="GST 28%", rate=Decimal("28.00")),
            ])
            db.commit()
            logger.info("Seeded global GST tax templates.")

        if db.query(PaymentTerm).filter(PaymentTerm.tenant_id.is_(None)).count() == 0:
            db.add_all([
                PaymentTerm(name="Due on Receipt", due_days=0),
                PaymentTerm(name="Net 15",          due_days=15),
                PaymentTerm(name="Net 30",          due_days=30),
                PaymentTerm(name="Net 60",          due_days=60),
            ])
            db.commit()
            logger.info("Seeded global payment terms.")

        if db.query(Contact).filter(Contact.tenant_id == DEMO_TENANT).count() == 0:
            db.add_all([
                Contact(
                    id=uuid.UUID("3fa85f64-5717-4562-b3fc-2c963f66afa6"),
                    tenant_id=DEMO_TENANT, name="Tata Consultancy Services Ltd",
                    email="finance@tcs.com", phone="+912267789999",
                    contact_type="CUSTOMER", gstin="27AAACT1234A1Z1", pan="AAACT1234A",
                    registration_type="REGULAR",
                    billing_address={"street": "TCS House", "city": "Mumbai",
                                     "state": "Maharashtra", "state_code": "27",
                                     "pincode": "400001", "country": "India"},
                    state_code="27",
                ),
                Contact(
                    id=uuid.UUID("3fa85f64-5717-4562-b3fc-2c963f66afa7"),
                    tenant_id=DEMO_TENANT, name="Infosys Technologies Ltd",
                    email="accounts@infosys.com", phone="+918028520261",
                    contact_type="BOTH", gstin="29AAACI5678B2Z2", pan="AAACI5678B",
                    registration_type="REGULAR",
                    billing_address={"street": "Electronics City", "city": "Bengaluru",
                                     "state": "Karnataka", "state_code": "29",
                                     "pincode": "560100", "country": "India"},
                    state_code="29",
                ),
            ])
            db.add_all([
                Product(
                    id=uuid.UUID("4fa85f64-5717-4562-b3fc-2c963f66afd9"),
                    tenant_id=DEMO_TENANT, name="MacBook Pro M3 Max",
                    sku="APL-MBP-M3MX", hsn_sac="84713010", product_type="GOODS",
                    uom="PCS", sales_price=Decimal("249900.00"),
                    purchase_price=Decimal("200000.00"), gst_rate=Decimal("18.00"),
                ),
                Product(
                    id=uuid.UUID("4fa85f64-5717-4562-b3fc-2c963f66afda"),
                    tenant_id=DEMO_TENANT, name="Cloud Database Consultancy",
                    sku="SRV-DB-CLOUD", hsn_sac="998313", product_type="SERVICE",
                    uom="HRS", sales_price=Decimal("4500.00"),
                    purchase_price=Decimal("0.00"), gst_rate=Decimal("18.00"),
                ),
            ])
            db.commit()
            logger.info("Seeded demo contacts and products.")
    except Exception as e:
        db.rollback()
        logger.error(f"Seed data failed (non-fatal): {e}")
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Bookkeeping — Indian Accounting & GST Platform",
    version="1.0.0",
    lifespan=lifespan,
    default_response_class=JSONResponse,
)


# ---------------------------------------------------------------------------
# Static Files (logos, etc.)
# ---------------------------------------------------------------------------
import os
os.makedirs("static/logos", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

# ---------------------------------------------------------------------------
# Rate Limiter
# ---------------------------------------------------------------------------
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limiter_exceeded_handler)


# ---------------------------------------------------------------------------
# Security Headers Middleware
# ---------------------------------------------------------------------------

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    if "access-control-request-private-network" in request.headers:
        response.headers["Access-Control-Allow-Private-Network"] = "true"
    if settings.is_production:
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains; preload"
        response.headers["Content-Security-Policy"] = "default-src 'self'"
    return response


# ---------------------------------------------------------------------------
# CORS
# ---------------------------------------------------------------------------

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Tenant-ID", "Accept"],
)


# ---------------------------------------------------------------------------
# Global Exception Handlers
# ---------------------------------------------------------------------------

@app.exception_handler(LedgerValidationError)
async def ledger_validation_handler(request: Request, exc: LedgerValidationError):
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": str(exc), "code": "LEDGER_VALIDATION_ERROR"},
    )


@app.exception_handler(IntegrityError)
async def integrity_error_handler(request: Request, exc: IntegrityError):
    logger.warning(f"DB IntegrityError on {request.url}: {exc.orig}")
    return JSONResponse(
        status_code=status.HTTP_409_CONFLICT,
        content={"detail": "A record with this data already exists.", "code": "DUPLICATE_RECORD"},
    )


@app.exception_handler(NoResultFound)
async def no_result_handler(request: Request, exc: NoResultFound):
    return JSONResponse(
        status_code=status.HTTP_404_NOT_FOUND,
        content={"detail": "The requested resource was not found.", "code": "NOT_FOUND"},
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception(f"Unhandled exception on {request.method} {request.url}: {exc}")
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "detail": "An internal server error occurred. Our team has been notified.",
            "code": "INTERNAL_SERVER_ERROR",
        },
    )


# ---------------------------------------------------------------------------
# Routers — /api/v1
# ---------------------------------------------------------------------------

app.include_router(auth_router,       prefix="/api/v1")
app.include_router(invoices_router,   prefix="/api/v1")
app.include_router(sales_router,      prefix="/api/v1")
app.include_router(bills_router,      prefix="/api/v1")
app.include_router(purchase_orders_router, prefix="/api/v1")
app.include_router(sales_orders_router, prefix="/api/v1")
app.include_router(delivery_challans_router, prefix="/api/v1")
app.include_router(proforma_invoices_router, prefix="/api/v1")
app.include_router(inventory_adjustments_router, prefix="/api/v1")
app.include_router(bank_reconciliation_router, prefix="/api/v1")
app.include_router(companies_router,  prefix="/api/v1")
app.include_router(masters_router,    prefix="/api/v1")
app.include_router(payments_router,   prefix="/api/v1")
app.include_router(accounting_router, prefix="/api/v1")
app.include_router(gst_router,        prefix="/api/v1")
app.include_router(eway_bills_router, prefix="/api/v1")
app.include_router(reports_router,    prefix="/api/v1")
app.include_router(audit_router,      prefix="/api/v1")
app.include_router(expenses_router,   prefix="/api/v1")
app.include_router(gstr2a_router,     prefix="/api/v1")


# ---------------------------------------------------------------------------
# Frontend-friendly aliases (frontend calls /contacts, /products not /masters/...)
# ---------------------------------------------------------------------------

@app.get("/api/v1/contacts", response_model=List[ContactResponse], tags=["Master Data"])
def alias_list_contacts(
    contact_type: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("contact:view"))
):
    offset = (page - 1) * limit
    q = db.query(Contact).filter(Contact.tenant_id == tenant_id, Contact.deleted_at == None)
    if contact_type:
        if contact_type in ("CUSTOMER", "VENDOR"):
            q = q.filter(Contact.contact_type.in_([contact_type, "BOTH"]))
        else:
            q = q.filter(Contact.contact_type == contact_type)
    return q.offset(offset).limit(limit).all()


@app.get("/api/v1/products", response_model=List[ProductResponse], tags=["Master Data"])
def alias_list_products(
    product_type: Optional[str] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    offset = (page - 1) * limit
    q = db.query(Product).filter(Product.tenant_id == tenant_id, Product.deleted_at == None)
    if product_type:
        q = q.filter(Product.product_type == product_type)
    return q.offset(offset).limit(limit).all()


# ---------------------------------------------------------------------------
# Health Check — deep ping of DB and Redis
# ---------------------------------------------------------------------------

@app.get("/health", tags=["Infrastructure"])
def health_check():
    """
    Deep health check. Pings PostgreSQL and Redis.
    Returns 503 if any dependency is unreachable.
    """
    checks = {}

    # PostgreSQL
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except OperationalError as e:
        logger.error(f"Health check — DB unreachable: {e}")
        checks["database"] = "error"

    # Redis
    try:
        import redis as redis_lib
        r = redis_lib.from_url(settings.REDIS_URL, socket_connect_timeout=2)
        r.ping()
        checks["redis"] = "ok"
    except Exception as e:
        logger.error(f"Health check — Redis unreachable: {e}")
        checks["redis"] = "error"

    all_ok = all(v == "ok" for v in checks.values())
    return JSONResponse(
        status_code=200 if all_ok else 503,
        content={
            "status": "healthy" if all_ok else "degraded",
            "service": "accounting-gst-api",
            "version": "1.0.0",
            "checks": checks,
        },
    )


@app.get("/", include_in_schema=False)
def root():
    return {"message": "Indian Accounting & GST Platform API", "docs": "/docs"}
