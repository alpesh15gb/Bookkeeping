from pydantic import BaseModel
from typing import List, Optional
from datetime import date
from decimal import Decimal
import uuid
from src.schemas import SchemaBase

# GSTR-1 B2B (Registered Customer Sales)
class GSTR1B2BLine(SchemaBase):
    customer_name: str
    customer_gstin: str
    invoice_number: str
    invoice_date: date
    pos_state_code: str
    taxable_value: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    total_value: Decimal

# GSTR-1 B2C Large (Unregistered Inter-state Sales > 2.5L)
class GSTR1B2CLine(SchemaBase):
    invoice_number: str
    invoice_date: date
    pos_state_code: str
    taxable_value: Decimal
    igst_amount: Decimal
    total_value: Decimal

# GSTR-1 B2C Small (Unregistered Sales Summary)
class GSTR1B2CSLine(SchemaBase):
    pos_state_code: str
    gst_rate: Decimal
    taxable_value: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal

# GSTR-1 Credit / Debit Notes
class GSTR1NoteLine(SchemaBase):
    note_number: str
    note_date: date
    note_type: str  # 'CREDIT' or 'DEBIT'
    invoice_number: Optional[str] = None
    customer_gstin: Optional[str] = None
    reason: Optional[str] = None
    taxable_value: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    total_value: Decimal

# GSTR-1 HSN Summary
class GSTR1HSNLine(SchemaBase):
    hsn_sac: str
    description: str
    uom: str
    total_quantity: Decimal
    total_value: Decimal
    taxable_value: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal

# GSTR-1 Complete Report Response
class GSTR1Response(SchemaBase):
    b2b: List[GSTR1B2BLine]
    b2cl: List[GSTR1B2CLine]
    b2cs: List[GSTR1B2CSLine]
    cdnr: List[GSTR1NoteLine]
    cdnur: List[GSTR1NoteLine]
    hsn_summary: List[GSTR1HSNLine]


# GSTR-2 B2B Purchases (Vendor Bills Summary)
class GSTR2B2BLine(SchemaBase):
    vendor_name: str
    vendor_gstin: str
    bill_number: str
    bill_date: date
    pos_state_code: str
    taxable_value: Decimal
    cgst_amount: Decimal
    sgst_amount: Decimal
    igst_amount: Decimal
    utgst_amount: Decimal
    cess_amount: Decimal
    total_value: Decimal

# GSTR-2 Complete Report Response
class GSTR2Response(SchemaBase):
    b2b_purchases: List[GSTR2B2BLine]
