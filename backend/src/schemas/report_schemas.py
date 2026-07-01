"""
Report Schemas — Module 9: Reports & Analytics
Pydantic response models for all financial, GST, and operational reports.
"""
from pydantic import BaseModel, Field
from typing import List, Optional, Any, Dict
from decimal import Decimal
from datetime import date
import uuid


# ---------------------------------------------------------------------------
# Shared primitives
# ---------------------------------------------------------------------------

class ReportLineItem(BaseModel):
    account_name: str
    account_code: str
    account_type: str
    balance: Decimal

    model_config = {"from_attributes": True}


# ---------------------------------------------------------------------------
# Balance Sheet
# ---------------------------------------------------------------------------

class BalanceSheetSection(BaseModel):
    items: List[ReportLineItem]
    total: Decimal


class BalanceSheetResponse(BaseModel):
    as_of_date: date
    assets: BalanceSheetSection
    liabilities: BalanceSheetSection
    equity: BalanceSheetSection
    total_liabilities_and_equity: Decimal
    is_balanced: bool


# ---------------------------------------------------------------------------
# GSTR-1: Outward Supplies Summary
# ---------------------------------------------------------------------------

class GSTR1B2BLine(BaseModel):
    """B2B supply line grouped by receiver GSTIN."""
    receiver_gstin: str
    receiver_name: str
    invoice_count: int
    taxable_value: Decimal
    cgst: Decimal
    sgst: Decimal
    igst: Decimal
    cess: Decimal
    total_tax: Decimal
    invoice_value: Decimal


class GSTR1B2CLLine(BaseModel):
    """B2CL (inter-state, large) line grouped by place of supply."""
    place_of_supply: str
    taxable_value: Decimal
    igst: Decimal
    cess: Decimal


class GSTR1B2CSLine(BaseModel):
    """B2CS (intra-state small or unregistered) grouped by GST rate and place of supply."""
    gst_rate: Decimal
    place_of_supply: Optional[str] = None
    taxable_value: Decimal
    cgst: Decimal
    sgst: Decimal
    igst: Decimal
    cess: Decimal


class GSTR1HSNLine(BaseModel):
    """HSN-wise summary."""
    hsn_sac: str
    description: Optional[str] = None
    uom: str
    total_qty: Decimal
    taxable_value: Decimal
    cgst: Decimal
    sgst: Decimal
    igst: Decimal
    cess: Decimal


class GSTR1Response(BaseModel):
    """Full GSTR-1 outward supply report."""
    period_start: date
    period_end: date
    b2b: List[GSTR1B2BLine]
    b2cl: List[GSTR1B2CLLine]
    b2cs: List[GSTR1B2CSLine]
    hsn_summary: List[GSTR1HSNLine]
    total_taxable_value: Decimal
    total_cgst: Decimal
    total_sgst: Decimal
    total_igst: Decimal
    total_cess: Decimal
    total_invoice_value: Decimal
    rcm_invoices: Optional[List[dict]] = None  # Table 4B: RCM supplies
    exports: Optional[List[dict]] = None  # Table 6A: Export supplies


# ---------------------------------------------------------------------------
# GSTR-3B: Monthly GST Summary
# ---------------------------------------------------------------------------

class GSTR3BOutwardSection(BaseModel):
    taxable_value: Decimal
    integrated_tax: Decimal
    central_tax: Decimal
    state_ut_tax: Decimal
    cess: Decimal


class GSTR3BInwardSection(BaseModel):
    """ITC available from purchases."""
    integrated_tax: Decimal
    central_tax: Decimal
    state_ut_tax: Decimal
    cess: Decimal


class GSTR3BResponse(BaseModel):
    period_start: date
    period_end: date
    gstin: Optional[str] = None
    outward_taxable_supplies: GSTR3BOutwardSection   # 3.1(a)
    nil_rated_supplies: GSTR3BOutwardSection          # 3.1(b)/(c)
    inward_supplies_itc: GSTR3BInwardSection          # Table 4 - ITC
    net_tax_payable_igst: Decimal
    net_tax_payable_cgst: Decimal
    net_tax_payable_sgst: Decimal
    net_tax_payable_cess: Decimal


