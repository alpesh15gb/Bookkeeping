from pydantic import BaseModel, Field
from typing import Optional, List
import uuid
from datetime import date, datetime
from decimal import Decimal

class SchemaBase(BaseModel):
    class Config:
        from_attributes = True

class ExpenseCreate(SchemaBase):
    expense_category_id: uuid.UUID
    expense_date: date
    vendor_name: Optional[str] = Field(None, max_length=150)
    description: Optional[str] = None
    amount: Decimal = Field(..., gt=Decimal("0.00"))

class ExpenseUpdate(SchemaBase):
    expense_category_id: Optional[uuid.UUID] = None
    expense_date: Optional[date] = None
    vendor_name: Optional[str] = Field(None, max_length=150)
    description: Optional[str] = None
    amount: Optional[Decimal] = Field(None, gt=Decimal("0.00"))

class ExpenseResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    expense_number: str
    expense_category_id: uuid.UUID
    expense_date: date
    vendor_name: Optional[str]
    description: Optional[str]
    amount: Decimal
    total: Decimal
    status: str
    category_name: Optional[str] = None
    created_at: datetime
    updated_at: datetime

class ExpenseListResponse(SchemaBase):
    id: uuid.UUID
    expense_number: str
    expense_date: date
    vendor_name: Optional[str]
    description: Optional[str]
    amount: Decimal
    total: Decimal
    status: str
    category_name: Optional[str] = None
    created_at: datetime
