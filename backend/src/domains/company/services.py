import uuid
import re
import base64
from typing import Optional
from datetime import date, timedelta
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


def indian_financial_year(on_date: date) -> tuple[date, date, str]:
    """Return the statutory April-March financial year containing ``on_date``."""
    start_year = on_date.year if on_date.month >= 4 else on_date.year - 1
    start = date(start_year, 4, 1)
    end = date(start_year + 1, 3, 31)
    return start, end, f"{start_year}-{(start_year + 1) % 100:02d}"


class NumberingSeriesService:
    _PREFIXES = {
        "INVOICE": "INV",
        "BILL": "BILL",
        "PAYMENT": "PAY",
        "JOURNAL": "JV",
        "RECEIPT": "REC",
        "DISBURSEMENT": "PAY",
        "CREDIT_NOTE": "CN",
        "DEBIT_NOTE": "DN",
        "PURCHASE_ORDER": "PO",
        "SALES_ORDER": "SO",
        "DELIVERY_CHALLAN": "DC",
        "PROFORMA_INVOICE": "PI",
        "SALES_RETURN": "SR",
        "PURCHASE_RETURN": "PR",
        "TRANSFER": "ST",
    }

    @staticmethod
    def _financial_year_label(db: Session, tenant_id: uuid.UUID) -> str:
        """Return the Indian FY label used in human-readable document numbers."""
        tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
        start = tenant.financial_year_start if tenant and tenant.financial_year_start else indian_financial_year(date.today())[0]
        end = date(start.year + 1, start.month, start.day) - timedelta(days=1)
        return f"{start.year % 100:02d}-{end.year % 100:02d}"

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
        code = NumberingSeriesService._PREFIXES.get(document_type, document_type)
        prefix = f"{code}/{NumberingSeriesService._financial_year_label(db, tenant_id)}/"
        start_num, padding = 1, 4

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
            "TRANSFER",
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

_GSTIN_PATTERN = re.compile(r'^\d{2}[A-Z]{5}\d{4}[A-Z]\d[Z][A-Z\d]$')


# ---------------------------------------------------------------------------
# Shared GST helpers — single source of truth for GSTIN validation,
# tax_mode detection, and origin_state_code derivation.
# ---------------------------------------------------------------------------

def is_valid_gstin(gstin: Optional[str]) -> bool:
    """Returns True if gstin is a valid 15-character GSTIN with correct format."""
    if not gstin or len(gstin) != 15:
        return False
    if not _GSTIN_PATTERN.match(gstin):
        return False
    return gstin[:2] in GST_STATE_CODES


def detect_tax_mode(gstin: Optional[str], explicit_mode: Optional[str] = None) -> str:
    """
    Determines the tax_mode for a tenant.

    Priority:
      1. explicit_mode if provided and valid (GST_REGULAR, GST_COMPOSITION, NON_GST)
      2. GST_REGULAR if gstin is a valid 15-char GSTIN
      3. NON_GST otherwise
    """
    if explicit_mode in ("GST_REGULAR", "GST_COMPOSITION", "NON_GST"):
        return explicit_mode
    return "GST_REGULAR" if is_valid_gstin(gstin) else "NON_GST"


def derive_origin_state_code(gstin: Optional[str]) -> Optional[str]:
    """
    Derives the 2-character origin state code from a GSTIN prefix.
    Returns None if GSTIN is invalid or state code is not recognized.
    """
    if not is_valid_gstin(gstin):
        return None
    prefix = gstin[:2]
    return prefix if prefix in GST_STATE_CODES else None


# ---------------------------------------------------------------------------
# Origin state resolution — from tenant GSTIN or TenantSetting fallback
# ---------------------------------------------------------------------------
def resolve_origin_state_code(db: Session, tenant_id: uuid.UUID) -> str:
    """
    Returns the 2-character origin state code for a tenant.

    Resolution order:
      1. TenantSetting.origin_state_code — explicit override (set in Settings page)
      2. Tenant.gstin[:2] — auto-detected from GSTIN prefix
      3. Fallback to "36" (Telangana) to prevent HTTP 500 crashes
    """
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    if setting and setting.origin_state_code:
        if setting.origin_state_code in GST_STATE_CODES:
            return setting.origin_state_code

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if tenant:
        derived = derive_origin_state_code(tenant.gstin)
        if derived:
            return derived

    return "36"



