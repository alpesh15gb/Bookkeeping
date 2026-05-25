import asyncio
import os
import sys
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import AsyncGenerator, Generator

import pytest
import pytest_asyncio
from fastapi import FastAPI
from fastapi.testclient import TestClient
from httpx import AsyncClient, ASGITransport
from sqlalchemy import create_engine, event, text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import StaticPool

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.config import settings

# Override settings for testing BEFORE importing app
settings.DATABASE_URL = "sqlite:///./test.db"
settings.REDIS_URL = "redis://localhost:6379/1"
settings.SECRET_KEY = "test-secret-key-for-testing-purposes-only"
settings.ACCESS_TOKEN_EXPIRE_MINUTES = 30
settings.DEBUG = True
settings.APP_ENV = "development"
settings.SEED_ON_STARTUP = False
settings.RATE_LIMIT_ENABLED = False

# Replace engine in src.core.database with StaticPool so all test files
# (both old unittest-style and new pytest-style) share the same engine.
import src.core.database as _db_mod
from sqlalchemy.pool import StaticPool
_db_mod.engine = create_engine(settings.DATABASE_URL, poolclass=StaticPool)
_db_mod.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_db_mod.engine)

from src.core.database import Base, get_db_session
from src.main import app
from src.infrastructure.database.models import (
    Tenant, Contact, Product, Invoice, InvoiceLine,
    JournalEntry, JournalLine, Payment, PaymentAllocation,
    Bill, BillLine, BillPayment, BillPaymentAllocation,
    PurchaseOrder, PurchaseOrderLine,
    SalesOrder, SalesOrderLine,
    DeliveryChallan, DeliveryChallanLine,
    ProformaInvoice, ProformaInvoiceLine,
    InventoryAdjustment, InventoryAdjustmentLine,
    BankStatement, BankTransaction, BankReconciliation,
    TenantInvitation, TaxTemplate, PaymentTerm, Account, BankingProfile,
    StockLedger, AuditLog, GSTReturn, WebhookEvent, TenantSetting, NumberingSeries,
    Branch, ExpenseCategory, User, TenantMembership
)
from src.domains.accounting.services import AccountResolver
from src.domains.taxation.services import GSTEngine
from src.domains.company.services import resolve_origin_state_code
from src.schemas.document import ContactResponse, ProductResponse
from src.api.deps import enforce_permission
from src.core.security import create_access_token, get_password_hash
from src.domains.accounting.services import LedgerPostingEngine

# Use the shared engine (already set on src.core.database with StaticPool)
engine = _db_mod.engine
TestingSessionLocal = _db_mod.SessionLocal

# Create all tables
Base.metadata.create_all(bind=engine)

# Override the get_db_session dependency
def override_get_db_session() -> Generator[Session, None, None]:
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db_session] = override_get_db_session

# Fixtures
# Ensure clean database
Base.metadata.drop_all(bind=engine)
Base.metadata.create_all(bind=engine)


@pytest.fixture
def db_session() -> Generator[Session, None, None]:
    session = TestingSessionLocal()

    def _override():
        yield session

    _original_override = app.dependency_overrides.get(get_db_session)
    app.dependency_overrides[get_db_session] = _override

    # Clean tables at start of each test to prevent cross-test data leakage
    session.execute(text("DELETE FROM tenant_memberships"))
    session.execute(text("DELETE FROM users"))
    session.execute(text("DELETE FROM tenants"))
    session.commit()

    yield session

    app.dependency_overrides[get_db_session] = _original_override or override_get_db_session
    session.rollback()
    session.close()

@pytest.fixture
def client(db_session):
    """Create a test client using the overridden dependency."""
    with TestClient(app) as c:
        yield c

@pytest_asyncio.fixture
async def async_client(db_session) -> AsyncGenerator[AsyncClient, None]:
    """Create an async client for testing."""
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as ac:
        yield ac

@pytest.fixture
def tenant(db_session):
    """Create a test tenant."""
    tenant_id = uuid.uuid4()
    tenant = Tenant(
        id=tenant_id,
        legal_name="Test Company Pvt Ltd",
        trade_name="Test Company",
        gstin="27AAPFU0939F1ZV",  # Valid GSTIN for Maharashtra
        pan="AAPFU0939F",
        financial_year_start=date(2026, 4, 1)
    )
    db_session.add(tenant)
    db_session.commit()
    db_session.refresh(tenant)
    return tenant