# ---------------------------------------------------------------------------
# Receivables / Payables Aging
# ---------------------------------------------------------------------------

class AgingBucket(BaseModel):
    label: str          # e.g. "0-30 days", "31-60 days", etc.
    days_from: int
    days_to: Optional[int]   # None = "90+ days"
    amount: Decimal


class AgingContactLine(BaseModel):
    contact_id: str
    contact_name: str
    total_outstanding: Decimal
    buckets: List[AgingBucket]


class AgingReportResponse(BaseModel):
    as_of_date: date
    report_type: str   # 'RECEIVABLES' or 'PAYABLES'
    lines: List[AgingContactLine]
    total_outstanding: Decimal
    bucket_totals: List[AgingBucket]


# ---------------------------------------------------------------------------
# Cash Flow Statement (Indirect Method)
# ---------------------------------------------------------------------------

class CashFlowItem(BaseModel):
    label: str
    amount: Decimal


class CashFlowSection(BaseModel):
    section: str
    items: List[CashFlowItem]
    net: Decimal


class CashFlowResponse(BaseModel):
    period_start: date
    period_end: date
    operating_activities: CashFlowSection
    investing_activities: CashFlowSection
    financing_activities: CashFlowSection
    net_change_in_cash: Decimal
    opening_cash_balance: Decimal
    closing_cash_balance: Decimal


# ---------------------------------------------------------------------------
# Sales Analytics
# ---------------------------------------------------------------------------

class TopCustomerLine(BaseModel):
    contact_id: str
    contact_name: str
    invoice_count: int
    total_sales: Decimal
    total_tax: Decimal
    total_invoiced: Decimal


class SalesAnalyticsResponse(BaseModel):
    period_start: date
    period_end: date
    total_sales: Decimal
    total_tax_collected: Decimal
    total_invoiced: Decimal
    invoice_count: int
    top_customers: List[TopCustomerLine]


# ---------------------------------------------------------------------------
# Purchase Analytics
# ---------------------------------------------------------------------------

class TopVendorLine(BaseModel):
    contact_id: str
    contact_name: str
    bill_count: int
    total_purchases: Decimal
    total_tax: Decimal
    total_billed: Decimal


class PurchaseAnalyticsResponse(BaseModel):
    period_start: date
    period_end: date
    total_purchases: Decimal
    total_tax_paid: Decimal
    total_billed: Decimal
    bill_count: int
    top_vendors: List[TopVendorLine]


# ---------------------------------------------------------------------------
# Outstanding Documents (AR / AP)
# ---------------------------------------------------------------------------

class OutstandingInvoiceLine(BaseModel):
    invoice_id: str
    invoice_number: str
    contact_name: str
    issue_date: date
    due_date: date
    total: Decimal
    amount_paid: Decimal
    outstanding: Decimal
    days_overdue: int


class OutstandingBillLine(BaseModel):
    bill_id: str
    bill_number: str
    contact_name: str
    issue_date: date
    due_date: date
    total: Decimal
    amount_paid: Decimal
    outstanding: Decimal
    days_overdue: int


class OutstandingARResponse(BaseModel):
    as_of_date: date
    invoices: List[OutstandingInvoiceLine]
    total_outstanding: Decimal


class OutstandingAPResponse(BaseModel):
    as_of_date: date
    bills: List[OutstandingBillLine]
    total_outstanding: Decimal


# ---------------------------------------------------------------------------
# Party Statement
# ---------------------------------------------------------------------------

class PartyStatementRow(BaseModel):
    date: date
    particulars: str
    voucher_type: str
    voucher_no: str
    debit: Optional[Decimal] = None
    credit: Optional[Decimal] = None
    balance: str

class PartyStatementSummary(BaseModel):
    opening_balance: Decimal
    total_sales: Decimal
    total_receipts: Decimal
    total_purchases: Decimal
    total_payments: Decimal
    closing_outstanding: Decimal

