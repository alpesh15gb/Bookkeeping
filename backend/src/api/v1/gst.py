from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
from datetime import date
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import Invoice, Bill, CreditNote, DebitNote, Contact, Tenant, TenantSetting
from src.schemas.gst_schemas import (
    GSTR1Response, GSTR1B2BLine, GSTR1B2CLine, GSTR1B2CSLine, GSTR1NoteLine, GSTR1HSNLine,
    GSTR2Response, GSTR2B2BLine
)
from src.domains.company.services import resolve_origin_state_code
from src.api.deps import enforce_permission

router = APIRouter(prefix="/gst", tags=["GST Compliance"])

@router.get("/gstr1", response_model=GSTR1Response)
def get_gstr1_report(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Compiles GSTR-1 outward supply sales tax returns for a given period."""
    # 1. Fetch tenant origin state code
    origin_state_code = resolve_origin_state_code(db, tenant_id)

    # 2. Fetch finalized sales invoices
    q_inv = db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.status.in_(["SENT", "PARTIALLY_PAID", "PAID"]),
        Invoice.deleted_at == None
    )
    if start_date:
        q_inv = q_inv.filter(Invoice.issue_date >= start_date)
    if end_date:
        q_inv = q_inv.filter(Invoice.issue_date <= end_date)
    invoices = q_inv.all()

    b2b_lines = []
    b2cl_lines = []
    b2cs_groups = {}  # key: (pos_state_code, gst_rate)
    hsn_groups = {}  # key: hsn_sac

    for inv in invoices:
        contact = inv.contact
        is_registered = contact and contact.gstin

        if is_registered:
            # Section 4: B2B registered sales
            b2b_lines.append(
                GSTR1B2BLine(
                    customer_name=contact.name,
                    customer_gstin=contact.gstin,
                    invoice_number=inv.invoice_number,
                    invoice_date=inv.issue_date,
                    pos_state_code=inv.pos_state_code,
                    taxable_value=inv.subtotal,
                    cgst_amount=inv.cgst_amount,
                    sgst_amount=inv.sgst_amount,
                    igst_amount=inv.igst_amount,
                    utgst_amount=inv.utgst_amount,
                    cess_amount=inv.cess_amount,
                    total_value=inv.total
                )
            )
        else:
            # Section 5 & 7: Unregistered Sales (B2C)
            is_inter_state = (inv.pos_state_code != origin_state_code)
            if is_inter_state and inv.total > Decimal("250000.00"):
                # B2C Large (Inter-state, > 2.5L total)
                b2cl_lines.append(
                    GSTR1B2CLine(
                        invoice_number=inv.invoice_number,
                        invoice_date=inv.issue_date,
                        pos_state_code=inv.pos_state_code,
                        taxable_value=inv.subtotal,
                        igst_amount=inv.igst_amount,
                        total_value=inv.total
                    )
                )
            else:
                # B2C Small (All other unregistered)
                for line in inv.lines:
                    key = (inv.pos_state_code, line.gst_rate)
                    if key not in b2cs_groups:
                        b2cs_groups[key] = {
                            "taxable_value": Decimal("0.0000"),
                            "cgst_amount": Decimal("0.0000"),
                            "sgst_amount": Decimal("0.0000"),
                            "igst_amount": Decimal("0.0000"),
                            "utgst_amount": Decimal("0.0000"),
                            "cess_amount": Decimal("0.0000")
                        }
                    b2cs_groups[key]["taxable_value"] += line.subtotal
                    b2cs_groups[key]["cgst_amount"] += line.cgst_amount
                    b2cs_groups[key]["sgst_amount"] += line.sgst_amount
                    b2cs_groups[key]["igst_amount"] += line.igst_amount
                    b2cs_groups[key]["utgst_amount"] += line.utgst_amount
                    b2cs_groups[key]["cess_amount"] += line.cess_amount

        # Section 12: HSN Summary aggregation
        for line in inv.lines:
            hsn = line.hsn_sac
            product = line.product
            desc = product.name if product else "N/A"
            uom = product.uom if product else "PCS"

            if hsn not in hsn_groups:
                hsn_groups[hsn] = {
                    "description": desc,
                    "uom": uom,
                    "total_quantity": Decimal("0.0000"),
                    "total_value": Decimal("0.0000"),
                    "taxable_value": Decimal("0.0000"),
                    "cgst_amount": Decimal("0.0000"),
                    "sgst_amount": Decimal("0.0000"),
                    "igst_amount": Decimal("0.0000"),
                    "utgst_amount": Decimal("0.0000"),
                    "cess_amount": Decimal("0.0000")
                }
            hsn_groups[hsn]["total_quantity"] += line.quantity
            hsn_groups[hsn]["total_value"] += line.total
            hsn_groups[hsn]["taxable_value"] += line.subtotal
            hsn_groups[hsn]["cgst_amount"] += line.cgst_amount
            hsn_groups[hsn]["sgst_amount"] += line.sgst_amount
            hsn_groups[hsn]["igst_amount"] += line.igst_amount
            hsn_groups[hsn]["utgst_amount"] += line.utgst_amount
            hsn_groups[hsn]["cess_amount"] += line.cess_amount

    b2cs_lines = [
        GSTR1B2CSLine(
            pos_state_code=k[0],
            gst_rate=k[1],
            taxable_value=v["taxable_value"],
            cgst_amount=v["cgst_amount"],
            sgst_amount=v["sgst_amount"],
            igst_amount=v["igst_amount"],
            utgst_amount=v["utgst_amount"],
            cess_amount=v["cess_amount"]
        )
        for k, v in b2cs_groups.items()
    ]

    hsn_lines = [
        GSTR1HSNLine(
            hsn_sac=hsn,
            description=v["description"],
            uom=v["uom"],
            total_quantity=v["total_quantity"],
            total_value=v["total_value"],
            taxable_value=v["taxable_value"],
            cgst_amount=v["cgst_amount"],
            sgst_amount=v["sgst_amount"],
            igst_amount=v["igst_amount"],
            utgst_amount=v["utgst_amount"],
            cess_amount=v["cess_amount"]
        )
        for hsn, v in hsn_groups.items()
    ]

    # 2. Fetch finalized Credit and Debit Notes
    q_cn = db.query(CreditNote).filter(
        CreditNote.tenant_id == tenant_id,
        CreditNote.status == "ISSUED",
        CreditNote.deleted_at == None
    )
    if start_date:
        q_cn = q_cn.filter(CreditNote.issue_date >= start_date)
    if end_date:
        q_cn = q_cn.filter(CreditNote.issue_date <= end_date)
    credit_notes = q_cn.all()

    q_dn = db.query(DebitNote).filter(
        DebitNote.tenant_id == tenant_id,
        DebitNote.status == "ISSUED",
        DebitNote.deleted_at == None
    )
    if start_date:
        q_dn = q_dn.filter(DebitNote.issue_date >= start_date)
    if end_date:
        q_dn = q_dn.filter(DebitNote.issue_date <= end_date)
    debit_notes = q_dn.all()

    cdnr_lines = []
    cdnur_lines = []

    # Process Credit Notes (Section 9B CDNR/CDNUR)
    for cn in credit_notes:
        invoice = cn.invoice
        contact = invoice.contact if invoice else None
        is_registered = contact and contact.gstin

        note_line = GSTR1NoteLine(
            note_number=cn.credit_note_number,
            note_date=cn.issue_date,
            note_type="CREDIT",
            invoice_number=invoice.invoice_number if invoice else None,
            customer_gstin=contact.gstin if is_registered else None,
            reason=cn.reason,
            taxable_value=cn.subtotal,
            cgst_amount=cn.cgst_amount,
            sgst_amount=cn.sgst_amount,
            igst_amount=cn.igst_amount,
            utgst_amount=cn.utgst_amount,
            cess_amount=cn.cess_amount,
            total_value=cn.total
        )
        if is_registered:
            cdnr_lines.append(note_line)
        else:
            cdnur_lines.append(note_line)

    # Process Debit Notes (Section 9B CDNR/CDNUR)
    for dn in debit_notes:
        invoice = dn.invoice
        contact = invoice.contact if invoice else None
        is_registered = contact and contact.gstin

        note_line = GSTR1NoteLine(
            note_number=dn.debit_note_number,
            note_date=dn.issue_date,
            note_type="DEBIT",
            invoice_number=invoice.invoice_number if invoice else None,
            customer_gstin=contact.gstin if is_registered else None,
            reason=dn.reason,
            taxable_value=dn.subtotal,
            cgst_amount=dn.cgst_amount,
            sgst_amount=dn.sgst_amount,
            igst_amount=dn.igst_amount,
            utgst_amount=dn.utgst_amount,
            cess_amount=dn.cess_amount,
            total_value=dn.total
        )
        if is_registered:
            cdnr_lines.append(note_line)
        else:
            cdnur_lines.append(note_line)

    return GSTR1Response(
        b2b=b2b_lines,
        b2cl=b2cl_lines,
        b2cs=b2cs_lines,
        cdnr=cdnr_lines,
        cdnur=cdnur_lines,
        hsn_summary=hsn_lines
    )

@router.get("/gstr2", response_model=GSTR2Response)
def get_gstr2_report(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Compiles GSTR-2 inward purchase invoice summaries for Input Tax Credit reconciliation."""
    # Fetch finalized vendor bills
    q_bill = db.query(Bill).filter(
        Bill.tenant_id == tenant_id,
        Bill.status.in_(["UNPAID", "PARTIALLY_PAID", "PAID"]),
        Bill.deleted_at == None
    )
    if start_date:
        q_bill = q_bill.filter(Bill.issue_date >= start_date)
    if end_date:
        q_bill = q_bill.filter(Bill.issue_date <= end_date)
    bills = q_bill.all()

    b2b_purchases = []
    for b in bills:
        contact = b.contact
        # GSTR-2 maps registered vendor purchases
        if contact and contact.gstin:
            b2b_purchases.append(
                GSTR2B2BLine(
                    vendor_name=contact.name,
                    vendor_gstin=contact.gstin,
                    bill_number=b.bill_number,
                    bill_date=b.issue_date,
                    pos_state_code=b.pos_state_code,
                    taxable_value=b.subtotal,
                    cgst_amount=b.cgst_amount,
                    sgst_amount=b.sgst_amount,
                    igst_amount=b.igst_amount,
                    utgst_amount=b.utgst_amount,
                    cess_amount=b.cess_amount,
                    total_value=b.total
                )
            )

    return GSTR2Response(b2b_purchases=b2b_purchases)
