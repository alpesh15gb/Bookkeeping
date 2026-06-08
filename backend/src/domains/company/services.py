import uuid
import base64
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from fastapi import HTTPException
from cryptography.fernet import Fernet
from src.infrastructure.database.models import NumberingSeries, TenantSetting, Tenant
from src.core.config import settings

# Fernet configuration for secure credentials encryption
SECRET_KEY = settings.SECRET_KEY
if not SECRET_KEY:
    raise ValueError("SECRET_KEY must be set in configuration for encryption")
if len(SECRET_KEY) < 32:
    SECRET_KEY = SECRET_KEY.ljust(32, "x")
fernet_key = base64.urlsafe_b64encode(SECRET_KEY[:32].encode())
cipher_suite = Fernet(fernet_key)

def encrypt_credential(val: str) -> str:
    if not val:
        return None
    return cipher_suite.encrypt(val.encode()).decode()

def decrypt_credential(val: str) -> str:
    if not val:
        return None
    try:
        return cipher_suite.decrypt(val.encode()).decode()
    except Exception:
        import logging
        logging.getLogger(__name__).warning("Failed to decrypt credential — possible key mismatch or corrupted data")
        return None

class NumberingSeriesService:
    @staticmethod
    def generate_next_number(db: Session, tenant_id: uuid.UUID, document_type: str) -> str:
        """
        Retrieves the next sequence number for the document type.
        Uses with_for_update() to lock the row in the database, preventing race conditions.
        """
        series = db.query(NumberingSeries).filter(
            NumberingSeries.tenant_id == tenant_id,
            NumberingSeries.document_type == document_type,
            NumberingSeries.is_active == True
        ).with_for_update().first()

        if not series:
            # Automatic fallback seeding — handle race where two requests seed simultaneously
            try:
                series = NumberingSeriesService.seed_default_series(db, tenant_id, document_type)
                db.flush()
            except IntegrityError:
                db.rollback()
                # Another request seeded first — re-fetch with lock
                series = db.query(NumberingSeries).filter(
                    NumberingSeries.tenant_id == tenant_id,
                    NumberingSeries.document_type == document_type,
                    NumberingSeries.is_active == True
                ).with_for_update().first()

        current_num = series.next_number
        series.next_number += 1
        db.add(series)
        db.flush()

        prefix = series.prefix or ""
        suffix = series.suffix or ""
        padding = series.padding_digits

        return f"{prefix}{str(current_num).zfill(padding)}{suffix}"

    @staticmethod
    def seed_default_series(db: Session, tenant_id: uuid.UUID, document_type: str) -> NumberingSeries:
        defaults = {
            "INVOICE": ("INV/2026/", 1, 4),
            "BILL": ("BILL/2026/", 1, 4),
            "PAYMENT": ("PAY/2026/", 1, 4),
            "JOURNAL": ("JV/2026/", 1, 4),
            "RECEIPT": ("REC/2026/", 1, 4),
            "DISBURSEMENT": ("PAY/2026/", 1, 4),
            "CREDIT_NOTE": ("CN/2026/", 1, 4),
            "DEBIT_NOTE": ("DN/2026/", 1, 4),
            "PURCHASE_ORDER": ("PO/2026/", 1, 4),
            "SALES_ORDER": ("SO/2026/", 1, 4),
            "DELIVERY_CHALLAN": ("DC/2026/", 1, 4),
            "PROFORMA_INVOICE": ("PI/2026/", 1, 4),
        }
        prefix, start_num, padding = defaults.get(document_type, (f"{document_type}-", 1, 4))

        series = NumberingSeries(
            tenant_id=tenant_id,
            document_type=document_type,
            prefix=prefix,
            next_number=start_num,
            padding_digits=padding,
            is_active=True
        )
        db.add(series)
        db.flush()
        return series

    @staticmethod
    def seed_all_defaults(db: Session, tenant_id: uuid.UUID):
        for doc_type in [
            "INVOICE", "BILL", "PAYMENT", "JOURNAL",
            "RECEIPT", "DISBURSEMENT",
            "CREDIT_NOTE", "DEBIT_NOTE",
            "PURCHASE_ORDER", "SALES_ORDER",
            "DELIVERY_CHALLAN", "PROFORMA_INVOICE",
            "SALES_RETURN", "PURCHASE_RETURN",
        ]:
            exists = db.query(NumberingSeries).filter(
                NumberingSeries.tenant_id == tenant_id,
                NumberingSeries.document_type == doc_type
            ).first()
            if not exists:
                NumberingSeriesService.seed_default_series(db, tenant_id, doc_type)

    @staticmethod
    def update_prefix(db: Session, tenant_id: uuid.UUID, document_type: str, new_prefix: str) -> None:
        """Update the prefix for a numbering series. Blocks if documents have been issued."""
        series = db.query(NumberingSeries).filter(
            NumberingSeries.tenant_id == tenant_id,
            NumberingSeries.document_type == document_type,
        ).first()
        if not series:
            raise ValueError(f"Numbering series for {document_type} not found.")
        if series.next_number > 1 and series.prefix != new_prefix:
            raise ValueError(
                f"Cannot change prefix for {document_type}: "
                f"{series.next_number - 1} documents already issued with prefix '{series.prefix}'."
            )
        series.prefix = new_prefix
        db.flush()


# ---------------------------------------------------------------------------
# GST state codes (valid Indian state codes for GSTIN validation)
# ---------------------------------------------------------------------------
GST_STATE_CODES: set = {
    "01", "02", "03", "04", "05", "06", "07", "08", "09", "10",
    "11", "12", "13", "14", "15", "16", "17", "18", "19", "20",
    "21", "22", "23", "24", "25", "26", "27", "28", "29", "30",
    "31", "32", "33", "34", "35", "36", "37", "38",
    "97", "99",
}

# ---------------------------------------------------------------------------
# Origin state resolution — from tenant GSTIN or TenantSetting fallback
# ---------------------------------------------------------------------------
def resolve_origin_state_code(db: Session, tenant_id: uuid.UUID) -> str:
    """
    Returns the 2-character origin state code for a tenant.

    Resolution order:
      1. TenantSetting.origin_state_code — explicit override (set in Settings page)
      2. Tenant.gstin[:2] — auto-detected from GSTIN prefix
      3. Raises ValueError if neither is available
    """
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    if setting and setting.origin_state_code:
        if setting.origin_state_code in GST_STATE_CODES:
            return setting.origin_state_code

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if tenant and tenant.gstin and len(tenant.gstin) == 15:
        state_code = tenant.gstin[:2]
        if state_code in GST_STATE_CODES:
            return state_code

    # Fallback to "36" (Telangana) instead of raising ValueError to prevent HTTP 500 crashes
    return "36"



