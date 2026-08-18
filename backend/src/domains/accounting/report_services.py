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

from sqlalchemy.orm import Session, joinedload
from sqlalchemy import func, case, and_, or_, cast, Numeric as SaNumeric

from src.infrastructure.database.models import (
    Invoice, InvoiceLine, Bill, BillLine,
    Contact, Account, JournalEntry, JournalLine,
    Payment, BillPayment, CreditNote, DebitNote,
    Expense
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
    PartyStatementRow, PartyStatementSummary, PartyStatementResponse,
    TrialBalanceLine, TrialBalanceResponse,
    CashBookResponse, CashBookRow, CashBookSummary, CashBookTaxSummary,
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
# Trial Balance
# ---------------------------------------------------------------------------

class TrialBalanceService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, as_of_date: date) -> TrialBalanceResponse:
        """
        Compiles the Trial Balance as of a specific date.
        Shows ALL account types (Asset, Liability, Equity, Revenue, Expense)
        with opening balance, period debits, period credits, and closing balance.
        """
        fy_year = as_of_date.year if as_of_date.month >= 4 else as_of_date.year - 1
        fy_start = date(fy_year, 4, 1)

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
                Account.deleted_at == None,
            )
            .group_by(Account.id, Account.name, Account.code, Account.account_type, Account.opening_balance)
            .order_by(Account.account_type.asc(), Account.code.asc())
            .all()
        )

        lines = []
        total_debits = ZERO
        total_credits = ZERO

        for row in rows:
            op = _q(row.opening_balance)
            deb = _q(row.debits)
            cred = _q(row.credits)
            acc_type = row.account_type

            if acc_type in ("ASSET", "EXPENSE"):
                closing = op + deb - cred
                direction = "DEBIT" if closing >= 0 else "CREDIT"
            else:
                closing = op + cred - deb
                direction = "CREDIT" if closing >= 0 else "DEBIT"

            abs_closing = abs(closing)
            if acc_type in ("ASSET", "EXPENSE"):
                total_debits += abs_closing if direction == "DEBIT" else ZERO
                total_credits += abs_closing if direction == "CREDIT" else ZERO
            else:
                total_credits += abs_closing if direction == "CREDIT" else ZERO
                total_debits += abs_closing if direction == "DEBIT" else ZERO

            lines.append(TrialBalanceLine(
                account_name=row.name,
                account_code=row.code,
                account_type=acc_type,
                opening_balance=op,
                period_debits=deb,
                period_credits=cred,
                closing_balance=abs_closing,
                closing_direction=direction,
            ))

        return TrialBalanceResponse(
            as_of_date=as_of_date,
            lines=lines,
            total_debits=_q(total_debits),
            total_credits=_q(total_credits),
            # A trial balance is balanced only when debits exactly equal
            # credits. Tolerating a paise hides real breaks; the DB-level
            # journal-line balance trigger (apex_guard_journal_entries_balance)
            # is the backstop that prevents unbalanced entries from existing.
            is_balanced=_q(total_debits) == _q(total_credits),
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
            .outerjoin(JournalLine, Account.id == JournalLine.account_id)
            .outerjoin(JournalEntry, JournalLine.entry_id == JournalEntry.id)
            .filter(
                Account.tenant_id == tenant_id,
                Account.account_type.in_(["REVENUE", "EXPENSE"]),
                Account.deleted_at == None,
                JournalEntry.entry_date >= start_date,
                JournalEntry.entry_date <= end_date,
                JournalEntry.source_type != "YEAR_END_CLOSING",
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
        # Get origin state code for inter-state detection
        from src.domains.company.services import resolve_origin_state_code
        origin_state = resolve_origin_state_code(db, tenant_id)

        invoices = (
            db.query(Invoice)
            .options(
                joinedload(Invoice.contact),
                joinedload(Invoice.lines).joinedload(InvoiceLine.product),
            )
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
                Invoice.deleted_at == None,
                Invoice.issue_date >= start_date,
                Invoice.issue_date <= end_date,
            )
            .all()
        )

        b2b_map: dict = {}
        b2cl_map: dict = {}
        b2cs_map: dict = {}
        hsn_map: dict = {}
        rcm_list: list = []
        exports_list: list = []
        total_taxable = ZERO
        total_cgst = ZERO
        total_sgst = ZERO
        total_igst = ZERO
        total_cess = ZERO
        total_invoice_val = ZERO

        for inv in invoices:
            contact = inv.contact
            taxable = _q(inv.subtotal) - _q(inv.discount_total)
            cgst = _q(inv.cgst_amount)
            sgst = _q(inv.sgst_amount)
            igst = _q(inv.igst_amount)
            cess = _q(inv.cess_amount)
            inv_total = _q(inv.total)
            total_tax = _q(cgst + sgst + igst + cess)

            # Export invoices go to Table 6A
            if inv.supply_type and inv.supply_type.startswith("EXPORT"):
                exports_list.append({
                    "invoice_number": inv.invoice_number,
                    "invoice_date": str(inv.issue_date),
                    "supply_type": inv.supply_type,
                    "taxable_value": str(taxable),
                    "igst": str(igst),
                    "cess": str(cess),
                    "total": str(inv_total),
                    "port_code": getattr(inv, 'port_code', None),
                    "shipping_bill_number": getattr(inv, 'shipping_bill_number', None),
                })
                total_taxable += taxable
                total_igst += igst
                total_cess += cess
                total_invoice_val += inv_total
                continue

            # RCM invoices go to Table 4B, not into standard buckets
            if inv.is_rcm:
                rcm_list.append({
                    "invoice_number": inv.invoice_number,
                    "invoice_date": str(inv.issue_date),
                    "receiver_gstin": contact.gstin if contact else None,
                    "receiver_name": contact.name if contact else "Unknown",
                    "taxable_value": str(taxable),
                    "igst": str(igst),
                    "cgst": str(cgst),
                    "sgst": str(sgst),
                    "cess": str(cess),
                    "total": str(inv_total),
                })
                continue

            total_taxable += taxable
            total_cgst += cgst
            total_sgst += sgst
            total_igst += igst
            total_cess += cess
            total_invoice_val += inv_total

            is_registered = bool(contact and contact.gstin)
            is_inter_state = (inv.pos_state_code and inv.pos_state_code != origin_state)

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
                    # B2CS: Aggregate at line level by (gst_rate, pos_state_code)
                    for line in inv.lines:
                        line_taxable = _q(line.subtotal)
                        line_cgst = _q(line.cgst_amount)
                        line_sgst = _q(line.sgst_amount)
                        line_igst = _q(line.igst_amount)
                        line_cess = _q(line.cess_amount)
                        eff_rate = _q(line.gst_rate)
                        b2cs_key = f"{eff_rate}_{inv.pos_state_code}"
                        if b2cs_key not in b2cs_map:
                            b2cs_map[b2cs_key] = {
                                "gst_rate": eff_rate,
                                "place_of_supply": inv.pos_state_code or "",
                                "taxable_value": ZERO,
                                "cgst": ZERO, "sgst": ZERO, "igst": ZERO, "cess": ZERO,
                            }
                        b2cs_map[b2cs_key]["taxable_value"] += line_taxable
                        b2cs_map[b2cs_key]["cgst"] += line_cgst
                        b2cs_map[b2cs_key]["sgst"] += line_sgst
                        b2cs_map[b2cs_key]["igst"] += line_igst
                        b2cs_map[b2cs_key]["cess"] += line_cess

            # HSN summary (line level)
            for line in inv.lines:
                key = line.hsn_sac
                uom = "PCS"
                if line.product:
                    uom = line.product.uom or "PCS"
                if key not in hsn_map:
                    hsn_map[key] = {
                        "hsn_sac": key,
                        "uom": uom,
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
            rcm_invoices=rcm_list if rcm_list else None,
            exports=exports_list if exports_list else None,
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
                Bill.deleted_at == None,
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
            if not bill.itc_eligible:
                continue
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
                Invoice.deleted_at == None,
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
                Bill.deleted_at == None,
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
            if due is None:
                due = getattr(doc, "issue_date", as_of_date)
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

        # Change in AR: invoiced this period vs cash collected this period
        ar_invoiced = _q(
            db.query(func.coalesce(func.sum(Invoice.total), 0))
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.issue_date.between(start_date, end_date),
                Invoice.status.notin_(["DRAFT", "CANCELLED"]),
                Invoice.deleted_at == None,
            )
            .scalar() or 0
        )
        ar_collected = _q(
            db.query(func.coalesce(func.sum(Payment.amount), 0))
            .filter(
                Payment.tenant_id == tenant_id,
                Payment.payment_date.between(start_date, end_date),
                Payment.status == "ACTIVE",
                Payment.deleted_at == None,
            )
            .scalar() or 0
        )
        change_in_ar = ar_collected - ar_invoiced  # negative = increase in AR

        # Change in AP: billed this period vs cash paid this period
        ap_billed = _q(
            db.query(func.coalesce(func.sum(Bill.total), 0))
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.issue_date.between(start_date, end_date),
                Bill.status.notin_(["DRAFT", "CANCELLED"]),
                Bill.deleted_at == None,
            )
            .scalar() or 0
        )
        ap_paid = _q(
            db.query(func.coalesce(func.sum(BillPayment.amount), 0))
            .filter(
                BillPayment.tenant_id == tenant_id,
                BillPayment.payment_date.between(start_date, end_date),
                BillPayment.status == "ACTIVE",
                BillPayment.deleted_at == None,
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
                Account.code.notlike("CASH%"),
                Account.code.notlike("BANK%"),
                Account.code.notlike("UPI%"),
                Account.code.notlike("POS%"),
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
                    Account.deleted_at == None,
                    Account.code.in_(["CASH", "BANK", "UPI", "POS"]))
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
        # Aggregate totals in SQL
        totals = db.query(
            func.coalesce(func.sum(Invoice.subtotal - Invoice.discount_total), 0).label("total_sales"),
            func.coalesce(func.sum(Invoice.cgst_amount + Invoice.sgst_amount + Invoice.igst_amount + Invoice.cess_amount), 0).label("total_tax"),
            func.coalesce(func.sum(Invoice.total), 0).label("total_invoiced"),
            func.count(Invoice.id).label("invoice_count"),
        ).filter(
            Invoice.tenant_id == tenant_id,
            Invoice.status.notin_(["DRAFT", "CANCELLED"]),
            Invoice.deleted_at == None,
            Invoice.issue_date.between(start_date, end_date),
        ).first()

        # Top customers via SQL GROUP BY
        top_customers_q = db.query(
            Contact.id.label("contact_id"),
            Contact.name.label("contact_name"),
            func.count(Invoice.id).label("invoice_count"),
            func.coalesce(func.sum(Invoice.subtotal - Invoice.discount_total), 0).label("total_sales"),
            func.coalesce(func.sum(Invoice.cgst_amount + Invoice.sgst_amount + Invoice.igst_amount + Invoice.cess_amount), 0).label("total_tax"),
            func.coalesce(func.sum(Invoice.total), 0).label("total_invoiced"),
        ).join(Invoice, Invoice.contact_id == Contact.id).filter(
            Invoice.tenant_id == tenant_id,
            Invoice.status.notin_(["DRAFT", "CANCELLED"]),
            Invoice.deleted_at == None,
            Invoice.issue_date.between(start_date, end_date),
        ).group_by(Contact.id, Contact.name).order_by(
            func.sum(Invoice.total).desc()
        ).limit(top_n).all()

        top_customers = [
            TopCustomerLine(
                contact_id=str(row.contact_id),
                contact_name=row.contact_name,
                invoice_count=row.invoice_count,
                total_sales=_q(row.total_sales),
                total_tax=_q(row.total_tax),
                total_invoiced=_q(row.total_invoiced),
            )
            for row in top_customers_q
        ]

        return SalesAnalyticsResponse(
            period_start=start_date,
            period_end=end_date,
            total_sales=_q(totals.total_sales),
            total_tax_collected=_q(totals.total_tax),
            total_invoiced=_q(totals.total_invoiced),
            invoice_count=totals.invoice_count,
            top_customers=top_customers,
        )


# ---------------------------------------------------------------------------
# Purchase Analytics
# ---------------------------------------------------------------------------

class PurchaseAnalyticsService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date,
            top_n: int = 10) -> PurchaseAnalyticsResponse:
        # Aggregate totals in SQL
        totals = db.query(
            func.coalesce(func.sum(Bill.subtotal), 0).label("total_purchases"),
            func.coalesce(func.sum(Bill.cgst_amount + Bill.sgst_amount + Bill.igst_amount + Bill.cess_amount), 0).label("total_tax"),
            func.coalesce(func.sum(Bill.total), 0).label("total_billed"),
            func.count(Bill.id).label("bill_count"),
        ).filter(
            Bill.tenant_id == tenant_id,
            Bill.status.notin_(["DRAFT", "CANCELLED"]),
            Bill.deleted_at == None,
            Bill.issue_date.between(start_date, end_date),
        ).first()

        # Top vendors via SQL GROUP BY
        top_vendors_q = db.query(
            Contact.id.label("contact_id"),
            Contact.name.label("contact_name"),
            func.count(Bill.id).label("bill_count"),
            func.coalesce(func.sum(Bill.subtotal), 0).label("total_purchases"),
            func.coalesce(func.sum(Bill.cgst_amount + Bill.sgst_amount + Bill.igst_amount + Bill.cess_amount), 0).label("total_tax"),
            func.coalesce(func.sum(Bill.total), 0).label("total_billed"),
        ).join(Bill, Bill.contact_id == Contact.id).filter(
            Bill.tenant_id == tenant_id,
            Bill.status.notin_(["DRAFT", "CANCELLED"]),
            Bill.deleted_at == None,
            Bill.issue_date.between(start_date, end_date),
        ).group_by(Contact.id, Contact.name).order_by(
            func.sum(Bill.total).desc()
        ).limit(top_n).all()

        top_vendors = [
            TopVendorLine(
                contact_id=str(row.contact_id),
                contact_name=row.contact_name,
                bill_count=row.bill_count,
                total_purchases=_q(row.total_purchases),
                total_tax=_q(row.total_tax),
                total_billed=_q(row.total_billed),
            )
            for row in top_vendors_q
        ]

        return PurchaseAnalyticsResponse(
            period_start=start_date,
            period_end=end_date,
            total_purchases=_q(totals.total_purchases),
            total_tax_paid=_q(totals.total_tax),
            total_billed=_q(totals.total_billed),
            bill_count=totals.bill_count,
            top_vendors=top_vendors,
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
                Invoice.deleted_at == None,
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
                Bill.deleted_at == None,
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


class PartyStatementService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, contact_id: uuid.UUID, start_date: date, end_date: date) -> PartyStatementResponse:
        contact = db.get(Contact, contact_id)
        if not contact or contact.tenant_id != tenant_id or contact.deleted_at is not None:
            raise ValueError("Contact not found")

        # 1. Opening Balance Calculation (transactions before start_date)
        inv_before = db.query(func.coalesce(func.sum(Invoice.total), 0)).filter(
            Invoice.tenant_id == tenant_id,
            Invoice.contact_id == contact_id,
            Invoice.issue_date < start_date,
            Invoice.status.notin_(["DRAFT", "CANCELLED"]),
            Invoice.deleted_at == None
        ).scalar()
        
        pay_before = db.query(func.coalesce(func.sum(Payment.amount), 0)).filter(
            Payment.tenant_id == tenant_id,
            Payment.contact_id == contact_id,
            Payment.payment_date < start_date,
            Payment.status == "ACTIVE",
            Payment.deleted_at == None
        ).scalar()

        bill_before = db.query(func.coalesce(func.sum(Bill.total), 0)).filter(
            Bill.tenant_id == tenant_id,
            Bill.contact_id == contact_id,
            Bill.issue_date < start_date,
            Bill.status.notin_(["DRAFT", "CANCELLED"]),
            Bill.deleted_at == None
        ).scalar()

        bp_before = db.query(func.coalesce(func.sum(BillPayment.amount), 0)).filter(
            BillPayment.tenant_id == tenant_id,
            BillPayment.contact_id == contact_id,
            BillPayment.payment_date < start_date,
            BillPayment.status == "ACTIVE",
            BillPayment.deleted_at == None
        ).scalar()

        # Credit Notes reduce AR (customer owes less)
        cn_before = db.query(func.coalesce(func.sum(CreditNote.total), 0)).join(
            Invoice, CreditNote.invoice_id == Invoice.id
        ).filter(
            CreditNote.tenant_id == tenant_id,
            Invoice.contact_id == contact_id,
            CreditNote.issue_date < start_date,
            CreditNote.status.notin_(["DRAFT", "CANCELLED"]),
            CreditNote.deleted_at == None
        ).scalar()

        # Debit Notes increase AR (customer owes more)
        dn_before = db.query(func.coalesce(func.sum(DebitNote.total), 0)).join(
            Invoice, DebitNote.invoice_id == Invoice.id
        ).filter(
            DebitNote.tenant_id == tenant_id,
            Invoice.contact_id == contact_id,
            DebitNote.issue_date < start_date,
            DebitNote.status.notin_(["DRAFT", "CANCELLED"]),
            DebitNote.deleted_at == None
        ).scalar()

        debits_before = _q(inv_before) + _q(bp_before) + _q(dn_before)
        credits_before = _q(pay_before) + _q(bill_before) + _q(cn_before)
        opening_balance = debits_before - credits_before

        # 2. Get all transactions during the period
        invoices = db.query(Invoice).filter(
            Invoice.tenant_id == tenant_id,
            Invoice.contact_id == contact_id,
            Invoice.issue_date >= start_date,
            Invoice.issue_date <= end_date,
            Invoice.status.notin_(["DRAFT", "CANCELLED"]),
            Invoice.deleted_at == None
        ).all()

        payments = db.query(Payment).filter(
            Payment.tenant_id == tenant_id,
            Payment.contact_id == contact_id,
            Payment.payment_date >= start_date,
            Payment.payment_date <= end_date,
            Payment.status == "ACTIVE",
            Payment.deleted_at == None
        ).all()

        bills = db.query(Bill).filter(
            Bill.tenant_id == tenant_id,
            Bill.contact_id == contact_id,
            Bill.issue_date >= start_date,
            Bill.issue_date <= end_date,
            Bill.status.notin_(["DRAFT", "CANCELLED"]),
            Bill.deleted_at == None
        ).all()

        bill_payments = db.query(BillPayment).filter(
            BillPayment.tenant_id == tenant_id,
            BillPayment.contact_id == contact_id,
            BillPayment.payment_date >= start_date,
            BillPayment.payment_date <= end_date,
            BillPayment.status == "ACTIVE",
            BillPayment.deleted_at == None
        ).all()

        # Credit Notes and Debit Notes for this contact
        credit_notes = db.query(CreditNote).join(
            Invoice, CreditNote.invoice_id == Invoice.id
        ).filter(
            CreditNote.tenant_id == tenant_id,
            Invoice.contact_id == contact_id,
            CreditNote.issue_date >= start_date,
            CreditNote.issue_date <= end_date,
            CreditNote.status.notin_(["DRAFT", "CANCELLED"]),
            CreditNote.deleted_at == None
        ).all()

        debit_notes = db.query(DebitNote).join(
            Invoice, DebitNote.invoice_id == Invoice.id
        ).filter(
            DebitNote.tenant_id == tenant_id,
            Invoice.contact_id == contact_id,
            DebitNote.issue_date >= start_date,
            DebitNote.issue_date <= end_date,
            DebitNote.status.notin_(["DRAFT", "CANCELLED"]),
            DebitNote.deleted_at == None
        ).all()

        raw_ledger = []
        for x in invoices:
            raw_ledger.append({
                "date": x.issue_date,
                "particulars": "Sales Invoice",
                "voucher_type": "Sales",
                "voucher_no": x.invoice_number,
                "debit": _q(x.total),
                "credit": None,
            })
        for x in payments:
            raw_ledger.append({
                "date": x.payment_date,
                "particulars": "Receipt Received",
                "voucher_type": "Receipt",
                "voucher_no": x.payment_number,
                "debit": None,
                "credit": _q(x.amount),
            })
        for x in bills:
            raw_ledger.append({
                "date": x.issue_date,
                "particulars": "Purchase Bill",
                "voucher_type": "Purchase",
                "voucher_no": x.bill_number,
                "debit": None,
                "credit": _q(x.total),
            })
        for x in bill_payments:
            raw_ledger.append({
                "date": x.payment_date,
                "particulars": "Payment Made",
                "voucher_type": "Payment",
                "voucher_no": x.payment_number,
                "debit": _q(x.amount),
                "credit": None,
            })
        for x in credit_notes:
            raw_ledger.append({
                "date": x.issue_date,
                "particulars": "Credit Note",
                "voucher_type": "Credit Note",
                "voucher_no": x.credit_note_number,
                "debit": None,
                "credit": _q(x.total),
            })
        for x in debit_notes:
            raw_ledger.append({
                "date": x.issue_date,
                "particulars": "Debit Note",
                "voucher_type": "Debit Note",
                "voucher_no": x.debit_note_number,
                "debit": _q(x.total),
                "credit": None,
            })

        # Sort chronologically by date
        raw_ledger.sort(key=lambda item: (item["date"], item["voucher_type"], item["voucher_no"]))

        # Build final ledger rows with running balance
        running_balance = opening_balance
        ledger_rows = []

        def format_bal(val: Decimal) -> str:
            if val >= ZERO:
                return f"{abs(val):,.2f} Dr"
            else:
                return f"{abs(val):,.2f} Cr"

        # Add initial Opening Balance row
        op_row = PartyStatementRow(
            date=start_date,
            particulars="Opening Balance",
            voucher_type="Opening",
            voucher_no="-",
            debit=abs(opening_balance) if opening_balance >= ZERO else None,
            credit=abs(opening_balance) if opening_balance < ZERO else None,
            balance=format_bal(opening_balance)
        )
        ledger_rows.append(op_row)

        total_sales = ZERO
        total_receipts = ZERO
        total_purchases = ZERO
        total_payments = ZERO

        for item in raw_ledger:
            deb = item["debit"]
            cred = item["credit"]
            if deb is not None:
                running_balance += deb
                if item["voucher_type"] == "Sales":
                    total_sales += deb
                elif item["voucher_type"] == "Payment":
                    total_payments += deb
            if cred is not None:
                running_balance -= cred
                if item["voucher_type"] == "Receipt":
                    total_receipts += cred
                elif item["voucher_type"] == "Purchase":
                    total_purchases += cred

            ledger_rows.append(PartyStatementRow(
                date=item["date"],
                particulars=item["particulars"],
                voucher_type=item["voucher_type"],
                voucher_no=item["voucher_no"],
                debit=deb,
                credit=cred,
                balance=format_bal(running_balance)
            ))

        # Add Closing Balance row
        cl_row = PartyStatementRow(
            date=end_date,
            particulars="Closing Balance",
            voucher_type="-",
            voucher_no="-",
            debit=None,
            credit=None,
            balance=format_bal(running_balance)
        )
        ledger_rows.append(cl_row)

        summary = PartyStatementSummary(
            opening_balance=abs(opening_balance),
            total_sales=total_sales,
            total_receipts=total_receipts,
            total_purchases=total_purchases,
            total_payments=total_payments,
            closing_outstanding=abs(running_balance)
        )

        billing_addr = contact.billing_address or {}
        address_parts = []
        if isinstance(billing_addr, dict):
            for k in ["address_line1", "address_line2", "city", "state", "postal_code"]:
                if billing_addr.get(k):
                    address_parts.append(str(billing_addr[k]))
        addr_str = ", ".join(address_parts) if address_parts else None

        return PartyStatementResponse(
            contact_id=str(contact.id),
            contact_name=contact.name,
            contact_type=contact.contact_type,
            address=addr_str,
            gstin=contact.gstin,
            phone=contact.phone,
            start_date=start_date,
            end_date=end_date,
            ledger=ledger_rows,
            summary=summary
        )


