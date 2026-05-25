from pydantic import BaseModel, Field, computed_field
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid

class SchemaBase(BaseModel):
    class Config:
        from_attributes = True

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
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    allocations: List[PaymentAllocationCreate] = []

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
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None
    allocations: List[PaymentAllocationResponse]

    @computed_field
    def status(self) -> str:
        return "CANCELLED" if self.deleted_at is not None else "ACTIVE"

class PaymentListResponse(SchemaBase):
    id: uuid.UUID
    payment_number: str
    payment_date: date
    payment_mode: str
    amount: Decimal
    contact_name: str
    status: str
    created_at: datetime

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
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    allocations: List[BillPaymentAllocationCreate] = []

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
    created_at: datetime
    updated_at: datetime
    deleted_at: Optional[datetime] = None
    allocations: List[BillPaymentAllocationResponse]

    @computed_field
    def status(self) -> str:
        return "CANCELLED" if self.deleted_at is not None else "ACTIVE"

class BillPaymentListResponse(SchemaBase):
    id: uuid.UUID
    payment_number: str
    payment_date: date
    payment_mode: str
    amount: Decimal
    contact_name: str
    status: str
    created_at: datetime

