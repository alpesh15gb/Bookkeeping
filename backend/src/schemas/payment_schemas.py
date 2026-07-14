from pydantic import BaseModel, Field, computed_field
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid
from src.schemas import SchemaBase

# Customer Receipt (Payment In) Allocations
class PaymentAllocationCreate(SchemaBase):
    invoice_id: uuid.UUID
    amount: Decimal = Field(..., gt=0)

class PaymentAllocationResponse(SchemaBase):
    id: uuid.UUID
    invoice_id: uuid.UUID
    amount: Decimal
    created_at: datetime

# Customer Receipt Create/Response
class PaymentCreate(SchemaBase):
    contact_id: uuid.UUID
    payment_number: Optional[str] = Field(None, max_length=50) # Auto-generated if omitted
    payment_date: date
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|CHEQUE|NEFT_RTGS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    advance_supply_type: Optional[str] = Field(None, pattern="^(GOODS|SERVICES)$")
    allocations: List[PaymentAllocationCreate] = Field(default_factory=list)

class PaymentResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    contact_id: uuid.UUID
    payment_number: str
    payment_date: date
    payment_mode: str
    amount: Decimal
    reference_number: Optional[str] = None
    description: Optional[str] = None
    advance_supply_type: Optional[str] = None
    status: str
    cancelled_at: Optional[datetime] = None
    cancellation_reason: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None
    allocations: List[PaymentAllocationResponse]

class PaymentListResponse(SchemaBase):
    id: uuid.UUID
    payment_number: str
    payment_date: date
    payment_mode: str
    amount: Decimal
    contact_name: str
    status: str
    created_at: datetime

class PaymentCancel(SchemaBase):
    reason: str = Field(..., min_length=3, max_length=500)
    cancellation_date: Optional[date] = None

class OutstandingInvoiceResponse(SchemaBase):
    id: uuid.UUID
    invoice_number: str
    issue_date: date
    due_date: date
    total: Decimal
    amount_paid: Decimal
    outstanding: Decimal
    contact_id: uuid.UUID
    contact_name: str
    status: str

# Vendor Payment (Payment Out / Disbursement) Allocations
class BillPaymentAllocationCreate(SchemaBase):
    bill_id: uuid.UUID
    amount: Decimal = Field(..., gt=0)

class BillPaymentAllocationResponse(SchemaBase):
    id: uuid.UUID
    bill_id: uuid.UUID
    amount: Decimal
    created_at: datetime

# Vendor Payment Create/Response
class BillPaymentCreate(SchemaBase):
    contact_id: uuid.UUID
    payment_number: Optional[str] = Field(None, max_length=50) # Auto-generated if omitted
    payment_date: date
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|CHEQUE|NEFT_RTGS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    allocations: List[BillPaymentAllocationCreate] = Field(default_factory=list)

class BillPaymentResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    contact_id: uuid.UUID
    payment_number: str
    payment_date: date
    payment_mode: str
    amount: Decimal
    reference_number: Optional[str] = None
    description: Optional[str] = None
    status: str
    cancelled_at: Optional[datetime] = None
    cancellation_reason: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None
    allocations: List[BillPaymentAllocationResponse]

class BillPaymentListResponse(SchemaBase):
    id: uuid.UUID
    payment_number: str
    payment_date: date
    payment_mode: str
    amount: Decimal
    contact_name: str
    status: str
    created_at: datetime

