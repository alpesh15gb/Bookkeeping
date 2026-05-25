import hashlib
import json
import base64
import uuid
from datetime import date, datetime, timezone
from sqlalchemy.orm import Session
from fastapi import HTTPException, status

from src.infrastructure.database.models import Invoice, Tenant, TenantSetting, Contact


def get_financial_year(target_date: date) -> str:
    """Returns Indian FY as YYYYNN, where NN is the FY end year's last two digits."""
    start_year = target_date.year if target_date.month >= 4 else target_date.year - 1
    end_year_short = (start_year + 1) % 100
    return f"{start_year}{end_year_short:02d}"


class EInvoiceService:
    @staticmethod
    def _call_irp_generate_invoice(
        tenant: Tenant,
        contact: Contact,
        invoice: Invoice,
        irn_hash: str,
    ) -> dict:
        """Mock IRP call. Replace with live NIC API integration later."""
        qr_data = {
            "SupplierGSTIN": tenant.gstin,
            "RecipientGSTIN": contact.gstin,
            "DocNo": invoice.invoice_number,
            "DocDt": str(invoice.issue_date),
            "TotVal": float(invoice.total),
            "ItemCnt": len(invoice.lines),
            "MainHSN": invoice.lines[0].hsn_sac if invoice.lines else "998313",
            "Irn": irn_hash,
        }

        return {
            "irn": irn_hash,
            "qr_code": base64.b64encode(json.dumps(qr_data).encode("utf-8")).decode("utf-8"),
            "ack_number": str(100000000000000 + int(invoice.created_at.timestamp())),
            "ack_date": datetime.now(timezone.utc).replace(tzinfo=None),
        }

    @staticmethod
    def generate_einvoice(db: Session, tenant_id: uuid.UUID, invoice_id: uuid.UUID):
        # 1. Fetch Invoice
        invoice = db.query(Invoice).filter(
            Invoice.id == invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.deleted_at == None
        ).first()
        if not invoice:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Invoice not found in this company context."
            )

        # 2. Check Invoice Status
        if invoice.status == "DRAFT":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot generate e-invoice for a draft invoice. Please finalize it first."
            )

        # 3. Check Tenant Settings
        setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
        if not setting or not setting.e_invoicing_enabled:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="e-Invoicing is not enabled for this company context."
            )

        # 4. Check if already generated
        if invoice.e_invoice_status == "GENERATED":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="e-Invoice is already generated for this invoice."
            )

        # 5. Check if recipient has GSTIN (B2B check)
        contact = invoice.contact
        if not contact or not contact.gstin:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="e-Invoicing is only applicable for B2B transactions. Recipient must have a valid GSTIN."
            )

        # 6. Check if supplier has GSTIN
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
        if not tenant or not tenant.gstin:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Supplier company does not have a registered GSTIN."
            )

        # 7. Generate deterministic SHA-256 IRN
        # Supplier GSTIN + Document Type (INV) + Document Number + Financial Year
        financial_year = get_financial_year(invoice.issue_date)
        raw_irn_str = f"{tenant.gstin}INV{invoice.invoice_number}{financial_year}"
        irn_hash = hashlib.sha256(raw_irn_str.encode("utf-8")).hexdigest()

        try:
            irp_response = EInvoiceService._call_irp_generate_invoice(
                tenant=tenant,
                contact=contact,
                invoice=invoice,
                irn_hash=irn_hash,
            )
        except Exception as exc:
            invoice.irn = None
            invoice.qr_code = None
            invoice.e_invoice_status = "FAILED"
            invoice.e_invoice_error = str(exc)
            invoice.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
            db.commit()
            db.refresh(invoice)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"IRP e-invoice generation failed: {exc}",
            )

        # Check for duplicate IRN across all tenant contexts after IRP succeeds.
        dup = db.query(Invoice).filter(Invoice.irn == irp_response["irn"]).first()
        if dup:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Duplicate e-invoice request. IRN already exists."
            )

        # 8. Update invoice fields only after successful IRP response.
        invoice.irn = irp_response["irn"]
        invoice.qr_code = irp_response["qr_code"]
        invoice.e_invoice_status = "GENERATED"
        invoice.e_invoice_error = None
        invoice.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        db.commit()
        db.refresh(invoice)

        return {
            "invoice_id": invoice.id,
            "irn": invoice.irn,
            "qr_code": invoice.qr_code,
            "e_invoice_status": invoice.e_invoice_status,
            "ack_number": irp_response["ack_number"],
            "ack_date": irp_response["ack_date"]
        }

    @staticmethod
    def cancel_einvoice(db: Session, tenant_id: uuid.UUID, invoice_id: uuid.UUID, cancel_reason: str, cancel_remarks: str):
        # 1. Fetch Invoice
        invoice = db.query(Invoice).filter(
            Invoice.id == invoice_id,
            Invoice.tenant_id == tenant_id,
            Invoice.deleted_at == None
        ).first()
        if not invoice:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Invoice not found in this company context."
            )

        # 2. Check e-invoice status
        if invoice.e_invoice_status != "GENERATED":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot cancel e-invoice. Status is not GENERATED."
            )

        # 3. Check 24-hour cancellation rule
        time_elapsed = datetime.now(timezone.utc).replace(tzinfo=None) - invoice.updated_at
        if time_elapsed.total_seconds() > 24 * 3600:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="IRP Error [912]: Cancellation not allowed after 24 hours of generation."
            )

        # 4. Update status
        invoice.e_invoice_status = "CANCELLED"
        invoice.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)

        db.commit()
        db.refresh(invoice)

        return {
            "invoice_id": invoice.id,
            "e_invoice_status": invoice.e_invoice_status,
            "cancel_date": invoice.updated_at
        }
