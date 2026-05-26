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


@router.post("/upload", response_model=GSTR2AUploadResponse)
def upload_gstr2a(
    file: UploadFile = File(...),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("gst:filing_manage")),
):
    """Upload a GSTR-2A JSON file (downloaded from GST portal) and reconcile against purchase bills."""
    import json

    content = file.file.read()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON file. Download GSTR-2A as JSON from the GST portal.")

    # Extract B2B invoices from GSTR-2A
    gstr2a_items: List[GSTR2AItem] = []
    for b2b in data.get("b2b", []):
        for inv in b2b.get("invoices", []):
            item = GSTR2AItem(
                supplier_gstin=b2b.get("gstin", ""),
                supplier_name=b2b.get("tradeName", "") or b2b.get("legalName", ""),
                invoice_number=inv.get("inum", ""),
                invoice_date=inv.get("idt", ""),
                invoice_value=float(inv.get("val", 0)),
                taxable_value=float(inv.get("txval", 0)),
                igst=float(inv.get("igst", 0)),
                cgst=float(inv.get("cgst", 0)),
                sgst=float(inv.get("sgst", 0)),
                cess=float(inv.get("cess", 0)),
            )
            gstr2a_items.append(item)

    if not gstr2a_items:
        raise HTTPException(status_code=400, detail="No B2B invoices found in the uploaded GSTR-2A file.")

    # Reconcile: match supplier invoice number against purchase bills
    matches = []
    unmatched_items = []
    matched_count = 0
    partial_count = 0

    for item in gstr2a_items:
        # Find matching purchase bill
        bill = db.query(Bill).join(Contact, Bill.contact_id == Contact.id).filter(
            Contact.gstin == item.supplier_gstin,
            Bill.bill_number == item.invoice_number,
            Bill.tenant_id == tenant_id,
            Bill.deleted_at == None,
        ).first()

        if bill:
            diff = abs(float(bill.total) - item.invoice_value)
            status_label = "matched" if diff < 1 else "partial"
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
                "difference": round(diff, 2),
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
