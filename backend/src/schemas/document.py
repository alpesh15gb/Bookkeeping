from pydantic import BaseModel, Field, EmailStr, model_validator
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid
from src.schemas import SchemaBase

# Contact Schemas
class ContactBase(SchemaBase):
    name: str = Field(..., max_length=150)
    email: Optional[EmailStr] = None
    phone: Optional[str] = Field(None, max_length=20)
    contact_type: str = Field(..., pattern="^(CUSTOMER|VENDOR|BOTH)$")
    gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    pan: Optional[str] = Field(None, pattern="^[A-Z]{5}[0-9]{4}[A-Z]{1}$")
    registration_type: str = Field("CONSUMER", pattern="^(REGULAR|COMPOSITION|SEZ|UNREGISTERED|CONSUMER)$")
    billing_address: dict  # {street, city, state, state_code, pincode, country}
    shipping_address: Optional[dict] = None
    state_code: str = Field(..., pattern="^[0-9]{2}$")

class ContactCreate(ContactBase):
    pass

class ContactResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    contact_type: str
    gstin: Optional[str] = None
    pan: Optional[str] = None
    registration_type: str
    billing_address: dict
    shipping_address: Optional[dict] = None
    state_code: str
    is_active: bool
    created_at: datetime

# Product Schemas
class ProductBase(SchemaBase):
    name: str = Field(..., max_length=150)
    sku: Optional[str] = Field(None, max_length=50)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    product_type: str = Field(..., pattern="^(GOODS|SERVICE)$")
    uom: str = Field(..., max_length=10)
    sales_price: Decimal = Field(default=Decimal("0.0000"), ge=0)
    purchase_price: Decimal = Field(default=Decimal("0.0000"), ge=0)
    gst_rate: Decimal = Field(default=Decimal("0.00"), ge=0, le=100)

class ProductCreate(ProductBase):
    pass

class ProductResponse(ProductBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    is_active: bool

# Invoice Line Schemas
class InvoiceLineBase(SchemaBase):
    product_id: uuid.UUID
    description: Optional[str] = None
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Decimal = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class InvoiceLineCreate(InvoiceLineBase):
    id: Optional[uuid.UUID] = None  # For updates: match by UUID instead of composite key

class InvoiceLineResponse(InvoiceLineBase):
    id: uuid.UUID
    product_name: Optional[str] = None
    subtotal: Decimal
    cgst_rate: Decimal
    cgst_amount: Decimal
    sgst_rate: Decimal
    sgst_amount: Decimal
    igst_rate: Decimal
    igst_amount: Decimal
    utgst_rate: Decimal
    utgst_amount: Decimal
    cess_rate: Decimal
    cess_amount: Decimal
    total: Decimal

# Invoice Header Schemas
class InvoiceBase(SchemaBase):
    contact_id: uuid.UUID
    invoice_number: Optional[str] = Field(None, max_length=50)
    issue_date: date
    due_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")
    billing_address: Optional[dict] = None
    shipping_address: Optional[dict] = None
    currency: Optional[str] = Field(default="INR", max_length=10)
    exchange_rate: Optional[Decimal] = Field(default=Decimal("1.000000"), ge=0)

    @model_validator(mode="after")
    def validate_dates(self):
        if self.due_date < self.issue_date:
            raise ValueError("Due date cannot be before invoice date")
        return self

class InvoiceCreate(InvoiceBase):
    line_items: List[InvoiceLineCreate] = Field(..., min_length=1)
    discount_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    reference_number: Optional[str] = Field(None, max_length=50)
    sales_person_id: Optional[uuid.UUID] = None
    is_gst_inclusive: Optional[bool] = False
    is_rcm: Optional[bool] = False
    supply_type: Optional[str] = Field(default="DOMESTIC", pattern="^(DOMESTIC|EXPORT_WITH_TAX|EXPORT_WITHOUT_TAX|SEZ_WITH_TAX|SEZ_WITHOUT_TAX)$")
    tds_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    tcs_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    post_on_create: bool = True

class InvoicePreviewRequest(SchemaBase):
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")
    line_items: List[InvoiceLineCreate]
    discount_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    is_gst_inclusive: Optional[bool] = False
    currency: Optional[str] = Field(default="INR", max_length=10)
    exchange_rate: Optional[Decimal] = Field(default=Decimal("1.000000"), ge=0)
    is_rcm: Optional[bool] = False
    supply_type: Optional[str] = Field(default="DOMESTIC", pattern="^(DOMESTIC|EXPORT_WITH_TAX|EXPORT_WITHOUT_TAX|SEZ_WITH_TAX|SEZ_WITHOUT_TAX)$")
    tds_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    tcs_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)

class InvoiceUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    invoice_number: Optional[str] = None
    issue_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[InvoiceLineCreate]] = None
    discount_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=None, ge=0)
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    reference_number: Optional[str] = None
    sales_person_id: Optional[uuid.UUID] = None
    is_gst_inclusive: Optional[bool] = None
    is_rcm: Optional[bool] = None
    supply_type: Optional[str] = Field(
        default=None,
        pattern="^(DOMESTIC|EXPORT_WITH_TAX|EXPORT_WITHOUT_TAX|SEZ_WITH_TAX|SEZ_WITHOUT_TAX)$",
    )
    tds_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)
    tcs_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)
    currency: Optional[str] = None
    exchange_rate: Optional[Decimal] = None
    tds_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)
    tcs_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)

class InvoiceResponse(InvoiceBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    status: str
    is_gst_inclusive: Optional[bool] = False
    is_rcm: Optional[bool] = False
    supply_type: Optional[str] = "DOMESTIC"
    currency: str = "INR"
    exchange_rate: Decimal = Decimal("1.000000")
    tds_rate: Decimal = Decimal("0.00")
    tds_amount: Decimal = Decimal("0.0000")
    tcs_rate: Decimal = Decimal("0.00")
    tcs_amount: Decimal = Decimal("0.0000")
    subtotal: Decimal
    discount_total: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    round_off: Decimal
    total: Decimal
    amount_paid: Decimal
    irn: Optional[str] = None
    qr_code: Optional[str] = None
    e_invoice_status: str
    e_invoice_error: Optional[str] = None
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    reference_number: Optional[str] = None
    sales_person_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime
    lines: List[InvoiceLineResponse]
    contact: Optional[ContactResponse] = None

class InvoiceListResponse(SchemaBase):
    id: uuid.UUID
    contact_id: uuid.UUID
    invoice_number: str
    issue_date: date
    due_date: date
    status: str
    is_gst_inclusive: Optional[bool] = False
    is_rcm: Optional[bool] = False
    supply_type: Optional[str] = "DOMESTIC"
    currency: str = "INR"
    exchange_rate: Decimal = Decimal("1.000000")
    total: Decimal
    amount_paid: Decimal
    contact_name: str
    reference_number: Optional[str] = None
    created_at: datetime

class PaginatedInvoiceResponse(SchemaBase):
    items: List[InvoiceListResponse]
    total: int
    page: int
    limit: int

# CREDIT NOTE SCHEMAS
class CreditNoteLineCreate(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class CreditNoteLineResponse(SchemaBase):
    id: uuid.UUID
    product_id: uuid.UUID
    quantity: Decimal
    rate: Decimal
    subtotal: Decimal
    hsn_sac: str
    gst_rate: Decimal
    cgst_rate: Decimal
    cgst_amount: Decimal
    sgst_rate: Decimal
    sgst_amount: Decimal
    igst_rate: Decimal
    igst_amount: Decimal
    utgst_rate: Decimal
    utgst_amount: Decimal
    cess_rate: Decimal
    cess_amount: Decimal
    total: Decimal

class CreditNoteCreate(SchemaBase):
    invoice_id: Optional[uuid.UUID] = None
    credit_note_number: Optional[str] = Field(None, max_length=50)
    issue_date: date
    reason: str = Field(..., min_length=1, max_length=255)
    restock_items: bool = True
    line_items: List[CreditNoteLineCreate] = Field(..., min_length=1)

class CreditNoteResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    invoice_id: Optional[uuid.UUID]
    credit_note_number: str
    issue_date: date
    reason: Optional[str]
    restock_items: bool
    status: str
    subtotal: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    round_off: Decimal
    total: Decimal
    created_at: datetime
    updated_at: datetime
    lines: List[CreditNoteLineResponse]

class CreditNoteListResponse(SchemaBase):
    id: uuid.UUID
    credit_note_number: str
    issue_date: date
    status: str
    total: Decimal
    reason: Optional[str]
    created_at: datetime
    invoice_number: Optional[str] = None
    contact_name: Optional[str] = None

# DEBIT NOTE SCHEMAS
class DebitNoteLineCreate(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class DebitNoteLineResponse(SchemaBase):
    id: uuid.UUID
    product_id: uuid.UUID
    quantity: Decimal
    rate: Decimal
    subtotal: Decimal
    hsn_sac: str
    gst_rate: Decimal
    cgst_rate: Decimal
    cgst_amount: Decimal
    sgst_rate: Decimal
    sgst_amount: Decimal
    igst_rate: Decimal
    igst_amount: Decimal
    utgst_rate: Decimal
    utgst_amount: Decimal
    cess_rate: Decimal
    cess_amount: Decimal
    total: Decimal

class DebitNoteCreate(SchemaBase):
    invoice_id: Optional[uuid.UUID] = None
    contact_id: Optional[uuid.UUID] = None
    debit_note_number: Optional[str] = Field(None, max_length=50)
    issue_date: date
    reason: str = Field(..., min_length=1, max_length=255)
    line_items: List[DebitNoteLineCreate]

class DebitNoteResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    invoice_id: Optional[uuid.UUID]
    debit_note_number: str
    issue_date: date
    reason: Optional[str]
    status: str
    subtotal: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    round_off: Decimal
    total: Decimal
    created_at: datetime
    updated_at: datetime
    lines: List[DebitNoteLineResponse]

class DebitNoteListResponse(SchemaBase):
    id: uuid.UUID
    debit_note_number: str
    issue_date: date
    status: str
    total: Decimal
    reason: Optional[str]
    created_at: datetime

# Payment Recieve Schemas
class PaymentAllocationSchema(SchemaBase):
    invoice_id: uuid.UUID
    amount: Decimal = Field(..., gt=0)

class PaymentCreate(SchemaBase):
    contact_id: uuid.UUID
    payment_number: Optional[str] = Field(None, max_length=50)
    payment_date: date
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    allocations: List[PaymentAllocationSchema] = []

# ── SALES RETURN SCHEMAS ──
class SalesReturnLineCreate(SchemaBase):
    invoice_line_id: uuid.UUID
    product_id: uuid.UUID
    description: Optional[str] = None
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class SalesReturnLineResponse(SchemaBase):
    id: uuid.UUID
    product_id: uuid.UUID
    invoice_line_id: uuid.UUID
    product_name: Optional[str] = None
    description: Optional[str] = None
    quantity: Decimal
    rate: Decimal
    subtotal: Decimal
    hsn_sac: str
    gst_rate: Decimal
    cgst_rate: Decimal
    cgst_amount: Decimal
    sgst_rate: Decimal
    sgst_amount: Decimal
    igst_rate: Decimal
    igst_amount: Decimal
    utgst_rate: Decimal
    utgst_amount: Decimal
    cess_rate: Decimal
    cess_amount: Decimal
    total: Decimal

class SalesReturnCreate(SchemaBase):
    invoice_id: uuid.UUID
    contact_id: uuid.UUID
    issue_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")
    line_items: List[SalesReturnLineCreate]
    notes: Optional[str] = None

class SalesReturnResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    contact_id: uuid.UUID
    invoice_id: uuid.UUID
    return_number: str
    issue_date: date
    status: str
    subtotal: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    round_off: Decimal
    total: Decimal
    pos_state_code: str
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    lines: List[SalesReturnLineResponse]

class SalesReturnListResponse(SchemaBase):
    id: uuid.UUID
    return_number: str
    issue_date: date
    status: str
    total: Decimal
    contact_name: Optional[str] = None


# ── PURCHASE RETURN SCHEMAS ──
class PurchaseReturnLineCreate(SchemaBase):
    bill_line_id: uuid.UUID
    product_id: uuid.UUID
    description: Optional[str] = None
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class PurchaseReturnLineResponse(SchemaBase):
    id: uuid.UUID
    product_id: uuid.UUID
    bill_line_id: uuid.UUID
    product_name: Optional[str] = None
    description: Optional[str] = None
    quantity: Decimal
    rate: Decimal
    subtotal: Decimal
    hsn_sac: str
    gst_rate: Decimal
    cgst_rate: Decimal
    cgst_amount: Decimal
    sgst_rate: Decimal
    sgst_amount: Decimal
    igst_rate: Decimal
    igst_amount: Decimal
    utgst_rate: Decimal
    utgst_amount: Decimal
    cess_rate: Decimal
    cess_amount: Decimal
    total: Decimal

class PurchaseReturnCreate(SchemaBase):
    bill_id: uuid.UUID
    contact_id: uuid.UUID
    issue_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")
    line_items: List[PurchaseReturnLineCreate]
    notes: Optional[str] = None

class PurchaseReturnResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    contact_id: uuid.UUID
    bill_id: uuid.UUID
    return_number: str
    issue_date: date
    status: str
    subtotal: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    round_off: Decimal
    total: Decimal
    pos_state_code: str
    notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    lines: List[PurchaseReturnLineResponse]

class PurchaseReturnListResponse(SchemaBase):
    id: uuid.UUID
    return_number: str
    issue_date: date
    status: str
    total: Decimal
    contact_name: Optional[str] = None


# ── RECURRING INVOICE SCHEMAS ──
class RecurringInvoiceItemCreate(SchemaBase):
    product_id: uuid.UUID
    description: Optional[str] = None
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class RecurringInvoiceItemResponse(SchemaBase):
    id: uuid.UUID
    product_id: Optional[uuid.UUID] = None
    description: Optional[str] = None
    quantity: Decimal
    rate: Decimal
    discount: Decimal
    hsn_sac: str
    gst_rate: Decimal

class RecurringInvoiceCreate(SchemaBase):
    contact_id: uuid.UUID
    template_name: str = Field(..., min_length=1, max_length=150)
    frequency: str = Field(default="MONTHLY", pattern="^(WEEKLY|MONTHLY|QUARTERLY|YEARLY)$")
    interval_count: int = Field(default=1, ge=1, le=12)
    next_date: date
    end_mode: str = Field(default="NEVER", pattern="^(NEVER|ON_DATE|AFTER_N)$")
    end_date: Optional[date] = None
    max_occurrences: Optional[int] = Field(default=None, ge=1)
    currency: Optional[str] = Field(default="INR", max_length=10)
    exchange_rate: Optional[Decimal] = Field(default=Decimal("1.000000"), ge=0)
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    items: List[RecurringInvoiceItemCreate]

    @model_validator(mode="after")
    def validate_end_condition(self):
        if self.end_mode == "ON_DATE" and self.end_date is None:
            raise ValueError("end_date is required when end_mode is ON_DATE")
        if self.end_mode == "AFTER_N" and self.max_occurrences is None:
            raise ValueError("max_occurrences is required when end_mode is AFTER_N")
        return self

class RecurringInvoiceUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    template_name: Optional[str] = Field(None, min_length=1, max_length=150)
    is_active: Optional[bool] = None
    frequency: Optional[str] = Field(None, pattern="^(WEEKLY|MONTHLY|QUARTERLY|YEARLY)$")
    interval_count: Optional[int] = Field(None, ge=1, le=12)
    next_date: Optional[date] = None
    end_mode: Optional[str] = Field(None, pattern="^(NEVER|ON_DATE|AFTER_N)$")
    end_date: Optional[date] = None
    max_occurrences: Optional[int] = Field(None, ge=1)
    currency: Optional[str] = None
    exchange_rate: Optional[Decimal] = None
    pos_state_code: Optional[str] = None
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    items: Optional[List[RecurringInvoiceItemCreate]] = None

    @model_validator(mode="after")
    def validate_end_condition(self):
        if self.end_mode == "ON_DATE" and self.end_date is None:
            raise ValueError("end_date is required when end_mode is ON_DATE")
        if self.end_mode == "AFTER_N" and self.max_occurrences is None:
            raise ValueError("max_occurrences is required when end_mode is AFTER_N")
        return self

class RecurringInvoiceResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    contact_id: uuid.UUID
    template_name: str
    is_active: bool
    frequency: str
    interval_count: int
    next_date: date
    end_mode: str
    end_date: Optional[date]
    max_occurrences: Optional[int]
    occurrences_created: int
    last_generated: Optional[date]
    currency: str
    exchange_rate: Decimal
    pos_state_code: str
    notes: Optional[str]
    terms_and_conditions: Optional[str]
    created_at: datetime
    updated_at: datetime
    items: List[RecurringInvoiceItemResponse]
    contact: Optional[ContactResponse] = None

class RecurringInvoiceListResponse(SchemaBase):
    id: uuid.UUID
    contact_id: uuid.UUID
    template_name: str
    is_active: bool
    frequency: str
    next_date: date
    occurrences_created: int
    currency: str
    created_at: datetime
    contact_name: Optional[str] = None


# ── TERMS TEMPLATE SCHEMAS ──
class TermsTemplateCreate(SchemaBase):
    name: str = Field(..., min_length=1, max_length=150)
    content: str = Field(..., min_length=1)

class TermsTemplateUpdate(SchemaBase):
    name: Optional[str] = Field(None, min_length=1, max_length=150)
    content: Optional[str] = Field(None, min_length=1)
    is_active: Optional[bool] = None

class TermsTemplateResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: Optional[uuid.UUID]
    name: str
    content: str
    is_preset: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime
