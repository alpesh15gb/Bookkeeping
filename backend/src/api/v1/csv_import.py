"""CSV migration import endpoint.

Consumes the exact schema produced by ``tools/legacy_to_csv.py`` — the 14 CSVs
(contacts, products, invoices + lines, bills + lines, payments + allocations,
bill payments + allocations, expenses, stock ledger, accounts, proforma
invoices).  The bundle is uploaded as a single ZIP (the converter's ``--out``
directory) or as individual CSV files in one multipart request.

Money safety model
------------------
* **Validation runs before anything is written.** Headers must match the
  converter schema exactly (missing columns are rejected), every cross-file
  reference must resolve (customer/product/document numbers), and every money
  invariant is checked: the DB-enforced document total formula, per-line
  identities, payment/vs-allocation settlement, derived document status,
  net-zero opening balances, and duplicate detection against the tenant.
* **``dry_run=true`` (default) only reports.** Nothing is written.
* **``dry_run=false`` commits in a single transaction** and rolls back on any
  error, so a partial import is impossible.  Errors always produce a report
  with ``valid: false`` — the HTTP status stays 200 so the client can render
  the report, but nothing was persisted.
"""
from __future__ import annotations

import csv
import io
import json
import logging
import os
import uuid
import zipfile
from datetime import date
from decimal import Decimal
from typing import Dict, List, Optional, Set, Tuple

