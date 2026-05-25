"""
Reports API Router — Module 9: Reports & Analytics
All endpoints under /api/v1/reports/
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
import uuid
from datetime import date

from src.core.database import get_db_session
from src.api.deps import enforce_permission
from src.domains.accounting.report_services import (
    BalanceSheetService,
    GSTR1Service,
    GSTR3BService,
    AgingService,
    CashFlowService,
    SalesAnalyticsService,
    PurchaseAnalyticsService,
    OutstandingService,
)
from src.schemas.report_schemas import (
    BalanceSheetResponse,
    GSTR1Response,
    GSTR3BResponse,
    AgingReportResponse,
    CashFlowResponse,
    SalesAnalyticsResponse,
    PurchaseAnalyticsResponse,
    OutstandingARResponse,
    OutstandingAPResponse,
)

router = APIRouter(prefix="/reports", tags=["Reports & Analytics"])


# ---------------------------------------------------------------------------
# Balance Sheet
# ---------------------------------------------------------------------------

@router.get(
    "/balance-sheet",
    response_model=BalanceSheetResponse,
    summary="Balance Sheet",
    description=(
        "Returns the Balance Sheet (Assets = Liabilities + Equity) as of a given date. "
        "Current Year Net Profit/Loss is automatically computed from journal entries and "
        "injected into the Equity section."
    ),
)
def get_balance_sheet(
    as_of_date: date = Query(..., description="Report date, e.g. 2025-03-31"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return BalanceSheetService.get(db, tenant_id, as_of_date)


# ---------------------------------------------------------------------------
# GST Reports
# ---------------------------------------------------------------------------

@router.get(
    "/gst/gstr1",
    response_model=GSTR1Response,
    summary="GSTR-1 Outward Supplies",
    description=(
        "Compiles GSTR-1 outward supply data for the given period. "
        "Splits invoices into B2B (registered), B2CL (inter-state large), "
        "B2CS (intra-state / small), and HSN-wise summary tables."
    ),
)
def get_gstr1(
    start_date: date = Query(..., description="Period start, e.g. 2025-04-01"),
    end_date: date = Query(..., description="Period end, e.g. 2025-06-30"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return GSTR1Service.get(db, tenant_id, start_date, end_date)


@router.get(
    "/gst/gstr3b",
    response_model=GSTR3BResponse,
    summary="GSTR-3B Monthly Summary",
    description=(
        "Compiles the GSTR-3B summary: outward taxable supplies, nil-rated supplies, "
        "and ITC available from purchase bills. Net tax payable = Output Tax − ITC."
    ),
)
def get_gstr3b(
    start_date: date = Query(..., description="Month start date, e.g. 2025-04-01"),
    end_date: date = Query(..., description="Month end date, e.g. 2025-04-30"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return GSTR3BService.get(db, tenant_id, start_date, end_date)


# ---------------------------------------------------------------------------
# Aging Reports
# ---------------------------------------------------------------------------

@router.get(
    "/aging/receivables",
    response_model=AgingReportResponse,
    summary="Accounts Receivable Aging",
    description=(
        "Groups outstanding customer invoices into aging buckets: "
        "0-30, 31-60, 61-90, and 91+ days overdue."
    ),
)
def get_ar_aging(
    as_of_date: date = Query(..., description="Report date for aging calculation"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return AgingService.get_receivables(db, tenant_id, as_of_date)


@router.get(
    "/aging/payables",
    response_model=AgingReportResponse,
    summary="Accounts Payable Aging",
    description=(
        "Groups outstanding vendor bills into aging buckets: "
        "0-30, 31-60, 61-90, and 91+ days overdue."
    ),
)
def get_ap_aging(
    as_of_date: date = Query(..., description="Report date for aging calculation"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return AgingService.get_payables(db, tenant_id, as_of_date)


# ---------------------------------------------------------------------------
# Cash Flow
# ---------------------------------------------------------------------------

@router.get(
    "/cash-flow",
    response_model=CashFlowResponse,
    summary="Cash Flow Statement",
    description=(
        "Indirect-method Cash Flow Statement. "
        "Operating = Net Profit ± changes in AR/AP. "
        "Investing = capital asset journal movements. "
        "Financing = equity/loan journal movements."
    ),
)
def get_cash_flow(
    start_date: date = Query(..., description="Period start"),
    end_date: date = Query(..., description="Period end"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return CashFlowService.get(db, tenant_id, start_date, end_date)


# ---------------------------------------------------------------------------
# Sales Analytics
# ---------------------------------------------------------------------------

@router.get(
    "/analytics/sales",
    response_model=SalesAnalyticsResponse,
    summary="Sales Analytics",
    description=(
        "Aggregate sales analytics for the period: total taxable sales, tax collected, "
        "invoice count, and top customers by invoice value."
    ),
)
def get_sales_analytics(
    start_date: date = Query(..., description="Period start"),
    end_date: date = Query(..., description="Period end"),
    top_n: int = Query(default=10, ge=1, le=50, description="Number of top customers to return"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return SalesAnalyticsService.get(db, tenant_id, start_date, end_date, top_n)


# ---------------------------------------------------------------------------
# Purchase Analytics
# ---------------------------------------------------------------------------

@router.get(
    "/analytics/purchases",
    response_model=PurchaseAnalyticsResponse,
    summary="Purchase Analytics",
    description=(
        "Aggregate purchase analytics for the period: total taxable purchases, tax paid, "
        "bill count, and top vendors by billed value."
    ),
)
def get_purchase_analytics(
    start_date: date = Query(..., description="Period start"),
    end_date: date = Query(..., description="Period end"),
    top_n: int = Query(default=10, ge=1, le=50, description="Number of top vendors to return"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return PurchaseAnalyticsService.get(db, tenant_id, start_date, end_date, top_n)


# ---------------------------------------------------------------------------
# Outstanding Documents (AR / AP snapshots)
# ---------------------------------------------------------------------------

@router.get(
    "/outstanding/receivables",
    response_model=OutstandingARResponse,
    summary="Outstanding Receivables",
    description="Lists all unpaid/partially-paid customer invoices with outstanding amounts as of a date.",
)
def get_outstanding_ar(
    as_of_date: date = Query(..., description="Snapshot date"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return OutstandingService.get_ar(db, tenant_id, as_of_date)


@router.get(
    "/outstanding/payables",
    response_model=OutstandingAPResponse,
    summary="Outstanding Payables",
    description="Lists all unpaid/partially-paid vendor bills with outstanding amounts as of a date.",
)
def get_outstanding_ap(
    as_of_date: date = Query(..., description="Snapshot date"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return OutstandingService.get_ap(db, tenant_id, as_of_date)
