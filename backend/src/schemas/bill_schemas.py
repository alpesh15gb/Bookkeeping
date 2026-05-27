from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid
from src.schemas.document import ContactResponse
from src.schemas.master_schemas import BankingProfileResponse
from src.schemas.payment_schemas import PaymentResponse, BillPaymentResponse

class SchemaBase(BaseModel):
    class Config:
        from_attributes = True

# Bill Line Items Schemas
class BillLineBase(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Decimal = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class BillLineCreate(BillLineBase):
    pass

class BillLineResponse(BillLineBase):
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

# Bill Header Schemas
class BillBase(SchemaBase):
    contact_id: uuid.UUID
    bill_number: str = Field(..., max_length=50)
    issue_date: date
    due_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")

class BillCreate(BillBase):
    line_items: List[BillLineCreate]
    discount_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)

class BillUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    bill_number: Optional[str] = None
    issue_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[BillLineCreate]] = None
    discount_rate: Optional[Decimal] = Field(default=None, ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=None, ge=0)

class BillResponse(BillBase):
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
    round_off: Decimal = Decimal("0.0000")
    total: Decimal
    amount_paid: Decimal
    created_at: datetime
    updated_at: datetime
    lines: List[BillLineResponse]
    contact: ContactResponse

class BillListResponse(SchemaBase):
    id: uuid.UUID
    bill_number: str
    issue_date: date
    due_date: date
    status: str
    total: Decimal
    amount_paid: Decimal
    contact_name: str
    created_at: datetime

# Bill Payments Schemas
class BillPaymentAllocationSchema(SchemaBase):
    bill_id: uuid.UUID
    amount: Decimal = Field(..., gt=0)

class BillPaymentCreate(SchemaBase):
    contact_id: uuid.UUID
    payment_number: str = Field(..., max_length=50)
    payment_date: date
    payment_mode: str = Field(..., pattern="^(CASH|BANK|UPI|POS|OTHER)$")
    amount: Decimal = Field(..., gt=0)
    reference_number: Optional[str] = None
    description: Optional[str] = None
    allocations: List[BillPaymentAllocationSchema]


# PURCHASE ORDER SCHEMAS
class PurchaseOrderLineBase(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Decimal = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class PurchaseOrderLineCreate(PurchaseOrderLineBase):
    pass

class PurchaseOrderLineResponse(PurchaseOrderLineBase):
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

# Purchase Order Header Schemas
class PurchaseOrderBase(SchemaBase):
    contact_id: uuid.UUID
    po_number: str = Field(..., max_length=50)
    order_date: date
    due_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")

class PurchaseOrderCreate(PurchaseOrderBase):
    line_items: List[PurchaseOrderLineCreate]

class PurchaseOrderUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    po_number: Optional[str] = None
    order_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[PurchaseOrderLineCreate]] = None

class PurchaseOrderResponse(PurchaseOrderBase):
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
    total: Decimal
    amount_received: Decimal
    created_at: datetime
    updated_at: datetime
    lines: List[PurchaseOrderLineResponse]
    contact: ContactResponse

class PurchaseOrderListResponse(SchemaBase):
    id: uuid.UUID
    po_number: str
    order_date: date
    due_date: date
    status: str
    total: Decimal
    amount_received: Decimal
    contact_name: str
    created_at: datetime


# SALES ORDER SCHEMAS
class SalesOrderLineBase(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Decimal = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class SalesOrderLineCreate(SalesOrderLineBase):
    pass

class SalesOrderLineResponse(SalesOrderLineBase):
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

# Sales Order Header Schemas
class SalesOrderBase(SchemaBase):
    contact_id: uuid.UUID
    so_number: str = Field(..., max_length=50)
    order_date: date
    due_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")

class SalesOrderCreate(SalesOrderBase):
    line_items: List[SalesOrderLineCreate]

class SalesOrderUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    so_number: Optional[str] = None
    order_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[SalesOrderLineCreate]] = None

class SalesOrderResponse(SalesOrderBase):
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
    total: Decimal
    amount_advanced: Decimal
    created_at: datetime
    updated_at: datetime
    lines: List[SalesOrderLineResponse]
    contact: ContactResponse

class SalesOrderListResponse(SchemaBase):
    id: uuid.UUID
    so_number: str
    order_date: date
    due_date: date
    status: str
    total: Decimal
    amount_advanced: Decimal
    contact_name: str
    created_at: datetime


# DELIVERY CHALLAN SCHEMAS
class DeliveryChallanLineBase(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Decimal = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class DeliveryChallanLineCreate(DeliveryChallanLineBase):
    pass

class DeliveryChallanLineResponse(DeliveryChallanLineBase):
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

# Delivery Challan Header Schemas
class DeliveryChallanBase(SchemaBase):
    contact_id: uuid.UUID
    challan_number: str = Field(..., max_length=50)
    challan_date: date
    due_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")

class DeliveryChallanCreate(DeliveryChallanBase):
    line_items: List[DeliveryChallanLineCreate]

class DeliveryChallanUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    challan_number: Optional[str] = None
    challan_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[DeliveryChallanLineCreate]] = None

class DeliveryChallanResponse(DeliveryChallanBase):
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
    total: Decimal
    created_at: datetime
    updated_at: datetime
    lines: List[DeliveryChallanLineResponse]
    contact: ContactResponse

class DeliveryChallanListResponse(SchemaBase):
    id: uuid.UUID
    challan_number: str
    challan_date: date
    due_date: date
    status: str
    total: Decimal
    contact_name: str
    created_at: datetime


