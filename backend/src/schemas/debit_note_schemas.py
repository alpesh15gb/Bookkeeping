"""
src/schemas/debit_note_schemas.py
Pydantic schemas for Debit Note API endpoints.
"""
from pydantic import BaseModel, Field
from typing import List, Optional
import uuid
from datetime import datetime, date
from decimal import Decimal


class SchemaBase(BaseModel):
    class Config:
        from_attributes = True


# ---------------------------------------------------------------------------
# Request schemas
# ---------------------------------------------------------------------------

class DebitNoteLineCreate(BaseModel):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    hsn_sac: Optional[str] = Field(None, max_length=20)
    gst_rate: Decimal = Field(..., ge=0)


class DebitNoteCreate(BaseModel):
    invoice_id: Optional[uuid.UUID] = None
    issue_date: date
    reason: str = Field(..., max_length=255)
    pos_state_code: str = Field(..., min_length=2, max_length=2, pattern="^[0-9]{2}$")
    line_items: List[DebitNoteLineCreate]


# ---------------------------------------------------------------------------
# Response schemas
# ---------------------------------------------------------------------------

class DebitNoteLineResponse(SchemaBase):
    id: uuid.UUID
    debit_note_id: uuid.UUID
    product_id: uuid.UUID
    quantity: Decimal
    rate: Decimal
    subtotal: Decimal
    hsn_sac: Optional[str]
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


class DebitNoteResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    invoice_id: Optional[uuid.UUID]
    debit_note_number: str
    issue_date: date
    reason: str
    status: str
    subtotal: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    round_off: Decimal
    pos_state_code: str
    total: Decimal
    lines: List[DebitNoteLineResponse]
    created_at: datetime
    updated_at: datetime


class DebitNoteListResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    invoice_id: Optional[uuid.UUID]
    debit_note_number: str
    issue_date: date
    reason: str
    status: str
    total: Decimal
    created_at: datetime