class PartyStatementResponse(BaseModel):
    contact_id: str
    contact_name: str
    contact_type: str
    address: Optional[str] = None
    gstin: Optional[str] = None
    phone: Optional[str] = None
    start_date: date
    end_date: date
    ledger: List[PartyStatementRow]
    summary: PartyStatementSummary


# ---------------------------------------------------------------------------
# Trial Balance
# ---------------------------------------------------------------------------

class TrialBalanceLine(BaseModel):
    account_name: str
    account_code: str
    account_type: str
    opening_balance: Decimal
    period_debits: Decimal
    period_credits: Decimal
    closing_balance: Decimal
    closing_direction: str  # "DEBIT" or "CREDIT"

    model_config = {"from_attributes": True}


class TrialBalanceResponse(BaseModel):
    as_of_date: date
    lines: List[TrialBalanceLine]
    total_debits: Decimal
    total_credits: Decimal
    is_balanced: bool


# ---------------------------------------------------------------------------
# Cash Book
# ---------------------------------------------------------------------------

class CashBookRow(BaseModel):
    date: date
    transaction_details: str
    invoice_amount: Optional[Decimal] = None
    tax_amount: Optional[Decimal] = None
    amount: Decimal

class CashBookSummary(BaseModel):
    cash_inflow: Decimal
    cash_outflow: Decimal
    closing_balance: Decimal
    actual_cash_in_hand: Decimal
    difference: Decimal

class CashBookTaxSummary(BaseModel):
    tax_paid: Decimal
    tax_received: Decimal
    tax_payable: Decimal

class CashBookResponse(BaseModel):
    period_start: date
    period_end: date
    opening_balance: Decimal
    inflows: List[CashBookRow]
    outflows: List[CashBookRow]
    summary: CashBookSummary
    tax_summary: CashBookTaxSummary


class DayBookLine(BaseModel):
    account_id: str
    account_name: str
    account_code: str
    amount: Decimal
    direction: str
    narration: Optional[str] = None

class DayBookEntry(BaseModel):
    id: str
    entry_date: date
    reference_number: str
    description: str
    source_type: str
    source_id: Optional[str] = None
    lines: List[DayBookLine]

class DayBookResponse(BaseModel):
    start_date: date
    end_date: date
    total_debit: Decimal
    total_credit: Decimal
    entries: List[DayBookEntry]
    total_count: int


class StockRegisterLine(BaseModel):
    product_id: uuid.UUID
    product_name: str
    sku: Optional[str] = None
    uom: str
    opening_stock: Decimal
    inward_qty: Decimal
    outward_qty: Decimal
    adjustment_qty: Decimal
    closing_stock: Decimal

class StockRegisterResponse(BaseModel):
    start_date: date
    end_date: date
    items: List[StockRegisterLine]
    total_count: int


class TDSDetailLine(BaseModel):
    id: uuid.UUID
    type: str
    number: str
    date: date
    contact_name: str
    taxable_amount: Decimal
    tds_rate: Decimal
    tds_amount: Decimal

class TDSSummaryLine(BaseModel):
    contact_id: uuid.UUID
    contact_name: str
    total_taxable_amount: Decimal
    total_tds_amount: Decimal

class TDSReportResponse(BaseModel):
    start_date: date
    end_date: date
    report_type: str
    total_tds_amount: Decimal
    detailed_items: Optional[List[TDSDetailLine]] = None
    summary_items: Optional[List[TDSSummaryLine]] = None

class TCSDetailLine(BaseModel):
    id: uuid.UUID
    number: str
    date: date
    contact_name: str
    taxable_amount: Decimal
    tcs_rate: Decimal
    tcs_amount: Decimal

class TCSSummaryLine(BaseModel):
    contact_id: uuid.UUID
    contact_name: str
    total_taxable_amount: Decimal
    total_tcs_amount: Decimal

class TCSReportResponse(BaseModel):
    start_date: date
    end_date: date
    report_type: str
    total_tcs_amount: Decimal
    detailed_items: Optional[List[TCSDetailLine]] = None
    summary_items: Optional[List[TCSSummaryLine]] = None
