from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Request, status
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from typing import List
import os, uuid
from datetime import datetime, timezone

from src.core.config import settings
from src.core.database import get_db_session
from src.infrastructure.database.models import User, Tenant, TenantMembership, Branch, TenantSetting, NumberingSeries
from src.schemas.company_schemas import (
    CompanyCreate, CompanyResponse,
    BranchCreate, BranchUpdate, BranchResponse,
    TenantSettingUpdate, TenantSettingResponse,
    NumberingSeriesCreate, NumberingSeriesUpdate, NumberingSeriesResponse
)
from src.domains.company.services import NumberingSeriesService, encrypt_credential
from src.api.deps import get_current_user, enforce_permission

router = APIRouter(tags=["Company & Settings"])

# 1. Company endpoints
@router.post("/companies", response_model=CompanyResponse, status_code=status.HTTP_201_CREATED)
def create_company(
    payload: CompanyCreate,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user)
):
    """Registers an additional company/tenant context under the current active user."""
    tenant = Tenant(
        legal_name=payload.legal_name,
        trade_name=payload.trade_name or payload.legal_name,
        gstin=payload.gstin,
        pan=payload.pan
    )
    db.add(tenant)
    db.flush()

    membership = TenantMembership(
        tenant_id=tenant.id,
        user_id=current_user.id,
        role="owner",
        is_active=True
    )
    db.add(membership)

    # Seed default configurations
    NumberingSeriesService.seed_all_defaults(db, tenant.id)

    setting = TenantSetting(
        tenant_id=tenant.id,
        currency="INR",
        gst_enabled=True if payload.gstin else False,
        e_invoicing_enabled=False
    )
    db.add(setting)

    db.commit()
    db.refresh(tenant)
    return tenant

@router.get("/companies/{id}", response_model=CompanyResponse)
def get_company(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user)
):
    """Retrieves metadata of the specified company context."""
    membership = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == id,
        TenantMembership.user_id == current_user.id,
        TenantMembership.is_active == True
    ).first()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not have access to this company context."
        )

    tenant = db.query(Tenant).filter(Tenant.id == id, Tenant.deleted_at == None).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found.")
    return tenant

@router.put("/companies/{id}", response_model=CompanyResponse)
def update_company(
    id: uuid.UUID,
    payload: CompanyCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Updates company metadata."""
    if id != tenant_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot update another tenant's details."
        )

    tenant = db.query(Tenant).filter(Tenant.id == id, Tenant.deleted_at == None).first()
    if not tenant:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Company not found.")

    tenant.legal_name = payload.legal_name
    tenant.trade_name = payload.trade_name or payload.legal_name
    tenant.gstin = payload.gstin
    tenant.pan = payload.pan

    db.commit()
    db.refresh(tenant)
    return tenant

# 2. Branch endpoints
@router.get("/companies/{id}/branches", response_model=List[BranchResponse])
def list_branches(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user)
):
    """Lists all active branches / warehouses for the specified company context."""
    membership = db.query(TenantMembership).filter(
        TenantMembership.tenant_id == id,
        TenantMembership.user_id == current_user.id,
        TenantMembership.is_active == True
    ).first()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User does not have access to this company context."
        )

    return db.query(Branch).filter(Branch.tenant_id == id, Branch.deleted_at == None).all()

@router.post("/companies/{id}/branches", response_model=BranchResponse, status_code=status.HTTP_201_CREATED)
def create_branch(
    id: uuid.UUID,
    payload: BranchCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Creates a new branch office / warehouse."""
    if id != tenant_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Header tenant ID and path ID mismatch."
        )

    branch = Branch(
        tenant_id=tenant_id,
        name=payload.name,
        gstin=payload.gstin,
        address=payload.address.dict(),
        is_active=True
    )
    db.add(branch)
    db.commit()
    db.refresh(branch)
    return branch

@router.put("/companies/{id}/branches/{branch_id}", response_model=BranchResponse)
def update_branch(
    id: uuid.UUID,
    branch_id: uuid.UUID,
    payload: BranchUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Updates a branch profile details."""
    if id != tenant_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Header tenant ID and path ID mismatch."
        )

    branch = db.query(Branch).filter(
        Branch.id == branch_id,
        Branch.tenant_id == tenant_id,
        Branch.deleted_at == None
    ).first()
    if not branch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Branch not found.")

    if payload.name is not None:
        branch.name = payload.name
    if payload.gstin is not None:
        branch.gstin = payload.gstin
    if payload.address is not None:
        branch.address = payload.address.dict()
    if payload.is_active is not None:
        branch.is_active = payload.is_active

    db.commit()
    db.refresh(branch)
    return branch

@router.delete("/companies/{id}/branches/{branch_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_branch(
    id: uuid.UUID,
    branch_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Soft deletes a branch profile."""
    if id != tenant_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Header tenant ID and path ID mismatch."
        )

    branch = db.query(Branch).filter(
        Branch.id == branch_id,
        Branch.tenant_id == tenant_id,
        Branch.deleted_at == None
    ).first()
    if not branch:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Branch not found.")

    branch.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return None

