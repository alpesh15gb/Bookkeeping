from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid
from src.schemas import SchemaBase

class EInvoiceResponse(SchemaBase):
    invoice_id: uuid.UUID
    irn: str
    qr_code: str
    e_invoice_status: str
    ack_number: str
    ack_date: datetime

class EInvoiceCancelRequest(SchemaBase):
    cancel_reason: str = Field(..., pattern="^(1|2|3|4)$")  # "1" - Duplicate, "2" - Data entry mistake, "3" - Order cancelled, "4" - Other
    cancel_remarks: Optional[str] = Field(None, max_length=100)

class EInvoiceCancelResponse(SchemaBase):
    invoice_id: uuid.UUID
    e_invoice_status: str
    cancel_date: datetime
