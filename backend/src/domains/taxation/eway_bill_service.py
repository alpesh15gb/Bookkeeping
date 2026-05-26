import uuid
from datetime import datetime, timezone, timedelta
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from fastapi import HTTPException, status

from src.infrastructure.database.models import EWayBill, Invoice, Bill, Product
from src.schemas.eway_bill_schemas import EWayBillCreate, EWayBillVehicleUpdate, EWayBillCancelRequest, ConsolidatedEWayBillCreate

class EWayBillService:
    @staticmethod
    def generate_eway_bill(db: Session, tenant_id: uuid.UUID, payload: EWayBillCreate):
        # 1. Enforce that either invoice_id or bill_id is provided
        if not payload.invoice_id and not payload.bill_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Either invoice_id or bill_id must be provided to generate an e-Way Bill."
            )

        invoice = None
        bill = None

        # 2. Load and validate document status and line items
        if payload.invoice_id:
            invoice = db.query(Invoice).filter(
                Invoice.id == payload.invoice_id,
                Invoice.tenant_id == tenant_id,
                Invoice.deleted_at == None
            ).first()
            if not invoice:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Invoice not found in this company context."
                )
            if invoice.status == "DRAFT":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot generate e-Way Bill for a draft invoice. Please finalize it first."
                )
            if invoice.status == "CANCELLED":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot generate e-Way Bill for a cancelled invoice."
                )
            
            # Goods only check
            has_goods = any(line.product and line.product.product_type == "GOODS" for line in invoice.lines)
            if not has_goods:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="e-Way Bill is only applicable for movement of GOODS. Services do not require an e-Way Bill."
                )

        else:
            bill = db.query(Bill).filter(
                Bill.id == payload.bill_id,
                Bill.tenant_id == tenant_id,
                Bill.deleted_at == None
            ).first()
            if not bill:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Vendor Bill not found in this company context."
                )
            if bill.status == "DRAFT":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot generate e-Way Bill for a draft vendor bill. Please finalize it first."
                )
            if bill.status == "CANCELLED":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Cannot generate e-Way Bill for a cancelled vendor bill."
                )
            
            # Goods only check
            has_goods = any(line.product and line.product.product_type == "GOODS" for line in bill.lines)
            if not has_goods:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="e-Way Bill is only applicable for movement of GOODS. Services do not require an e-Way Bill."
                )

        # 3. Generate unique 12-digit E-Way Bill Number via NIC API
        import requests
        from src.core.config import settings

        ewb_number = None
        if settings.IRP_USERNAME and settings.IRP_PASSWORD:
            try:
                from src.infrastructure.database.models import Tenant
                tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
                tenant_gstin = tenant.gstin if tenant else None

                ewb_payload = {
                    "Irn": "",
                    "DocNo": (invoice.invoice_number if invoice else bill.bill_number) if (invoice or bill) else "",
                    "DocDt": str(invoice.issue_date if invoice else bill.issue_date) if (invoice or bill) else "",
                    "FromGstin": tenant_gstin or "",
                    "FromTrdName": "",
                    "ToGstin": "",
                    "ToTrdName": payload.transporter_name or "",
                    "TotInvVal": float(invoice.total if invoice else bill.total) if (invoice or bill) else 0,
                    "ItemCnt": 1,
                    "MainHsnCode": "998313",
                    "TransDistance": payload.trans_distance,
                    "TransMode": payload.trans_mode or "1",
                    "VehicleNo": payload.vehicle_number or "",
                }
                headers = {
                    "Content-Type": "application/json",
                    "gstin": tenant_gstin or "",
                    "user_name": settings.IRP_USERNAME,
                    "password": settings.IRP_PASSWORD,
                }
                resp = requests.post(
                    f"{settings.IRP_BASE_URL}/ic/irp/api/v1/ewb/generate",
                    json=ewb_payload, headers=headers, timeout=15
                )
                resp.raise_for_status()
                ewb_data = resp.json()
                ewb_number = str(ewb_data.get("ewayBillNo", ""))
            except Exception:
                import logging
                logging.getLogger("ewaybill").warning("NIC e-way bill API unreachable, falling back to local generation")

        if not ewb_number:
            # Mock 12-digit number starting with 201
            ewb_number = f"201{int(datetime.now(timezone.utc).timestamp()) % 1000000000:09d}"

        # Check duplicate (unlikely, but safe)
        dup = db.query(EWayBill).filter(EWayBill.eway_bill_number == ewb_number).first()
        if dup:
            ewb_number = f"201{(int(datetime.now(timezone.utc).timestamp()) + 1) % 1000000000:09d}"

        # 4. Calculate validity: 1 day per 200 km, minimum 1 day
        validity_days = max(1, (payload.trans_distance + 199) // 200)
        valid_until = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=validity_days)

        # 5. Create E-Way Bill
        ewb = EWayBill(
            tenant_id=tenant_id,
            invoice_id=payload.invoice_id,
            bill_id=payload.bill_id,
            eway_bill_number=ewb_number,
            status="GENERATED",
            supply_type=payload.supply_type,
            sub_supply_type=payload.sub_supply_type,
            transporter_id=payload.transporter_id,
            transporter_name=payload.transporter_name,
            trans_doc_number=payload.trans_doc_number,
            trans_doc_date=payload.trans_doc_date,
            trans_distance=payload.trans_distance,
            trans_mode=payload.trans_mode,
            vehicle_number=payload.vehicle_number,
            vehicle_type=payload.vehicle_type,
            valid_until=valid_until,
            vehicle_history=[]
        )

        db.add(ewb)
        db.commit()
        db.refresh(ewb)

        return ewb

    @staticmethod
    def update_eway_bill_vehicle(db: Session, tenant_id: uuid.UUID, eway_bill_id: uuid.UUID, payload: EWayBillVehicleUpdate):
        # 1. Fetch E-Way Bill
        ewb = db.query(EWayBill).filter(
            EWayBill.id == eway_bill_id,
            EWayBill.tenant_id == tenant_id
        ).first()
        if not ewb:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="e-Way Bill not found."
            )

        # 2. Verify status
        if ewb.status != "GENERATED":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot update vehicle details. e-Way Bill status is not GENERATED."
            )

        # 3. Log old details to history
        history_entry = {
            "vehicle_number": ewb.vehicle_number,
            "vehicle_type": ewb.vehicle_type,
            "updated_at": str(datetime.now(timezone.utc).replace(tzinfo=None)),
            "reason_code": payload.reason_code,
            "reason_remarks": payload.reason_remarks,
            "from_place": payload.from_place,
            "from_state_code": payload.from_state_code
        }
        
        # SQLAlchemy mutability tracking: copy list, append and assign
        history_list = list(ewb.vehicle_history or [])
        history_list.append(history_entry)
        ewb.vehicle_history = history_list
        flag_modified(ewb, "vehicle_history")

        # 4. Update current fields
        ewb.vehicle_number = payload.vehicle_number
        ewb.vehicle_type = payload.vehicle_type
        ewb.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        db.commit()
        db.refresh(ewb)
        return ewb

    @staticmethod
    def cancel_eway_bill(db: Session, tenant_id: uuid.UUID, eway_bill_id: uuid.UUID, payload: EWayBillCancelRequest):
        # 1. Fetch E-Way Bill
        ewb = db.query(EWayBill).filter(
            EWayBill.id == eway_bill_id,
            EWayBill.tenant_id == tenant_id
        ).first()
        if not ewb:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="e-Way Bill not found."
            )

        # 2. Verify status
        if ewb.status == "CANCELLED":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="e-Way Bill is already cancelled."
            )

        # 3. Verify 24-hour limit
        time_elapsed = datetime.now(timezone.utc).replace(tzinfo=None) - ewb.created_at
        if time_elapsed.total_seconds() > 24 * 3600:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="IRP Error [912]: Cancellation not allowed after 24 hours of generation."
            )

        # 4. Update cancellation details
        ewb.status = "CANCELLED"
        ewb.cancel_reason = payload.cancel_reason
        ewb.cancel_remarks = payload.cancel_remarks
        ewb.cancel_date = datetime.now(timezone.utc).replace(tzinfo=None)
        ewb.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        db.commit()
        db.refresh(ewb)
        return ewb

    @staticmethod
    def generate_consolidated_eway_bill(db: Session, tenant_id: uuid.UUID, payload: ConsolidatedEWayBillCreate):
        # 1. Validate that all e-way bills exist, belong to this tenant, and are active
        for num in payload.eway_bill_numbers:
            ewb = db.query(EWayBill).filter(
                EWayBill.eway_bill_number == num,
                EWayBill.tenant_id == tenant_id
            ).first()
            if not ewb:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"e-Way Bill with number {num} not found or belongs to another tenant."
                )
            if ewb.status != "GENERATED":
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"e-Way Bill with number {num} is cancelled and cannot be consolidated."
                )

        # 2. Compile consolidated e-way bill (mock 12-digit number starting with 301)
        con_ewb_number = f"301{int(datetime.now(timezone.utc).timestamp()) % 1000000000:09d}"

        return {
            "consolidated_eway_bill_number": con_ewb_number,
            "consolidated_date": datetime.now(timezone.utc).replace(tzinfo=None),
            "vehicle_number": payload.vehicle_number,
            "status": "GENERATED",
            "eway_bills": payload.eway_bill_numbers
        }