# 3. Logo upload endpoint
ALLOWED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp"}

@router.post("/settings/logo")
def upload_logo(
    file: UploadFile = File(...),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update")),
    request: Request = None
):
    """Uploads a company logo image for the active tenant. Saved to static/logos/<tenant_id>.ext"""
    ext = os.path.splitext(file.filename or ".png")[1].lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail=f"Invalid file type: {ext}. Allowed: {', '.join(ALLOWED_EXTENSIONS)}")

    logo_path = os.path.join("static", "logos", f"{tenant_id}{ext}")
    os.makedirs(os.path.dirname(logo_path), exist_ok=True)

    contents = file.file.read()
    with open(logo_path, "wb") as f:
        f.write(contents)

    base_url = str(request.base_url).rstrip("/")
    forwarded_proto = request.headers.get("x-forwarded-proto", "")
    if forwarded_proto == "https":
        base_url = base_url.replace("http://", "https://")
    logo_url = f"{base_url}/static/logos/{tenant_id}{ext}"

    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    if not setting:
        setting = TenantSetting(tenant_id=tenant_id)
        db.add(setting)
    setting.logo_url = logo_url
    db.commit()
    db.refresh(setting)

    return {"logo_url": logo_url, "detail": "Logo uploaded successfully"}


# 4. Settings endpoints
@router.get("/settings", response_model=TenantSettingResponse)
def get_settings(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:view"))
):
    """Gets tenant-specific settings and visual parameters."""
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    if not setting:
        setting = TenantSetting(
            tenant_id=tenant_id,
            currency="INR",
            gst_enabled=True,
            e_invoicing_enabled=False
        )
        db.add(setting)
        db.commit()
        db.refresh(setting)
    return setting

