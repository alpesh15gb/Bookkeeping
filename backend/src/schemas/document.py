from pydantic import BaseModel, Field, EmailStr
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid

# Base configurations
class SchemaBase(BaseModel):
    class Config:
        from_attributes = True

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

class ContactResponse(ContactBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
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

class InvoiceCreate(InvoiceBase):
    line_items: List[InvoiceLineCreate]
    discount_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)

class InvoiceUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    invoice_number: Optional[str] = None
    issue_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[InvoiceLineCreate]] = None
    discount_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=None, ge=0)

class InvoiceResponse(InvoiceBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    status: str
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
    created_at: datetime
    updated_at: datetime
    lines: List[InvoiceLineResponse]
    contact: ContactResponse

class InvoiceListResponse(SchemaBase):
    id: uuid.UUID
    invoice_number: str
    issue_date: date
    due_date: date
    status: str
    total: Decimal
    amount_paid: Decimal
    contact_name: str
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
    reason: Optional[str] = Field(None, max_length=255)
    line_items: List[CreditNoteLineCreate]

class CreditNoteResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    invoice_id: Optional[uuid.UUID]
    credit_note_number: str
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
    debit_note_number: Optional[str] = Field(None, max_length=50)
    issue_date: date
    reason: Optional[str] = Field(None, max_length=255)
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
    payment_number: str = Field(..., max_length=50)
    payment_date: date
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    allocations: List[PaymentAllocationSchema]
