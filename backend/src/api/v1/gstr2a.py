import uuid
from decimal import Decimal
from typing import List, Optional
from datetime import date
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from pydantic import BaseModel

from src.core.database import get_db_session
from src.infrastructure.database.models import Bill, Contact, Invoice
from src.api.deps import enforce_permission

router = APIRouter(prefix="/gst/gstr2a", tags=["GST Reconciliation"])


class GSTR2AItem(BaseModel):
    supplier_gstin: str
    supplier_name: str
    invoice_number: str
    invoice_date: str
    invoice_value: float
    taxable_value: float
    igst: float = 0.0
    cgst: float = 0.0
    sgst: float = 0.0
    cess: float = 0.0


class GSTR2AUploadResponse(BaseModel):
    total_suppliers: int
    matched: int
    unmatched: int
    partially_matched: int
    matches: List[dict]
    unmatched_items: List[GSTR2AItem]


def extract_portal_purchase_items(data: dict) -> List[GSTR2AItem]:
    """Normalize legacy GSTR-2A and current GSTR-2B B2B JSON shapes."""
    document_data = data
    if isinstance(data.get("data"), dict):
        document_data = data["data"].get("docdata") or data["data"]
    elif isinstance(data.get("docdata"), dict):
        document_data = data["docdata"]

    result: List[GSTR2AItem] = []
    portal_b2b = list(document_data.get("b2b", []) or [])
    portal_b2b.extend(document_data.get("b2ba", []) or [])
    for b2b in portal_b2b:
        invoices = b2b.get("inv") or b2b.get("invoices") or []
        for inv in invoices:
            taxable = Decimal(str(inv.get("txval", 0) or 0))
            igst = Decimal(str(inv.get("igst", inv.get("iamt", 0)) or 0))
            cgst = Decimal(str(inv.get("cgst", inv.get("camt", 0)) or 0))
            sgst = Decimal(str(inv.get("sgst", inv.get("samt", 0)) or 0))
            cess = Decimal(str(inv.get("cess", inv.get("csamt", 0)) or 0))
            line_items = inv.get("itms") or inv.get("items") or []
            if line_items:
                taxable = igst = cgst = sgst = cess = Decimal("0")
                for raw_line in line_items:
                    line = raw_line.get("itm_det") or raw_line.get("item_det") or raw_line
                    taxable += Decimal(str(line.get("txval", 0) or 0))
                    igst += Decimal(str(line.get("igst", line.get("iamt", 0)) or 0))
                    cgst += Decimal(str(line.get("cgst", line.get("camt", 0)) or 0))
                    sgst += Decimal(str(line.get("sgst", line.get("samt", 0)) or 0))
                    cess += Decimal(str(line.get("cess", line.get("csamt", 0)) or 0))
            result.append(GSTR2AItem(
                supplier_gstin=b2b.get("ctin", "") or b2b.get("gstin", ""),
                supplier_name=(b2b.get("trdnm", "") or b2b.get("tradeName", "") or b2b.get("legalName", "")),
                invoice_number=inv.get("inum", ""),
                invoice_date=inv.get("idt", ""),
                invoice_value=float(inv.get("val", 0)),
                taxable_value=float(taxable),
                igst=float(igst),
                cgst=float(cgst),
                sgst=float(sgst),
                cess=float(cess),
            ))
    return result


@router.post("/upload", response_model=GSTR2AUploadResponse)
def upload_gstr2a(
    file: UploadFile = File(...),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("gst:filing_manage")),
):
    """Upload GST-portal GSTR-2A/2B JSON and reconcile it with purchase bills."""
    import json

    content = file.file.read()
    if len(content) > 25 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="GST portal JSON must be 25 MB or smaller.")
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON file. Download GSTR-2B as JSON from the GST portal.")
    if not isinstance(data, dict):
        raise HTTPException(status_code=400, detail="The GST portal JSON must contain an object at its root.")

    # Portal downloads have used both the legacy GSTR-2A shape and the newer
    # GSTR-2B ``data.docdata`` envelope. Accept both without making accountants
    # transform a statutory file before importing it.
    gstr2a_items = extract_portal_purchase_items(data)

    if not gstr2a_items:
        raise HTTPException(
            status_code=400,
            detail="No B2B invoices were found. Upload the JSON downloaded directly from the GST portal's GSTR-2B or GSTR-2A tile.",
        )

    # Reconcile: match supplier invoice number against purchase bills
    matches = []
    unmatched_items = []
    matched_count = 0
    partial_count = 0

    for item in gstr2a_items:
        # GST invoice numbers are case-insensitive in day-to-day entry and often
        # differ only by spaces. Narrow by GSTIN, then compare normalized values.
        candidates = db.query(Bill).join(Contact, Bill.contact_id == Contact.id).filter(
            Contact.gstin == item.supplier_gstin,
            Bill.tenant_id == tenant_id,
            Bill.deleted_at == None,
        ).all()
        normalized_number = "".join(item.invoice_number.upper().split())
        bill = next(
            (
                candidate for candidate in candidates
                if "".join((candidate.bill_number or "").upper().split()) == normalized_number
            ),
            None,
        )

        if bill:
            value_diff = abs(float(bill.total) - item.invoice_value)
            portal_tax = item.igst + item.cgst + item.sgst + item.cess
            books_tax = float(
                (bill.igst_amount or 0) + (bill.cgst_amount or 0)
                + (bill.sgst_amount or 0) + (bill.utgst_amount or 0)
                + (bill.cess_amount or 0)
            )
            tax_diff = abs(books_tax - portal_tax)
            status_label = "matched" if value_diff < 1 and tax_diff < 1 else "partial"
            if status_label == "matched":
                matched_count += 1
            else:
                partial_count += 1
            matches.append({
                "supplier_gstin": item.supplier_gstin,
                "supplier_name": item.supplier_name,
                "gstr2a_invoice": item.invoice_number,
                "gstr2a_value": item.invoice_value,
                "bill_number": bill.bill_number,
                "bill_value": float(bill.total),
                "difference": round(value_diff, 2),
                "portal_tax": round(portal_tax, 2),
                "books_tax": round(books_tax, 2),
                "tax_difference": round(tax_diff, 2),
                "status": status_label,
            })
        else:
            unmatched_items.append(item)

    return GSTR2AUploadResponse(
        total_suppliers=len(gstr2a_items),
        matched=matched_count,
        unmatched=len(unmatched_items),
        partially_matched=partial_count,
        matches=matches,
        unmatched_items=unmatched_items,
    )