# PROFORMA INVOICE SCHEMAS
class ProformaInvoiceLineBase(SchemaBase):
    product_id: uuid.UUID
    quantity: Decimal = Field(..., gt=0)
    rate: Decimal = Field(..., ge=0)
    discount: Decimal = Field(default=Decimal("0.0000"), ge=0)
    hsn_sac: str = Field(..., pattern="^[0-9]{4,8}$")
    gst_rate: Decimal = Field(..., ge=0, le=100)

class ProformaInvoiceLineCreate(ProformaInvoiceLineBase):
    pass

class ProformaInvoiceLineResponse(ProformaInvoiceLineBase):
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

# Proforma Invoice Header Schemas
class ProformaInvoiceBase(SchemaBase):
    contact_id: uuid.UUID
    proforma_number: str = Field(..., max_length=50)
    issue_date: date
    due_date: date
    pos_state_code: str = Field(..., pattern="^[0-9]{2}$")

class ProformaInvoiceCreate(ProformaInvoiceBase):
    line_items: List[ProformaInvoiceLineCreate]

class ProformaInvoiceUpdate(SchemaBase):
    contact_id: Optional[uuid.UUID] = None
    proforma_number: Optional[str] = None
    issue_date: Optional[date] = None
    due_date: Optional[date] = None
    pos_state_code: Optional[str] = None
    line_items: Optional[List[ProformaInvoiceLineCreate]] = None

class ProformaInvoiceResponse(ProformaInvoiceBase):
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
    total: Decimal
    converted_to_invoice_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime
    lines: List[ProformaInvoiceLineResponse]
    contact: ContactResponse

class ProformaInvoiceListResponse(SchemaBase):
    id: uuid.UUID
    proforma_number: str
    issue_date: date
    due_date: date
    status: str
    total: Decimal
    contact_name: str
    converted_to_invoice_id: Optional[uuid.UUID] = None
    created_at: datetime


# INVENTORY ADJUSTMENT SCHEMAS
class InventoryAdjustmentLineBase(SchemaBase):
    product_id: uuid.UUID
    quantity_change: Decimal = Field(..., description="Positive for increase, negative for decrease")
    unit_cost: Optional[Decimal] = Field(None, ge=0, description="Cost per unit for valuation")

class InventoryAdjustmentLineCreate(InventoryAdjustmentLineBase):
    pass

class InventoryAdjustmentLineResponse(InventoryAdjustmentLineBase):
    id: uuid.UUID
    total_cost: Decimal
    created_at: datetime
    product_name: Optional[str] = None

# Inventory Adjustment Header Schemas
class InventoryAdjustmentBase(SchemaBase):
    adjustment_number: str = Field(..., max_length=50)
    adjustment_date: date
    reason: Optional[str] = Field(None, max_length=65535)

class InventoryAdjustmentCreate(InventoryAdjustmentBase):
    line_items: List[InventoryAdjustmentLineCreate]

class InventoryAdjustmentUpdate(SchemaBase):
    adjustment_number: Optional[str] = None
    adjustment_date: Optional[date] = None
    reason: Optional[str] = None
    line_items: Optional[List[InventoryAdjustmentLineCreate]] = None

class InventoryAdjustmentResponse(InventoryAdjustmentBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    status: str
    created_at: datetime
    updated_at: datetime
    lines: List[InventoryAdjustmentLineResponse]

class InventoryAdjustmentListResponse(SchemaBase):
    id: uuid.UUID
    adjustment_number: str
    adjustment_date: date
    status: str
    created_at: datetime


# BANK RECONCILIATION SCHEMAS
class BankTransactionBase(SchemaBase):
    transaction_date: date
    amount: Decimal = Field(..., description="Positive for credit (deposit), negative for debit (withdrawal)")
    description: Optional[str] = None
    reference_number: Optional[str] = Field(None, max_length=50)

class BankTransactionCreate(BankTransactionBase):
    pass

class BankTransactionResponse(BankTransactionBase):
    id: uuid.UUID
    status: str
    created_at: datetime
    updated_at: datetime

class BankStatementBase(SchemaBase):
    banking_profile_id: uuid.UUID
    statement_date: date
    starting_balance: Decimal = Field(default=Decimal("0.0000"))
    ending_balance: Decimal = Field(default=Decimal("0.0000"))
    currency: str = Field(default="INR", max_length=10)

class BankStatementCreate(BankStatementBase):
    pass

class BankStatementResponse(BankStatementBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    status: str
    created_at: datetime
    updated_at: datetime
    banking_profile: BankingProfileResponse  # Assuming we have this from master_schemas
    transactions: List[BankTransactionResponse] = []

class BankStatementListResponse(SchemaBase):
    id: uuid.UUID
    statement_date: date
    status: str
    created_at: datetime

class BankReconciliationBase(SchemaBase):
    bank_transaction_id: uuid.UUID
    amount: Decimal = Field(..., description="The reconciled amount")
    notes: Optional[str] = None

class BankReconciliationCreate(BankReconciliationBase):
    pass

class BankReconciliationResponse(BankReconciliationBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    bank_transaction: BankTransactionResponse
    payment: Optional[PaymentResponse] = None  # Assuming we have this from payment_schemas
    bill_payment: Optional[BillPaymentResponse] = None  # Assuming we have this from bill_schemas

class BankReconciliationListResponse(SchemaBase):
    id: uuid.UUID
    bank_transaction_id: uuid.UUID
    amount: Decimal
    notes: Optional[str] = None
    created_at: datetime
