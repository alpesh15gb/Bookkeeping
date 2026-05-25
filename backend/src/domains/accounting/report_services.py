"""
Report Services — Module 9: Reports & Analytics
Domain service layer that compiles all financial, GST, and operational reports.

Design principles:
  - All monetary values use Decimal with quantize(0.01) for precision.
  - Every query is tenant-scoped via explicit tenant_id predicate.
  - No raw text() SQL — uses SQLAlchemy ORM / expression API exclusively.
  - Indian financial year: April 1 → March 31.
"""
from decimal import Decimal, ROUND_HALF_UP
from typing import List, Optional
from datetime import date, timedelta
import uuid

from sqlalchemy.orm import Session
from sqlalchemy import func, case, and_, cast, Numeric as SaNumeric

from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Bill, BillLine,
    Contact, Account, JournalEntry, JournalLine
)
from src.schemas.report_schemas import (
    BalanceSheetSection, BalanceSheetResponse, ReportLineItem,
    GSTR1B2BLine, GSTR1B2CLLine, GSTR1B2CSLine, GSTR1HSNLine, GSTR1Response,
    GSTR3BOutwardSection, GSTR3BInwardSection, GSTR3BResponse,
    AgingBucket, AgingContactLine, AgingReportResponse,
    CashFlowItem, CashFlowSection, CashFlowResponse,
    TopCustomerLine, SalesAnalyticsResponse,
    TopVendorLine, PurchaseAnalyticsResponse,
    OutstandingInvoiceLine, OutstandingBillLine,
    OutstandingARResponse, OutstandingAPResponse,
)

D = Decimal
ZERO = D("0.00")
Q = D("0.01")

# B2CL threshold per transaction (₹2.5 lakh inter-state)
B2CL_THRESHOLD = D("250000.00")


def _q(v) -> Decimal:
    return D(str(v)).quantize(Q, rounding=ROUND_HALF_UP)


# ---------------------------------------------------------------------------
# Balance Sheet
# ---------------------------------------------------------------------------

class BalanceSheetService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, as_of_date: date) -> BalanceSheetResponse:
        """
        Compiles the Balance Sheet as of a specific date.
        Current Year Earnings (net P&L from FY start) is injected into Equity.
        """
        rows = (
            db.query(
                Account.id,
                Account.name,
                Account.code,
                Account.account_type,
                Account.opening_balance,
                func.coalesce(
                    func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0
                ).label("debits"),
                func.coalesce(
                    func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0
                ).label("credits"),
            )
            .outerjoin(JournalLine, Account.id == JournalLine.account_id)
            .outerjoin(
                JournalEntry,
                and_(JournalLine.entry_id == JournalEntry.id, JournalEntry.entry_date <= as_of_date),
            )
            .filter(
                Account.tenant_id == tenant_id,
                Account.account_type.in_(["ASSET", "LIABILITY", "EQUITY"]),
                Account.deleted_at == None,
            )
            .group_by(Account.id, Account.name, Account.code, Account.account_type, Account.opening_balance)
            .order_by(Account.account_type.asc(), Account.code.asc())
            .all()
        )

        assets, liabilities, equity = [], [], []
        total_assets = ZERO
        total_liab = ZERO
        total_eq = ZERO

        for row in rows:
            op = _q(row.opening_balance)
            deb = _q(row.debits)
            cred = _q(row.credits)
            acc_type = row.account_type

            if acc_type == "ASSET":
                net = op + deb - cred
                total_assets += net
                assets.append(ReportLineItem(account_name=row.name, account_code=row.code, account_type=acc_type, balance=net))
            elif acc_type == "LIABILITY":
                net = op + cred - deb
                total_liab += net
                liabilities.append(ReportLineItem(account_name=row.name, account_code=row.code, account_type=acc_type, balance=net))
            elif acc_type == "EQUITY":
                net = op + cred - deb
                total_eq += net
                equity.append(ReportLineItem(account_name=row.name, account_code=row.code, account_type=acc_type, balance=net))

        # Inject Current Year Net Profit into Equity
        fy_year = as_of_date.year if as_of_date.month >= 4 else as_of_date.year - 1
        fy_start = date(fy_year, 4, 1)
        cy_earnings = PLService._compute_net(db, tenant_id, fy_start, as_of_date)
        total_eq += cy_earnings
        equity.append(
            ReportLineItem(
                account_name="Current Year Earnings (P&L)",
                account_code="39999",
                account_type="EQUITY",
                balance=cy_earnings,
            )
        )

        total_l_and_e = _q(total_liab + total_eq)
        return BalanceSheetResponse(
            as_of_date=as_of_date,
            assets=BalanceSheetSection(items=assets, total=_q(total_assets)),
            liabilities=BalanceSheetSection(items=liabilities, total=_q(total_liab)),
            equity=BalanceSheetSection(items=equity, total=_q(total_eq)),
            total_liabilities_and_equity=total_l_and_e,
            is_balanced=_q(total_assets) == total_l_and_e,
        )


