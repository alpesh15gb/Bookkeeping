from pydantic import BaseModel, Field, EmailStr
from typing import Optional, Dict, Any, List
import uuid
from datetime import datetime
from decimal import Decimal
from src.schemas.company_schemas import AddressSchema, SchemaBase

class ContactCreate(BaseModel):
    name: str = Field(..., max_length=150)
    email: Optional[EmailStr] = None
    phone: Optional[str] = Field(None, max_length=20)
    contact_type: str = Field(..., pattern="^(CUSTOMER|VENDOR|BOTH)$")
    gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    pan: Optional[str] = Field(None, pattern="^[A-Z]{5}[0-9]{4}[A-Z]{1}$")
    registration_type: str = Field("CONSUMER", pattern="^(REGULAR|COMPOSITION|SEZ|UNREGISTERED|CONSUMER)$")
    billing_address: AddressSchema
    shipping_address: Optional[AddressSchema] = None
    state_code: str = Field(..., min_length=2, max_length=2, pattern="^[0-9]{2}$")

class ContactUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=150)
    email: Optional[EmailStr] = None
    phone: Optional[str] = Field(None, max_length=20)
    contact_type: Optional[str] = Field(None, pattern="^(CUSTOMER|VENDOR|BOTH)$")
    gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    pan: Optional[str] = Field(None, pattern="^[A-Z]{5}[0-9]{4}[A-Z]{1}$")
    registration_type: Optional[str] = Field(None, pattern="^(REGULAR|COMPOSITION|SEZ|UNREGISTERED|CONSUMER)$")
    billing_address: Optional[AddressSchema] = None
    shipping_address: Optional[AddressSchema] = None
    state_code: Optional[str] = Field(None, min_length=2, max_length=2, pattern="^[0-9]{2}$")
    is_active: Optional[bool] = None

class ContactResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    email: Optional[str]
    phone: Optional[str]
    contact_type: str
    gstin: Optional[str]
    pan: Optional[str]
    registration_type: str
    billing_address: Dict[str, Any]
    shipping_address: Optional[Dict[str, Any]]
    state_code: str
    is_active: bool
    created_at: datetime
    updated_at: datetime

class ProductCreate(BaseModel):
    name: str = Field(..., max_length=150)
    sku: Optional[str] = Field(None, max_length=50)
    hsn_sac: str = Field(..., min_length=6, max_length=8, pattern="^[0-9]{6,8}$")
    product_type: str = Field(..., pattern="^(GOODS|SERVICE)$")
    uom: str = Field(..., max_length=10)
    sales_price: Decimal = Field(Decimal("0.00"), ge=Decimal("0.00"))
    purchase_price: Decimal = Field(Decimal("0.00"), ge=Decimal("0.00"))
    gst_rate: Decimal = Field(Decimal("0.00"), ge=Decimal("0.00"), le=Decimal("100.00"))
    opening_stock: Decimal = Field(Decimal("0.00"), ge=Decimal("0.00"))
    reorder_level: Decimal = Field(Decimal("0.00"), ge=Decimal("0.00"))

class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=150)
    sku: Optional[str] = Field(None, max_length=50)
    hsn_sac: Optional[str] = Field(None, min_length=6, max_length=8, pattern="^[0-9]{6,8}$")
    product_type: Optional[str] = Field(None, pattern="^(GOODS|SERVICE)$")
    uom: Optional[str] = Field(None, max_length=10)
    sales_price: Optional[Decimal] = Field(None, ge=Decimal("0.00"))
    purchase_price: Optional[Decimal] = Field(None, ge=Decimal("0.00"))
    gst_rate: Optional[Decimal] = Field(None, ge=Decimal("0.00"), le=Decimal("100.00"))
    opening_stock: Optional[Decimal] = Field(None, ge=Decimal("0.00"))
    reorder_level: Optional[Decimal] = Field(None, ge=Decimal("0.00"))
    is_active: Optional[bool] = None

class ProductResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    sku: Optional[str]
    hsn_sac: str
    product_type: str
    uom: str
    sales_price: Decimal
    purchase_price: Decimal
    gst_rate: Decimal
    opening_stock: Decimal
    current_stock: Decimal
    reorder_level: Decimal
    is_active: bool
    created_at: datetime
    updated_at: datetime

class AccountCreate(BaseModel):
    name: str = Field(..., max_length=150)
    code: str = Field(..., max_length=50)
    account_type: str = Field(..., pattern="^(ASSET|LIABILITY|EQUITY|REVENUE|EXPENSE)$")
    parent_id: Optional[uuid.UUID] = None
    opening_balance: Decimal = Field(Decimal("0.00"))

class AccountUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=150)
    code: Optional[str] = Field(None, max_length=50)
    parent_id: Optional[uuid.UUID] = None
    opening_balance: Optional[Decimal] = None
    is_active: Optional[bool] = None

class AccountResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    code: str
    account_type: str
    parent_id: Optional[uuid.UUID]
    opening_balance: Decimal
    current_balance: Decimal
    is_active: bool
    created_at: datetime
    updated_at: datetime

class BankingProfileCreate(BaseModel):
    bank_name: str = Field(..., max_length=150)
    account_number: str = Field(..., max_length=50)
    ifsc_code: str = Field(..., min_length=11, max_length=11, pattern="^[A-Z]{4}[0-9][A-Z0-9]{6}$")
    branch_name: Optional[str] = Field(None, max_length=150)
    account_holder_name: str = Field(..., max_length=150)
    upi_id: Optional[str] = Field(None, max_length=100)
    is_primary: bool = False

class BankingProfileUpdate(BaseModel):
    bank_name: Optional[str] = Field(None, max_length=150)
    account_number: Optional[str] = Field(None, max_length=50)
    ifsc_code: Optional[str] = Field(None, min_length=11, max_length=11, pattern="^[A-Z]{4}[0-9][A-Z0-9]{6}$")
    branch_name: Optional[str] = Field(None, max_length=150)
    account_holder_name: Optional[str] = Field(None, max_length=150)
    upi_id: Optional[str] = Field(None, max_length=100)
    is_primary: Optional[bool] = None
    is_active: Optional[bool] = None

class BankingProfileResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    bank_name: str
    account_number: str
    ifsc_code: str
    branch_name: Optional[str]
    account_holder_name: str
    upi_id: Optional[str]
    is_primary: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime

class ExpenseCategoryCreate(BaseModel):
    name: str = Field(..., max_length=150)
    description: Optional[str] = None
    linked_account_id: Optional[uuid.UUID] = None

class ExpenseCategoryUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=150)
    description: Optional[str] = None
    linked_account_id: Optional[uuid.UUID] = None
    is_active: Optional[bool] = None

class ExpenseCategoryResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    description: Optional[str]
    linked_account_id: Optional[uuid.UUID]
    is_active: bool
    created_at: datetime
    updated_at: datetime

class TaxTemplateResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: Optional[uuid.UUID]
    name: str
    rate: Decimal
    is_active: bool

class PaymentTermResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: Optional[uuid.UUID]
    name: str
    due_days: int
    is_active: bool