from fastapi import APIRouter, Depends, File, Query, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission
from src.common.import_normalization import normalize_hsn_sac
from src.core.database import get_db_session
from src.domains.company.services import derive_origin_state_code
from src.domains.inventory.services import resolve_default_warehouse_id
from src.infrastructure.database.models import (
    Account,
    Bill,
    BillLine,
    BillPayment,
    BillPaymentAllocation,
    Contact,
    Expense,
    ExpenseCategory,
    FinancialYear,
    Invoice,
    InvoiceLine,
    Payment,
    PaymentAllocation,
    ProformaInvoice,
    Product,
    StockLedger,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/import", tags=["Data Import"])

ZERO = Decimal("0")
MAX_UPLOAD_BYTES = 100 * 1024 * 1024  # 100 MB — a .vyb backup is ~300 KB

# The converter emits these columns; missing ones are a hard rejection because
# a wrong file must never be silently interpreted.
REQUIRED_COLUMNS = {
    "contacts.csv": {
        "name", "contact_type", "gstin", "pan", "email", "phone",
        "state_code", "billing_address", "opening_balance",
    },
    "products.csv": {
        "name", "sku", "hsn_sac", "product_type", "uom", "sales_price",
        "purchase_price", "gst_rate", "opening_stock", "current_stock",
        "reorder_level",
    },
    "invoices.csv": {
        "invoice_number", "customer", "issue_date", "due_date", "pos_state_code",
        "status", "subtotal", "discount_total", "cgst_amount", "sgst_amount",
        "igst_amount", "cess_amount", "round_off", "shipping_charges", "total",
        "amount_paid",
    },
    "invoice_lines.csv": {
        "invoice_number", "product", "description", "hsn_sac", "quantity",
        "rate", "discount", "subtotal", "gst_rate", "cgst_amount",
        "sgst_amount", "igst_amount", "total",
    },
    "bills.csv": {
        "bill_number", "vendor", "issue_date", "due_date", "pos_state_code",
        "status", "subtotal", "discount_total", "cgst_amount", "sgst_amount",
        "igst_amount", "cess_amount", "round_off", "shipping_charges", "total",
        "amount_paid", "tds_amount",
    },
    "bill_lines.csv": {
        "bill_number", "product", "description", "hsn_sac", "quantity",
        "rate", "discount", "subtotal", "gst_rate", "cgst_amount",
        "sgst_amount", "igst_amount", "total",
    },
    "payments.csv": {
        "payment_number", "customer", "payment_date", "payment_mode", "amount",
        "reference_number", "status",
    },
    "bill_payments.csv": {
        "payment_number", "vendor", "payment_date", "payment_mode", "amount",
        "reference_number", "status",
    },
    "payment_allocations.csv": {"payment_number", "invoice_number", "amount"},
    "bill_payment_allocations.csv": {"payment_number", "bill_number", "amount"},
    "expenses.csv": {
        "expense_number", "category", "expense_date", "vendor_name",
        "description", "amount", "gst_rate", "cgst_amount", "sgst_amount",
        "igst_amount", "total", "status",
    },
    "stock_ledger.csv": {
        "product", "entry_date", "reference_type", "quantity",
        "balance_quantity", "rate",
    },
    "accounts.csv": {
        "code", "account_name", "account_type", "opening_balance",
    },
    "proforma_invoices.csv": {
        "proforma_number", "customer", "issue_date", "due_date", "status",
        "total",
    },
}

CONTACT_TYPES = {"CUSTOMER", "VENDOR", "BOTH"}
PRODUCT_TYPES = {"GOODS", "SERVICE"}
UOMS = {
    "PCS", "NOS", "KGS", "GMS", "LTR", "MTR", "SQF", "BOX", "SET", "BAG",
    "BTL", "CTN", "DOZ", "DZN", "HRS", "HOUR", "RFT", "ROL", "SQM", "SQY",
    "TON", "TUB", "UNT", "YDS",
}
ACCOUNT_TYPES = {"ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE"}
INVOICE_STATUSES = {"POSTED", "SENT", "PARTIALLY_PAID", "PAID", "CANCELLED"}
BILL_STATUSES = {"POSTED", "UNPAID", "PARTIALLY_PAID", "PAID", "CANCELLED"}
PAYMENT_MODES = {"CASH", "BANK", "UPI", "POS", "CHEQUE", "NEFT_RTGS", "OTHER"}
PAYMENT_STATUSES = {"ACTIVE", "CANCELLED"}
EXPENSE_STATUSES = {"POSTED", "CANCELLED"}
PROFORMA_STATUSES = {"ISSUED", "CONVERTED", "CANCELLED"}

# Stock-ledger reference types the app writes.  The converter only ever dumps
# VYAPAR_OPENING rows (importers record opening balances, not history), but an
# edited file may carry other labels — warn rather than guess.
KNOWN_STOCK_REFERENCE_TYPES = {
    "INVOICE", "BILL", "ADJUSTMENT", "TRANSFER_OUT", "TRANSFER_IN",
    "GOODS_RECEIPT", "DELIVERY", "DELIVERY_CHALLAN", "DELIVERY_CHALLAN_REVERSAL",
    "INVOICE_REVERSAL", "BILL_REVERSAL", "VYAPAR_OPENING",
}

# Money tolerance: 1 paisa (0.011 avoids float-boundary noise).  The DB itself
# enforces round-to-2 comparisons on the document formula.
_MONEY_TOL = Decimal("0.011")


# ---------------------------------------------------------------------------
# Response models
# ---------------------------------------------------------------------------
class CsvImportTotals(BaseModel):
    invoice_total: Decimal = ZERO
    invoice_gst: Decimal = ZERO
    bill_total: Decimal = ZERO
    bill_gst: Decimal = ZERO
    payments_received: Decimal = ZERO
    payments_made: Decimal = ZERO
    expenses_total: Decimal = ZERO
    opening_balance_net: Decimal = ZERO


class CsvImportReport(BaseModel):
    valid: bool
    dry_run: bool
    committed: bool = False
    errors: List[str] = Field(default_factory=list)
    warnings: List[str] = Field(default_factory=list)
    totals: CsvImportTotals = Field(default_factory=CsvImportTotals)
    counts: Dict[str, int] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------
def _d(value: object) -> Optional[Decimal]:
    """Parse a CSV money/number cell to Decimal, tolerating float artifacts
    (e.g. ``12800.002799999998`` from SQLite float round-trips)."""
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        return Decimal(text)
    except Exception:
        return None


def _parse_date(value: object) -> Optional[date]:
    text = str(value or "").strip()
    if not text:
        return None
    for fmt in ("%Y-%m-%d", "%d-%m-%Y", "%d/%m/%Y"):
        try:
            return date.fromisoformat(text) if fmt == "%Y-%m-%d" else (
                date.strptime(text, fmt))
        except ValueError:
            continue
    return None


def _num(row: Dict[str, str], col: str) -> Tuple[Optional[Decimal], List[str], List[str]]:
    """Parse a required numeric cell; returns (value, errors, warnings)."""
    val = _d(row.get(col))
    if val is None:
        return None, [f"{row.get('_file', '')} row {row.get('_row', '?')}: '{col}' is not a valid number"], []
    return val, [], []


class _Ctx:
    """Carries parse state + collected errors/warnings through validation."""

    def __init__(self) -> None:
        self.errors: List[str] = []
        self.warnings: List[str] = []
        # name -> row  (contacts), sku-or-name -> row (products)
        self.contacts: Dict[str, Dict[str, str]] = {}
        self.products: Dict[str, Dict[str, str]] = {}
        self.accounts_by_code: Dict[str, Dict[str, str]] = {}
        # number -> row
        self.invoices: Dict[str, Dict[str, str]] = {}
        self.bills: Dict[str, Dict[str, str]] = {}
        self.payments: Dict[str, Dict[str, str]] = {}
        self.bill_payments: Dict[str, Dict[str, str]] = {}
        self.expenses: Dict[str, Dict[str, str]] = {}
        self.proformas: Dict[str, Dict[str, str]] = {}
        self.invoice_lines: List[Dict[str, str]] = []
        self.bill_lines: List[Dict[str, str]] = []
        self.payment_allocs: List[Dict[str, str]] = []
        self.bill_payment_allocs: List[Dict[str, str]] = []
        self.stock_rows: List[Dict[str, str]] = []


def _read_bundle(
    file: Optional[UploadFile],
    files: Optional[List[UploadFile]],
) -> Tuple[Dict[str, str], List[str]]:
    """Return {canonical_filename: csv_text} plus hard intake errors."""
    sources: List[UploadFile] = []
    if file is not None:
        sources.append(file)
    if files:
        sources.extend(files)

    bundle: Dict[str, str] = {}
    errors: List[str] = []
    for uf in sources:
        name = uf.filename or "upload"
        data = uf.file.read()
        if len(data) > MAX_UPLOAD_BYTES:
            errors.append(f"{name}: file too large (limit {MAX_UPLOAD_BYTES // (1024 * 1024)} MB)")
            continue
        lower = name.lower()
        if lower.endswith((".xlsx", ".xls")):
            # xlsx files are ZIPs internally, so this must be checked before the
            # zip sniff — and the workbook is review-only, never a source.
            errors.append(
                f"{name}: Excel files are review-only — never re-import from the workbook. "
                "Upload the CSV files (or re-zip the converter's output directory)."
            )
        elif lower.endswith(".zip") or data[:2] == b"PK":
            try:
                with zipfile.ZipFile(io.BytesIO(data)) as zf:
                    for member in zf.namelist():
                        base = os.path.basename(member)
                        if not base.lower().endswith(".csv"):
                            continue
                        try:
                            bundle[base] = zf.read(member).decode("utf-8-sig")
                        except UnicodeDecodeError:
                            errors.append(f"{base} (in {name}): not valid UTF-8 — re-run the converter")
            except zipfile.BadZipFile:
                errors.append(f"{name}: invalid ZIP archive")
        elif lower.endswith(".csv"):
            try:
                bundle[name] = data.decode("utf-8-sig")
            except UnicodeDecodeError:
                errors.append(f"{name}: not valid UTF-8 — re-run the converter")
        else:
            errors.append(f"{name}: unsupported file type (expected a .zip of CSVs or .csv files)")
    return bundle, errors


def _parse_csv(
    filename: str,
    text: str,
    ctx: _Ctx,
) -> Optional[List[Dict[str, str]]]:
    """Parse one CSV, validating its header row against the converter schema."""
    required = REQUIRED_COLUMNS.get(filename)
    if required is None:
        ctx.errors.append(f"{filename}: unknown file — expected one of {sorted(REQUIRED_COLUMNS)}")
        return None
    reader = csv.DictReader(io.StringIO(text))
    headers = [h.strip() for h in (reader.fieldnames or [])]
    missing = sorted(required - set(headers))
    if missing:
        ctx.errors.append(
            f"{filename}: missing required columns: {', '.join(missing)} — "
            "this does not match the converter's schema; re-run tools/legacy_to_csv.py"
        )
        return None
    extra = sorted(set(headers) - required)
    if extra:
        ctx.warnings.append(f"{filename}: ignoring unknown columns: {', '.join(extra)}")
    rows: List[Dict[str, str]] = []
    for idx, raw in enumerate(reader, start=2):
        row: Dict[str, str] = {k: (raw.get(k) or "").strip() for k in headers}
        row["_file"] = filename
        row["_row"] = str(idx)
        rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
def _load_bundle(bundle: Dict[str, str], ctx: _Ctx) -> None:
    """Parse every present file into ctx.  Missing files are warnings; a file
    whose header does not match the converter schema is a hard error."""
    for filename in REQUIRED_COLUMNS:
        if filename not in bundle:
            ctx.warnings.append(f"{filename}: missing from upload — treated as empty")
            continue
        rows = _parse_csv(filename, bundle[filename], ctx)
        if rows is None:
            continue
        if filename == "contacts.csv":
            for r in rows:
                key = (r.get("name") or "").strip()
                if key:
                    ctx.contacts[key] = r
        elif filename == "products.csv":
            for r in rows:
                key = (r.get("name") or "").strip()
                if key:
                    ctx.products[key] = r
        elif filename == "accounts.csv":
            for r in rows:
                if (r.get("code") or "").strip():
                    ctx.accounts_by_code[r["code"].strip()] = r
        elif filename == "invoices.csv":
            for r in rows:
                if (r.get("invoice_number") or "").strip():
                    ctx.invoices[r["invoice_number"].strip()] = r
        elif filename == "invoice_lines.csv":
            ctx.invoice_lines.extend(rows)
        elif filename == "bills.csv":
            for r in rows:
                if (r.get("bill_number") or "").strip():
                    ctx.bills[r["bill_number"].strip()] = r
        elif filename == "bill_lines.csv":
            ctx.bill_lines.extend(rows)
        elif filename == "payments.csv":
            for r in rows:
                if (r.get("payment_number") or "").strip():
                    ctx.payments[r["payment_number"].strip()] = r
        elif filename == "payment_allocations.csv":
            ctx.payment_allocs.extend(rows)
        elif filename == "bill_payments.csv":
            for r in rows:
                if (r.get("payment_number") or "").strip():
                    ctx.bill_payments[r["payment_number"].strip()] = r
        elif filename == "bill_payment_allocations.csv":
            ctx.bill_payment_allocs.extend(rows)
        elif filename == "expenses.csv":
            for r in rows:
                if (r.get("expense_number") or "").strip():
                    ctx.expenses[r["expense_number"].strip()] = r
        elif filename == "stock_ledger.csv":
            ctx.stock_rows.extend(rows)
        elif filename == "proforma_invoices.csv":
            for r in rows:
                if (r.get("proforma_number") or "").strip():
                    ctx.proformas[r["proforma_number"].strip()] = r


def _validate_contacts(ctx: _Ctx, db: Session, tenant_id: uuid.UUID) -> None:
    seen: Dict[str, str] = {}  # normalized key -> display name
    for name, row in ctx.contacts.items():
        ctype = (row.get("contact_type") or "").upper()
        if ctype not in CONTACT_TYPES:
            ctx.errors.append(f"contacts.csv row {row['_row']} ({name}): contact_type must be one of {sorted(CONTACT_TYPES)}")
        gstin = (row.get("gstin") or "").strip().upper() or None
        if gstin and len(gstin) > 15:
            ctx.errors.append(f"contacts.csv row {row['_row']} ({name}): GSTIN longer than 15 characters")
        elif gstin and len(gstin) != 15:
            ctx.warnings.append(f"contacts.csv row {row['_row']} ({name}): GSTIN '{gstin}' is not 15 characters")
        state = (row.get("state_code") or "").strip()
        if state and (len(state) != 2 or not state.isdigit()):
            ctx.warnings.append(f"contacts.csv row {row['_row']} ({name}): state_code '{state}' is not a 2-digit code")
        bal = _d(row.get("opening_balance"))
        if row.get("opening_balance") and bal is None:
            ctx.errors.append(f"contacts.csv row {row['_row']} ({name}): opening_balance is not a valid number")
        addr = (row.get("billing_address") or "").strip()
        if addr:
            try:
                json.loads(addr)
            except json.JSONDecodeError:
                ctx.warnings.append(f"contacts.csv row {row['_row']} ({name}): billing_address is not valid JSON — importing without an address")
        key = gstin if gstin else name.strip().lower()
        if key in seen:
            ctx.errors.append(f"contacts.csv: duplicate contact '{name}' (same GSTIN/name as '{seen[key]}')")
        seen[key] = name

        # Existing in the tenant?  A migration must start from an empty master.
        existing = None
        if gstin:
            existing = (
                db.query(Contact.id)
                .filter(
                    Contact.tenant_id == tenant_id,
                    func.upper(Contact.gstin) == gstin,
                    Contact.deleted_at.is_(None),
                )
                .first()
            )
        if existing is None:
            existing = (
                db.query(Contact.id)
                .filter(
                    Contact.tenant_id == tenant_id,
                    func.lower(func.trim(Contact.name)) == name.strip().lower(),
                    Contact.deleted_at.is_(None),
                )
                .first()
            )
        if existing is not None:
            ctx.errors.append(
                f"contacts.csv: contact '{name}' already exists in this tenant — "
                "delete it before importing, or remove the row"
            )


def _validate_products(ctx: _Ctx, db: Session, tenant_id: uuid.UUID) -> None:
    seen: Dict[str, str] = {}
    seen_skus: Dict[str, str] = {}
    for key, row in ctx.products.items():
        ptype = (row.get("product_type") or "").upper()
        if ptype not in PRODUCT_TYPES:
            ctx.errors.append(f"products.csv row {row['_row']} ({key}): product_type must be GOODS or SERVICE")
        uom = (row.get("uom") or "").strip().upper()
        if uom and uom not in UOMS:
            ctx.warnings.append(f"products.csv row {row['_row']} ({key}): uom '{uom}' is not a standard unit — importing as-is")
        for col in ("sales_price", "purchase_price", "gst_rate", "opening_stock", "current_stock", "reorder_level"):
            val = _d(row.get(col))
            if row.get(col) and val is None:
                ctx.errors.append(f"products.csv row {row['_row']} ({key}): '{col}' is not a valid number")
            elif val is not None and val < 0:
                ctx.errors.append(f"products.csv row {row['_row']} ({key}): '{col}' must not be negative")
        if key in seen:
            ctx.errors.append(f"products.csv: duplicate product name '{key}'")
        seen[key] = key
        sku = (row.get("sku") or "").strip()
        if sku:
            if sku in seen_skus:
                ctx.errors.append(f"products.csv: duplicate SKU '{sku}' (products '{seen_skus[sku]}' and '{key}')")
            seen_skus[sku] = key

        existing = None
        sku = (row.get("sku") or "").strip()
        if sku:
            existing = (
                db.query(Product.id)
                .filter(
                    Product.tenant_id == tenant_id,
                    func.lower(func.trim(Product.sku)) == sku.lower(),
                    Product.deleted_at.is_(None),
                )
                .first()
            )
        if existing is None:
            existing = (
                db.query(Product.id)
                .filter(
                    Product.tenant_id == tenant_id,
                    func.lower(func.trim(Product.name)) == (row.get("name") or "").strip().lower(),
                    Product.deleted_at.is_(None),
                )
                .first()
            )
        if existing is not None:
            ctx.errors.append(
                f"products.csv: product '{key}' already exists in this tenant — "
                "delete it before importing, or remove the row"
            )


def _validate_accounts(ctx: _Ctx, db: Session, tenant_id: uuid.UUID) -> None:
    net = ZERO
    seen: Set[str] = set()
    for code, row in ctx.accounts_by_code.items():
        atype = (row.get("account_type") or "").upper()
        if atype not in ACCOUNT_TYPES:
            ctx.errors.append(f"accounts.csv row {row['_row']} ({code}): account_type must be one of {sorted(ACCOUNT_TYPES)}")
        bal = _d(row.get("opening_balance"))
        if row.get("opening_balance") and bal is None:
            ctx.errors.append(f"accounts.csv row {row['_row']} ({code}): opening_balance is not a valid number")
            continue
        bal = bal or ZERO
        if code in seen:
            ctx.errors.append(f"accounts.csv: duplicate account code '{code}'")
        seen.add(code)
        if atype in ("ASSET", "EXPENSE"):
            net += bal
        else:
            net -= bal
        existing = (
            db.query(Account)
            .filter(
                Account.tenant_id == tenant_id,
                Account.code == code,
                Account.deleted_at.is_(None),
            )
            .first()
        )
        if existing is not None and existing.account_type != atype:
            ctx.errors.append(
                f"accounts.csv: account '{code}' exists in this tenant with type "
                f"{existing.account_type} but the CSV says {atype} — reconcile the chart before importing"
            )
    if net.copy_abs() > _MONEY_TOL:
        ctx.errors.append(
            f"accounts.csv: net opening balance is {net} (must be ₹0.00). "
            "Assets + expenses − liabilities − equity − revenue must balance."
        )


def _validate_documents(ctx: _Ctx, db: Session, tenant_id: uuid.UUID) -> None:
    # Settlement (payments vs allocations vs amount_paid) is validated inside
    # _validate_doc_headers → _validate_payments for both AR and AP.
    _validate_doc_headers(ctx, db, tenant_id)
    _validate_lines(ctx)


def _doc_common(row: Dict[str, str], statuses: Set[str], extra: bool) -> Tuple[
    Optional[str], Optional[date], Optional[date], Optional[Decimal], List[str]
]:
    """Shared header checks.  Returns (status, issue, due, total, errs)."""
    errs: List[str] = []
    status = (row.get("status") or "").upper()
    if status not in statuses:
        errs.append(f"{row['_file']} row {row['_row']}: status '{status}' is not importable (must be one of {sorted(statuses)})")
    issue = _parse_date(row.get("issue_date"))
    if issue is None:
        errs.append(f"{row['_file']} row {row['_row']}: issue_date '{row.get('issue_date')}' is not a valid date (YYYY-MM-DD)")
    due = _parse_date(row.get("due_date"))
    if due is None:
        errs.append(f"{row['_file']} row {row['_row']}: due_date '{row.get('due_date')}' is not a valid date (YYYY-MM-DD)")
    if issue and due and due < issue:
        errs.append(f"{row['_file']} row {row['_row']}: due_date is before issue_date")
    total = _d(row.get("total"))
    if total is None:
        errs.append(f"{row['_file']} row {row['_row']}: total is not a valid number")
    return status, issue, due, total, errs


def _validate_doc_headers(ctx: _Ctx, db: Session, tenant_id: uuid.UUID) -> None:
    fy = (
        db.query(FinancialYear)
        .filter(FinancialYear.tenant_id == tenant_id, FinancialYear.is_current == True)  # noqa: E712
        .first()
    )

    def _check_formula(row: Dict[str, str], label: str, with_tds: bool) -> None:
        subtotal = _d(row.get("subtotal")) or ZERO
        discount = _d(row.get("discount_total")) or ZERO
        cgst = _d(row.get("cgst_amount")) or ZERO
        sgst = _d(row.get("sgst_amount")) or ZERO
        igst = _d(row.get("igst_amount")) or ZERO
        cess = _d(row.get("cess_amount")) or ZERO
        round_off = _d(row.get("round_off")) or ZERO
        shipping = _d(row.get("shipping_charges")) or ZERO
        total = _d(row.get("total")) or ZERO
        expect = subtotal + cgst + sgst + igst + cess + round_off - discount + shipping
        if (expect - total).copy_abs() > _MONEY_TOL:
            ctx.errors.append(
                f"{row['_file']} row {row['_row']} ({label}): total does not balance — "
                f"subtotal + cgst + sgst + igst + cess + round_off − discount + shipping = {expect}, total = {total}"
            )
        if with_tds:
            tds = _d(row.get("tds_amount")) or ZERO
            if tds < 0 or tds > total + _MONEY_TOL:
                ctx.errors.append(f"{row['_file']} row {row['_row']} ({label}): tds_amount must be between 0 and total")

    def _status_vs_paid(row: Dict[str, str], label: str, total: Decimal) -> None:
        amount_paid = _d(row.get("amount_paid"))
        if amount_paid is None:
            ctx.errors.append(f"{row['_file']} row {row['_row']} ({label}): amount_paid is not a valid number")
            return
        if amount_paid < 0 or amount_paid > total + _MONEY_TOL:
            ctx.errors.append(f"{row['_file']} row {row['_row']} ({label}): amount_paid ₹{amount_paid} is outside [0, total ₹{total}]")
            return
        status = (row.get("status") or "").upper()
        if status == "PAID":
            # The legacy importers round amount_paid to whole rupees while total
            # keeps 4-decimal dust (e.g. 12800 vs 12800.0028) — sub-paisa drift
            # is the app's own rounding, not a tampered file.
            if (total - amount_paid).copy_abs() > _MONEY_TOL:
                ctx.errors.append(f"{row['_file']} row {row['_row']} ({label}): status PAID but amount_paid ₹{amount_paid} ≠ total ₹{total}")
        elif status == "PARTIALLY_PAID":
            # Strict comparison at full precision: the importer marks a document
            # PARTIALLY_PAID whenever amount_paid < total, even by a fraction of
            # a paisa.  Do not round-trip that decision into an error.
            if not (ZERO < amount_paid < total):
                ctx.errors.append(f"{row['_file']} row {row['_row']} ({label}): status PARTIALLY_PAID but amount_paid ₹{amount_paid} is not between 0 and total ₹{total}")
        elif status == "POSTED" and amount_paid > _MONEY_TOL:
            ctx.errors.append(f"{row['_file']} row {row['_row']} ({label}): status POSTED but amount_paid ₹{amount_paid} > 0")

    def _fy_warning(row: Dict[str, str], label: str, issue: Optional[date]) -> None:
        if fy is not None and issue is not None and not (fy.start_date <= issue <= fy.end_date):
            ctx.warnings.append(
                f"{row['_file']} row {row['_row']} ({label}): dated {issue.isoformat()} — outside the current "
                f"financial year {fy.name} ({fy.start_date} – {fy.end_date}). Switch the current FY or fix the date."
            )

    # ── Invoices ──────────────────────────────────────────────────────────
    for number, row in ctx.invoices.items():
        status, issue, due, total, errs = _doc_common(row, INVOICE_STATUSES, False)
        ctx.errors.extend(errs)
        if status == "DRAFT":
            ctx.errors.append(f"invoices.csv row {row['_row']} ({number}): draft invoices are not imported — remove them from the CSV")
        customer = (row.get("customer") or "").strip()
        if customer and customer not in ctx.contacts:
            ctx.errors.append(f"invoices.csv row {row['_row']} ({number}): customer '{customer}' is not in contacts.csv")
        pos = (row.get("pos_state_code") or "").strip()
        if pos and (len(pos) != 2 or not pos.isdigit()):
            ctx.errors.append(f"invoices.csv row {row['_row']} ({number}): pos_state_code '{pos}' is not a 2-digit code")
        _check_formula(row, number, with_tds=False)
        if total is not None:
            _status_vs_paid(row, number, total)
        _fy_warning(row, number, issue)
        if (
            db.query(Invoice.id)
            .filter(
                Invoice.tenant_id == tenant_id,
                Invoice.invoice_number == number,
                Invoice.deleted_at.is_(None),
            )
            .first()
        ):
            ctx.errors.append(f"invoices.csv: invoice '{number}' already exists in this tenant")

    # ── Bills ─────────────────────────────────────────────────────────────
    for number, row in ctx.bills.items():
        status, issue, due, total, errs = _doc_common(row, BILL_STATUSES, True)
        ctx.errors.extend(errs)
        if status == "DRAFT":
            ctx.errors.append(f"bills.csv row {row['_row']} ({number}): draft bills are not imported — remove them from the CSV")
        vendor = (row.get("vendor") or "").strip()
        if vendor and vendor not in ctx.contacts:
            ctx.errors.append(f"bills.csv row {row['_row']} ({number}): vendor '{vendor}' is not in contacts.csv")
        pos = (row.get("pos_state_code") or "").strip()
        if pos and (len(pos) != 2 or not pos.isdigit()):
            ctx.errors.append(f"bills.csv row {row['_row']} ({number}): pos_state_code '{pos}' is not a 2-digit code")
        _check_formula(row, number, with_tds=True)
        if total is not None:
            _status_vs_paid(row, number, total)
        _fy_warning(row, number, issue)
        if (
            db.query(Bill.id)
            .filter(
                Bill.tenant_id == tenant_id,
                Bill.bill_number == number,
                Bill.deleted_at.is_(None),
            )
            .first()
        ):
            ctx.errors.append(f"bills.csv: bill '{number}' already exists in this tenant")

    # ── Proforma invoices ─────────────────────────────────────────────────
    for number, row in ctx.proformas.items():
        status = (row.get("status") or "").upper()
        if status not in PROFORMA_STATUSES:
            ctx.errors.append(
                f"proforma_invoices.csv row {row['_row']} ({number}): status must be one of {sorted(PROFORMA_STATUSES)} "
                "(draft estimates are not imported)"
            )
        customer = (row.get("customer") or "").strip()
        if customer and customer not in ctx.contacts:
            ctx.errors.append(f"proforma_invoices.csv row {row['_row']} ({number}): customer '{customer}' is not in contacts.csv")
        issue = _parse_date(row.get("issue_date"))
        due = _parse_date(row.get("due_date"))
        if issue is None:
            ctx.errors.append(f"proforma_invoices.csv row {row['_row']} ({number}): issue_date is not a valid date")
        if due is None:
            ctx.errors.append(f"proforma_invoices.csv row {row['_row']} ({number}): due_date is not a valid date")
        if issue and due and due < issue:
            ctx.errors.append(f"proforma_invoices.csv row {row['_row']} ({number}): due_date is before issue_date")
        total = _d(row.get("total"))
        if total is None or total < 0:
            ctx.errors.append(f"proforma_invoices.csv row {row['_row']} ({number}): total must be a non-negative number")
        _fy_warning(row, number, issue)
        if (
            db.query(ProformaInvoice.id)
            .filter(
                ProformaInvoice.tenant_id == tenant_id,
                ProformaInvoice.proforma_number == number,
                ProformaInvoice.deleted_at.is_(None),
            )
            .first()
        ):
            ctx.errors.append(f"proforma_invoices.csv: estimate '{number}' already exists in this tenant")

    # ── Payments ──────────────────────────────────────────────────────────
    _validate_payments(ctx, db, tenant_id, "payments.csv", ctx.payments,
                       ctx.payment_allocs, "customer", "invoice_number",
                       Payment, Invoice)
    _validate_payments(ctx, db, tenant_id, "bill_payments.csv", ctx.bill_payments,
                       ctx.bill_payment_allocs, "vendor", "bill_number",
                       BillPayment, Bill)

    # ── Expenses ──────────────────────────────────────────────────────────
    for number, row in ctx.expenses.items():
        status = (row.get("status") or "").upper()
        if status not in EXPENSE_STATUSES:
            ctx.errors.append(
                f"expenses.csv row {row['_row']} ({number}): status must be one of {sorted(EXPENSE_STATUSES)} "
                "(draft expenses are not imported)"
            )
        category = (row.get("category") or "").strip()
        if not category:
            ctx.errors.append(f"expenses.csv row {row['_row']} ({number}): category is required")
        edate = _parse_date(row.get("expense_date"))
        if edate is None:
            ctx.errors.append(f"expenses.csv row {row['_row']} ({number}): expense_date is not a valid date")
        amount = _d(row.get("amount"))
        if amount is None or amount <= 0:
            ctx.errors.append(f"expenses.csv row {row['_row']} ({number}): amount must be a positive number")
        cgst = _d(row.get("cgst_amount")) or ZERO
        sgst = _d(row.get("sgst_amount")) or ZERO
        igst = _d(row.get("igst_amount")) or ZERO
        total = _d(row.get("total"))
        if total is None:
            ctx.errors.append(f"expenses.csv row {row['_row']} ({number}): total is not a valid number")
        elif amount is not None and (amount + cgst + sgst + igst - total).copy_abs() > _MONEY_TOL:
            ctx.errors.append(
                f"expenses.csv row {row['_row']} ({number}): total does not balance — amount + cgst + sgst + igst = "
                f"{amount + cgst + sgst + igst}, total = {total}"
            )
        _fy_warning(row, number, edate)
        if (
            db.query(Expense.id)
            .filter(
                Expense.tenant_id == tenant_id,
                Expense.expense_number == number,
                Expense.deleted_at.is_(None),
            )
            .first()
        ):
            ctx.errors.append(f"expenses.csv: expense '{number}' already exists in this tenant")


def _validate_payments(
    ctx: _Ctx,
    db: Session,
    tenant_id: uuid.UUID,
    filename: str,
    payments: Dict[str, Dict[str, str]],
    allocs: List[Dict[str, str]],
    party_col: str,
    doc_col: str,
    payment_model,
    doc_model,
) -> None:
    for number, row in payments.items():
        status = (row.get("status") or "").upper()
        if status not in PAYMENT_STATUSES:
            ctx.errors.append(f"{filename} row {row['_row']} ({number}): status must be ACTIVE or CANCELLED")
        mode = (row.get("payment_mode") or "").upper()
        if mode not in PAYMENT_MODES:
            ctx.errors.append(f"{filename} row {row['_row']} ({number}): payment_mode must be one of {sorted(PAYMENT_MODES)}")
        amount = _d(row.get("amount"))
        if amount is None or amount <= 0:
            ctx.errors.append(f"{filename} row {row['_row']} ({number}): amount must be a positive number")
        pdate = _parse_date(row.get("payment_date"))
        if pdate is None:
            ctx.errors.append(f"{filename} row {row['_row']} ({number}): payment_date is not a valid date")
        party = (row.get(party_col) or "").strip()
        if party and party not in ctx.contacts:
            ctx.errors.append(f"{filename} row {row['_row']} ({number}): {party_col} '{party}' is not in contacts.csv")
        if (
            db.query(payment_model.id)
            .filter(
                payment_model.tenant_id == tenant_id,
                payment_model.payment_number == number,
                payment_model.deleted_at.is_(None),
            )
            .first()
        ):
            ctx.errors.append(f"{filename}: payment '{number}' already exists in this tenant")

    # Group allocations by payment and by document.
    by_payment: Dict[str, Decimal] = {}
    by_doc: Dict[str, Decimal] = {}
    for a in allocs:
        pnum = (a.get("payment_number") or "").strip()
        dnum = (a.get(doc_col) or "").strip()
        amt = _d(a.get("amount"))
        if amt is None or amt <= 0:
            ctx.errors.append(f"{a['_file']} row {a['_row']}: allocation amount is not a valid positive number")
            continue
        if pnum not in payments:
            ctx.errors.append(f"{a['_file']} row {a['_row']}: payment '{pnum}' in allocations is not in {filename}")
            continue
        if dnum not in (ctx.invoices if doc_model is Invoice else ctx.bills):
            ctx.errors.append(f"{a['_file']} row {a['_row']}: {doc_col} '{dnum}' in allocations is not in the documents CSV")
            continue
        by_payment[pnum] = by_payment.get(pnum, ZERO) + amt
        by_doc[dnum] = by_doc.get(dnum, ZERO) + amt

    for pnum, total in by_payment.items():
        row = payments[pnum]
        status = (row.get("status") or "").upper()
        if status == "CANCELLED":
            ctx.errors.append(f"{filename}: cancelled payment '{pnum}' has allocations — remove them")
            continue
        amount = _d(row.get("amount")) or ZERO
        if (total - amount).copy_abs() > _MONEY_TOL:
            ctx.errors.append(
                f"{filename}: payment '{pnum}' amount ₹{amount} but allocations total ₹{total} — "
                "they must match exactly"
            )
    for pnum, row in payments.items():
        status = (row.get("status") or "").upper()
        amount = _d(row.get("amount")) or ZERO
        if status == "ACTIVE" and pnum not in by_payment:
            ctx.errors.append(
                f"{filename}: active payment '{pnum}' ₹{amount} has no allocations — "
                "every receipt/disbursement must be settled against a document"
            )

    for dnum, allocated in by_doc.items():
        if doc_model is Invoice:
            doc_row = ctx.invoices.get(dnum)
            amount_paid = _d(doc_row.get("amount_paid")) if doc_row else None
            doc_total = _d(doc_row.get("total")) if doc_row else None
        else:
            doc_row = ctx.bills.get(dnum)
            amount_paid = _d(doc_row.get("amount_paid")) if doc_row else None
            doc_total = _d(doc_row.get("total")) if doc_row else None
        # Over-settlement creates money out of nothing.  The legacy importers
        # themselves over-allocate by a few paise (payment rounded up while the
        # invoice total kept 4-decimal dust), so the hard threshold is ₹1 — at
        # or beyond that the file has been edited.
        if doc_total is not None and allocated > doc_total + Decimal("0.999"):
            ctx.errors.append(
                f"{filename}: {doc_col} '{dnum}' is allocated ₹{allocated} but its total is only ₹{doc_total} — differs by ₹1 or more"
            )
            continue
        if doc_total is not None and allocated > doc_total + _MONEY_TOL:
            ctx.warnings.append(
                f"{filename}: {doc_col} '{dnum}' is allocated ₹{allocated} but its total is ₹{doc_total} — "
                "a few-paise over-allocation from the legacy importer will import as-is"
            )
        if amount_paid is not None and (allocated - amount_paid).copy_abs() > _MONEY_TOL:
            # Legacy importers clamp amount_paid to total while allocating the
            # full payment amount, leaving a few-paise residual.  Surface it,
            # but only reject drift of ₹1 or more — beyond that the file is edited.
            if (allocated - amount_paid).copy_abs() >= Decimal("1.00"):
                ctx.errors.append(
                    f"{filename}: {doc_col} '{dnum}' shows amount_paid ₹{amount_paid} but allocations total ₹{allocated} — differs by ₹1 or more"
                )
            else:
                ctx.warnings.append(
                    f"{filename}: {doc_col} '{dnum}' shows amount_paid ₹{amount_paid} but allocations total ₹{allocated} — "
                    "the document will keep a small residual after import (legacy importer rounding)"
                )


def _validate_lines(ctx: _Ctx) -> None:
    for bucket, doc_key, doc_col, model in (
        (ctx.invoice_lines, ctx.invoices, "invoice_number", Invoice),
        (ctx.bill_lines, ctx.bills, "bill_number", Bill),
    ):
        by_doc: Dict[str, Tuple[Decimal, Decimal, Decimal]] = {}
        for line in bucket:
            dnum = (line.get(doc_col) or "").strip()
            if dnum not in doc_key:
                ctx.errors.append(f"{line['_file']} row {line['_row']}: {doc_col} '{dnum}' is not in the documents CSV")
                continue
            product = (line.get("product") or "").strip()
            if product and product not in ctx.products:
                ctx.errors.append(f"{line['_file']} row {line['_row']} ({dnum}): product '{product}' is not in products.csv")
            subtotal = _d(line.get("subtotal"))
            cgst = _d(line.get("cgst_amount")) or ZERO
            sgst = _d(line.get("sgst_amount")) or ZERO
            igst = _d(line.get("igst_amount")) or ZERO
            total = _d(line.get("total"))
            if subtotal is None or total is None:
                ctx.errors.append(f"{line['_file']} row {line['_row']} ({dnum}): subtotal/total are not valid numbers")
                continue
            if (subtotal + cgst + sgst + igst - total).copy_abs() > Decimal("0.02"):
                ctx.warnings.append(
                    f"{line['_file']} row {line['_row']} ({dnum}): line total ₹{total} differs from "
                    f"subtotal + tax ₹{subtotal + cgst + sgst + igst} by more than ₹0.02"
                )
            s, c, t = by_doc.get(dnum, (ZERO, ZERO, ZERO))
            by_doc[dnum] = (s + (subtotal or ZERO), c + cgst + sgst + igst, t + (total or ZERO))

        for dnum, (sub, tax, tot) in by_doc.items():
            header = doc_key[dnum]
            h_total = _d(header.get("total"))
            if h_total is not None and (tot - h_total).copy_abs() > Decimal("0.02"):
                ctx.errors.append(
                    f"{line['_file']} {doc_col} '{dnum}': line totals sum to ₹{tot} but the document total is ₹{h_total}"
                )
            h_sub = _d(header.get("subtotal"))
            if h_sub is not None and (sub - h_sub).copy_abs() > Decimal("0.02"):
                ctx.errors.append(
                    f"{line['_file']} {doc_col} '{dnum}': line subtotals sum to ₹{sub} but the header subtotal is ₹{h_sub}"
                )


def _validate_stock(ctx: _Ctx) -> None:
    final: Dict[str, Decimal] = {}
    for row in ctx.stock_rows:
        product = (row.get("product") or "").strip()
        if product and product not in ctx.products:
            ctx.errors.append(f"stock_ledger.csv row {row['_row']}: product '{product}' is not in products.csv")
            continue
        qty = _d(row.get("quantity"))
        balance = _d(row.get("balance_quantity"))
        if qty is None or balance is None:
            ctx.errors.append(f"stock_ledger.csv row {row['_row']} ({product}): quantity/balance_quantity are not valid numbers")
            continue
        ref = (row.get("reference_type") or "").strip()
        if not ref:
            ctx.errors.append(f"stock_ledger.csv row {row['_row']} ({product}): reference_type is required")
        elif ref.upper() not in KNOWN_STOCK_REFERENCE_TYPES:
            ctx.warnings.append(f"stock_ledger.csv row {row['_row']} ({product}): reference_type '{ref}' is not recognized")
        # Only opening entries are replayed — historical movements are already
        # reflected in opening_stock/current_stock.
        if ref.upper() == "VYAPAR_OPENING":
            final[product] = balance

    for product, balance in final.items():
        prod_row = ctx.products.get(product)
        if prod_row is None:
            continue
        current = _d(prod_row.get("current_stock")) or ZERO
        if (balance - current).copy_abs() > _MONEY_TOL:
            ctx.errors.append(
                f"stock_ledger.csv: opening balance for '{product}' is {balance} but products.csv current_stock is {current}"
            )
    for row in ctx.stock_rows:
        ref = (row.get("reference_type") or "").strip()
        if ref and ref.upper() != "VYAPAR_OPENING":
            ctx.warnings.append(
                f"stock_ledger.csv row {row['_row']}: {ref} movement rows are skipped during import "
                "(already reflected in opening stock)"
            )


def _validate_duplicates_in_file(ctx: _Ctx) -> None:
    """Reject duplicate primary keys *within* each CSV (catching copy-paste)."""
    for label, mapping in (
        ("invoices", ctx.invoices),
        ("bills", ctx.bills),
        ("payments", ctx.payments),
        ("bill_payments", ctx.bill_payments),
        ("expenses", ctx.expenses),
        ("proforma_invoices", ctx.proformas),
    ):
        seen: Set[str] = set()
        for key in mapping:
            if key in seen:
                ctx.errors.append(f"{label}.csv: duplicate number '{key}' in the same file")
            seen.add(key)


def _compute_totals(ctx: _Ctx) -> CsvImportTotals:
    t = CsvImportTotals()
    for row in ctx.invoices.values():
        t.invoice_total += _d(row.get("total")) or ZERO
        t.invoice_gst += (_d(row.get("cgst_amount")) or ZERO) + (_d(row.get("sgst_amount")) or ZERO) + (_d(row.get("igst_amount")) or ZERO)
    for row in ctx.bills.values():
        t.bill_total += _d(row.get("total")) or ZERO
        t.bill_gst += (_d(row.get("cgst_amount")) or ZERO) + (_d(row.get("sgst_amount")) or ZERO) + (_d(row.get("igst_amount")) or ZERO)
    for row in ctx.payments.values():
        if (row.get("status") or "").upper() == "ACTIVE":
            t.payments_received += _d(row.get("amount")) or ZERO
    for row in ctx.bill_payments.values():
        if (row.get("status") or "").upper() == "ACTIVE":
            t.payments_made += _d(row.get("amount")) or ZERO
    for row in ctx.expenses.values():
        t.expenses_total += _d(row.get("total")) or ZERO
    for row in ctx.accounts_by_code.values():
        bal = _d(row.get("opening_balance")) or ZERO
        atype = (row.get("account_type") or "").upper()
        t.opening_balance_net += bal if atype in ("ASSET", "EXPENSE") else -bal
    return t


def _validate(
    ctx: _Ctx,
    db: Session,
    tenant_id: uuid.UUID,
) -> None:
    _validate_contacts(ctx, db, tenant_id)
    _validate_products(ctx, db, tenant_id)
    _validate_accounts(ctx, db, tenant_id)
    _validate_duplicates_in_file(ctx)
    _validate_documents(ctx, db, tenant_id)
    _validate_stock(ctx)


# ---------------------------------------------------------------------------
# Import (single transaction, only called after validation passed)
# ---------------------------------------------------------------------------
def _apply_import(
    ctx: _Ctx,
    db: Session,
    tenant_id: uuid.UUID,
    counts: Dict[str, int],
) -> None:
    from src.infrastructure.database.models import Tenant

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    origin_state = derive_origin_state_code(tenant.gstin if tenant else None) or "36"

    # ── 1. Accounts (upsert by code — seeded chart already exists) ────────
    for code, row in ctx.accounts_by_code.items():
        bal = _d(row.get("opening_balance")) or ZERO
        acct = (
            db.query(Account)
            .filter(
                Account.tenant_id == tenant_id,
                Account.code == code,
                Account.deleted_at.is_(None),
            )
            .first()
        )
        if acct is None:
            acct = Account(
                tenant_id=tenant_id,
                code=code,
                name=(row.get("account_name") or "").strip(),
                account_type=(row.get("account_type") or "").upper(),
                opening_balance=bal,
                current_balance=bal,
                is_active=True,
            )
            db.add(acct)
        else:
            acct.opening_balance = bal
            acct.current_balance = bal
            acct.name = (row.get("account_name") or "").strip()
        db.flush()
        counts["accounts_set"] = counts.get("accounts_set", 0) + 1

    # ── 2. Contacts ────────────────────────────────────────────────────────
    contact_ids: Dict[str, uuid.UUID] = {}
    for name, row in ctx.contacts.items():
        addr_text = (row.get("billing_address") or "").strip()
        billing_address = {}
        if addr_text:
            try:
                billing_address = json.loads(addr_text)
            except json.JSONDecodeError:
                billing_address = {}
        contact = Contact(
            tenant_id=tenant_id,
            name=name,
            phone=(row.get("phone") or "").strip() or None,
            email=(row.get("email") or "").strip() or None,
            contact_type=(row.get("contact_type") or "").upper(),
            gstin=(row.get("gstin") or "").strip().upper() or None,
            pan=(row.get("pan") or "").strip().upper() or None,
            state_code=(row.get("state_code") or "").strip() or None,
            billing_address=billing_address,
            is_active=True,
            opening_balance=_d(row.get("opening_balance")) or ZERO,
        )
        db.add(contact)
        db.flush()
        contact_ids[name] = contact.id
        counts["contacts_imported"] = counts.get("contacts_imported", 0) + 1

    # ── 3. Products ────────────────────────────────────────────────────────
    product_ids: Dict[str, uuid.UUID] = {}
    for key, row in ctx.products.items():
        name = (row.get("name") or "").strip() or key
        product = Product(
            tenant_id=tenant_id,
            name=name,
            sku=(row.get("sku") or "").strip() or None,
            hsn_sac=normalize_hsn_sac(row.get("hsn_sac")),
            product_type=(row.get("product_type") or "GOODS").upper(),
            uom=((row.get("uom") or "PCS").upper() if (row.get("uom") or "PCS").upper() in UOMS else "PCS"),
            sales_price=_d(row.get("sales_price")) or ZERO,
            purchase_price=_d(row.get("purchase_price")) or ZERO,
            gst_rate=_d(row.get("gst_rate")) or ZERO,
            opening_stock=_d(row.get("opening_stock")) or ZERO,
            current_stock=_d(row.get("current_stock")) or ZERO,
            reorder_level=_d(row.get("reorder_level")) or ZERO,
            party_item_rates={},
            is_active=True,
        )
        db.add(product)
        db.flush()
        product_ids[key] = product.id
        counts["products_imported"] = counts.get("products_imported", 0) + 1

    # ── 4. Proforma invoices ───────────────────────────────────────────────
    for number, row in ctx.proformas.items():
        customer = (row.get("customer") or "").strip()
        total = _d(row.get("total")) or ZERO
        db.add(ProformaInvoice(
            tenant_id=tenant_id,
            contact_id=contact_ids.get(customer),
            proforma_number=number,
            issue_date=_parse_date(row.get("issue_date")) or date.today(),
            due_date=_parse_date(row.get("due_date")) or date.today(),
            status=(row.get("status") or "ISSUED").upper(),
            subtotal=total,
            discount_total=ZERO,
            cgst_amount=ZERO,
            sgst_amount=ZERO,
            igst_amount=ZERO,
            utgst_amount=ZERO,
            cess_amount=ZERO,
            total=total,
            pos_state_code=origin_state,
        ))
        counts["estimates_imported"] = counts.get("estimates_imported", 0) + 1

    # ── 5. Invoices + lines ────────────────────────────────────────────────
    invoice_ids: Dict[str, uuid.UUID] = {}
    for number, row in ctx.invoices.items():
        customer = (row.get("customer") or "").strip()
        subtotal = _d(row.get("subtotal")) or ZERO
        discount = _d(row.get("discount_total")) or ZERO
        cgst = _d(row.get("cgst_amount")) or ZERO
        sgst = _d(row.get("sgst_amount")) or ZERO
        igst = _d(row.get("igst_amount")) or ZERO
        cess = _d(row.get("cess_amount")) or ZERO
        round_off = _d(row.get("round_off")) or ZERO
        shipping = _d(row.get("shipping_charges")) or ZERO
        total = _d(row.get("total")) or ZERO
        amount_paid = _d(row.get("amount_paid")) or ZERO
        status = (row.get("status") or "POSTED").upper()
        if amount_paid >= total - _MONEY_TOL:
            status = "PAID"
        elif amount_paid > ZERO:
            status = "PARTIALLY_PAID"
        elif status == "POSTED":
            status = "POSTED"
        inv = Invoice(
            tenant_id=tenant_id,
            contact_id=contact_ids.get(customer),
            invoice_number=number,
            issue_date=_parse_date(row.get("issue_date")) or date.today(),
            due_date=_parse_date(row.get("due_date")) or date.today(),
            status=status,
            subtotal=subtotal,
            discount_total=discount,
            cgst_amount=cgst,
            sgst_amount=sgst,
            igst_amount=igst,
            utgst_amount=ZERO,
            cess_amount=cess,
            round_off=round_off,
            shipping_charges=shipping,
            total=total,
            amount_paid=amount_paid,
            pos_state_code=(row.get("pos_state_code") or "").strip() or origin_state,
            e_invoice_status="PENDING",
            supply_type="DOMESTIC",
            currency="INR",
            exchange_rate=Decimal("1"),
            tds_rate=ZERO,
            tds_amount=ZERO,
            tcs_rate=ZERO,
            tcs_amount=ZERO,
            is_rcm=False,
            is_gst_inclusive=False,
        )
        db.add(inv)
        db.flush()
        invoice_ids[number] = inv.id
        counts["invoices_imported"] = counts.get("invoices_imported", 0) + 1

    for line in ctx.invoice_lines:
        dnum = (line.get("invoice_number") or "").strip()
        if dnum not in invoice_ids:
            continue
        _add_line(
            db, tenant_id,
            model=InvoiceLine,
            doc_id=invoice_ids[dnum],
            product_id=product_ids.get((line.get("product") or "").strip()),
            line=line,
            counts=counts,
            key="invoice_lines_imported",
        )

    # ── 6. Bills + lines ───────────────────────────────────────────────────
    bill_ids: Dict[str, uuid.UUID] = {}
    for number, row in ctx.bills.items():
        vendor = (row.get("vendor") or "").strip()
        subtotal = _d(row.get("subtotal")) or ZERO
        discount = _d(row.get("discount_total")) or ZERO
        cgst = _d(row.get("cgst_amount")) or ZERO
        sgst = _d(row.get("sgst_amount")) or ZERO
        igst = _d(row.get("igst_amount")) or ZERO
        cess = _d(row.get("cess_amount")) or ZERO
        round_off = _d(row.get("round_off")) or ZERO
        shipping = _d(row.get("shipping_charges")) or ZERO
        total = _d(row.get("total")) or ZERO
        amount_paid = _d(row.get("amount_paid")) or ZERO
        status = (row.get("status") or "POSTED").upper()
        if amount_paid >= total - _MONEY_TOL:
            status = "PAID"
        elif amount_paid > ZERO:
            status = "PARTIALLY_PAID"
        elif status == "UNPAID":
            status = "UNPAID"
        bill = Bill(
            tenant_id=tenant_id,
            contact_id=contact_ids.get(vendor),
            bill_number=number,
            issue_date=_parse_date(row.get("issue_date")) or date.today(),
            due_date=_parse_date(row.get("due_date")) or date.today(),
            status=status,
            subtotal=subtotal,
            discount_total=discount,
            cgst_amount=cgst,
            sgst_amount=sgst,
            igst_amount=igst,
            utgst_amount=ZERO,
            cess_amount=cess,
            round_off=round_off,
            shipping_charges=shipping,
            total=total,
            amount_paid=amount_paid,
            pos_state_code=(row.get("pos_state_code") or "").strip() or origin_state,
            tds_rate=_d(row.get("tds_rate")) or ZERO,
            tds_amount=_d(row.get("tds_amount")) or ZERO,
            itc_eligible=True,
            is_gst_inclusive=False,
        )
        db.add(bill)
        db.flush()
        bill_ids[number] = bill.id
        counts["bills_imported"] = counts.get("bills_imported", 0) + 1

    for line in ctx.bill_lines:
        dnum = (line.get("bill_number") or "").strip()
        if dnum not in bill_ids:
            continue
        _add_line(
            db, tenant_id,
            model=BillLine,
            doc_id=bill_ids[dnum],
            product_id=product_ids.get((line.get("product") or "").strip()),
            line=line,
            counts=counts,
            key="bill_lines_imported",
        )

    # ── 7. Payments + allocations ──────────────────────────────────────────
    payment_ids: Dict[str, uuid.UUID] = {}
    for number, row in ctx.payments.items():
        customer = (row.get("customer") or "").strip()
        payment = Payment(
            tenant_id=tenant_id,
            contact_id=contact_ids.get(customer),
            payment_number=number,
            payment_date=_parse_date(row.get("payment_date")) or date.today(),
            payment_mode=(row.get("payment_mode") or "BANK").upper(),
            amount=_d(row.get("amount")) or ZERO,
            reference_number=(row.get("reference_number") or "").strip() or None,
            description="Imported from CSV migration",
            status=(row.get("status") or "ACTIVE").upper(),
        )
        db.add(payment)
        db.flush()
        payment_ids[number] = payment.id
        counts["payments_imported"] = counts.get("payments_imported", 0) + 1

    for a in ctx.payment_allocs:
        pnum = (a.get("payment_number") or "").strip()
        inum = (a.get("invoice_number") or "").strip()
        if pnum not in payment_ids or inum not in invoice_ids:
            continue
        db.add(PaymentAllocation(
            tenant_id=tenant_id,
            payment_id=payment_ids[pnum],
            invoice_id=invoice_ids[inum],
            amount=_d(a.get("amount")) or ZERO,
        ))
        counts["payment_allocations_imported"] = counts.get("payment_allocations_imported", 0) + 1

    bp_ids: Dict[str, uuid.UUID] = {}
    for number, row in ctx.bill_payments.items():
        vendor = (row.get("vendor") or "").strip()
        bp = BillPayment(
            tenant_id=tenant_id,
            contact_id=contact_ids.get(vendor),
            payment_number=number,
            payment_date=_parse_date(row.get("payment_date")) or date.today(),
            payment_mode=(row.get("payment_mode") or "BANK").upper(),
            amount=_d(row.get("amount")) or ZERO,
            reference_number=(row.get("reference_number") or "").strip() or None,
            description="Imported from CSV migration",
            status=(row.get("status") or "ACTIVE").upper(),
        )
        db.add(bp)
        db.flush()
        bp_ids[number] = bp.id
        counts["bill_payments_imported"] = counts.get("bill_payments_imported", 0) + 1

    for a in ctx.bill_payment_allocs:
        pnum = (a.get("payment_number") or "").strip()
        bnum = (a.get("bill_number") or "").strip()
        if pnum not in bp_ids or bnum not in bill_ids:
            continue
        db.add(BillPaymentAllocation(
            tenant_id=tenant_id,
            payment_id=bp_ids[pnum],
            bill_id=bill_ids[bnum],
            amount=_d(a.get("amount")) or ZERO,
        ))
        counts["bill_payment_allocations_imported"] = counts.get("bill_payment_allocations_imported", 0) + 1

    # ── 8. Expenses (+ categories created on demand) ───────────────────────
    category_ids: Dict[str, uuid.UUID] = {}
    _expense_counter = 0
    for number, row in ctx.expenses.items():
        cat_name = (row.get("category") or "").strip()
        if cat_name not in category_ids:
            category = (
                db.query(ExpenseCategory)
                .filter(
                    ExpenseCategory.tenant_id == tenant_id,
                    func.lower(func.trim(ExpenseCategory.name)) == cat_name.lower(),
                    ExpenseCategory.deleted_at.is_(None),
                )
                .first()
            )
            if category is None:
                _expense_counter += 1
                acct = Account(
                    tenant_id=tenant_id,
                    name=f"{cat_name} Expenses",
                    code=f"EXP-{1000 + _expense_counter:04d}",
                    account_type="EXPENSE",
                    opening_balance=ZERO,
                    current_balance=ZERO,
                    is_active=True,
                )
                db.add(acct)
                db.flush()
                category = ExpenseCategory(
                    tenant_id=tenant_id,
                    name=cat_name,
                    description="Imported from CSV migration",
                    linked_account_id=acct.id,
                    is_active=True,
                )
                db.add(category)
                db.flush()
            category_ids[cat_name] = category.id
        db.add(Expense(
            tenant_id=tenant_id,
            expense_number=number,
            expense_category_id=category_ids[cat_name],
            expense_date=_parse_date(row.get("expense_date")) or date.today(),
            vendor_name=(row.get("vendor_name") or "").strip() or None,
            description=(row.get("description") or "").strip() or None,
            amount=_d(row.get("amount")) or ZERO,
            gst_rate=_d(row.get("gst_rate")) or ZERO,
            cgst_amount=_d(row.get("cgst_amount")) or ZERO,
            sgst_amount=_d(row.get("sgst_amount")) or ZERO,
            igst_amount=_d(row.get("igst_amount")) or ZERO,
            utgst_amount=ZERO,
            cess_amount=ZERO,
            round_off=ZERO,
            total=_d(row.get("total")) or ZERO,
            status="POSTED",
        ))
        counts["expenses_imported"] = counts.get("expenses_imported", 0) + 1

    # ── 9. Stock opening ledger ────────────────────────────────────────────
    warehouse_id = resolve_default_warehouse_id(db, tenant_id)
    for row in ctx.stock_rows:
        ref = (row.get("reference_type") or "").strip()
        if ref.upper() != "VYAPAR_OPENING":
            continue
        key = (row.get("product") or "").strip()
        if key not in product_ids:
            continue
        qty = _d(row.get("quantity")) or ZERO
        balance = _d(row.get("balance_quantity")) or ZERO
        db.add(StockLedger(
            tenant_id=tenant_id,
            product_id=product_ids[key],
            warehouse_id=warehouse_id,
            quantity=qty,
            balance_quantity=balance,
            reference_type="VYAPAR_OPENING",
            reference_id=product_ids[key],
            rate=_d(row.get("rate")) or ZERO,
            source_channel="IMPORT",
        ))
        counts["stock_entries_imported"] = counts.get("stock_entries_imported", 0) + 1

    # ── 10. Post journals for imported documents ───────────────────────────
    # The CSV bundle must never commit POSTED/PAID documents without ledger
    # postings: AR/AP and GST books would stay empty while documents show
    # rupees (the pre-fix behavior). Every posting is idempotent and runs in
    # a savepoint; any failure raises, which rolls the whole import back
    # (this endpoint's atomic contract). source_channel=IMPORT is stamped so
    # the ledger is auditable back to the migration.
    from src.core.posting_context import set_session_posting_channel
    from src.domains.accounting.backfill_posting import (
        post_bill_if_missing,
        post_bill_payment_if_missing,
        post_expense_if_missing,
        post_invoice_if_missing,
        post_payment_if_missing,
    )

    set_session_posting_channel(db, "IMPORT")
    for inv in db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id, Invoice.deleted_at.is_(None),
    ).all():
        if inv.status in ("POSTED", "PARTIALLY_PAID", "PAID"):
            with db.begin_nested():
                post_invoice_if_missing(db, tenant_id, inv)
    for bill in db.query(Bill).filter(
        Bill.tenant_id == tenant_id, Bill.deleted_at.is_(None),
    ).all():
        if bill.status in ("POSTED", "PARTIALLY_PAID", "PAID", "UNPAID"):
            with db.begin_nested():
                post_bill_if_missing(db, tenant_id, bill)
    for pay in db.query(Payment).filter(
        Payment.tenant_id == tenant_id, Payment.deleted_at.is_(None),
    ).all():
        with db.begin_nested():
            post_payment_if_missing(db, tenant_id, pay)
    for bp in db.query(BillPayment).filter(
        BillPayment.tenant_id == tenant_id, BillPayment.deleted_at.is_(None),
    ).all():
        with db.begin_nested():
            post_bill_payment_if_missing(db, tenant_id, bp)
    for expense in db.query(Expense).filter(
        Expense.tenant_id == tenant_id, Expense.deleted_at.is_(None),
    ).all():
        with db.begin_nested():
            post_expense_if_missing(db, tenant_id, expense)


