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
    BigInteger, Column, String, Boolean, Numeric, Date, DateTime,
    ForeignKey, Text, JSON, Integer, Index, UniqueConstraint, CheckConstraint, text, Uuid,
    inspect,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship, Session
from sqlalchemy import event
from src.core.database import Base

# ---------------------------------------------------------------------------
# Timezone-aware UTC timestamp helpers
# ---------------------------------------------------------------------------
_now = lambda: datetime.now(timezone.utc)  # noqa: E731


def _current_indian_financial_year_start() -> date:
    today = date.today()
    return date(today.year if today.month >= 4 else today.year - 1, 4, 1)


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
    tax_mode = Column(String(20), nullable=False, default="NON_GST", server_default="NON_GST")
    financial_year_start = Column(Date, nullable=False, default=_current_indian_financial_year_start)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    memberships = relationship("TenantMembership", back_populates="tenant", cascade="all, delete-orphan")

    @property
    def gst_enabled(self) -> bool:
        return self.tax_mode in ("GST_REGULAR", "GST_COMPOSITION")


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)
    full_name = Column(String(150), nullable=False)
    phone_number = Column(String(15))
    is_active = Column(Boolean, nullable=False, default=True)
    failed_login_attempts = Column(Integer, nullable=False, default=0)
    locked_until = Column(DateTime(timezone=True))
    last_login_at = Column(DateTime(timezone=True))
    email_verified = Column(Boolean, nullable=False, default=False)
    email_verify_token = Column(String(255))
    email_verify_expires = Column(DateTime(timezone=True))
    totp_secret = Column(String(32))
    totp_enabled = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    memberships = relationship("TenantMembership", back_populates="user", cascade="all, delete-orphan")


