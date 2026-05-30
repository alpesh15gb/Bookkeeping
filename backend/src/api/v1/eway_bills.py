from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List
import uuid
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import EWayBill, Invoice
from src.schemas.eway_bill_schemas import (
    EWayBillCreate, EWayBillResponse, EWayBillVehicleUpdate, EWayBillCancelRequest,
    ConsolidatedEWayBillCreate, ConsolidatedEWayBillResponse
)
from src.domains.taxation.eway_bill_service import EWayBillService
from src.api.deps import enforce_permission

router = APIRouter(prefix="/eway-bills", tags=["e-Way Bills"])

@router.post("", response_model=EWayBillResponse, status_code=status.HTTP_201_CREATED)
def create_eway_bill(
    payload: EWayBillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Generates an outward or inward e-Way Bill for transport of physical Goods."""
    # E-Way Bill is required for goods movement exceeding ₹50,000
    if payload.invoice_id:
        invoice = db.query(Invoice).filter(Invoice.id == payload.invoice_id).first()
        if invoice:
            has_goods = any(line.product and line.product.product_type == "GOODS" for line in invoice.lines)
            if not has_goods:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="e-Way Bill is only applicable for movement of GOODS. Services do not require an e-Way Bill."
                )
            if invoice.total < Decimal("50000"):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="E-Way Bill is not required for invoices below ₹50,000 threshold."
                )
    return EWayBillService.generate_eway_bill(db=db, tenant_id=tenant_id, payload=payload)

@router.get("", response_model=List[EWayBillResponse])
def list_eway_bills(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Lists all e-Way Bills for the active company context."""
    return db.query(EWayBill).filter(EWayBill.tenant_id == tenant_id).all()

@router.get("/{id}", response_model=EWayBillResponse)
def get_eway_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """Retrieves details of an e-Way Bill."""
    ewb = db.query(EWayBill).filter(EWayBill.id == id, EWayBill.tenant_id == tenant_id).first()
    if not ewb:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="e-Way Bill not found."
        )
    return ewb

@router.post("/{id}/cancel", response_model=EWayBillResponse)
def cancel_eway_bill(
    id: uuid.UUID,
    payload: EWayBillCancelRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Cancels an active e-Way Bill on the IRP within 24 hours of generation."""
    return EWayBillService.cancel_eway_bill(db=db, tenant_id=tenant_id, eway_bill_id=id, payload=payload)

@router.post("/{id}/vehicle", response_model=EWayBillResponse)
def update_eway_bill_vehicle(
    id: uuid.UUID,
    payload: EWayBillVehicleUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Updates vehicle and transporter assignment details (e.g. for breakdown or transhipment)."""
    return EWayBillService.update_eway_bill_vehicle(db=db, tenant_id=tenant_id, eway_bill_id=id, payload=payload)

@router.post("/consolidated", response_model=ConsolidatedEWayBillResponse)
def generate_consolidated_eway_bill(
    payload: ConsolidatedEWayBillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:finalize"))
):
    """Compiles a consolidated e-Way Bill for transporting multiple active consignments in a single vehicle."""
    return EWayBillService.generate_consolidated_eway_bill(db=db, tenant_id=tenant_id, payload=payload)