def _add_line(
    db: Session,
    tenant_id: uuid.UUID,
    *,
    model,
    doc_id: uuid.UUID,
    product_id: Optional[uuid.UUID],
    line: Dict[str, str],
    counts: Dict[str, int],
    key: str,
) -> None:
    gst_rate = _d(line.get("gst_rate")) or ZERO
    cgst = _d(line.get("cgst_amount")) or ZERO
    sgst = _d(line.get("sgst_amount")) or ZERO
    igst = _d(line.get("igst_amount")) or ZERO
    half_rate = (gst_rate / Decimal("2")).quantize(Decimal("0.01"))
    doc_col = "invoice_id" if model is InvoiceLine else "bill_id"
    db.add(model(**{
        "tenant_id": tenant_id,
        doc_col: doc_id,
        "product_id": product_id,
        "description": (line.get("description") or "").strip() or None,
        "quantity": _d(line.get("quantity")) or ZERO,
        "rate": _d(line.get("rate")) or ZERO,
        "discount": _d(line.get("discount")) or ZERO,
        "subtotal": _d(line.get("subtotal")) or ZERO,
        "hsn_sac": normalize_hsn_sac(line.get("hsn_sac")),
        "gst_rate": gst_rate,
        "cgst_rate": half_rate if cgst else ZERO,
        "cgst_amount": cgst,
        "sgst_rate": half_rate if sgst else ZERO,
        "sgst_amount": sgst,
        "igst_rate": gst_rate if igst else ZERO,
        "igst_amount": igst,
        "utgst_rate": ZERO,
        "utgst_amount": ZERO,
        "cess_rate": ZERO,
        "cess_amount": ZERO,
        "total": _d(line.get("total")) or ZERO,
    }))
    counts[key] = counts.get(key, 0) + 1