# ---------------------------------------------------------------------------
# P&L helper (internal use — shared with Balance Sheet)
# ---------------------------------------------------------------------------

class PLService:
    @staticmethod
    def _compute_net(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date) -> Decimal:
        rows = (
            db.query(
                Account.account_type,
                func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
                func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits"),
            )
            .join(JournalLine, Account.id == JournalLine.account_id)
            .join(JournalEntry, JournalLine.entry_id == JournalEntry.id)
            .filter(
                Account.tenant_id == tenant_id,
                Account.account_type.in_(["REVENUE", "EXPENSE"]),
                Account.deleted_at == None,
                JournalEntry.entry_date >= start_date,
                JournalEntry.entry_date <= end_date,
            )
            .group_by(Account.account_type)
            .all()
        )
        rev = ZERO
        exp = ZERO
        for row in rows:
            if row.account_type == "REVENUE":
                rev += _q(row.credits) - _q(row.debits)
            else:
                exp += _q(row.debits) - _q(row.credits)
        return _q(rev - exp)


# ---------------------------------------------------------------------------
# GSTR-1 Report
# ---------------------------------------------------------------------------

class GSTR1Service:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date) -> GSTR1Response:
        """
        Compiles GSTR-1 outward supply report:
          - B2B: Registered receiver (has GSTIN), grouped by receiver GSTIN
          - B2CL: Unregistered / consumer, inter-state, invoice > ₹2.5 lakh
          - B2CS: Unregistered / consumer, intra-state or invoice ≤ ₹2.5 lakh
          - HSN: Line-level HSN summary
        Only FINALIZED (not DRAFT/CANCELLED) invoices are included.
        """
        invoices = (
            db.query(Invoice)
            .join(Contact, Invoice.contact_id == Contact.id)
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
                Invoice.issue_date >= start_date,
                Invoice.issue_date <= end_date,
            )
            .all()
        )

        b2b_map: dict = {}
        b2cl_map: dict = {}
        b2cs_map: dict = {}
        hsn_map: dict = {}
        total_taxable = ZERO
        total_cgst = ZERO
        total_sgst = ZERO
        total_igst = ZERO
        total_cess = ZERO
        total_invoice_val = ZERO

        for inv in invoices:
            contact = db.get(Contact, inv.contact_id)
            taxable = _q(inv.subtotal) - _q(inv.discount_total)
            cgst = _q(inv.cgst_amount)
            sgst = _q(inv.sgst_amount)
            igst = _q(inv.igst_amount)
            cess = _q(inv.cess_amount)
            inv_total = _q(inv.total)
            total_tax = _q(cgst + sgst + igst + cess)

            total_taxable += taxable
            total_cgst += cgst
            total_sgst += sgst
            total_igst += igst
            total_cess += cess
            total_invoice_val += inv_total

            is_registered = bool(contact and contact.gstin)
            is_inter_state = (igst > ZERO)

            if is_registered:
                key = contact.gstin
                if key not in b2b_map:
                    b2b_map[key] = {
                        "receiver_gstin": contact.gstin,
                        "receiver_name": contact.name,
                        "invoice_count": 0,
                        "taxable_value": ZERO,
                        "cgst": ZERO, "sgst": ZERO,
                        "igst": ZERO, "cess": ZERO,
                        "total_tax": ZERO,
                        "invoice_value": ZERO,
                    }
                b = b2b_map[key]
                b["invoice_count"] += 1
                b["taxable_value"] += taxable
                b["cgst"] += cgst
                b["sgst"] += sgst
                b["igst"] += igst
                b["cess"] += cess
                b["total_tax"] += total_tax
                b["invoice_value"] += inv_total
            else:
                # Unregistered: B2CL if inter-state AND invoice > 2.5L
                if is_inter_state and inv_total >= B2CL_THRESHOLD:
                    key = inv.pos_state_code
                    if key not in b2cl_map:
                        b2cl_map[key] = {
                            "place_of_supply": key,
                            "taxable_value": ZERO,
                            "igst": ZERO,
                            "cess": ZERO,
                        }
                    b2cl_map[key]["taxable_value"] += taxable
                    b2cl_map[key]["igst"] += igst
                    b2cl_map[key]["cess"] += cess
                else:
                    # B2CS: Group by effective GST rate
                    # Derive effective rate from first line
                    eff_rate = ZERO
                    if inv.lines:
                        eff_rate = _q(inv.lines[0].gst_rate)
                    key = str(eff_rate)
                    if key not in b2cs_map:
                        b2cs_map[key] = {
                            "gst_rate": eff_rate,
                            "taxable_value": ZERO,
                            "cgst": ZERO, "sgst": ZERO, "cess": ZERO,
                        }
                    b2cs_map[key]["taxable_value"] += taxable
                    b2cs_map[key]["cgst"] += cgst
                    b2cs_map[key]["sgst"] += sgst
                    b2cs_map[key]["cess"] += cess

            # HSN summary (line level)
            for line in inv.lines:
                key = line.hsn_sac
                if key not in hsn_map:
                    hsn_map[key] = {
                        "hsn_sac": key,
                        "uom": "PCS",   # default; would come from product in production
                        "total_qty": ZERO,
                        "taxable_value": ZERO,
                        "cgst": ZERO, "sgst": ZERO, "igst": ZERO, "cess": ZERO,
                    }
                h = hsn_map[key]
                h["total_qty"] += _q(line.quantity)
                line_taxable = _q(line.subtotal)
                h["taxable_value"] += line_taxable
                h["cgst"] += _q(line.cgst_amount)
                h["sgst"] += _q(line.sgst_amount)
                h["igst"] += _q(line.igst_amount)
                h["cess"] += _q(line.cess_amount)

        return GSTR1Response(
            period_start=start_date,
            period_end=end_date,
            b2b=[GSTR1B2BLine(**v) for v in b2b_map.values()],
            b2cl=[GSTR1B2CLLine(**v) for v in b2cl_map.values()],
            b2cs=[GSTR1B2CSLine(**v) for v in b2cs_map.values()],
            hsn_summary=[GSTR1HSNLine(**v) for v in hsn_map.values()],
            total_taxable_value=_q(total_taxable),
            total_cgst=_q(total_cgst),
            total_sgst=_q(total_sgst),
            total_igst=_q(total_igst),
            total_cess=_q(total_cess),
            total_invoice_value=_q(total_invoice_val),
        )