# ---------------------------------------------------------------------------
# Cash Book Report
# ---------------------------------------------------------------------------

class CashBookService:
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date) -> CashBookResponse:
        # Provisioned accounts use numeric codes (1001 Cash on Hand, 1003 UPI,
        # 1004 POS, 1005 Petty Cash), while imported/custom charts may retain
        # the historical CASH* convention.  Select by the accounting group as
        # well as the legacy code so the register reflects real journal lines.
        return CashBookService._get_register(db, tenant_id, start_date, end_date, "cash")

    @staticmethod
    def _get_register(
        db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date, register_kind: str
    ) -> CashBookResponse:
        if register_kind == "cash":
            register_filter = or_(
                Account.code.like("CASH%"),
                Account.code.in_(["1001", "1003", "1004", "1005"]),
                and_(
                    Account.account_group == "Cash & Bank",
                    ~Account.name.ilike("%bank%"),
                ),
            )
        else:
            register_filter = or_(
                Account.code.like("BANK%"),
                Account.code == "1002",
                and_(
                    Account.account_group == "Cash & Bank",
                    Account.name.ilike("%bank%"),
                ),
            )

        accounts = db.query(Account).filter(
            Account.tenant_id == tenant_id,
            Account.deleted_at == None,
            register_filter,
        ).all()
        account_ids = [a.id for a in accounts]

        op_bal_base = sum(a.opening_balance for a in accounts)

        if not account_ids:
            return CashBookResponse(
                period_start=start_date,
                period_end=end_date,
                opening_balance=ZERO,
                inflows=[],
                outflows=[],
                summary=CashBookSummary(cash_inflow=ZERO, cash_outflow=ZERO, closing_balance=ZERO, actual_cash_in_hand=ZERO, difference=ZERO),
                tax_summary=CashBookTaxSummary(tax_paid=ZERO, tax_received=ZERO, tax_payable=ZERO)
            )

        past_journals = db.query(
            func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)).label("debits"),
            func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)).label("credits")
        ).join(JournalEntry, JournalLine.entry_id == JournalEntry.id).filter(
            JournalLine.account_id.in_(account_ids),
            JournalEntry.entry_date < start_date
        ).first()

        op_debits = _q(past_journals.debits if past_journals and past_journals.debits else 0)
        op_credits = _q(past_journals.credits if past_journals and past_journals.credits else 0)
        opening_balance = _q(op_bal_base) + op_debits - op_credits

        lines = db.query(JournalLine, JournalEntry).join(
            JournalEntry, JournalLine.entry_id == JournalEntry.id
        ).filter(
            JournalLine.account_id.in_(account_ids),
            JournalEntry.entry_date.between(start_date, end_date)
        ).order_by(JournalEntry.entry_date.asc(), JournalEntry.created_at.asc()).all()

        inflows = []
        outflows = []
        total_inflow = ZERO
        total_outflow = ZERO
        tax_paid = ZERO
        tax_received = ZERO

        for jl, je in lines:
            amt = _q(jl.amount)
            tax_amt = ZERO
            inv_amt = amt

            if je.source_type == "INVOICE" and je.source_id:
                inv = db.query(Invoice).filter_by(id=je.source_id).first()
                if inv:
                    tax_amt = _q(inv.cgst_amount) + _q(inv.sgst_amount) + _q(inv.igst_amount) + _q(inv.cess_amount)
                    inv_amt = _q(inv.total)
            elif je.source_type == "BILL" and je.source_id:
                bill = db.query(Bill).filter_by(id=je.source_id).first()
                if bill:
                    tax_amt = _q(bill.cgst_amount) + _q(bill.sgst_amount) + _q(bill.igst_amount) + _q(bill.cess_amount)
                    inv_amt = _q(bill.total)
            elif je.source_type == "EXPENSE" and je.source_id:
                exp = db.query(Expense).filter_by(id=je.source_id).first()
                if exp:
                    tax_amt = _q(exp.cgst_amount) + _q(exp.sgst_amount) + _q(exp.igst_amount) + _q(exp.cess_amount)
                    inv_amt = _q(exp.total)

            row = CashBookRow(
                date=je.entry_date,
                transaction_details=je.description or je.reference_number or "Cash Transaction",
                invoice_amount=inv_amt if tax_amt > ZERO else None,
                tax_amount=tax_amt if tax_amt > ZERO else None,
                amount=amt
            )

            if jl.direction == "DEBIT":
                inflows.append(row)
                total_inflow += amt
                tax_received += tax_amt
            else:
                outflows.append(row)
                total_outflow += amt
                tax_paid += tax_amt

        closing_balance = opening_balance + total_inflow - total_outflow

        return CashBookResponse(
            period_start=start_date,
            period_end=end_date,
            opening_balance=opening_balance,
            inflows=inflows,
            outflows=outflows,
            summary=CashBookSummary(
                cash_inflow=total_inflow,
                cash_outflow=total_outflow,
                closing_balance=closing_balance,
                actual_cash_in_hand=closing_balance,
                difference=ZERO
            ),
            tax_summary=CashBookTaxSummary(
                tax_paid=tax_paid,
                tax_received=tax_received,
                tax_payable=max(ZERO, tax_received - tax_paid)
            )
        )


class BankBookService:
    """Bank Book: tracks bank account inflows and outflows."""
    @staticmethod
    def get(db: Session, tenant_id: uuid.UUID, start_date: date, end_date: date) -> CashBookResponse:
        return CashBookService._get_register(db, tenant_id, start_date, end_date, "bank")
