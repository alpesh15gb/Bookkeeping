"""
src/core/security.py
JWT auth, password hashing, RBAC permissions.
All secrets are sourced from src.core.config (never hardcoded).
"""
from datetime import datetime, timedelta, timezone
from typing import List, Optional
import jwt
import bcrypt

from src.core.config import settings

# ---------------------------------------------------------------------------
# JWT Configuration — all from environment via settings
# ---------------------------------------------------------------------------
SECRET_KEY = settings.JWT_SECRET_KEY
ALGORITHM = settings.JWT_ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = settings.REFRESH_TOKEN_EXPIRE_DAYS


# ---------------------------------------------------------------------------
# RBAC Permissions
# ---------------------------------------------------------------------------
class Permissions:
    # Company Profiles
    TENANT_VIEW = "tenant:view"
    TENANT_UPDATE = "tenant:update"

    # Contact Context
    CONTACT_CREATE = "contact:create"
    CONTACT_VIEW = "contact:view"
    CONTACT_UPDATE = "contact:update"
    CONTACT_DELETE = "contact:delete"

    # Invoices/Billing Context
    INVOICE_CREATE = "invoice:create"
    INVOICE_VIEW = "invoice:view"
    INVOICE_UPDATE = "invoice:update"
    INVOICE_FINALIZE = "invoice:finalize"
    INVOICE_DELETE = "invoice:delete"

    # Payments Context
    PAYMENT_CREATE = "payment:create"
    PAYMENT_VIEW = "payment:view"
    PAYMENT_DELETE = "payment:delete"

    # Ledger & Accounting Context
    LEDGER_VIEW = "ledger:view"
    LEDGER_MANUAL_POST = "ledger:manual_post"
    ACCOUNTS_MANAGE = "accounts:manage"

    # Compliance & GST Context
    GST_REPORT_VIEW = "gst:report_view"
    GST_FILING_MANAGE = "gst:filing_manage"

    # Credit / Debit Notes
    CREDIT_NOTE_CREATE = "credit_note:create"
    CREDIT_NOTE_VIEW = "credit_note:view"
    DEBIT_NOTE_CREATE = "debit_note:create"
    DEBIT_NOTE_VIEW = "debit_note:view"

    # Audit Logs
    AUDIT_VIEW = "audit:view"

    # Reports & Analytics
    REPORTS_VIEW = "reports:view"

    # Expenses
    EXPENSE_CREATE = "expense:create"
    EXPENSE_VIEW = "expense:view"
    EXPENSE_EDIT = "expense:edit"
    EXPENSE_DELETE = "expense:delete"
    EXPENSE_FINALIZE = "expense:finalize"


ROLE_PERMISSIONS = {
    "superadmin": [perm for name, perm in Permissions.__dict__.items() if not name.startswith("__")],
    "owner": [
        Permissions.TENANT_VIEW, Permissions.TENANT_UPDATE,
        Permissions.CONTACT_CREATE, Permissions.CONTACT_VIEW,
        Permissions.CONTACT_UPDATE, Permissions.CONTACT_DELETE,
        Permissions.INVOICE_CREATE, Permissions.INVOICE_VIEW,
        Permissions.INVOICE_UPDATE, Permissions.INVOICE_FINALIZE, Permissions.INVOICE_DELETE,
        Permissions.PAYMENT_CREATE, Permissions.PAYMENT_VIEW, Permissions.PAYMENT_DELETE,
        Permissions.LEDGER_VIEW, Permissions.LEDGER_MANUAL_POST, Permissions.ACCOUNTS_MANAGE,
        Permissions.GST_REPORT_VIEW, Permissions.GST_FILING_MANAGE,
        Permissions.CREDIT_NOTE_CREATE, Permissions.CREDIT_NOTE_VIEW,
        Permissions.DEBIT_NOTE_CREATE, Permissions.DEBIT_NOTE_VIEW,
        Permissions.AUDIT_VIEW, Permissions.REPORTS_VIEW,
        Permissions.EXPENSE_CREATE, Permissions.EXPENSE_VIEW,
        Permissions.EXPENSE_EDIT, Permissions.EXPENSE_DELETE, Permissions.EXPENSE_FINALIZE,
    ],
    "accountant": [
        Permissions.TENANT_VIEW,
        Permissions.CONTACT_VIEW, Permissions.CONTACT_CREATE, Permissions.CONTACT_UPDATE,
        Permissions.INVOICE_VIEW, Permissions.INVOICE_FINALIZE,
        Permissions.PAYMENT_VIEW, Permissions.PAYMENT_CREATE,
        Permissions.LEDGER_VIEW, Permissions.LEDGER_MANUAL_POST, Permissions.ACCOUNTS_MANAGE,
        Permissions.GST_REPORT_VIEW, Permissions.GST_FILING_MANAGE,
        Permissions.CREDIT_NOTE_CREATE, Permissions.CREDIT_NOTE_VIEW,
        Permissions.DEBIT_NOTE_CREATE, Permissions.DEBIT_NOTE_VIEW,
        Permissions.AUDIT_VIEW, Permissions.REPORTS_VIEW,
        Permissions.EXPENSE_VIEW, Permissions.EXPENSE_CREATE, Permissions.EXPENSE_FINALIZE,
    ],
    "salesperson": [
        Permissions.CONTACT_VIEW, Permissions.CONTACT_CREATE, Permissions.CONTACT_UPDATE,
        Permissions.INVOICE_CREATE, Permissions.INVOICE_VIEW, Permissions.INVOICE_UPDATE,
        Permissions.PAYMENT_VIEW, Permissions.PAYMENT_CREATE,
    ],
    "auditor": [
        Permissions.TENANT_VIEW,
        Permissions.CONTACT_VIEW,
        Permissions.INVOICE_VIEW,
        Permissions.PAYMENT_VIEW,
        Permissions.LEDGER_VIEW,
        Permissions.GST_REPORT_VIEW,
        Permissions.CREDIT_NOTE_VIEW, Permissions.DEBIT_NOTE_VIEW,
        Permissions.AUDIT_VIEW, Permissions.REPORTS_VIEW,
    ],
}


# ---------------------------------------------------------------------------
# Password hashing — bcrypt
# ---------------------------------------------------------------------------

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Uses bcrypt to verify a plain text password against a stored hash."""
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except Exception:
        return False


def get_password_hash(password: str) -> str:
    """Uses bcrypt to hash a password string securely."""
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt())
    return hashed.decode("utf-8")


# ---------------------------------------------------------------------------
# JWT token generation & decoding
# ---------------------------------------------------------------------------

def create_access_token(user_id: str, scopes: List[str] = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": user_id,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
        "scopes": scopes or [],
        "type": "access",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    payload = {
        "sub": user_id,
        "exp": expire,
        "iat": datetime.now(timezone.utc),
        "type": "refresh",
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str, expected_type: str = None) -> dict:
    payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM], options={"require": ["exp", "iat"]})
    if expected_type and payload.get("type") != expected_type:
        raise jwt.InvalidTokenError(f"Expected token type '{expected_type}', got '{payload.get('type')}'")
    return payload