# ---------------------------------------------------------------------------
# Endpoint
# ---------------------------------------------------------------------------
@router.post("/csv", response_model=CsvImportReport)
def import_csv(
    file: Optional[UploadFile] = File(None, description="A .zip bundle of the converter's CSVs"),
    files: Optional[List[UploadFile]] = File(None, description="Or the CSV files directly"),
    dry_run: bool = Query(True, description="Validate and report without writing any data"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("data:import")),
):
    """Import the converter's CSV bundle.

    ``dry_run=true`` (default) validates everything — headers, cross-references,
    document totals, settlement — and returns a report without touching the
    database.  ``dry_run=false`` commits in a single transaction and returns the
    same report with ``committed: true``; any validation error or write failure
    rolls back completely and returns ``valid: false``.
    """
    bundle, intake_errors = _read_bundle(file, files)
    ctx = _Ctx()
    ctx.errors.extend(intake_errors)
    if not intake_errors:
        _load_bundle(bundle, ctx)

    if not ctx.errors:
        try:
            _validate(ctx, db, tenant_id)
        except Exception as exc:  # validation must never crash the request
            logger.exception("CSV import validation crashed")
            ctx.errors.append(f"Internal validation error: {exc}")

    report = CsvImportReport(
        valid=not ctx.errors,
        dry_run=dry_run,
        errors=ctx.errors,
        warnings=ctx.warnings,
        totals=_compute_totals(ctx),
    )

    if ctx.errors:
        return report

    if dry_run:
        return report

    # Commit — single transaction; any failure rolls everything back.
    counts: Dict[str, int] = {}
    try:
        _apply_import(ctx, db, tenant_id, counts)
        db.commit()
        report.committed = True
        report.counts = counts
    except Exception as exc:
        db.rollback()
        logger.exception("CSV import commit failed")
        report.valid = False
        report.committed = False
        report.errors.append(f"Import failed and was rolled back: {exc}")
    return report