# ---------------------------------------------------------------------------
# GSTR-3B Report
# ---------------------------------------------------------------------------

class GSTR3BService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date) -> GSTR3BResponse:
        """
        Compiles GSTR-3B monthly consolidated GST summary.
          Table 3.1: Outward supplies (taxable, nil-rated)
          Table 4:   ITC available (from purchase bills)
          Net payable = Output Tax - ITC
        """
        # ---- Outward (Sales) ----
        sales = (
            db.query(Invoice)
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
                Invoice.issue_date >= start_date,
                Invoice.issue_date <= end_date,
            )
            .all()
        )

        out_taxable_val = ZERO
        out_cgst = ZERO
        out_sgst = ZERO
        out_igst = ZERO
        out_cess = ZERO
        nil_val = ZERO

        for inv in sales:
            taxable = _q(inv.subtotal) - _q(inv.discount_total)
            cgst = _q(inv.cgst_amount)
            sgst = _q(inv.sgst_amount)
            igst = _q(inv.igst_amount)
            cess = _q(inv.cess_amount)
            total_tax = cgst + sgst + igst + cess

            if total_tax == ZERO:
                nil_val += taxable
            else:
                out_taxable_val += taxable
                out_cgst += cgst
                out_sgst += sgst
                out_igst += igst
                out_cess += cess

        # ---- Inward ITC (Purchase Bills) ----
        bills = (
            db.query(Bill)
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.status.notin_(["DRAFT", "CANCELLED"]),
                Bill.issue_date >= start_date,
                Bill.issue_date <= end_date,
            )
            .all()
        )

        itc_cgst = ZERO
        itc_sgst = ZERO
        itc_igst = ZERO
        itc_cess = ZERO

        for bill in bills:
            itc_cgst += _q(bill.cgst_amount)
            itc_sgst += _q(bill.sgst_amount)
            itc_igst += _q(bill.igst_amount)
            itc_cess += _q(bill.cess_amount)

        # Net payable = Output Tax - ITC (can't go below 0 per component)
        net_igst = max(ZERO, out_igst - itc_igst)
        net_cgst = max(ZERO, out_cgst - itc_cgst)
        net_sgst = max(ZERO, out_sgst - itc_sgst)
        net_cess = max(ZERO, out_cess - itc_cess)

        return GSTR3BResponse(
            period_start=start_date,
            period_end=end_date,
            outward_taxable_supplies=GSTR3BOutwardSection(
                taxable_value=_q(out_taxable_val),
                integrated_tax=_q(out_igst),
                central_tax=_q(out_cgst),
                state_ut_tax=_q(out_sgst),
                cess=_q(out_cess),
            ),
            nil_rated_supplies=GSTR3BOutwardSection(
                taxable_value=_q(nil_val),
                integrated_tax=ZERO, central_tax=ZERO,
                state_ut_tax=ZERO, cess=ZERO,
            ),
            inward_supplies_itc=GSTR3BInwardSection(
                integrated_tax=_q(itc_igst),
                central_tax=_q(itc_cgst),
                state_ut_tax=_q(itc_sgst),
                cess=_q(itc_cess),
            ),
            net_tax_payable_igst=_q(net_igst),
            net_tax_payable_cgst=_q(net_cgst),
            net_tax_payable_sgst=_q(net_sgst),
            net_tax_payable_cess=_q(net_cess),
        )


