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
    PartyStatementService,
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
    PartyStatementResponse,
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


# ---------------------------------------------------------------------------
# Party Statement
# ---------------------------------------------------------------------------

@router.get(
    "/party-statement",
    response_model=PartyStatementResponse,
    summary="Party Statement JSON Data",
    description="Calculates and returns ledger, running balances, and summaries for a specific party.",
)
def get_party_statement(
    contact_id: uuid.UUID = Query(..., description="ID of the party/contact"),
    start_date: date = Query(..., description="Period start date"),
    end_date: date = Query(..., description="Period end date"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    return PartyStatementService.get(db, tenant_id, contact_id, start_date, end_date)


@router.get(
    "/party-statement/pdf",
    summary="Party Statement A4 PDF",
    description="Generates and streams an A4 PDF document for the party statement.",
)
def get_party_statement_pdf(
    contact_id: uuid.UUID = Query(..., description="ID of the party/contact"),
    start_date: date = Query(..., description="Period start date"),
    end_date: date = Query(..., description="Period end date"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    from fastapi.responses import StreamingResponse
    from io import BytesIO
    from src.domains.printing.invoice_pdf import generate_party_statement_pdf
    from src.infrastructure.database.models import Tenant, TenantSetting

    statement = PartyStatementService.get(db, tenant_id, contact_id, start_date, end_date)
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()

    company_name = tenant.legal_name if tenant else "ApexBooks"
    company_gstin = tenant.gstin if tenant else None
    
    company_address = None
    company_phone = None
    if setting and setting.extra_settings:
        company_address = setting.extra_settings.get("company_address")
        company_phone = setting.extra_settings.get("company_phone")

    pdf_bytes = generate_party_statement_pdf(
        statement=statement,
        company_name=company_name,
        company_address=company_address,
        company_gstin=company_gstin,
        company_phone=company_phone,
    )

    return StreamingResponse(
        BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=PartyStatement_{statement.contact_name.replace(' ', '_')}.pdf"}
    )


@router.get(
    "/party-statement/excel",
    summary="Party Statement Excel Sheet",
    description="Generates and streams an Excel spreadsheet (.xlsx) for the party statement.",
)
def get_party_statement_excel(
    contact_id: uuid.UUID = Query(..., description="ID of the party/contact"),
    start_date: date = Query(..., description="Period start date"),
    end_date: date = Query(..., description="Period end date"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("reports:view")),
):
    from fastapi.responses import StreamingResponse
    from io import BytesIO
    from src.infrastructure.database.models import Tenant
    import openpyxl
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

    statement = PartyStatementService.get(db, tenant_id, contact_id, start_date, end_date)
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    company_name = tenant.legal_name if tenant else "ApexBooks"

    # Excel Generation Logic
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Party Statement"
    ws.views.sheetView[0].showGridLines = True

    title_font = Font(name="Calibri", size=16, bold=True, color="0F1B3D")
    section_font = Font(name="Calibri", size=11, bold=True)
    header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
    bold_font = Font(name="Calibri", size=11, bold=True)
    normal_font = Font(name="Calibri", size=11)
    
    header_fill = PatternFill(start_color="0F1B3D", end_color="0F1B3D", fill_type="solid")
    accent_fill = PatternFill(start_color="E2E8F0", end_color="E2E8F0", fill_type="solid")
    
    thin_side = Side(border_style="thin", color="D1D5DB")
    thin_border = Border(left=thin_side, right=thin_side, top=thin_side, bottom=thin_side)

    ws["A1"] = "Party Statement"
    ws["A1"].font = title_font
    
    ws["A3"] = f"Company Name: {company_name}"
    ws["A3"].font = bold_font
    
    ws["A4"] = f"Party Name: {statement.contact_name}"
    ws["A4"].font = bold_font
    ws["A5"] = f"Address: {statement.address or 'N/A'}"
    ws["A5"].font = normal_font
    ws["A6"] = f"GSTIN: {statement.gstin or 'N/A'}"
    ws["A6"].font = normal_font
    ws["A7"] = f"Mobile: {statement.phone or 'N/A'}"
    ws["A7"].font = normal_font

    start_str = statement.start_date.strftime("%d-%b-%Y")
    end_str = statement.end_date.strftime("%d-%b-%Y")
    ws["A9"] = f"Statement Period: {start_str} to {end_str}"
    ws["A9"].font = section_font

    headers = ["Date", "Particulars", "Voucher Type", "Voucher No.", "Debit (₹)", "Credit (₹)", "Balance (₹)"]
    for col_idx, h in enumerate(headers, start=1):
        cell = ws.cell(row=11, column=col_idx, value=h)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="right" if col_idx in [5, 6, 7] else "left", vertical="center")

    current_row = 12
    for row in statement.ledger:
        date_str = row.date.strftime("%d-%b-%Y")
        ws.cell(row=current_row, column=1, value=date_str).font = normal_font
        ws.cell(row=current_row, column=2, value=row.particulars).font = normal_font
        ws.cell(row=current_row, column=3, value=row.voucher_type).font = normal_font
        ws.cell(row=current_row, column=4, value=row.voucher_no).font = normal_font
        
        deb_cell = ws.cell(row=current_row, column=5, value=float(row.debit) if row.debit is not None else "")
        deb_cell.font = normal_font
        deb_cell.number_format = "#,##0.00"
        
        cred_cell = ws.cell(row=current_row, column=6, value=float(row.credit) if row.credit is not None else "")
        cred_cell.font = normal_font
        cred_cell.number_format = "#,##0.00"
        
        bal_cell = ws.cell(row=current_row, column=7, value=row.balance)
        bal_cell.font = normal_font
        bal_cell.alignment = Alignment(horizontal="right")
        
        for c in range(1, 8):
            ws.cell(row=current_row, column=c).border = thin_border
            
        current_row += 1

    current_row += 2
    ws.cell(row=current_row, column=1, value="Summary").font = section_font
    current_row += 1
    
    sum_headers = ["Particulars", "Amount (₹)"]
    for col_idx, h in enumerate(sum_headers, start=1):
        cell = ws.cell(row=current_row, column=col_idx, value=h)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="right" if col_idx == 2 else "left", vertical="center")
    
    summary = statement.summary
    summary_rows = [
        ("Opening Balance", float(summary.opening_balance)),
    ]
    if statement.contact_type in ["CUSTOMER", "BOTH"] or summary.total_sales > 0 or summary.total_receipts > 0:
        summary_rows.append(("Total Sales", float(summary.total_sales)))
        summary_rows.append(("Total Receipts", float(summary.total_receipts)))
    if statement.contact_type in ["VENDOR", "BOTH"] or summary.total_purchases > 0 or summary.total_payments > 0:
        summary_rows.append(("Total Purchases", float(summary.total_purchases)))
        summary_rows.append(("Total Payments", float(summary.total_payments)))
    summary_rows.append(("Closing Outstanding", float(summary.closing_outstanding)))

    for label, val in summary_rows:
        current_row += 1
        is_closing = (label == "Closing Outstanding")
        lbl_cell = ws.cell(row=current_row, column=1, value=label)
        val_cell = ws.cell(row=current_row, column=2, value=val)
        
        lbl_cell.font = bold_font if is_closing else normal_font
        val_cell.font = bold_font if is_closing else normal_font
        val_cell.number_format = "#,##0.00"
        
        for c in [1, 2]:
            cell = ws.cell(row=current_row, column=c)
            cell.border = thin_border
            if is_closing:
                cell.fill = accent_fill

    # Adjust columns
    for col in ws.columns:
        max_len = 0
        for cell in col:
            val_str = str(cell.value or '')
            if cell.number_format and isinstance(cell.value, (int, float)):
                val_str = f"{cell.value:,.2f}"
            max_len = max(max_len, len(val_str))
        col_letter = openpyxl.utils.get_column_letter(col[0].column)
        ws.column_dimensions[col_letter].width = max(max_len + 3, 12)

    excel_buffer = BytesIO()
    wb.save(excel_buffer)
    excel_buffer.seek(0)

    return StreamingResponse(
        excel_buffer,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename=PartyStatement_{statement.contact_name.replace(' ', '_')}.xlsx"}
    )