@router.put("/settings", response_model=TenantSettingResponse)
def update_settings(
    payload: TenantSettingUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Updates tenant setting details, securely encrypting API credentials."""
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    if not setting:
        setting = TenantSetting(tenant_id=tenant_id)
        db.add(setting)

    if payload.logo_url is not None:
        setting.logo_url = payload.logo_url
    if payload.currency is not None:
        setting.currency = payload.currency
    if payload.gst_enabled is not None:
        setting.gst_enabled = payload.gst_enabled
    if payload.e_invoicing_enabled is not None:
        setting.e_invoicing_enabled = payload.e_invoicing_enabled
    if payload.e_invoice_username is not None:
        setting.e_invoice_username = payload.e_invoice_username
    if payload.e_invoice_password is not None:
        setting.e_invoice_password_hash = encrypt_credential(payload.e_invoice_password)
    if payload.e_way_bill_username is not None:
        setting.e_way_bill_username = payload.e_way_bill_username
    if payload.e_way_bill_password is not None:
        setting.e_way_bill_password_hash = encrypt_credential(payload.e_way_bill_password)
    if payload.origin_state_code is not None:
        setting.origin_state_code = payload.origin_state_code
    if payload.extra_settings is not None:
        setting.extra_settings = payload.extra_settings
        from sqlalchemy.orm.attributes import flag_modified
        flag_modified(setting, "extra_settings")

    db.commit()
    db.refresh(setting)
    return setting

# 4. Numbering series endpoints
@router.get("/settings/series", response_model=List[NumberingSeriesResponse])
def list_series(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:view"))
):
    """Lists sequence numbering configurations for documents."""
    series = db.query(NumberingSeries).filter(NumberingSeries.tenant_id == tenant_id).all()
    if not series:
        NumberingSeriesService.seed_all_defaults(db, tenant_id)
        db.commit()
        series = db.query(NumberingSeries).filter(NumberingSeries.tenant_id == tenant_id).all()
    return series

@router.post("/settings/series", response_model=NumberingSeriesResponse, status_code=status.HTTP_201_CREATED)
def create_series(
    payload: NumberingSeriesCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Configures a new numbering series, automatically deactivating other active series of the same type."""
    # Mark old series as inactive
    db.query(NumberingSeries).filter(
        NumberingSeries.tenant_id == tenant_id,
        NumberingSeries.document_type == payload.document_type
    ).update({"is_active": False})

    series = NumberingSeries(
        tenant_id=tenant_id,
        document_type=payload.document_type,
        prefix=payload.prefix,
        next_number=payload.next_number,
        suffix=payload.suffix,
        padding_digits=payload.padding_digits,
        is_active=True
    )
    db.add(series)
    db.commit()
    db.refresh(series)
    return series

@router.put("/settings/series/{series_id}", response_model=NumberingSeriesResponse)
def update_series(
    series_id: uuid.UUID,
    payload: NumberingSeriesUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Updates sequence numbering parameters."""
    series = db.query(NumberingSeries).filter(
        NumberingSeries.id == series_id,
        NumberingSeries.tenant_id == tenant_id
    ).first()
    if not series:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Numbering series not found.")

    if payload.prefix is not None:
        series.prefix = payload.prefix
    if payload.next_number is not None:
        series.next_number = payload.next_number
    if payload.suffix is not None:
        series.suffix = payload.suffix
    if payload.padding_digits is not None:
        series.padding_digits = payload.padding_digits
    if payload.is_active is not None:
        if payload.is_active:
            db.query(NumberingSeries).filter(
                NumberingSeries.tenant_id == tenant_id,
                NumberingSeries.document_type == series.document_type,
                NumberingSeries.id != series.id
            ).update({"is_active": False})
        series.is_active = payload.is_active

    db.commit()
    db.refresh(series)
    return series


# ── Purge Company Data endpoints ──────────────────────────────────────────────
import secrets
import smtplib
from email.mime.text import MIMEText
import logging
from pydantic import BaseModel

logger = logging.getLogger(__name__)
_PURGE_OTP_CACHE = {}


class VerifyPurgeRequest(BaseModel):
    otp: str


@router.post("/purge/request", status_code=status.HTTP_200_OK)
def request_purge_otp(
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Generates a 6-digit OTP to authorize purging of the company data, and emails it to the owner."""
    otp = f"{secrets.randbelow(900000) + 100000}"
    
    import redis
    redis_client = None
    try:
        redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True, socket_connect_timeout=1)
        redis_client.ping()
    except Exception:
        pass

    cache_key = f"purge_otp:{tenant_id}:{current_user.id}"
    if redis_client:
        redis_client.setex(cache_key, 300, otp)
    else:
        _PURGE_OTP_CACHE[cache_key] = (otp, datetime.now(timezone.utc))

    msg = MIMEText(
        f"Hello {current_user.full_name or 'User'},\n\n"
        f"You have requested to purge all data for your company context (Tenant ID: {tenant_id}).\n\n"
        f"Your verification OTP code is: {otp}\n\n"
        f"This OTP is valid for 5 minutes. Enter this code in the settings panel to confirm the purge.\n"
        f"WARNING: Purging data will permanently delete all invoices, bills, payments, contacts, products, and expenses. This action cannot be undone.\n\n"
        f"Regards,\n"
        f"Apex Books Team"
    )
    msg["Subject"] = "Verify Company Data Purge - Apex Books"
    msg["From"] = settings.EMAIL_FROM
    msg["To"] = current_user.email

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                server.starttls()
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.send_message(msg)
    except Exception as e:
        logger.error(f"Failed to send purge OTP email to {current_user.email}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send OTP email. Please ensure SMTP configuration is correct."
        )

    return {"detail": "Verification OTP sent to your email address."}


@router.post("/purge/verify", status_code=status.HTTP_200_OK)
def verify_and_execute_purge(
    payload: VerifyPurgeRequest,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update"))
):
    """Verifies the OTP and purges all transactional and master data for the tenant."""
    import redis
    redis_client = None
    try:
        redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True, socket_connect_timeout=1)
        redis_client.ping()
    except Exception:
        pass

    cache_key = f"purge_otp:{tenant_id}:{current_user.id}"
    valid_otp = None

    if redis_client:
        valid_otp = redis_client.get(cache_key)
        if valid_otp:
            redis_client.delete(cache_key)
    else:
        cached = _PURGE_OTP_CACHE.get(cache_key)
        if cached:
            otp_val, created_at = cached
            if (datetime.now(timezone.utc) - created_at).total_seconds() <= 300:
                valid_otp = otp_val
            del _PURGE_OTP_CACHE[cache_key]

    if not valid_otp or valid_otp != payload.otp.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification OTP."
        )

    from src.infrastructure.database.models import (
        Invoice, InvoiceLine,
        Bill, BillLine,
        ProformaInvoice, ProformaInvoiceLine,
        Payment, PaymentAllocation,
        BillPayment, BillPaymentAllocation,
        Expense,
        JournalEntry, JournalLine,
        InventoryAdjustment, InventoryAdjustmentLine,
        CreditNote, CreditNoteLine,
        DebitNote, DebitNoteLine,
        DeliveryChallan, DeliveryChallanLine,
        SalesOrder, SalesOrderLine,
        PurchaseOrder, PurchaseOrderLine,
        EWayBill, BankReconciliation, BankStatement, BankTransaction,
        StockLedger, GSTReturn,
        Contact, Product, AuditLog, Account
    )

    try:
        # 1. Delete lines / children referencing parent documents of this tenant
        db.query(InvoiceLine).filter(InvoiceLine.invoice_id.in_(db.query(Invoice.id).filter(Invoice.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(BillLine).filter(BillLine.bill_id.in_(db.query(Bill.id).filter(Bill.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(ProformaInvoiceLine).filter(ProformaInvoiceLine.proforma_invoice_id.in_(db.query(ProformaInvoice.id).filter(ProformaInvoice.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(JournalLine).filter(JournalLine.entry_id.in_(db.query(JournalEntry.id).filter(JournalEntry.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(InventoryAdjustmentLine).filter(InventoryAdjustmentLine.inventory_adjustment_id.in_(db.query(InventoryAdjustment.id).filter(InventoryAdjustment.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(CreditNoteLine).filter(CreditNoteLine.credit_note_id.in_(db.query(CreditNote.id).filter(CreditNote.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(DebitNoteLine).filter(DebitNoteLine.debit_note_id.in_(db.query(DebitNote.id).filter(DebitNote.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(DeliveryChallanLine).filter(DeliveryChallanLine.delivery_challan_id.in_(db.query(DeliveryChallan.id).filter(DeliveryChallan.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(SalesOrderLine).filter(SalesOrderLine.sales_order_id.in_(db.query(SalesOrder.id).filter(SalesOrder.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(PurchaseOrderLine).filter(PurchaseOrderLine.purchase_order_id.in_(db.query(PurchaseOrder.id).filter(PurchaseOrder.tenant_id == tenant_id))).delete(synchronize_session=False)
        
        # Allocations
        db.query(PaymentAllocation).filter(PaymentAllocation.payment_id.in_(db.query(Payment.id).filter(Payment.tenant_id == tenant_id))).delete(synchronize_session=False)
        db.query(BillPaymentAllocation).filter(BillPaymentAllocation.payment_id.in_(db.query(BillPayment.id).filter(BillPayment.tenant_id == tenant_id))).delete(synchronize_session=False)
        
        # Bank transactions (delete before bank statements)
        db.query(BankTransaction).filter(BankTransaction.bank_statement_id.in_(db.query(BankStatement.id).filter(BankStatement.tenant_id == tenant_id))).delete(synchronize_session=False)
        
        # 2. Delete tables that have foreign keys pointing to Invoices, Bills, Payments, etc.
        db.query(BankReconciliation).filter(BankReconciliation.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(EWayBill).filter(EWayBill.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(CreditNote).filter(CreditNote.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(DebitNote).filter(DebitNote.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(ProformaInvoice).filter(ProformaInvoice.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(StockLedger).filter(StockLedger.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(GSTReturn).filter(GSTReturn.tenant_id == tenant_id).delete(synchronize_session=False)

        # 3. Delete parent transaction documents
        db.query(Invoice).filter(Invoice.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(Bill).filter(Bill.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(Payment).filter(Payment.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(BillPayment).filter(BillPayment.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(Expense).filter(Expense.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(JournalEntry).filter(JournalEntry.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(InventoryAdjustment).filter(InventoryAdjustment.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(DeliveryChallan).filter(DeliveryChallan.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(SalesOrder).filter(SalesOrder.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(PurchaseOrder).filter(PurchaseOrder.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(BankStatement).filter(BankStatement.tenant_id == tenant_id).delete(synchronize_session=False)

        # 4. Delete master data
        db.query(Contact).filter(Contact.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(Product).filter(Product.tenant_id == tenant_id).delete(synchronize_session=False)
        db.query(AuditLog).filter(AuditLog.tenant_id == tenant_id).delete(synchronize_session=False)

        # Reset account balances
        db.query(Account).filter(Account.tenant_id == tenant_id).update(
            {Account.current_balance: 0, Account.opening_balance: 0},
            synchronize_session=False
        )

        log = AuditLog(
            action="tenant.purge",
            actor_id=current_user.id,
            tenant_id=tenant_id,
            entity_type="Tenant",
            after_state={"purged_by": current_user.email, "timestamp": datetime.now(timezone.utc).isoformat()},
        )
        db.add(log)
        db.commit()

    except Exception as e:
        db.rollback()
        logger.error(f"Failed to purge company data: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An error occurred while purging company data: {str(e)}"
        )

    return {"detail": "Company data purged successfully. All transactions, contacts, and products have been deleted."}