# ---------------------------------------------------------------------------
# Receivables Aging
# ---------------------------------------------------------------------------

AGING_BUCKETS = [
    ("0-30 days", 0, 30),
    ("31-60 days", 31, 60),
    ("61-90 days", 61, 90),
    ("91+ days", 91, None),
]


class AgingService:
    @staticmethod
    def get_receivables(db: Session, tenant_id: uuid.UUID, as_of_date: date) -> AgingReportResponse:
        """AR Aging: groups outstanding customer invoices by age buckets."""
        invoices = (
            db.query(Invoice)
            .join(Contact, Invoice.contact_id == Contact.id)
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.status.notin_(["DRAFT", "CANCELLED", "PAID"]),
            )
            .all()
        )
        return AgingService._build_report(
            as_of_date, invoices, "RECEIVABLES",
            id_attr="id", num_attr="invoice_number",
            contact_attr="contact_id", total_attr="total", paid_attr="amount_paid",
            due_attr="due_date", db=db,
        )

    @staticmethod
    def get_payables(db: Session, tenant_id: uuid.UUID, as_of_date: date) -> AgingReportResponse:
        """AP Aging: groups outstanding vendor bills by age buckets."""
        bills = (
            db.query(Bill)
            .join(Contact, Bill.contact_id == Contact.id)
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.status.notin_(["DRAFT", "CANCELLED", "PAID"]),
            )
            .all()
        )
        return AgingService._build_report(
            as_of_date, bills, "PAYABLES",
            id_attr="id", num_attr="bill_number",
            contact_attr="contact_id", total_attr="total", paid_attr="amount_paid",
            due_attr="due_date", db=db,
        )

    @staticmethod
    def _build_report(as_of_date, docs, report_type,
                      id_attr, num_attr, contact_attr, total_attr, paid_attr, due_attr, db):
        contact_map: dict = {}

        # Initialize bucket totals
        bucket_totals = {label: ZERO for label, *_ in AGING_BUCKETS}

        for doc in docs:
            outstanding = _q(getattr(doc, total_attr)) - _q(getattr(doc, paid_attr))
            if outstanding <= ZERO:
                continue

            due = getattr(doc, due_attr)
            days_overdue = max(0, (as_of_date - due).days)
            bucket_label = AgingService._bucket_label(days_overdue)
            bucket_totals[bucket_label] += outstanding

            contact_id = str(getattr(doc, contact_attr))
            if contact_id not in contact_map:
                contact = db.get(Contact, getattr(doc, contact_attr))
                contact_map[contact_id] = {
                    "contact_id": contact_id,
                    "contact_name": contact.name if contact else "Unknown",
                    "total_outstanding": ZERO,
                    "buckets": {label: ZERO for label, *_ in AGING_BUCKETS},
                }
            contact_map[contact_id]["total_outstanding"] += outstanding
            contact_map[contact_id]["buckets"][bucket_label] += outstanding

        lines = []
        grand_total = ZERO
        for cdata in contact_map.values():
            grand_total += cdata["total_outstanding"]
            lines.append(AgingContactLine(
                contact_id=cdata["contact_id"],
                contact_name=cdata["contact_name"],
                total_outstanding=_q(cdata["total_outstanding"]),
                buckets=[
                    AgingBucket(
                        label=label,
                        days_from=d_from,
                        days_to=d_to,
                        amount=_q(cdata["buckets"][label]),
                    )
                    for label, d_from, d_to in AGING_BUCKETS
                ],
            ))

        lines.sort(key=lambda x: x.total_outstanding, reverse=True)

        return AgingReportResponse(
            as_of_date=as_of_date,
            report_type=report_type,
            lines=lines,
            total_outstanding=_q(grand_total),
            bucket_totals=[
                AgingBucket(label=label, days_from=d_from, days_to=d_to, amount=_q(bucket_totals[label]))
                for label, d_from, d_to in AGING_BUCKETS
            ],
        )

    @staticmethod
    def _bucket_label(days_overdue: int) -> str:
        for label, d_from, d_to in AGING_BUCKETS:
            if d_to is None or days_overdue <= d_to:
                return label
        return AGING_BUCKETS[-1][0]