@pytest.fixture
def tenant_headers(tenant):
    """Return headers with tenant ID."""
    return {"X-Tenant-ID": str(tenant.id)}

@pytest.fixture
def auth_headers():
    """Return a function to generate auth headers for a given role."""
    def _auth_headers(role: str = "OWNER", user_id: uuid.UUID = None, email: str = "test@example.com"):
        if user_id is None:
            user_id = uuid.uuid4()
        access_token = create_access_token(user_id=str(user_id))
        return {"Authorization": f"Bearer {access_token}"}
    return _auth_headers

@pytest.fixture
def combined_headers(auth_headers, tenant_headers):
    """Return a function to generate combined auth and tenant headers."""
    def _combined_headers(role: str = "OWNER"):
        headers = auth_headers(role)
        headers.update(tenant_headers)
        return headers
    return _combined_headers

# Factory fixtures
@pytest.fixture
def contact_factory(db_session, tenant):
    """Factory for creating contacts."""
    def _create_contact(**kwargs):
        contact_id = uuid.uuid4()
        defaults = {
            "id": contact_id,
            "tenant_id": tenant.id,
            "name": "Test Contact",
            "email": "contact@test.com",
            "phone": "+919876543210",
            "contact_type": "CUSTOMER",
            "gstin": "27AACTC1234A1Z5",
            "pan": "AACTC1234A",
            "registration_type": "REGULAR",
            "billing_address": {"street": "123 Test St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
            "state_code": "27",
            "is_active": True
        }
        defaults.update(kwargs)
        contact = Contact(**defaults)
        db_session.add(contact)
        db_session.commit()
        db_session.refresh(contact)
        return contact
    return _create_contact

@pytest.fixture
def product_factory(db_session, tenant):
    """Factory for creating products."""
    def _create_product(**kwargs):
        product_id = uuid.uuid4()
        defaults = {
            "id": product_id,
            "tenant_id": tenant.id,
            "name": "Test Product",
            "sku": "TEST-001",
            "hsn_sac": "1234",
            "product_type": "GOODS",
            "uom": "PCS",
            "sales_price": Decimal("1000.00"),
            "purchase_price": Decimal("800.00"),
            "gst_rate": Decimal("18.00"),
            "is_active": True
        }
        defaults.update(kwargs)
        product = Product(**defaults)
        db_session.add(product)
        db_session.commit()
        db_session.refresh(product)
        return product
    return _create_product

@pytest.fixture
def invoice_factory(db_session, tenant, contact_factory, product_factory):
    """Factory for creating invoices."""
    def _create_invoice(**kwargs):
        contact = contact_factory() if kwargs.get("contact_id") is None else db_session.query(Contact).get(kwargs["contact_id"])
        invoice_id = uuid.uuid4()
        defaults = {
            "id": invoice_id,
            "tenant_id": tenant.id,
            "contact_id": contact.id,
            "invoice_number": f"INV-{uuid.uuid4().hex[:8].upper()}",
            "issue_date": date.today(),
            "due_date": date.today(),
            "status": "DRAFT",
            "subtotal": Decimal("0.00"),
            "discount_total": Decimal("0.00"),
            "cgst_amount": Decimal("0.00"),
            "sgst_amount": Decimal("0.00"),
            "igst_amount": Decimal("0.00"),
            "utgst_amount": Decimal("0.00"),
            "cess_amount": Decimal("0.00"),
            "total": Decimal("0.00"),
            "amount_paid": Decimal("0.00"),
            "pos_state_code": contact.state_code,
            "e_invoice_status": "PENDING",
            "lines": []
        }
        defaults.update(kwargs)
        invoice = Invoice(**defaults)
        db_session.add(invoice)
        db_session.commit()
        db_session.refresh(invoice)
        return invoice
    return _create_invoice

# Global pytest marks
def pytest_configure(config):
    config.addinivalue_line(
        "markers", "regression: mark test as a regression test"
    )
    config.addinivalue_line(
        "markers", "slow: mark test as slow running"
    )