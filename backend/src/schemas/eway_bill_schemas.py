from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import date, datetime
import uuid
from src.schemas import SchemaBase

class EWayBillCreate(SchemaBase):
    invoice_id: Optional[uuid.UUID] = None
    bill_id: Optional[uuid.UUID] = None
    supply_type: str = Field("OUTWARD", pattern="^(OUTWARD|INWARD)$")
    sub_supply_type: str = Field("SUPPLY", pattern="^(SUPPLY|IMPORT|EXPORT|JOB_WORK|SEZ|LINE_SALES|OTHER)$")
    transporter_id: Optional[str] = Field(None, pattern="^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$")
    transporter_name: Optional[str] = Field(None, max_length=150)
    trans_doc_number: Optional[str] = Field(None, max_length=50)
    trans_doc_date: Optional[date] = None
    trans_distance: int = Field(..., ge=1, le=4000)
    trans_mode: str = Field("ROAD", pattern="^(ROAD|RAIL|AIR|SHIP)$")
    vehicle_number: str = Field(..., pattern="^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$")
    vehicle_type: str = Field("REGULAR", pattern="^(REGULAR|ODC)$")

class EWayBillVehicleUpdate(SchemaBase):
    vehicle_number: str = Field(..., pattern="^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$")
    vehicle_type: str = Field("REGULAR", pattern="^(REGULAR|ODC)$")
    from_place: str = Field(..., max_length=50)
    from_state_code: str = Field(..., pattern="^[0-9]{2}$")
    reason_code: str = Field(..., pattern="^(1|2|3|4)$")  # "1" - Transporter change, "2" - Breakdown, "3" - Transhipment, "4" - Other
    reason_remarks: Optional[str] = Field(None, max_length=100)

class EWayBillCancelRequest(SchemaBase):
    cancel_reason: str = Field(..., pattern="^(1|2|3|4)$")  # "1" - Duplicate, "2" - Order Cancelled, "3" - Active EWB exists, "4" - Other
    cancel_remarks: Optional[str] = Field(None, max_length=100)

class ConsolidatedEWayBillCreate(SchemaBase):
    vehicle_number: str = Field(..., pattern="^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$")
    vehicle_type: str = Field("REGULAR", pattern="^(REGULAR|ODC)$")
    from_place: str = Field(..., max_length=50)
    from_state_code: str = Field(..., pattern="^[0-9]{2}$")
    eway_bill_numbers: List[str] = Field(..., min_items=1)

class EWayBillResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    invoice_id: Optional[uuid.UUID]
    bill_id: Optional[uuid.UUID]
    eway_bill_number: Optional[str]
    status: str
    supply_type: str
    sub_supply_type: str
    transporter_id: Optional[str]
    transporter_name: Optional[str]
    trans_doc_number: Optional[str]
    trans_doc_date: Optional[date]
    trans_distance: int
    trans_mode: str
    vehicle_number: str
    vehicle_type: str
    valid_until: Optional[datetime]
    vehicle_history: List[dict]
    created_at: datetime
    updated_at: datetime

class ConsolidatedEWayBillResponse(SchemaBase):
    consolidated_eway_bill_number: str
    consolidated_date: datetime
    vehicle_number: str
    status: str
    eway_bills: List[str]