# ---------------------------------------------------------------------------
# Cash Flow Statement (Indirect Method)
# ---------------------------------------------------------------------------

class CashFlowService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date) -> CashFlowResponse:
        """
        Indirect method Cash Flow Statement.
        Operating: Net Profit ± changes in AR / AP
        Investing:  movements in ASSET accounts (non-cash)
        Financing:  movements in EQUITY/LIABILITY non-trade accounts
        """
        # Net Profit
        net_profit = PLService._compute_net(db, tenant_id, start_date, end_date)

        # Change in AR (invoiced - collected = net AR movement)
        ar_invoiced = _q(
            db.query(func.coalesce(func.sum(Invoice.total), 0))
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.issue_date.between(start_date, end_date),
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
            )
            .scalar() or 0
        )
        ar_collected = _q(
            db.query(func.coalesce(func.sum(Invoice.amount_paid), 0))
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.issue_date.between(start_date, end_date),
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
            )
            .scalar() or 0
        )
        change_in_ar = ar_collected - ar_invoiced  # negative = increase in AR

        # Change in AP (billed - paid = net AP movement)
        ap_billed = _q(
            db.query(func.coalesce(func.sum(Bill.total), 0))
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.issue_date.between(start_date, end_date),
                Bill.status.notin_(["DRAFT", "CANCELLED"]),
            )
            .scalar() or 0
        )
        ap_paid = _q(
            db.query(func.coalesce(func.sum(Bill.amount_paid), 0))
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.issue_date.between(start_date, end_date),
                Bill.status.notin_(["DRAFT", "CANCELLED"]),
            )
            .scalar() or 0
        )
        change_in_ap = ap_billed - ap_paid   # positive = increase in AP (cash saving)

        operating_net = _q(net_profit + change_in_ar + change_in_ap)

        # Investing: Net debit movement on ASSET accounts via journal entries (non-AR/non-cash simplification)
        investing_rows = (
            db.query(
                Account.name,
                func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
                func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits"),
            )
            .join(JournalLine, Account.id == JournalLine.account_id)
            .join(JournalEntry, JournalLine.entry_id == JournalEntry.id)
            .filter(
                Account.tenant_id == tenant_id,
                Account.account_type == "ASSET",
                Account.deleted_at == None,
                Account.code.notlike("1%"),
                JournalEntry.entry_date.between(start_date, end_date),
                JournalEntry.source_type == "MANUAL",
            )
            .group_by(Account.id, Account.name)
            .all()
        )

        investing_items = []
        investing_net = ZERO
        for row in investing_rows:
            net = _q(row.debits) - _q(row.credits)
            investing_items.append(CashFlowItem(label=row.name, amount=-net))
            investing_net += (-net)

        # Financing: Net credit movement on EQUITY/LOAN accounts
        financing_rows = (
            db.query(
                Account.name,
                func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
                func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits"),
            )
            .join(JournalLine, Account.id == JournalLine.account_id)
            .join(JournalEntry, JournalLine.entry_id == JournalEntry.id)
            .filter(
                Account.tenant_id == tenant_id,
                Account.account_type.in_(["EQUITY", "LIABILITY"]),
                Account.deleted_at == None,
                JournalEntry.entry_date.between(start_date, end_date),
                JournalEntry.source_type == "MANUAL",
            )
            .group_by(Account.id, Account.name)
            .all()
        )

        financing_items = []
        financing_net = ZERO
        for row in financing_rows:
            net = _q(row.credits) - _q(row.debits)
            financing_items.append(CashFlowItem(label=row.name, amount=net))
            financing_net += net

        net_change = _q(operating_net + investing_net + financing_net)

        # Opening cash balance = cash+bank account balances at period start
        # (simplified: sum of ASSET account opening_balance as proxy)
        opening_cash = _q(
            db.query(func.coalesce(func.sum(Account.opening_balance), 0))
            .filter(Account.tenant_id == tenant_id, Account.account_type == "ASSET",
                    Account.deleted_at == None, Account.code.like("1%"))
            .scalar() or 0
        )

        return CashFlowResponse(
            period_start=start_date,
            period_end=end_date,
            operating_activities=CashFlowSection(
                section="Operating Activities",
                items=[
                    CashFlowItem(label="Net Profit / (Loss)", amount=net_profit),
                    CashFlowItem(label="Change in Accounts Receivable", amount=change_in_ar),
                    CashFlowItem(label="Change in Accounts Payable", amount=change_in_ap),
                ],
                net=operating_net,
            ),
            investing_activities=CashFlowSection(
                section="Investing Activities",
                items=investing_items if investing_items else [CashFlowItem(label="No investing activity", amount=ZERO)],
                net=_q(investing_net),
            ),
            financing_activities=CashFlowSection(
                section="Financing Activities",
                items=financing_items if financing_items else [CashFlowItem(label="No financing activity", amount=ZERO)],
                net=_q(financing_net),
            ),
            net_change_in_cash=net_change,
            opening_cash_balance=opening_cash,
            closing_cash_balance=_q(opening_cash + net_change),
        )


