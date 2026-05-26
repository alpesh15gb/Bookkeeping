from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, Dict, Any
import uuid
from decimal import Decimal
from datetime import datetime, date


def _decimal_to_float(obj):
    """Recursively convert Decimal to float in nested structures."""
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, dict):
        return {k: _decimal_to_float(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_decimal_to_float(v) for v in obj]
    return obj


class SchemaBase(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    def model_dump(self, *, mode: str = "python", **kwargs):
        # Always dump in python mode to preserve Decimal as Decimal objects
        result = super().model_dump(mode="python", **kwargs)
        if mode == "json":
            return _decimal_to_float(result)
        return result

class AddressSchema(BaseModel):
    street: str = Field(..., max_length=255)
    city: str = Field(..., max_length=100)
    state: str = Field(..., max_length=100)
    state_code: str = Field(..., min_length=2, max_length=2, pattern="^[0-9]{2}$")
    pincode: str = Field(..., min_length=6, max_length=6, pattern="^[0-9]{6}$")
    country: str = Field("India", max_length=100)

class CompanyCreate(BaseModel):
    legal_name: str = Field(..., max_length=150)
    trade_name: Optional[str] = Field(None, max_length=150)
    gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    pan: Optional[str] = Field(None, pattern="^[A-Z]{5}[0-9]{4}[A-Z]{1}$")
    financial_year_start: Optional[date] = None

class CompanyResponse(SchemaBase):
    id: uuid.UUID
    legal_name: str
    trade_name: Optional[str]
    gstin: Optional[str]
    pan: Optional[str]
    financial_year_start: Optional[date]
    created_at: datetime
    updated_at: datetime

class BranchCreate(BaseModel):
    name: str = Field(..., max_length=150)
    gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    address: AddressSchema

class BranchUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=150)
    gstin: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    address: Optional[AddressSchema] = None
    is_active: Optional[bool] = None

class BranchResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    name: str
    gstin: Optional[str]
    address: Dict[str, Any]
    is_active: bool
    created_at: datetime
    updated_at: datetime

class TenantSettingUpdate(BaseModel):
    logo_url: Optional[str] = Field(None, max_length=255)
    currency: Optional[str] = Field(None, max_length=10)
    gst_enabled: Optional[bool] = None
    e_invoicing_enabled: Optional[bool] = None
    e_invoice_username: Optional[str] = Field(None, max_length=100)
    e_invoice_password: Optional[str] = Field(None, max_length=100)
    e_way_bill_username: Optional[str] = Field(None, max_length=100)
    e_way_bill_password: Optional[str] = Field(None, max_length=100)
    origin_state_code: Optional[str] = Field(None, min_length=2, max_length=2, pattern="^[0-9]{2}$")
    extra_settings: Optional[Dict[str, Any]] = None

class TenantSettingResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    logo_url: Optional[str]
    currency: str
    gst_enabled: bool
    e_invoicing_enabled: bool
    e_invoice_username: Optional[str]
    e_way_bill_username: Optional[str]
    origin_state_code: Optional[str]
    extra_settings: Dict[str, Any]
    created_at: datetime
    updated_at: datetime

class NumberingSeriesCreate(BaseModel):
    document_type: str = Field(
        ...,
        max_length=50,
        pattern="^(INVOICE|BILL|PAYMENT|JOURNAL|RECEIPT|DISBURSEMENT|CREDIT_NOTE|DEBIT_NOTE|PURCHASE_ORDER|SALES_ORDER|DELIVERY_CHALLAN|PROFORMA_INVOICE)$"
    )
    prefix: str = Field(..., max_length=50)
    next_number: int = Field(1, ge=1)
    suffix: Optional[str] = Field(None, max_length=50)
    padding_digits: int = Field(4, ge=1, le=10)

class NumberingSeriesUpdate(BaseModel):
    prefix: Optional[str] = Field(None, max_length=50)
    next_number: Optional[int] = Field(None, ge=1)
    suffix: Optional[str] = Field(None, max_length=50)
    padding_digits: Optional[int] = Field(None, ge=1, le=10)
    is_active: Optional[bool] = None

class NumberingSeriesResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    document_type: str
    prefix: str
    next_number: int
    suffix: Optional[str]
    padding_digits: int
    is_active: bool
    created_at: datetime
    updated_at: datetime