class TenantMembership(Base):
    __tablename__ = "tenant_memberships"
    __table_args__ = (
        UniqueConstraint("tenant_id", "user_id", name="uq_membership_tenant_user"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    role = Column(String(50), nullable=False)  # 'owner', 'accountant', 'salesperson', 'auditor'
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant", back_populates="memberships")
    user = relationship("User", back_populates="memberships")


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    token = Column(String(255), nullable=False, index=True)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    user = relationship("User")


# ---------------------------------------------------------------------------
# CONTACT (Customer / Vendor)
# ---------------------------------------------------------------------------

class Contact(Base):
    __tablename__ = "contacts"
    __table_args__ = (
        Index("ix_contacts_tenant_id", "tenant_id"),
        Index("ix_contacts_tenant_type", "tenant_id", "contact_type"),
        Index("ix_contacts_tenant_deleted", "tenant_id", "deleted_at"),
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
    billing_address = Column(JSON, nullable=True)
    shipping_address = Column(JSON)
    state_code = Column(String(2), nullable=True)
    is_active = Column(Boolean, nullable=False, default=True)
    opening_balance = Column(Numeric(15, 4), nullable=False, default=0)
    credit_balance = Column(Numeric(15, 4), nullable=False, default=0)
    custom_fields = Column(JSON, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    invoices = relationship("Invoice", back_populates="contact")
    bills = relationship("Bill", back_populates="contact")


# ---------------------------------------------------------------------------
# PERIOD LOCK AUDIT — tracks who locked/unlocked periods and when
# ---------------------------------------------------------------------------

class PeriodLockAudit(Base):
    """Audit trail for period lock/unlock operations."""
    __tablename__ = "period_lock_audits"
    __table_args__ = (
        Index("ix_pla_tenant_date", "tenant_id", "period_date"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    period_date = Column(Date, nullable=False)
    action = Column(String(10), nullable=False)  # "LOCK" or "UNLOCK"
    locked_by = Column(UUID(as_uuid=True), nullable=False)
    locked_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    note = Column(Text)


# ---------------------------------------------------------------------------
# PRODUCT / SERVICE
# ---------------------------------------------------------------------------

class Product(Base):
    __tablename__ = "products"
    __table_args__ = (
        Index("ix_products_tenant_id", "tenant_id"),
        Index("ix_products_tenant_deleted", "tenant_id", "deleted_at"),
        Index(
            "uq_products_tenant_barcode",
            "tenant_id",
            "barcode",
            unique=True,
            postgresql_where=text("barcode IS NOT NULL AND deleted_at IS NULL"),
            sqlite_where=text("barcode IS NOT NULL AND deleted_at IS NULL"),
        ),
        CheckConstraint("sales_price >= 0", name="ck_products_sales_price"),
        CheckConstraint("purchase_price >= 0", name="ck_products_purchase_price"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    name = Column(String(150), nullable=False)
    sku = Column(String(50))
    barcode = Column(String(64))
    hsn_sac = Column(String(8), nullable=False)
    product_type = Column(String(10), nullable=False)  # 'GOODS', 'SERVICE'
    uom = Column(String(10), nullable=False)            # 'PCS', 'KGS', 'NOS', 'HRS'
    sales_price = Column(Numeric(15, 4), nullable=False, default=0)
    purchase_price = Column(Numeric(15, 4), nullable=False, default=0)
    gst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    opening_stock = Column(Numeric(12, 2), nullable=False, default=0)
    current_stock = Column(Numeric(12, 2), nullable=False, default=0)
    reorder_level = Column(Numeric(12, 2), nullable=False, default=0)
    party_item_rates = Column(JSON, nullable=False, default=dict)
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))


# ---------------------------------------------------------------------------
# SALES INVOICES
# ---------------------------------------------------------------------------

class Invoice(Base):
    __tablename__ = "invoices"
    __table_args__ = (
        # Hot path: all report and GST queries filter on these three columns
        Index("ix_invoices_tenant_date_status", "tenant_id", "issue_date", "status"),
        Index("ix_invoices_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_invoices_due_date", "tenant_id", "due_date"),
        Index("ix_invoices_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "invoice_number", name="uq_invoices_tenant_number"),
        UniqueConstraint("irn", name="uq_invoices_irn"),
        UniqueConstraint(
            "tenant_id", "source_document_type", "source_document_id",
            name="uq_invoices_source_document",
        ),
        CheckConstraint(
            "status IN ('DRAFT', 'POSTED', 'SENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
            name="ck_invoices_status",
        ),
        CheckConstraint(
            "e_invoice_status IN ('PENDING', 'GENERATED', 'CANCELLED', 'FAILED')",
            name="ck_invoices_e_invoice_status",
        ),
        CheckConstraint(
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off - discount_total + shipping_charges, 2)",
            name="ck_invoices_total_balance",
        ),
        CheckConstraint(
            "amount_paid <= total",
            name="ck_invoices_amount_paid",
        ),
        CheckConstraint("amount_paid >= 0", name="ck_invoices_amount_paid_nonnegative"),
        CheckConstraint("due_date >= issue_date", name="ck_invoices_due_date"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    source_document_type = Column(String(30))
    source_document_id = Column(UUID(as_uuid=True))
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
    shipping_charges = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    amount_paid = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    irn = Column(String(64))
    qr_code = Column(Text)
    e_invoice_status = Column(String(20), nullable=False, default="PENDING")
    e_invoice_error = Column(Text)
    notes = Column(Text)                       # internal / customer-facing notes
    terms_and_conditions = Column(Text)          # printed on invoice
    reference_number = Column(String(50))        # PO ref, order number
    vyapar_custom_fields = Column(JSON, nullable=False, default=dict)  # UDF from Vyapar
    sales_person_id = Column(UUID(as_uuid=True)) # who made the sale
    is_rcm = Column(Boolean, nullable=False, default=False)  # Reverse Charge Mechanism
    is_gst_inclusive = Column(Boolean, nullable=False, default=False)
    supply_type = Column(String(20), nullable=False, default="DOMESTIC")  # DOMESTIC, EXPORT_WITH_TAX, EXPORT_WITHOUT_TAX, SEZ_WITH_TAX, SEZ_WITHOUT_TAX
    currency = Column(String(10), nullable=False, default="INR")  # ISO 4217 currency code
    exchange_rate = Column(Numeric(15, 6), nullable=False, default=1)  # Exchange rate to INR
    tds_rate = Column(Numeric(5, 2), nullable=False, default=0)  # TDS %
    tds_amount = Column(Numeric(15, 4), nullable=False, default=0)  # TDS deducted
    tcs_rate = Column(Numeric(5, 2), nullable=False, default=0)  # TCS %
    tcs_amount = Column(Numeric(15, 4), nullable=False, default=0)  # TCS collected
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact", back_populates="invoices")
    lines = relationship("InvoiceLine", back_populates="invoice", cascade="all, delete-orphan")


class InvoiceLine(Base):
    __tablename__ = "invoice_lines"
    __table_args__ = (
        Index("ix_invoice_lines_invoice_id", "invoice_id"),
        Index("ix_invoice_lines_invoice_product", "invoice_id", "product_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        Index("ix_payments_tenant_contact_date", "tenant_id", "contact_id", "payment_date"),
        Index("ix_payments_tenant_status_date", "tenant_id", "status", "payment_date"),
        Index("ix_payments_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "payment_number", name="uq_payments_tenant_number"),
        CheckConstraint(
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'CHEQUE', 'NEFT_RTGS', 'OTHER')",
            name="ck_payments_payment_mode",
        ),
        CheckConstraint("amount > 0", name="ck_payments_amount_positive"),
        CheckConstraint(
            "status IN ('ACTIVE', 'CANCELLED')",
            name="ck_payments_status",
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
    advance_supply_type = Column(String(10))
    status = Column(String(20), nullable=False, default="ACTIVE")
    cancelled_at = Column(DateTime(timezone=True))
    cancellation_reason = Column(Text)
    created_by = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    allocations = relationship("PaymentAllocation", back_populates="payment", cascade="all, delete-orphan")


class PaymentAllocation(Base):
    __tablename__ = "payment_allocations"
    __table_args__ = (
        Index("ix_payment_allocations_payment_id", "payment_id"),
        Index("ix_payment_allocations_invoice_id", "invoice_id"),
        Index("ix_payment_allocations_tenant", "tenant_id"),
        Index("ix_payment_allocations_payment_invoice", "payment_id", "invoice_id"),
        UniqueConstraint(
            "payment_id", "invoice_id", name="uq_payment_allocations_payment_invoice"
        ),
        CheckConstraint("amount > 0", name="ck_payment_allocations_amount"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        Index("ix_bills_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "bill_number", name="uq_bills_tenant_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'POSTED', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
            name="ck_bills_status",
        ),
        CheckConstraint(
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off - discount_total + shipping_charges, 2)",
            name="ck_bills_total_balance",
        ),
        CheckConstraint(
            "amount_paid <= total",
            name="ck_bills_amount_paid",
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
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    shipping_charges = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    amount_paid = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    notes = Column(Text)
    terms_and_conditions = Column(Text)
    reference_number = Column(String(50))
    vyapar_custom_fields = Column(JSON, nullable=False, default=dict)
    tds_rate = Column(Numeric(5, 2), nullable=False, default=0)    # TDS %
    tds_amount = Column(Numeric(15, 4), nullable=False, default=0)  # TDS deducted
    itc_eligible = Column(Boolean, nullable=False, default=True)  # ITC eligibility for GSTR-3B
    is_gst_inclusive = Column(Boolean, nullable=False, default=False)
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
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
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        Index("ix_bill_payments_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "payment_number", name="uq_bill_payments_tenant_number"),
        CheckConstraint(
            "payment_mode IN ('CASH', 'BANK', 'UPI', 'POS', 'CHEQUE', 'NEFT_RTGS', 'OTHER')",
            name="ck_bill_payments_payment_mode",
        ),
        CheckConstraint("amount > 0", name="ck_bill_payments_amount_positive"),
        CheckConstraint("status IN ('ACTIVE', 'CANCELLED')", name="ck_bill_payments_status"),
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
    status = Column(String(20), nullable=False, default="ACTIVE")
    cancelled_at = Column(DateTime(timezone=True))
    cancellation_reason = Column(Text)
    created_by = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    allocations = relationship("BillPaymentAllocation", back_populates="payment", cascade="all, delete-orphan")


class BillPaymentAllocation(Base):
    __tablename__ = "bill_payment_allocations"
    __table_args__ = (
        Index("ix_bill_payment_allocations_payment_id", "payment_id"),
        Index("ix_bill_payment_allocations_bill_id", "bill_id"),
        Index("ix_bill_payment_allocations_tenant", "tenant_id"),
        CheckConstraint("amount > 0", name="ck_bill_payment_allocations_amount"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        UniqueConstraint("tenant_id", "reference_number", name="uq_journal_entries_tenant_reference"),
        UniqueConstraint("tenant_id", "source_type", "source_id", name="uq_journal_entries_tenant_source"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    entry_date = Column(Date, nullable=False)
    reference_number = Column(String(50))
    description = Column(Text)
    source_type = Column(String(20), nullable=False)  # 'INVOICE', 'BILL', 'PAYMENT', 'MANUAL'
    source_id = Column(UUID(as_uuid=True))
    is_locked = Column(Boolean, nullable=False, default=True)
    # Direct-posting audit metadata — always populated from authenticated
    # server context, never from client input.
    created_by = Column(UUID(as_uuid=True), nullable=True)
    posted_by = Column(UUID(as_uuid=True), nullable=True)
    posted_at = Column(DateTime(timezone=True), nullable=True)
    source_channel = Column(String(20), nullable=True)  # UI / API / IMPORT / RECURRING / SYNC
    # Reversal / correction linkage (bidirectional, self-referencing).
    reversed_by = Column(UUID(as_uuid=True), nullable=True)
    reversed_at = Column(DateTime(timezone=True), nullable=True)
    reversal_transaction_id = Column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=True)
    reverses_transaction_id = Column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=True)
    replacement_transaction_id = Column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=True)
    original_transaction_id = Column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    lines = relationship("JournalLine", back_populates="entry", cascade="all, delete-orphan")


_JOURNAL_MUTABLE_META = frozenset({
    # Reversal/correction bookkeeping only — never amounts, accounts, dates,
    # or directions. These are written by the reversal/correction flow.
    "reversed_by",
    "reversed_at",
    "reversal_transaction_id",
    "reverses_transaction_id",
    "replacement_transaction_id",
    "updated_at",
})

@event.listens_for(JournalEntry, "before_update")
def prevent_journal_entry_update(mapper, connection, target):
    """Ledger history is append-only. Only reversal/correction metadata may
    change on a locked entry; everything else raises IntegrityError.

    An entry that is genuinely unlocked (``is_locked`` already False before
    this flush, not being flipped in it) may still be edited — that preserves
    pre-existing unlocked records. But an entry that is being *flipped* from
    locked to unlocked in the same flush that mutates financial fields is
    treated as a locked-entry change, closing the single-flush bypass.
    """
    from sqlalchemy import inspect as sa_inspect
    from sqlalchemy.exc import IntegrityError

    state = sa_inspect(target)
    changed = {
        attr.key
        for attr in state.mapper.column_attrs
        if state.attrs[attr.key].history.has_changes()
    }
    # If it is not locked AND is_locked is not being changed in this flush,
    # it was already unlocked before the flush — allow the edit.
    if not target.is_locked and "is_locked" not in changed:
        return
    if changed - _JOURNAL_MUTABLE_META:
        raise IntegrityError(
            "Cannot modify a locked journal entry. "
            "Create a reversal entry instead.",
            params={},
            orig=None,
        )


@event.listens_for(JournalEntry, "before_delete")
def prevent_journal_entry_delete(mapper, connection, target):
    """Ledger history is append-only: entries may be reversed, never deleted.

    There is no exception and no client-settable bypass: year-end reopen and
    every correction flow create REVERSAL entries instead of deleting
    history, so an attacker who can run raw SQL can never destroy accounting
    facts by setting a GUC.  The database-level triggers (see
    postgres_hardening.py) enforce the same rule for raw SQL.
    """
    from sqlalchemy.exc import IntegrityError
    raise IntegrityError(
        "Cannot delete a journal entry. "
        "Create a reversal entry instead.",
        params={},
        orig=None,
    )


class JournalLine(Base):
    __tablename__ = "journal_lines"
    __table_args__ = (
        Index("ix_journal_lines_entry_id", "entry_id"),
        Index("ix_journal_lines_account_id", "account_id"),
        Index("ix_journal_lines_entry_account", "entry_id", "account_id"),
        CheckConstraint("direction IN ('DEBIT', 'CREDIT')", name="ck_journal_lines_direction"),
        CheckConstraint("amount > 0", name="ck_journal_lines_amount"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    entry_id = Column(UUID(as_uuid=True), ForeignKey("journal_entries.id"), nullable=False)
    account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False)
    amount = Column(Numeric(15, 4), nullable=False)
    direction = Column(String(6), nullable=False)  # 'DEBIT', 'CREDIT'
    narration = Column(Text)

    entry = relationship("JournalEntry", back_populates="lines")
    account = relationship("Account")


@event.listens_for(JournalLine, "before_update")
def prevent_journal_line_update(mapper, connection, target):
    """Journal lines are immutable accounting history: no in-place edits."""
    from sqlalchemy.exc import IntegrityError
    raise IntegrityError(
        "Cannot modify a journal line. Journal entries are immutable; "
        "create a reversal entry instead.",
        params={},
        orig=None,
    )


@event.listens_for(JournalLine, "before_delete")
def prevent_journal_line_delete(mapper, connection, target):
    """Journal lines are part of immutable ledger history: never deletable.

    Same rule as JournalEntry: no exception, no bypass.  Year-end reopen
    reverses the roll-forward entries instead of deleting them.
    """
    from sqlalchemy.exc import IntegrityError
    raise IntegrityError(
        "Cannot delete a journal line. Journal entries are immutable; "
        "create a reversal entry instead.",
        params={},
        orig=None,
    )


# ---------------------------------------------------------------------------
# COMPANY & SETTINGS
# ---------------------------------------------------------------------------

class Branch(Base):
    __tablename__ = "branches"
    __table_args__ = (
        Index("ix_branches_tenant_deleted", "tenant_id", "deleted_at"),
    )

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
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    name = Column(String(100), nullable=True)  # Setting name/key (optional for backward compat)
    value = Column(String(255))  # Setting value
    logo_url = Column(String(255))
    currency = Column(String(10), nullable=False, default="INR")
    gst_enabled = Column(Boolean, nullable=False, default=True)
    e_invoicing_enabled = Column(Boolean, nullable=False, default=False)
    e_invoice_username = Column(String(100))
    e_invoice_password_hash = Column(String(255))
    e_way_bill_username = Column(String(100))
    e_way_bill_password_hash = Column(String(255))
    upi_id = Column(String(100))
    display_settings = Column(JSON, nullable=False, default=dict)
    extra_settings = Column(JSON, default=dict)
    origin_state_code = Column(String(2))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")

    @property
    def key(self):
        """Alias for name - allows constructing TenantSetting(key=...) for dynamic settings."""
        return getattr(self, "name", None)

    @key.setter
    def key(self, value):
        setattr(self, "name", value)


class NumberingSeries(Base):
    """
    Per-tenant document number sequences.
    next_number is incremented using SELECT FOR UPDATE to prevent race conditions.
    """
    __tablename__ = "numbering_series"
    __table_args__ = (
        Index(
            "uq_numbering_series_active_document",
            "tenant_id",
            "document_type",
            unique=True,
            postgresql_where=text("is_active"),
            sqlite_where=text("is_active = 1"),
        ),
        CheckConstraint("next_number > 0", name="ck_numbering_series_next_number"),
        CheckConstraint("padding_digits BETWEEN 1 AND 12", name="ck_numbering_series_padding"),
    )


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


class OfflineNumberAllocation(Base):
    """A durable document-number lease assigned to one installation."""

    __tablename__ = "offline_number_allocations"
    __table_args__ = (
        UniqueConstraint(
            "tenant_id",
            "document_type",
            "range_start",
            name="uq_offline_number_allocation_start",
        ),
        CheckConstraint(
            "range_start > 0 AND range_end >= range_start",
            name="ck_offline_number_allocation_range",
        ),
        Index(
            "ix_offline_number_allocations_device",
            "tenant_id",
            "device_id",
            "document_type",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    device_id = Column(UUID(as_uuid=True), nullable=False)
    financial_year_id = Column(UUID(as_uuid=True), nullable=False)
    numbering_series_id = Column(
        UUID(as_uuid=True),
        ForeignKey("numbering_series.id"),
        nullable=False,
    )
    document_type = Column(String(50), nullable=False)
    series = Column(String(50), nullable=False)
    prefix = Column(String(50), nullable=False, default="")
    suffix = Column(String(50))
    padding_digits = Column(Integer, nullable=False, default=4)
    range_start = Column(Integer, nullable=False)
    range_end = Column(Integer, nullable=False)
    allocated_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    expires_at = Column(DateTime(timezone=True))
    is_active = Column(Boolean, nullable=False, default=True)


# ---------------------------------------------------------------------------
# MASTER DATA
# ---------------------------------------------------------------------------

class Account(Base):
    __tablename__ = "accounts"
    __table_args__ = (
        Index("ix_accounts_tenant_type", "tenant_id", "account_type"),
        UniqueConstraint("tenant_id", "code", name="uq_account_tenant_code"),
        CheckConstraint(
            "account_type IN ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE')",
            name="ck_accounts_type",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=False)
    name = Column(String(150), nullable=False)
    code = Column(String(50), nullable=False)
    account_type = Column(String(50), nullable=False)
    account_group = Column(String(100), nullable=True)  # e.g. "Cash & Bank", "Fixed Assets", "GST Output"
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
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")
    linked_account = relationship("Account")


class Expense(Base):
    __tablename__ = "expenses"
    __table_args__ = (
        Index("ix_expenses_tenant_date", "tenant_id", "expense_date"),
        Index("ix_expenses_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "expense_number", name="uq_expenses_tenant_number"),
        CheckConstraint("status IN ('DRAFT', 'POSTED', 'CANCELLED')", name="ck_expenses_status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    expense_number = Column(String(50), nullable=False)
    expense_category_id = Column(UUID(as_uuid=True), ForeignKey("expense_categories.id"), nullable=False)
    bank_account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id"), nullable=True)
    expense_date = Column(Date, nullable=False)
    vendor_name = Column(String(150))
    description = Column(Text)
    amount = Column(Numeric(15, 4), nullable=False, default=0)
    gst_rate = Column(Numeric(5, 2), nullable=False, default=0)
    place_of_supply_state_code = Column(String(2), nullable=True)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    status = Column(String(20), nullable=False, default="DRAFT")
    notes = Column(Text)
    reference_number = Column(String(50))
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
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
        Index("ix_purchase_orders_tenant_deleted", "tenant_id", "deleted_at"),
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
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
# GOODS RECEIPTS (GRN)
# ---------------------------------------------------------------------------

class GoodsReceipt(Base):
    __tablename__ = "goods_receipts"
    __table_args__ = (
        Index("ix_goods_receipts_tenant_date", "tenant_id", "receipt_date"),
        Index("ix_goods_receipts_tenant_status", "tenant_id", "status"),
        UniqueConstraint(
            "tenant_id",
            "receipt_number",
            name="uq_goods_receipts_tenant_number",
        ),
        CheckConstraint(
            "status IN ('DRAFT', 'CONFIRMED', 'CANCELLED')",
            name="ck_goods_receipts_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    purchase_order_id = Column(
        UUID(as_uuid=True),
        ForeignKey("purchase_orders.id"),
        nullable=True,
    )
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    receipt_number = Column(String(50), nullable=False)
    receipt_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    notes = Column(Text)
    confirmed_at = Column(DateTime(timezone=True))
    cancelled_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        default=_now,
        onupdate=_now,
    )
    deleted_at = Column(DateTime(timezone=True))

    purchase_order = relationship("PurchaseOrder")
    contact = relationship("Contact")
    lines = relationship(
        "GoodsReceiptLine",
        back_populates="goods_receipt",
        cascade="all, delete-orphan",
    )


class GoodsReceiptLine(Base):
    __tablename__ = "goods_receipt_lines"
    __table_args__ = (
        Index("ix_goods_receipt_lines_receipt", "goods_receipt_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    goods_receipt_id = Column(
        UUID(as_uuid=True),
        ForeignKey("goods_receipts.id"),
        nullable=False,
    )
    purchase_order_line_id = Column(
        UUID(as_uuid=True),
        ForeignKey("purchase_order_lines.id"),
        nullable=True,
    )
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity_ordered = Column(Numeric(12, 4), nullable=False)
    quantity_received = Column(Numeric(12, 4), nullable=False)
    warehouse_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"), nullable=True)
    lot_number = Column(String(100))
    batch_number = Column(String(100))

    goods_receipt = relationship("GoodsReceipt", back_populates="lines")
    product = relationship("Product")
    warehouse = relationship("Branch")


# ---------------------------------------------------------------------------
# SALES ORDERS
# ---------------------------------------------------------------------------

class SalesOrder(Base):
    __tablename__ = "sales_orders"
    __table_args__ = (
        Index("ix_sales_orders_tenant_date_status", "tenant_id", "order_date", "status"),
        Index("ix_sales_orders_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_sales_orders_due_date", "tenant_id", "due_date"),
        Index("ix_sales_orders_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "so_number", name="uq_sales_orders_so_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'CONFIRMED', 'DELIVERED', 'CANCELLED')",
            name="ck_sales_orders_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    source_proforma_id = Column(UUID(as_uuid=True), ForeignKey("proforma_invoices.id"))
    converted_to_invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"))
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
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        Index("ix_delivery_challans_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "challan_number", name="uq_delivery_challans_challan_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'ISSUED', 'CANCELLED')",
            name="ck_delivery_challans_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    source_sales_order_id = Column(UUID(as_uuid=True), ForeignKey("sales_orders.id"))
    converted_to_invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"))
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
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        CheckConstraint(
            "(invoice_id IS NOT NULL AND bill_id IS NULL) OR (invoice_id IS NULL AND bill_id IS NOT NULL)",
            name="ck_eway_bills_single_parent",
        ),
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
        {"extend_existing": True},
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=True)
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
        Index("ix_stock_ledger_tenant_warehouse_product", "tenant_id", "warehouse_id", "product_id"),
        {"extend_existing": True},
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    warehouse_id = Column(UUID(as_uuid=True), ForeignKey("branches.id"))
    quantity = Column(Numeric(12, 4), nullable=False)      # positive for stock-in, negative for stock-out
    balance_quantity = Column(Numeric(12, 4), nullable=False)  # running balance after this entry
    reference_type = Column(String(20), nullable=False)    # 'INVOICE', 'BILL', 'ADJUSTMENT'
    reference_id = Column(UUID(as_uuid=True))
    rate = Column(Numeric(15, 4))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    # Phase 1: actor / channel attribution (stamped by before_insert from
    # session-scoped server context — never from client input).
    created_by = Column(UUID(as_uuid=True), nullable=True)
    source_channel = Column(String(20), nullable=True)  # UI / API / IMPORT / RECURRING / SYNC
    # Movement-level reversal linkage: a reversal movement points at the
    # original movement it reverses; the original records its reversal.
    reverses_movement_id = Column(
        UUID(as_uuid=True),
        ForeignKey("stock_ledger.id", name="fk_stock_ledger_reverses_movement"),
        nullable=True,
    )
    reversal_movement_id = Column(
        UUID(as_uuid=True),
        ForeignKey("stock_ledger.id", name="fk_stock_ledger_reversal_movement"),
        nullable=True,
    )
    reversed_by = Column(UUID(as_uuid=True), nullable=True)
    reversed_at = Column(DateTime(timezone=True), nullable=True)

    product = relationship("Product")


# ---------------------------------------------------------------------------
# STOCK-LEDGER APPEND-ONLY GUARDS
#
# Stock movements are inventory accounting history. Once written they may
# never be updated or deleted in place; corrections must create reversal
# movements (``original -> reversal -> replacement``). Unlike journal
# entries there is deliberately NO scoped system-maintenance exception: the
# year-end reopen flow does not touch stock_ledger, and every correction
# path (invoice cancel, credit-note cancel, returns, inventory adjustments)
# already creates ``*_REVERSAL`` rows. If a future flow needs to roll back
# system-generated movements it must be reviewed and added explicitly.
# ---------------------------------------------------------------------------

# The ONLY in-place mutations permitted on an existing movement are the
# reversal-linkage bookkeeping fields written by the correction flow when it
# creates the reversal movement. Quantity, balance, reference identity,
# product, warehouse, rate and tenant are never mutable.
_STOCK_MUTABLE_META = frozenset({
    "reversal_movement_id",
    "reversed_by",
    "reversed_at",
})


@event.listens_for(StockLedger, "before_update")
def prevent_stock_ledger_update(mapper, connection, target):
    """Existing stock movements are immutable except reversal-linkage meta."""
    from sqlalchemy import inspect as sa_inspect
    from sqlalchemy.exc import IntegrityError

    state = sa_inspect(target)
    changed = {
        attr.key
        for attr in state.mapper.column_attrs
        if state.attrs[attr.key].history.has_changes()
    }
    if changed - _STOCK_MUTABLE_META:
        raise IntegrityError(
            "Cannot modify a stock-ledger movement. "
            "Create a reversal movement instead.",
            params={},
            orig=None,
        )


@event.listens_for(StockLedger, "before_delete")
def prevent_stock_ledger_delete(mapper, connection, target):
    """Stock movements are append-only history — deletion is never allowed."""
    from sqlalchemy.exc import IntegrityError

    raise IntegrityError(
        "Cannot delete a stock-ledger movement. "
        "Create a reversal movement instead.",
        params={},
        orig=None,
    )


@event.listens_for(StockLedger, "before_insert")
def stamp_stock_ledger_attribution(mapper, connection, target):
    """Stamp actor + source channel from session-scoped server context.

    This is the single attribution mechanism for stock movements: the auth
    dependency (and the sync handler) attach the authenticated actor to the
    request's SQLAlchemy session via ``session.info["audit_context"]``, and
    sync/import/recurring flows stamp the channel via
    ``session.info["posting_channel"]``. Because it is a before_insert event
    every creation site is covered without trusting client-supplied values.
    """
    from sqlalchemy.orm import object_session
    # Single source of truth for channel normalization (Phase 0 posting_context).
    from src.core.posting_context import get_posting_channel

    session = object_session(target)
    if session is not None:
        if target.created_by is None:
            ctx = session.info.get("audit_context") or {}
            target.created_by = ctx.get("actor_id")
        if target.source_channel is None:
            target.source_channel = get_posting_channel(session)


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
        Index("ix_proforma_invoices_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "proforma_number", name="uq_proforma_invoices_proforma_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'ISSUED', 'CONVERTED', 'CANCELLED')",
            name="ck_proforma_invoices_status",
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
    # Deliberately not a second FK: SalesOrder.source_proforma_id is the
    # authoritative relationship and avoids a circular DDL dependency.
    converted_to_sales_order_id = Column(UUID(as_uuid=True))
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
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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
        UniqueConstraint("tenant_id", "adjustment_number", name="uq_inventory_adjustments_tenant_number"),
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
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    adjustment_id = Column("inventory_adjustment_id", UUID(as_uuid=True), ForeignKey("inventory_adjustments.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity_change = Column(Numeric(15, 4), nullable=False)  # Positive for increase, negative for decrease
    unit_cost = Column(Numeric(15, 4), nullable=False)
    total_cost = Column("total_change", Numeric(15, 4), nullable=False)
    reason = Column(String(255))

    adjustment = relationship("InventoryAdjustment", back_populates="lines")
    product = relationship("Product")

    @property
    def created_at(self):
        return self.adjustment.created_at

    @property
    def product_name(self):
        return self.product.name if self.product else None


# ---------------------------------------------------------------------------
# CREDIT NOTES & DEBIT NOTES
# ---------------------------------------------------------------------------

class CreditNote(Base):
    __tablename__ = "credit_notes"
    __table_args__ = (
        Index("ix_credit_notes_tenant_id", "tenant_id"),
        Index("ix_credit_notes_invoice_id", "invoice_id"),
        Index("ix_credit_notes_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "credit_note_number", name="uq_credit_notes_tenant_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'POSTED', 'ISSUED', 'CANCELLED')",
            name="ck_credit_notes_status",
        ),
        CheckConstraint(
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off, 2)",
            name="ck_credit_notes_total_balance",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=True)
    credit_note_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    reason = Column(String(255), nullable=False)
    restock_items = Column(Boolean, nullable=False, default=True)
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
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    # Relationships
    invoice = relationship("Invoice")
    lines = relationship("CreditNoteLine", back_populates="credit_note", cascade="all, delete-orphan")


class CreditNoteLine(Base):
    __tablename__ = "credit_note_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    credit_note_id = Column(UUID(as_uuid=True), ForeignKey("credit_notes.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity = Column(Numeric(15, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8))
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
        Index("ix_debit_notes_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "debit_note_number", name="uq_debit_notes_tenant_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'POSTED', 'ISSUED', 'CANCELLED')",
            name="ck_debit_notes_status",
        ),
        CheckConstraint(
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off, 2)",
            name="ck_debit_notes_total_balance",
        ),
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
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    # Relationships
    invoice = relationship("Invoice")
    lines = relationship("DebitNoteLine", back_populates="debit_note", cascade="all, delete-orphan")


class DebitNoteLine(Base):
    __tablename__ = "debit_note_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    debit_note_id = Column(UUID(as_uuid=True), ForeignKey("debit_notes.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    quantity = Column(Numeric(15, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8))
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
        CheckConstraint(
            "(payment_id IS NOT NULL AND bill_payment_id IS NULL) OR (payment_id IS NULL AND bill_payment_id IS NOT NULL)",
            name="ck_bank_reconciliations_single_payment",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
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


# ---------------------------------------------------------------------------
# ACCOUNTING PERIOD (period lock for closing books)
# ---------------------------------------------------------------------------

class AccountingPeriod(Base):
    __tablename__ = "accounting_periods"
    __table_args__ = (
        Index("ix_accounting_periods_tenant", "tenant_id"),
        UniqueConstraint("tenant_id", "period_name", name="uq_accounting_periods_tenant_name"),
        CheckConstraint(
            "is_closed IN (true, false)",
            name="ck_accounting_periods_is_closed",
        ),
        CheckConstraint("start_date <= end_date", name="ck_accounting_periods_date_range"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    period_name = Column(String(50), nullable=False)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    is_closed = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ---------------------------------------------------------------------------
# FINANCIAL YEAR (first-class FY management)
# ---------------------------------------------------------------------------

class FinancialYear(Base):
    __tablename__ = "financial_years"
    __table_args__ = (
        Index("ix_financial_years_tenant", "tenant_id"),
        UniqueConstraint("tenant_id", "name", name="uq_financial_years_tenant_name"),
        CheckConstraint(
            "status IN ('CURRENT', 'READY_TO_CLOSE', 'LOCKED', 'ARCHIVED')",
            name="ck_financial_years_status",
        ),
        CheckConstraint("start_date <= end_date", name="ck_financial_years_date_range"),
        Index(
            "uq_financial_years_one_current",
            "tenant_id",
            unique=True,
            postgresql_where=text("is_current"),
            sqlite_where=text("is_current = 1"),
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    name = Column(String(50), nullable=False)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="CURRENT")
    is_current = Column(Boolean, nullable=False, default=False)
    closed_at = Column(DateTime(timezone=True))
    closed_by = Column(UUID(as_uuid=True))
    reopened_at = Column(DateTime(timezone=True))
    reopened_by = Column(UUID(as_uuid=True))
    reopen_reason = Column(Text)
    journal_entry_id = Column(UUID(as_uuid=True))
    transaction_count = Column(Integer, nullable=False, default=0)
    created_by = Column(UUID(as_uuid=True))
    switched_by = Column(UUID(as_uuid=True))
    last_accessed_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


# ---------------------------------------------------------------------------
# FINANCIAL YEAR AUDIT TRAIL
# ---------------------------------------------------------------------------

class FinancialYearAudit(Base):
    __tablename__ = "financial_year_audits"
    __table_args__ = (
        Index("ix_fy_audits_tenant", "tenant_id"),
        Index("ix_fy_audits_fy", "financial_year_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    financial_year_id = Column(UUID(as_uuid=True), nullable=False)
    action = Column(String(50), nullable=False)
    detail = Column(Text)
    performed_by = Column(UUID(as_uuid=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)


# ---------------------------------------------------------------------------
# SALES RETURNS (standalone — customer returns goods without original invoice ref)
# ---------------------------------------------------------------------------

class SalesReturn(Base):
    __tablename__ = "sales_returns"
    __table_args__ = (
        Index("ix_sales_returns_tenant_date_status", "tenant_id", "issue_date", "status"),
        Index("ix_sales_returns_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_sales_returns_invoice", "tenant_id", "invoice_id"),
        Index("ix_sales_returns_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "return_number", name="uq_sales_returns_tenant_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'POSTED', 'CANCELLED')",
            name="ck_sales_returns_status",
        ),
        CheckConstraint(
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off, 2)",
            name="ck_sales_returns_total_balance",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=False)
    return_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    notes = Column(Text)
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    lines = relationship("SalesReturnLine", back_populates="sales_return", cascade="all, delete-orphan")


class SalesReturnLine(Base):
    __tablename__ = "sales_return_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    sales_return_id = Column(UUID(as_uuid=True), ForeignKey("sales_returns.id"), nullable=False)
    invoice_line_id = Column(UUID(as_uuid=True), ForeignKey("invoice_lines.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8))
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

    sales_return = relationship("SalesReturn", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# PURCHASE RETURNS (standalone — we return goods to vendor without original bill ref)
# ---------------------------------------------------------------------------

class PurchaseReturn(Base):
    __tablename__ = "purchase_returns"
    __table_args__ = (
        Index("ix_purchase_returns_tenant_date_status", "tenant_id", "issue_date", "status"),
        Index("ix_purchase_returns_tenant_contact", "tenant_id", "contact_id"),
        Index("ix_purchase_returns_bill", "tenant_id", "bill_id"),
        Index("ix_purchase_returns_tenant_deleted", "tenant_id", "deleted_at"),
        UniqueConstraint("tenant_id", "return_number", name="uq_purchase_returns_tenant_number"),
        CheckConstraint(
            "status IN ('DRAFT', 'POSTED', 'CANCELLED')",
            name="ck_purchase_returns_status",
        ),
        CheckConstraint(
            "round(total, 2) = round(subtotal + cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount + round_off, 2)",
            name="ck_purchase_returns_total_balance",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=True)
    bill_id = Column(UUID(as_uuid=True), ForeignKey("bills.id"), nullable=False)
    return_number = Column(String(50), nullable=False)
    issue_date = Column(Date, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    subtotal = Column(Numeric(15, 4), nullable=False, default=0)
    cgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    sgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    igst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    utgst_amount = Column(Numeric(15, 4), nullable=False, default=0)
    cess_amount = Column(Numeric(15, 4), nullable=False, default=0)
    round_off = Column(Numeric(15, 4), nullable=False, default=0)
    total = Column(Numeric(15, 4), nullable=False, default=0)
    pos_state_code = Column(String(2), nullable=False)
    notes = Column(Text)
    cancelled_at = Column(DateTime(timezone=True))
    cancelled_by = Column(UUID(as_uuid=True))
    created_by = Column(UUID(as_uuid=True), nullable=True)
    replaces_id = Column(UUID(as_uuid=True), nullable=True)
    replaced_by_id = Column(UUID(as_uuid=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    lines = relationship("PurchaseReturnLine", back_populates="purchase_return", cascade="all, delete-orphan")


class PurchaseReturnLine(Base):
    __tablename__ = "purchase_return_lines"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    purchase_return_id = Column(UUID(as_uuid=True), ForeignKey("purchase_returns.id"), nullable=False)
    bill_line_id = Column(UUID(as_uuid=True), ForeignKey("bill_lines.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    subtotal = Column(Numeric(15, 4), nullable=False)
    hsn_sac = Column(String(8))
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

    purchase_return = relationship("PurchaseReturn", back_populates="lines")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# OPENING BALANCE SNAPSHOTS — audit trail for FY roll-forward
# ---------------------------------------------------------------------------

class OpeningBalanceSnapshot(Base):
    """Point-in-time snapshot of every permanent account's balance at FY close.
    Created during roll-forward so we have a full audit trail of what was carried forward."""
    __tablename__ = "opening_balance_snapshots"
    __table_args__ = (
        Index("ix_ob_snapshots_tenant_fy", "tenant_id", "financial_year_id"),
        Index("ix_ob_snapshots_account", "account_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    financial_year_id = Column(UUID(as_uuid=True), nullable=False)
    account_id = Column(UUID(as_uuid=True), ForeignKey("accounts.id"), nullable=False)
    account_type = Column(String(50), nullable=False)
    account_name = Column(String(150), nullable=False)
    account_code = Column(String(50), nullable=False)
    closing_balance = Column(Numeric(15, 4), nullable=False, default=0)
    direction = Column(String(6), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    account = relationship("Account")


# ---------------------------------------------------------------------------
# INVENTORY CARRY FORWARD — audit trail for stock roll-forward
# ---------------------------------------------------------------------------

class InventoryCarryForward(Base):
    """Snapshot of every product's stock at FY close.
    Created during roll-forward so we have a full audit trail of what was carried forward."""
    __tablename__ = "inventory_carry_forwards"
    __table_args__ = (
        Index("ix_icf_tenant_fy", "tenant_id", "financial_year_id"),
        Index("ix_icf_product", "product_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    financial_year_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"), nullable=False)
    product_name = Column(String(150), nullable=False)
    product_sku = Column(String(50))
    closing_quantity = Column(Numeric(12, 2), nullable=False, default=0)
    closing_value = Column(Numeric(15, 4), nullable=False, default=0)
    unit_rate = Column(Numeric(15, 4), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    product = relationship("Product")


# ---------------------------------------------------------------------------
# RECURRING INVOICES
# ---------------------------------------------------------------------------

class RecurringInvoice(Base):
    """Templates for auto-generating invoices on a schedule."""
    __tablename__ = "recurring_invoices"
    __table_args__ = (
        Index("ix_recurring_invoices_tenant_active", "tenant_id", "is_active"),
        Index("ix_recurring_invoices_next_date", "next_date"),
        CheckConstraint(
            "frequency IN ('WEEKLY', 'MONTHLY', 'QUARTERLY', 'YEARLY')",
            name="ck_recurring_invoices_frequency",
        ),
        CheckConstraint(
            "end_mode IN ('NEVER', 'ON_DATE', 'AFTER_N')",
            name="ck_recurring_invoices_end_mode",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"), nullable=False)
    source_invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=True)
    template_name = Column(String(150), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    frequency = Column(String(20), nullable=False, default="MONTHLY")
    interval_count = Column(Integer, nullable=False, default=1)
    next_date = Column(Date, nullable=False)
    end_mode = Column(String(20), nullable=False, default="NEVER")
    end_date = Column(Date)
    max_occurrences = Column(Integer)
    occurrences_created = Column(Integer, nullable=False, default=0)
    last_generated = Column(Date)
    currency = Column(String(10), nullable=False, default="INR")
    exchange_rate = Column(Numeric(15, 6), nullable=False, default=1)
    pos_state_code = Column(String(2), nullable=False)
    notes = Column(Text)
    terms_and_conditions = Column(Text)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))

    contact = relationship("Contact")
    source_invoice = relationship("Invoice")
    items = relationship("RecurringInvoiceItem", back_populates="recurring_invoice", cascade="all, delete-orphan")


class RecurringInvoiceItem(Base):
    """Line items for recurring invoice templates."""
    __tablename__ = "recurring_invoice_items"
    __table_args__ = (
        Index("ix_recurring_invoice_items_template_id", "recurring_invoice_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    recurring_invoice_id = Column(UUID(as_uuid=True), ForeignKey("recurring_invoices.id"), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("products.id"))
    description = Column(String(255))
    quantity = Column(Numeric(12, 4), nullable=False)
    rate = Column(Numeric(15, 4), nullable=False)
    discount = Column(Numeric(15, 4), nullable=False, default=0)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate = Column(Numeric(5, 2), nullable=False)

    recurring_invoice = relationship("RecurringInvoice", back_populates="items")
    product = relationship("Product")


# ---------------------------------------------------------------------------
# INTER-WAREHOUSE TRANSFERS
# ---------------------------------------------------------------------------

class Transfer(Base):
    __tablename__ = "transfers"
    __table_args__ = (
        UniqueConstraint("tenant_id", "transfer_number", name="uq_transfers_tenant_number"),
        Index("ix_transfers_tenant_date", "tenant_id", "transfer_date"),
        Index("ix_transfers_tenant_status", "tenant_id", "status"),
        Index("ix_transfers_tenant_deleted", "tenant_id", "deleted_at"),
        CheckConstraint(
            "status IN ('DRAFT', 'IN_TRANSIT', 'COMPLETED', 'CANCELLED')",
            name="ck_transfers_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    transfer_number = Column(String(50))
    transfer_date = Column(Date)
    from_warehouse_id = Column(UUID(as_uuid=True))
    from_warehouse_name = Column(String(200))
    to_warehouse_id = Column(UUID(as_uuid=True))
    to_warehouse_name = Column(String(200))
    status = Column(String(20), nullable=False, default="DRAFT")
    lines = Column(JSON, nullable=False, default=list)
    notes = Column(Text)
    completed_at = Column(DateTime(timezone=True))
    completed_by = Column(UUID(as_uuid=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)
    deleted_at = Column(DateTime(timezone=True))


# ---------------------------------------------------------------------------
# TERMS & CONDITIONS TEMPLATES
# ---------------------------------------------------------------------------

class TermsTemplate(Base):
    """Reusable terms & conditions templates for invoices."""
    __tablename__ = "terms_templates"
    __table_args__ = (
        Index("ix_terms_templates_tenant", "tenant_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey("tenants.id"), nullable=True)  # NULL = global preset
    name = Column(String(150), nullable=False)
    content = Column(Text, nullable=False)  # Rich HTML content
    is_preset = Column(Boolean, nullable=False, default=False)  # True for India-specific presets
    is_active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)

    tenant = relationship("Tenant")


# ---------------------------------------------------------------------------
# SYNC EVENTS — ApexBooks offline-first event-sourced sync
# ---------------------------------------------------------------------------

class SyncEvent(Base):
    """Durable event store for ApexBooks offline-first sync.

    Each row represents one domain event pushed by an ApexBooks client or
    published by the server.  The (tenant_id, event_id) unique constraint
    makes push idempotent; server_sequence provides an ordered pull cursor.
    """
    __tablename__ = "sync_events"
    __table_args__ = (
        UniqueConstraint("tenant_id", "event_id", name="uq_sync_event_tenant_event"),
        Index("ix_sync_pull", "tenant_id", "server_sequence"),
        Index("ix_sync_tenant_processed", "tenant_id", "processed"),
        Index("ix_sync_tenant_event_type", "tenant_id", "event_type"),
    )

    server_sequence: int = Column(
        BigInteger().with_variant(Integer, "sqlite"),
        primary_key=True,
        autoincrement=True,
    )
    event_id: uuid.UUID = Column(Uuid(), nullable=False)
    tenant_id: uuid.UUID = Column(Uuid(), nullable=False, index=True)
    company_id: uuid.UUID = Column(Uuid(), nullable=False)
    device_id: uuid.UUID = Column(Uuid(), nullable=False)
    aggregate_type: str = Column(String(60), nullable=False)
    aggregate_id: uuid.UUID = Column(Uuid(), nullable=False)
    event_type: str = Column(String(100), nullable=False)
    event_version: int = Column(Integer, nullable=False)
    payload: dict = Column(JSON, nullable=False)
    occurred_at: datetime = Column(DateTime(timezone=True), nullable=False)
    received_at: datetime = Column(
        DateTime(timezone=True), nullable=False, server_default=text("CURRENT_TIMESTAMP")
    )
    processed: bool = Column(Boolean, nullable=False, default=False)
    processing_error: str | None = Column(Text, nullable=True)


# ---------------------------------------------------------------------------
# Tenant propagation for child / detail tables
# ---------------------------------------------------------------------------
# Child tables carry their own tenant_id so PostgreSQL RLS protects them
# directly (a foreign key to a tenant-owned parent provides NO RLS protection).
# Before flush, any child row whose tenant_id is unset inherits it from its
# parent.  The database trigger (see postgres_hardening.py) independently
# rejects any row whose tenant_id does not match its parent's, so the ORM
# listener is a convenience, not the enforcement boundary.

_CHILD_PARENT_MAP = {
    InvoiceLine: ("invoice_id", Invoice),
    BillLine: ("bill_id", Bill),
    JournalLine: ("entry_id", JournalEntry),
    PurchaseOrderLine: ("purchase_order_id", PurchaseOrder),
    GoodsReceiptLine: ("goods_receipt_id", GoodsReceipt),
    SalesOrderLine: ("sales_order_id", SalesOrder),
    DeliveryChallanLine: ("delivery_challan_id", DeliveryChallan),
    ProformaInvoiceLine: ("proforma_invoice_id", ProformaInvoice),
    InventoryAdjustmentLine: ("adjustment_id", InventoryAdjustment),
    CreditNoteLine: ("credit_note_id", CreditNote),
    DebitNoteLine: ("debit_note_id", DebitNote),
    SalesReturnLine: ("sales_return_id", SalesReturn),
    PurchaseReturnLine: ("purchase_return_id", PurchaseReturn),
    RecurringInvoiceItem: ("recurring_invoice_id", RecurringInvoice),
    # Payment allocations are tenant-owned join rows: the propagation listener
    # inherits the tenant from the payment, and the database trigger enforces
    # that the allocation's tenant matches BOTH the payment and the
    # invoice/bill it allocates against (see postgres_hardening.py).
    PaymentAllocation: ("payment_id", Payment),
    BillPaymentAllocation: ("payment_id", BillPayment),
}


@event.listens_for(Session, "before_flush")
def _propagate_parent_tenant_to_children(session, flush_context, instances):
    for obj in session.new:
        entry = _CHILD_PARENT_MAP.get(type(obj))
        if entry is None:
            continue
        if getattr(obj, "tenant_id", None) is not None:
            continue
        fk_attr, parent_cls = entry
        parent_id = getattr(obj, fk_attr, None)
        parent = None
        if parent_id is not None:
            parent = session.get(parent_cls, parent_id)
        if parent is None:
            # The parent may be a pending object linked through a relationship
            # whose FK column is only assigned later during flush.
            for rel in inspect(obj).mapper.relationships:
                if rel.mapper.class_ is parent_cls:
                    parent = getattr(obj, rel.key, None)
                    break
            if parent is None and parent_id is not None:
                # Or the parent may be another pending object in this same
                # flush whose PK was assigned before the child was built.
                # `session.get()` cannot see pending objects, so scan
                # session.new directly.
                pk_attr = parent_cls.__mapper__.primary_key[0].name
                for candidate in session.new:
                    if isinstance(candidate, parent_cls):
                        candidate_pk = getattr(candidate, pk_attr, None)
                        if candidate_pk is not None and str(candidate_pk) == str(parent_id):
                            parent = candidate
                            break
        if parent is not None and getattr(parent, "tenant_id", None) is not None:
            obj.tenant_id = parent.tenant_id