# ---------------------------------------------------------------------------
# Sales Analytics
# ---------------------------------------------------------------------------

class SalesAnalyticsService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date,
            top_n: int = 10) -> SalesAnalyticsResponse:
        invoices = (
            db.query(Invoice)
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
                Invoice.issue_date.between(start_date, end_date),
            )
            .all()
        )

        total_sales = ZERO
        total_tax = ZERO
        total_inv_val = ZERO
        contact_map: dict = {}

        for inv in invoices:
            taxable = _q(inv.subtotal) - _q(inv.discount_total)
            tax = _q(inv.cgst_amount) + _q(inv.sgst_amount) + _q(inv.igst_amount) + _q(inv.cess_amount)
            total = _q(inv.total)
            total_sales += taxable
            total_tax += tax
            total_inv_val += total

            cid = str(inv.contact_id)
            if cid not in contact_map:
                contact = db.get(Contact, inv.contact_id)
                contact_map[cid] = {
                    "contact_id": cid,
                    "contact_name": contact.name if contact else "Unknown",
                    "invoice_count": 0,
                    "total_sales": ZERO,
                    "total_tax": ZERO,
                    "total_invoiced": ZERO,
                }
            c = contact_map[cid]
            c["invoice_count"] += 1
            c["total_sales"] += taxable
            c["total_tax"] += tax
            c["total_invoiced"] += total

        top_customers = sorted(contact_map.values(), key=lambda x: x["total_invoiced"], reverse=True)[:top_n]

        return SalesAnalyticsResponse(
            period_start=start_date,
            period_end=end_date,
            total_sales=_q(total_sales),
            total_tax_collected=_q(total_tax),
            total_invoiced=_q(total_inv_val),
            invoice_count=len(invoices),
            top_customers=[TopCustomerLine(**c) for c in top_customers],
        )


# ---------------------------------------------------------------------------
# Purchase Analytics
# ---------------------------------------------------------------------------

