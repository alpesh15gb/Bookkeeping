"""
src/infrastructure/database/models.py
All SQLAlchemy ORM models for the Indian Accounting & GST platform.

Key rules:
  - All timestamps use lambda: datetime.now(timezone.utc) — never datetime.utcnow (deprecated).
  - Decimal precision: Numeric(15,4) for amounts, Numeric(5,2) for rates.
  - All tenant-scoped tables have tenant_id as an explicit column (no FK to tenants for perf).
  - DB indexes are declared on all hot query paths.
"""
import uuid
from datetime import datetime, date, timezone
from sqlalchemy import (
    Column, String, Boolean, Numeric, Date, DateTime,
    ForeignKey, Text, JSON, Integer, Index, UniqueConstraint, CheckConstraint
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from src.core.database import Base

# ---------------------------------------------------------------------------
# Timezone-aware UTC timestamp helpers
# ---------------------------------------------------------------------------
_now = lambda: datetime.now(timezone.utc)  # noqa: E731


# ---------------------------------------------------------------------------
# AUTH & TENANT FOUNDATION
# ---------------------------------------------------------------------------

class Tenant(Base):
    __tablename__ = "tenants"
    __table_args__ = (
        UniqueConstraint("gstin", name="uq_tenants_gstin"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    legal_name = Column(String(150), nullable=False)
    trade_name = Column(String(150))
    gstin = Column(String(15))
    pan = Column(String(10))
    financial_year_start = Column(Date, nullable=False, default=date(2026, 4, 1))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    memberships = relationship("TenantMembership", back_populates="tenant", cascade="all, delete-orphan")


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(150), nullable=False)
    phone_number = Column(String(15))
    is_active = Column(Boolean, nullable=False, default=True)
    last_login_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    memberships = relationship("TenantMembership", back_populates="user", cascade="all, delete-orphan")


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    token = Column(String(255), nullable=False, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    user = relationship("User")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=True)
    user_id = Column(UUID(as_uuid=True), nullable=True)
    action = Column(String(100), nullable=False)
    resource = Column(String(100))
    resource_id = Column(String(100))
    details = Column(JSON)
    ip_address = Column(String(45))
    user_agent = Column(String(500))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("ix_audit_logs_tenant_action", "tenant_id", "action"),
        Index("ix_audit_logs_created_at", "created_at"),
    )


# ---------------------------------------------------------------------------
# CONTACT (Customer / Vendor)
# ---------------------------------------------------------------------------

class Contact(Base):
    __tablename__ = "contacts"
    __table_args__ = (
        Index("ix_contacts_tenant_id", "tenant_id"),
        Index("ix_contacts_tenant_type", "tenant_id", "contact_type"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    name = Column(String(150), nullable=False)
    email = Column(String(255))
    phone = Column(String(20))
    contact_type = Column(String(10), nullable=False)  # 'CUSTOMER', 'VENDOR', 'BOTH'
    gstin = Column(String(15))
    pan = Column(String(10))
    registration_type = Column(String(20), nullable=False, default="CONSUMER")
    billing_address = Column(JSON, nullable=False)
    shipping_address = Column(JSON)
    state_code = Column(String(2), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    invoices = relationship("Invoice", back_populates="contact")
    bills = relationship("Bill", back_populates="contact")


# ---------------------------------------------------------------------------
# PRODUCT / SERVICE
# ---------------------------------------------------------------------------

class Product(Base):
    __tablename__ = "products"
    __table_args__ = (
        Index("ix_products_tenant_id", "tenant_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    name = Column(String(150), nullable=False)
    sku = Column(String(50))
    hsn_sac = Column(String(8), nullable=False)
    product_type = Column(String(10), nullable=False)  # 'GOODS', 'SERVICE'
    uom = Column(String(10), nullable=False)            # 'PCS', 'KGS', 'NOS', 'HRS'
    sales_price = Column(Numeric(15, 4), nullable=False, default=0)
    purchase_price = Column(Numeric(15, 4), nullable=False, default=0)
    gst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    opening_stock = Column(Numeric(12, 2), nullable=False, default=0)
    current_stock = Column(Numeric(12, 2), nullable=False, default=0)
    reorder_level = Column(Numeric(12, 2), nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))


class StockLedger(Base):
    __tablename__ = "stock_ledger"
    __table_args__ = (
        Index("ix_stock_ledger_product_id", "product_id"),
        Index("ix_stock_ledger_tenant_date", "tenant_id", "created_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    transaction_type = Column(String(20), nullable=False)  # 'PURCHASE', 'SALE', 'ADJUSTMENT', 'TRANSFER'
    transaction_id = Column(UUID(as_uuid=True))
    quantity = Column(Numeric(12, 2), nullable=False)
    running_balance = Column(Numeric(12, 2), nullable=False)
    rate = Column(Numeric(15, 4))
    description = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
# ---------------------------------------------------------------------------

class Invoice(Base):
    __tablename__ = "invoices"
    __table_args__ = (
        # Hot path: all report and GST queries filter on these three columns
        Index("ix_invoices_tenant_date_status", "tenant_id", "issue_date", "status"),
        Index("ix_invoices_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_invoices_due_date", "tenant_id", "due_date"),
        UniqueConstraint("irn", name="uq_invoices_irn"),
        CheckConstraint(
            "status IN ('DRAFT', 'SENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
            name="ck_invoices_status",
        ),
        CheckConstraint(
            "e_invoice_status IN ('PENDING', 'GENERATED', 'CANCELLED', 'FAILED')",
            name="ck_invoices_e_invoice_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    invoice_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    discount_total = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    amount_paid = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    irn = Column(String(64))
    qr_code = Column(Text)
    e_invoice_status = Column(String(20), nullable=False, default="PENDING")
    e_invoice_error = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact", back_populates="invoices")
    lines = relationship("InvoiceLine", back_populates="invoice", cascade="all, delete-orphan")


class InvoiceLine(Base):
    __tablename__ = "invoice_lines"
    __table_args__ = (
        Index("ix_invoice_lines_invoice_id", "invoice_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    invoice = relationship("Invoice", back_populates="lines")
    product = relationship("Product")

    @property
    def product_name(self) -> str | None:
        return self.product.name if self.product else None


# ---------------------------------------------------------------------------
# PAYMENTS (AR — Customer Receipts)
# ---------------------------------------------------------------------------

class Payment(Base):
    __tablename__ = "payments"
    __table_args__ = (
        Index("ix_payments_tenant_date", "tenant_id", "payment_date"),
        CheckConstraint(
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'OTHER')",
            name="ck_payments_payment_mode",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    payment_number = Column(String(50), nullable=False)
    payment_date = Column(Date, nullable=False)
    payment_mode = Column(String(20), nullable=False)  # 'CASH', 'BANK', 'UPI', 'POS', 'OTHER'
    amount = Column(Numeric(15, 4), nullable=False)
    reference_number = Column(String(50))
    description = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    allocations = relationship("PaymentAllocation", back_populates="payment", cascade="all, delete-orphan")


class PaymentAllocation(Base):
    __tablename__ = "payment_allocations"
    __table_args__ = (
        Index("ix_payment_allocations_payment_id", "payment_id"),
        Index("ix_payment_allocations_invoice_id", "invoice_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    payment_id = Column(UUID(as_uuid=True), ForeignKey("payments.id"), nullable=False)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=False)
    amount = Column(Numeric(15, 4), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    payment = relationship("Payment", back_populates="allocations")
    invoice = relationship("Invoice")


# ---------------------------------------------------------------------------
# VENDOR BILLS (AP)
# ---------------------------------------------------------------------------

class Bill(Base):
    __tablename__ = "bills"
    __table_args__ = (
        Index("ix_bills_tenant_date_status", "tenant_id", "issue_date", "status"),
        Index("ix_bills_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_bills_due_date", "tenant_id", "due_date"),
        CheckConstraint(
            "status IN ('DRAFT', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
            name="ck_bills_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    bill_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    discount_total = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    amount_paid = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact", back_populates="bills")
    lines = relationship("BillLine", back_populates="bill", cascade="all, delete-orphan")


class BillLine(Base):
    __tablename__ = "bill_lines"
    __table_args__ = (
        Index("ix_bill_lines_bill_id", "bill_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bill_id = Column(UUID(as_uuid=True), ForeignKey("bills.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    bill = relationship("Bill", back_populates="lines")
    product = relationship("Product")

    @property
    def product_name(self) -> str | None:
        return self.product.name if self.product else None


class BillPayment(Base):
    __tablename__ = "bill_payments"
    __table_args__ = (
        Index("ix_bill_payments_tenant_date", "tenant_id", "payment_date"),
        CheckConstraint(
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'OTHER')",
            name="ck_bill_payments_payment_mode",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    payment_number = Column(String(50), nullable=False)
    payment_date = Column(Date, nullable=False)
    payment_mode = Column(String(20), nullable=False)
    amount = Column(Numeric(15, 4), nullable=False)
    reference_number = Column(String(50))
    description = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    allocations = relationship("BillPaymentAllocation", back_populates="payment", cascade="all, delete-orphan")


class BillPaymentAllocation(Base):
    __tablename__ = "bill_payment_allocations"
    __table_args__ = (
        Index("ix_bill_payment_allocations_payment_id", "payment_id"),
        Index("ix_bill_payment_allocations_bill_id", "bill_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    payment_id = Column(UUID(as_uuid=True), ForeignKey("bill_payments.id"), nullable=False)
    bill_id = Column(UUID(as_uuid=True), ForeignKey("bills.id"), nullable=False)
    amount = Column(Numeric(15, 4), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    payment = relationship("BillPayment", back_populates="allocations")
    bill = relationship("Bill")


# ---------------------------------------------------------------------------
# LEDGER — DOUBLE-ENTRY JOURNAL
# ---------------------------------------------------------------------------

class JournalEntry(Base):
    __tablename__ = "journal_entries"
    __table_args__ = (
        Index("ix_journal_entries_tenant_date", "tenant_id", "entry_date"),
        Index("ix_journal_entries_source", "tenant_id", "source_type", "source_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    entry_date = Column(Date, nullable=False)
    reference_number = Column(String(50))
    description = Column(Text)
    source_type = Column(String(20), nullable=False)  # 'INVOICE', 'BILL', 'PAYMENT', 'MANUAL'
    source_id = Column(UUID(as_uuid=True))
    is_locked = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    lines = relationship("JournalLine", back_populates="entry", cascade="all, delete-orphan")


class JournalLine(Base):
    __tablename__ = "journal_lines"
    __table_args__ = (
        Index("ix_journal_lines_entry_id", "entry_id"),
        Index("ix_journal_lines_account_id", "account_id"),
        CheckConstraint("direction IN ('DEBIT', 'CREDIT')", name="ck_journal_lines_direction"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    entry_id = Column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=False)
    account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False)
    amount = Column(Numeric(15, 4), nullable=False)
    direction = Column(String(6), nullable=False)  # 'DEBIT', 'CREDIT'
    narration = Column(Text)

    entry = relationship("JournalEntry", back_populates="lines")
    account = relationship("Account")


# ---------------------------------------------------------------------------
# COMPANY & SETTINGS
# ---------------------------------------------------------------------------

class Branch(Base):
    __tablename__ = "branches"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    name = Column(String(150), nullable=False)
    gstin = Column(String(15))
    address = Column(JSON, nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    tenant = relationship("Tenant")


class TenantSetting(Base):
    __tablename__ = "tenant_settings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False, unique=True)
    logo_url = Column(String(255))
    currency = Column(String(10), nullable=False, default="INR")
    gst_enabled = Column(Boolean, nullable=False, default=True)
    e_invoicing_enabled = Column(Boolean, nullable=False, default=False)
    e_invoice_username = Column(String(100))
    e_invoice_password_hash = Column(String(255))
    e_way_bill_username = Column(String(100))
    e_way_bill_password_hash = Column(String(255))
    extra_settings = Column(JSON, default=dict)
    origin_state_code = Column(String(2))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")


class NumberingSeries(Base):
    """
    Per-tenant document number sequences.
    next_number is incremented using SELECT FOR UPDATE to prevent race conditions.
    """
    __tablename__ = "numbering_series"
    __table_args__ = tuple()

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    document_type = Column(String(50), nullable=False)  # 'INVOICE', 'BILL', 'PAYMENT', 'JOURNAL', 'CREDIT_NOTE', 'DEBIT_NOTE'
    prefix = Column(String(50), nullable=False)
    next_number = Column(Integer, nullable=False, default=1)
    suffix = Column(String(50))
    padding_digits = Column(Integer, nullable=False, default=4)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")


# ---------------------------------------------------------------------------
# MASTER DATA
# ---------------------------------------------------------------------------

class Account(Base):
    __tablename__ = "accounts"
    __table_args__ = (
        Index("ix_accounts_tenant_type", "tenant_id", "account_type"),
        UniqueConstraint("tenant_id", "code", name="uq_account_tenant_code"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    name = Column(String(150), nullable=False)
    code = Column(String(50), nullable=False)
    account_type = Column(String(50), nullable=False)
    parent_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id"))
    opening_balance = Column(Numeric(15, 4), nullable=False, default=0)
    current_balance = Column(Numeric(15, 4), nullable=False, default=0)
    is_active = Column(Boolean, nullable=False, default=True)
    deleted_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")
    parent = relationship("Account", remote_side=[id])


class BankingProfile(Base):
    __tablename__ = "banking_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    bank_name = Column(String(150), nullable=False)
    account_number = Column(String(50), nullable=False)
    ifsc_code = Column(String(20), nullable=False)
    branch_name = Column(String(150))
    account_holder_name = Column(String(150), nullable=False)
    upi_id = Column(String(100))
    is_primary = Column(Boolean, nullable=False, default=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")


class ExpenseCategory(Base):
    __tablename__ = "expense_categories"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    name = Column(String(150), nullable=False)
    description = Column(Text)
    linked_account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id"))
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")
    linked_account = relationship("Account")


class Expense(Base):
    __tablename__ = "expenses"
    __table_args__ = (
        Index("ix_expenses_tenant_date", "tenant_id", "expense_date"),
        CheckConstraint("status IN ('DRAFT', 'POSTED', 'CANCELLED')", name="ck_expenses_status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    expense_number = Column(String(50), nullable=False)
    expense_category_id = Column(UUID(as_uuid=True), ForeignKey("expense_categories.id"), nullable=False)
    expense_date = Column(Date, nullable=False)
    vendor_name = Column(String(150))
    description = Column(Text)
    amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    status = Column(String(20), nullable=False, default="DRAFT")
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    category = relationship("ExpenseCategory")


class TaxTemplate(Base):
    __tablename__ = "tax_templates"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=True)
    name = Column(String(100), nullable=False)
    rate = Column(Numeric(5, 2), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")


class PaymentTerm(Base):
    __tablename__ = "payment_terms"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=True)
    name = Column(String(100), nullable=False)
    due_days = Column(Integer, nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")


# ---------------------------------------------------------------------------
# PURCHASE ORDERS
# ---------------------------------------------------------------------------

class PurchaseOrder(Base):
    __tablename__ = "purchase_orders"
    __table_args__ = (
        Index("ix_purchase_orders_tenant_date_status", "tenant_id", "order_date", "status"),
        Index("ix_purchase_orders_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_purchase_orders_due_date", "tenant_id", "due_date"),
        UniqueConstraint("tenant_id", "po_number", name="uq_purchase_orders_po_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'CONFIRMED', 'RECEIVED', 'CANCELLED')",
            name="ck_purchase_orders_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    po_number = Column(String(50), nullable=False)
    order_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    discount_total = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    amount_received = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    lines = relationship("PurchaseOrderLine", back_populates="purchase_order", cascade="all, delete-orphan")


class PurchaseOrderLine(Base):
    __tablename__ = "purchase_order_lines"
    __table_args__ = (
        Index("ix_purchase_order_lines_po_id", "purchase_order_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    purchase_order_id = Column(UUID(as_uuid=True), ForeignKey("purchase_orders.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    purchase_order = relationship("PurchaseOrder", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# SALES ORDERS
# ---------------------------------------------------------------------------

class SalesOrder(Base):
    __tablename__ = "sales_orders"
    __table_args__ = (
        Index("ix_sales_orders_tenant_date_status", "tenant_id", "order_date", "status"),
        Index("ix_sales_orders_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_sales_orders_due_date", "tenant_id", "due_date"),
        UniqueConstraint("tenant_id", "so_number", name="uq_sales_orders_so_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'CONFIRMED', 'DELIVERED', 'CANCELLED')",
            name="ck_sales_orders_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    so_number = Column(String(50), nullable=False)
    order_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    discount_total = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    amount_advanced = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    lines = relationship("SalesOrderLine", back_populates="sales_order", cascade="all, delete-orphan")


class SalesOrderLine(Base):
    __tablename__ = "sales_order_lines"
    __table_args__ = (
        Index("ix_sales_order_lines_so_id", "sales_order_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sales_order_id = Column(UUID(as_uuid=True), ForeignKey("sales_orders.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    sales_order = relationship("SalesOrder", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# DELIVERY CHALLANS
# ---------------------------------------------------------------------------

class DeliveryChallan(Base):
    __tablename__ = "delivery_challans"
    __table_args__ = (
        Index("ix_delivery_challans_tenant_date_status", "tenant_id", "challan_date", "status"),
        Index("ix_delivery_challans_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_delivery_challans_due_date", "tenant_id", "due_date"),
        UniqueConstraint("tenant_id", "challan_number", name="uq_delivery_challans_challan_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'ISSUED', 'CANCELLED')",
            name="ck_delivery_challans_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    challan_number = Column(String(50), nullable=False)
    challan_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    discount_total = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    lines = relationship("DeliveryChallanLine", back_populates="delivery_challan", cascade="all, delete-orphan")


class DeliveryChallanLine(Base):
    __tablename__ = "delivery_challan_lines"
    __table_args__ = (
        Index("ix_delivery_challan_lines_dc_id", "delivery_challan_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    delivery_challan_id = Column(UUID(as_uuid=True), ForeignKey("delivery_challans.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    delivery_challan = relationship("DeliveryChallan", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# SALES ORDERS
# ---------------------------------------------------------------------------
# E-WAY BILL
# ---------------------------------------------------------------------------

class EWayBill(Base):
    __tablename__ = "eway_bills"
    __table_args__ = (
        Index("ix_eway_bills_tenant_id", "tenant_id"),
        UniqueConstraint("eway_bill_number", name="uq_eway_bill_number"),
        CheckConstraint("status IN ('GENERATED', 'CANCELLED')", name="ck_eway_bills_status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=True)
    bill_id = Column(UUID(as_uuid=True), ForeignKey("bills.id"), nullable=True)
    eway_bill_number = Column(String(12))
    status = Column(String(20), nullable=False, default="GENERATED")  # 'GENERATED', 'CANCELLED'
    supply_type = Column(String(10), nullable=False, default="OUTWARD")
    sub_supply_type = Column(String(20), nullable=False, default="SUPPLY")
    transporter_id = Column(String(15))
    transporter_name = Column(String(150))
    trans_doc_number = Column(String(50))
    trans_doc_date = Column(Date)
    trans_distance = Column(Integer, nullable=False)
    trans_mode = Column(String(10), nullable=False, default="ROAD")
    vehicle_number = Column(String(20), nullable=False)
    vehicle_type = Column(String(20), nullable=False, default="REGULAR")
    valid_until = Column(DateTime(timezone=True))
    vehicle_history = Column(JSON, default=list)
    cancel_reason = Column(String(20))
    cancel_remarks = Column(String(100))
    cancel_date = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    invoice = relationship("Invoice")
    bill = relationship("Bill")


# ---------------------------------------------------------------------------
# AUDIT LOG
# ---------------------------------------------------------------------------

class AuditLog(Base):
    """
    Immutable audit trail for all significant write operations.
    Entries are append-only — never updated or deleted.
    """
    __tablename__ = "audit_logs"
    __table_args__ = (
        Index("ix_audit_logs_tenant_timestamp", "tenant_id", "timestamp"),
        Index("ix_audit_logs_entity", "tenant_id", "entity_type", "entity_id"),
        Index("ix_audit_logs_actor", "tenant_id", "actor_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    actor_id = Column(UUID(as_uuid=True))              # user_id who performed the action
    actor_email = Column(String(255))
    action = Column(String(100), nullable=False)        # e.g. 'invoice.created', 'invoice.finalized'
    entity_type = Column(String(50), nullable=False)    # e.g. 'Invoice', 'Bill', 'Payment'
    entity_id = Column(UUID(as_uuid=True))
    before_state = Column(JSON)                         # snapshot before change (null for creates)
    after_state = Column(JSON)                          # snapshot after change (null for deletes)
    ip_address = Column(String(45))                     # supports IPv6
    user_agent = Column(String(512))
    timestamp = Column(DateTime(timezone=True), nullable=False, default=_now)

    # No relationships — audit log is intentionally decoupled for immutability


# ---------------------------------------------------------------------------
# GST RETURN FILING STATE MACHINE
# ---------------------------------------------------------------------------

class GSTReturn(Base):
    """
    Tracks the filing state of each GSTR period.
    One row per (tenant, return_type, period).
    """
    __tablename__ = "gst_returns"
    __table_args__ = (
        UniqueConstraint("tenant_id", "return_type", "period_start", name="uq_gst_return_period"),
        Index("ix_gst_returns_tenant", "tenant_id", "return_type"),
        CheckConstraint(
            "status IN ('COMPUTED', 'READY_TO_FILE', 'FILED', 'ACKNOWLEDGED')",
            name="ck_gst_returns_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    return_type = Column(String(20), nullable=False)    # 'GSTR1', 'GSTR3B', 'GSTR9'
    period_start = Column(Date, nullable=False)
    period_end = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="COMPUTED")
    # COMPUTED → READY_TO_FILE → FILED → ACKNOWLEDGED
    json_payload = Column(JSON)                         # GSTN-format payload snapshot at time of filing
    filed_by = Column(UUID(as_uuid=True))              # user_id
    filed_at = Column(DateTime(timezone=True))
    arn = Column(String(50))                            # Acknowledgement Reference Number from GSTN
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ---------------------------------------------------------------------------
# INVENTORY / STOCK LEDGER
# ---------------------------------------------------------------------------

class StockLedger(Base):
    """
    Tracks stock-in and stock-out movements per product.
    On invoice finalize -> stock-out entries created.
    On bill finalize -> stock-in entries created.
    """
    __tablename__ = "stock_ledger"
    __table_args__ = (
        Index("ix_stock_ledger_tenant_product", "tenant_id", "product_id"),
        Index("ix_stock_ledger_tenant_date", "tenant_id", "created_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity = Column(Numeric(12, 4), nullable=False)      # positive for stock-in, negative for stock-out
    balance_quantity = Column(Numeric(12, 4), nullable=False)  # running balance after this entry
    reference_type = Column(String(20), nullable=False)    # 'INVOICE', 'BILL', 'ADJUSTMENT'
    reference_id = Column(UUID(as_uuid=True))
    rate = Column(Numeric(15, 4))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    product = relationship("Product")


# ---------------------------------------------------------------------------
# WEBHOOK EVENTS
# ---------------------------------------------------------------------------

class WebhookEvent(Base):
    """
    Outbound webhook event queue.
    Services subscribe to events like invoice.paid, payment.received, etc.
    """
    __tablename__ = "webhook_events"
    __table_args__ = (
        Index("ix_webhook_events_status", "status"),
        CheckConstraint("status IN ('PENDING', 'DELIVERED', 'FAILED')", name="ck_webhook_events_status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    event_type = Column(String(100), nullable=False)       # 'invoice.paid', 'payment.received', 'gst_return.filed'
    payload = Column(JSON, nullable=False)
    status = Column(String(20), nullable=False, default="PENDING")  # 'PENDING', 'DELIVERED', 'FAILED'
    target_url = Column(String(512))
    retry_count = Column(Integer, nullable=False, default=0)
    max_retries = Column(Integer, nullable=False, default=3)
    last_error = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ---------------------------------------------------------------------------
# PROFORMA INVOICES
# ---------------------------------------------------------------------------

class ProformaInvoice(Base):
    __tablename__ = "proforma_invoices"
    __table_args__ = (
        Index("ix_proforma_invoices_tenant_date_status", "tenant_id", "issue_date", "status"),
        Index("ix_proforma_invoices_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_proforma_invoices_due_date", "tenant_id", "due_date"),
        UniqueConstraint("tenant_id", "proforma_number", name="uq_proforma_invoices_proforma_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'ISSUED', 'CONVERTED', 'CANCELLED')",
            "ck_proforma_invoices_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    proforma_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    due_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    discount_total = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    converted_to_invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    converted_invoice = relationship("Invoice")
    lines = relationship("ProformaInvoiceLine", back_populates="proforma_invoice", cascade="all, delete-orphan")


class ProformaInvoiceLine(Base):
    __tablename__ = "proforma_invoice_lines"
    __table_args__ = (
        Index("ix_proforma_invoice_lines_pi_id", "proforma_invoice_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    proforma_invoice_id = Column(UUID(as_uuid=True), ForeignKey("proforma_invoices.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    proforma_invoice = relationship("ProformaInvoice", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# INVENTORY ADJUSTMENTS
# ---------------------------------------------------------------------------

class InventoryAdjustment(Base):
    __tablename__ = "inventory_adjustments"
    __table_args__ = (
        Index("ix_inventory_adjustments_tenant_date", "tenant_id", "adjustment_date"),
        CheckConstraint(
            "status IN ('DRAFT', 'CONFIRMED', 'CANCELLED')",
            name="ck_inventory_adjustments_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    adjustment_number = Column(String(50), nullable=False)
    adjustment_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    reason = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    lines = relationship("InventoryAdjustmentLine", back_populates="adjustment", cascade="all, delete-orphan")


class InventoryAdjustmentLine(Base):
    __tablename__ = "inventory_adjustment_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    inventory_adjustment_id = Column(UUID(as_uuid=True), ForeignKey("inventory_adjustments.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity_change = Column(Numeric(15, 4), nullable=False)  # Positive for increase, negative for decrease
    unit_cost = Column(Numeric(15, 4), nullable=False)
    total_change = Column(Numeric(15, 4), nullable=False)
    reason = Column(String(255))

    adjustment = relationship("InventoryAdjustment", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# CREDIT NOTES & DEBIT NOTES
# ---------------------------------------------------------------------------

class CreditNote(Base):
    __tablename__ = "credit_notes"
    __table_args__ = (
        Index("ix_credit_notes_tenant_id", "tenant_id"),
        Index("ix_credit_notes_invoice_id", "invoice_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=True)
    credit_note_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    reason = Column(String(255), nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")  # DRAFT, ISSUED, CANCELLED
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    # Relationships
    invoice = relationship("Invoice")
    lines = relationship("CreditNoteLine", back_populates="credit_note", cascade="all, delete-orphan")


class CreditNoteLine(Base):
    __tablename__ = "credit_note_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    credit_note_id = Column(UUID(as_uuid=True), ForeignKey("credit_notes.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity = Column(Numeric(15, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(20))
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    # Relationships
    credit_note = relationship("CreditNote", back_populates="lines")
    product = relationship("Product")


class DebitNote(Base):
    __tablename__ = "debit_notes"
    __table_args__ = (
        Index("ix_debit_notes_tenant_id", "tenant_id"),
        Index("ix_debit_notes_invoice_id", "invoice_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=True)
    debit_note_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    reason = Column(String(255), nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")  # DRAFT, ISSUED, CANCELLED
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    # Relationships
    invoice = relationship("Invoice")
    lines = relationship("DebitNoteLine", back_populates="debit_note", cascade="all, delete-orphan")


class DebitNoteLine(Base):
    __tablename__ = "debit_note_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    debit_note_id = Column(UUID(as_uuid=True), ForeignKey("debit_notes.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity = Column(Numeric(15, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(20))
    gst_rate = Column(Numeric(5, 2), nullable=False)
    cgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_rate = Column(Numeric(5, 2), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False)

    # Relationships
    debit_note = relationship("DebitNote", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# BANKING & RECONCILIATION
# ---------------------------------------------------------------------------
# BANK RECONCILIATION
# ---------------------------------------------------------------------------

class BankStatement(Base):
    __tablename__ = "bank_statements"
    __table_args__ = (
        Index("ix_bank_statements_tenant_date", "tenant_id", "statement_date"),
        Index("ix_bank_statements_banking_profile", "tenant_id", "banking_profile_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    banking_profile_id = Column(UUID(as_uuid=True), ForeignKey("banking_profiles.id"), nullable=False)
    statement_date = Column(Date, nullable=False)  # Date of the statement
    starting_balance = Column(Numeric(15, 4), nullable=False, default=0)
    ending_balance = Column(Numeric(15, 4), nullable=False, default=0)
    currency = Column(String(10), nullable=False, default="INR")
    status = Column(String(20), nullable=False, default="IMPORTED")  # IMPORTED, RECONCILED
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    banking_profile = relationship("BankingProfile")
    transactions = relationship("BankTransaction", back_populates="bank_statement", cascade="all, delete-orphan")


class BankTransaction(Base):
    __tablename__ = "bank_transactions"
    __table_args__ = (
        Index("ix_bank_transactions_statement_date", "bank_statement_id", "transaction_date"),
        Index("ix_bank_transactions_amount", "bank_statement_id", "amount"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bank_statement_id = Column(UUID(as_uuid=True), ForeignKey("bank_statements.id"), nullable=False)
    transaction_date = Column(Date, nullable=False)
    amount = Column(Numeric(15, 4), nullable=False)  # Positive for credit (deposit), negative for debit (withdrawal)
    description = Column(Text)
    reference_number = Column(String(50))  # e.g., check number, transaction ID
    status = Column(String(20), nullable=False, default="PENDING")  # PENDING, CLEARED, RECONCILED
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    bank_statement = relationship("BankStatement", back_populates="transactions")
    # We'll link to either Payment or BillPayment via a reconciliation table


class BankReconciliation(Base):
    __tablename__ = "bank_reconciliations"
    __table_args__ = (
        Index("ix_bank_reconciliations_transaction_id", "bank_transaction_id"),
        Index("ix_bank_reconciliations_payment_id", "payment_id"),
        Index("ix_bank_reconciliations_bill_payment_id", "bill_payment_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    bank_transaction_id = Column(UUID(as_uuid=True), ForeignKey("bank_transactions.id"), nullable=False)
    payment_id = Column(UUID(as_uuid=True), ForeignKey("payments.id"), nullable=True)
    bill_payment_id = Column(UUID(as_uuid=True), ForeignKey("bill_payments.id"), nullable=True)
    amount = Column(Numeric(15, 4), nullable=False)  # The reconciled amount
    notes = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    bank_transaction = relationship("BankTransaction")
    payment = relationship("Payment")
    bill_payment = relationship("BillPayment")


# ---------------------------------------------------------------------------
# TENANT INVITATION
# ---------------------------------------------------------------------------

class TenantInvitation(Base):
    """
    Invite a user to join a tenant with a specific role.
    """
    __tablename__ = "tenant_invitations"
    __table_args__ = (
        Index("ix_tenant_invitations_email", "tenant_id", "email"),
        CheckConstraint("status IN ('PENDING', 'ACCEPTED', 'EXPIRED')", name="ck_tenant_invitations_status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    email = Column(String(255), nullable=False)
    role = Column(String(50), nullable=False)
    invited_by = Column(UUID(as_uuid=True), nullable=False)
    token = Column(String(255), nullable=False, unique=True)
    status = Column(String(20), nullable=False, default="PENDING")  # 'PENDING', 'ACCEPTED', 'EXPIRED'
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")