class PurchaseAnalyticsService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date,
            top_n: int = 10) -> PurchaseAnalyticsResponse:
        bills = (
            db.query(Bill)
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.status.notin_(["DRAFT", "CANCELLED"]),
                Bill.issue_date.between(start_date, end_date),
            )
            .all()
        )

        total_purchases = ZERO
        total_tax = ZERO
        total_billed_val = ZERO
        vendor_map: dict = {}

        for bill in bills:
            # Bill model uses subtotal (already net of line discounts)
            taxable = _q(bill.subtotal)
            tax = _q(bill.cgst_amount) + _q(bill.sgst_amount) + _q(bill.igst_amount) + _q(bill.cess_amount)
            total = _q(bill.total)
            total_purchases += taxable
            total_tax += tax
            total_billed_val += total

            cid = str(bill.contact_id)
            if cid not in vendor_map:
                contact = db.get(Contact, bill.contact_id)
                vendor_map[cid] = {
                    "contact_id": cid,
                    "contact_name": contact.name if contact else "Unknown",
                    "bill_count": 0,
                    "total_purchases": ZERO,
                    "total_tax": ZERO,
                    "total_billed": ZERO,
                }
            v = vendor_map[cid]
            v["bill_count"] += 1
            v["total_purchases"] += taxable
            v["total_tax"] += tax
            v["total_billed"] += total

        top_vendors = sorted(vendor_map.values(), key=lambda x: x["total_billed"], reverse=True)[:top_n]

        return PurchaseAnalyticsResponse(
            period_start=start_date,
            period_end=end_date,
            total_purchases=_q(total_purchases),
            total_tax_paid=_q(total_tax),
            total_billed=_q(total_billed_val),
            bill_count=len(bills),
            top_vendors=[TopVendorLine(**v) for v in top_vendors],
        )


# ---------------------------------------------------------------------------
# Outstanding AR / AP
# ---------------------------------------------------------------------------

class OutstandingService:
    @staticmethod
    def get_ar(db: Session, tenant_id: uuid.UUID, as_of_date: date) -> OutstandingARResponse:
        invoices = (
            db.query(Invoice)
            .join(Contact, Invoice.contact_id == Contact.id)
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.status.notin_(["DRAFT", "CANCELLED", "PAID"]),
            )
            .order_by(Invoice.due_date.asc())
            .all()
        )

        lines = []
        total = ZERO
        for inv in invoices:
            outstanding = _q(inv.total) - _q(inv.amount_paid)
            if outstanding <= ZERO:
                continue
            contact = db.get(Contact, inv.contact_id)
            days_overdue = max(0, (as_of_date - inv.due_date).days)
            total += outstanding
            lines.append(OutstandingInvoiceLine(
                invoice_id=str(inv.id),
                invoice_number=inv.invoice_number,
                contact_name=contact.name if contact else "Unknown",
                issue_date=inv.issue_date,
                due_date=inv.due_date,
                total=_q(inv.total),
                amount_paid=_q(inv.amount_paid),
                outstanding=outstanding,
                days_overdue=days_overdue,
            ))

        return OutstandingARResponse(as_of_date=as_of_date, invoices=lines, total_outstanding=_q(total))

    @staticmethod
    def get_ap(db: Session, tenant_id: uuid.UUID, as_of_date: date) -> OutstandingAPResponse:
        bills = (
            db.query(Bill)
            .join(Contact, Bill.contact_id == Contact.id)
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.status.notin_(["DRAFT", "CANCELLED", "PAID"]),
            )
            .order_by(Bill.due_date.asc())
            .all()
        )

        lines = []
        total = ZERO
        for bill in bills:
            outstanding = _q(bill.total) - _q(bill.amount_paid)
            if outstanding <= ZERO:
                continue
            contact = db.get(Contact, bill.contact_id)
            days_overdue = max(0, (as_of_date - bill.due_date).days)
            total += outstanding
            lines.append(OutstandingBillLine(
                bill_id=str(bill.id),
                bill_number=bill.bill_number,
                contact_name=contact.name if contact else "Unknown",
                issue_date=bill.issue_date,
                due_date=bill.due_date,
                total=_q(bill.total),
                amount_paid=_q(bill.amount_paid),
                outstanding=outstanding,
                days_overdue=days_overdue,
            ))

        return OutstandingAPResponse(as_of_date=as_of_date, bills=lines, total_outstanding=_q(total))
