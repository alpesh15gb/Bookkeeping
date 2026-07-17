import io
import uuid
import math
import logging
from decimal import Decimal
from typing import List, Optional, Dict
from datetime import datetime, date

logger = logging.getLogger(__name__)
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy import func
from sqlalchemy.orm import Session
from pydantic import BaseModel

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Contact, Product, Invoice, InvoiceLine, Bill, BillLine,
    Expense, ExpenseCategory, Account, Tenant,
    ProformaInvoice, ProformaInvoiceLine,
    Payment, PaymentAllocation, BillPayment, BillPaymentAllocation,
    StockLedger, EWayBill,
)
from src.api.deps import enforce_permission
from src.domains.company.services import NumberingSeriesService
from src.domains.inventory.services import resolve_default_warehouse_id
from src.common.import_normalization import normalize_hsn_sac

router = APIRouter(prefix="/import", tags=["Data Import"])


class ImportSummary(BaseModel):
    contacts_imported: int = 0
    products_imported: int = 0
    invoices_imported: int = 0
    bills_imported: int = 0
    estimates_imported: int = 0
    expenses_imported: int = 0
    payments_imported: int = 0
    stock_entries_imported: int = 0
    linked_transactions_imported: int = 0
    custom_fields_imported: int = 0
    party_addresses_imported: int = 0
    party_item_rates_imported: int = 0
    e_invoice_data_imported: int = 0
    opening_balances_set: int = 0
    errors: List[str] = []


# ---------------------------------------------------------------------------
# Vyapar GST tax_id -> tax rate (%) mapping helper
# Vyapar tax_code_type: 0 = split (CGST/SGST), 1 = combined (treated as IGST)
# tax_mapping groups always come in pairs (SGST + CGST) per rate
# We build a dict: tax_group_id -> (gst_rate_pct, is_intra_state)
# ---------------------------------------------------------------------------
def _build_tax_rate_map(vconn) -> Dict[int, Decimal]:
    """Return dict: kb_tax_code.tax_code_id -> total_gst_rate_pct (Decimal)"""
    rows = vconn.execute("SELECT tax_code_id, tax_rate, tax_code_type FROM kb_tax_code").fetchall()
    return {r[0]: Decimal(str(r[1] or 0)) for r in rows}


def _build_group_rate_map(vconn, tax_code_rates: Dict[int, Decimal]) -> Dict[int, Decimal]:
    """Return dict: tax_mapping_group_id -> total gst rate % (sum of component rates)"""
    mappings = vconn.execute(
        "SELECT tax_mapping_group_id, tax_mapping_code_id FROM kb_tax_mapping"
    ).fetchall()
    group_rates: Dict[int, Decimal] = {}
    for m in mappings:
        gid = m[0]
        code_rate = tax_code_rates.get(m[1], Decimal("0"))
        group_rates[gid] = group_rates.get(gid, Decimal("0")) + code_rate
    return group_rates


def _split_gst(
    total_tax_amount: Decimal,
    line_tax_id: Optional[int],
    group_rate_map: Dict[int, Decimal],
    is_intrastate: bool,
) -> tuple:
    """
    Given the total tax amount for a line, split it into CGST+SGST (intrastate)
    or IGST (interstate).  Returns (cgst_rate, cgst_amt, sgst_rate, sgst_amt, igst_rate, igst_amt).
    All as Decimal.
    """
    tax = total_tax_amount.quantize(Decimal("0.01"))
    total_rate = group_rate_map.get(line_tax_id or 0, Decimal("18.00")) if line_tax_id else Decimal("18.00")

    if is_intrastate:
        half_rate = (total_rate / Decimal("2")).quantize(Decimal("0.01"))
        half_tax = (tax / Decimal("2")).quantize(Decimal("0.01"))
        return (
            half_rate, half_tax,
            half_rate, half_tax,
            Decimal("0"), Decimal("0"),
        )
    else:
        return (
            Decimal("0"), Decimal("0"),
            Decimal("0"), Decimal("0"),
            total_rate, tax.quantize(Decimal("0.01")),
        )


@router.post("/vyapar", response_model=ImportSummary)
def import_vyapar_backup(
    file: UploadFile = File(...),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update")),
):
    """Import data from a Vyapar .vyb backup file.

    A .vyb file is a ZIP archive containing a single .vyp file which is an
    SQLite 3 database.  We read that database in-memory and map its records
    to our own models.
    """
    import zipfile
    import sqlite3
    import tempfile
    import os

    # ── 0. Fix constraints in postgres db (handles older DB schemas) ─────────
    from sqlalchemy import text
    try:
        db.execute(text("ALTER TABLE invoices DROP CONSTRAINT IF EXISTS ck_invoices_status"))
        db.execute(text("ALTER TABLE invoices ADD CONSTRAINT ck_invoices_status CHECK (status IN ('DRAFT', 'POSTED', 'SENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED'))"))
        db.execute(text("ALTER TABLE bills DROP CONSTRAINT IF EXISTS ck_bills_status"))
        db.execute(text("ALTER TABLE bills ADD CONSTRAINT ck_bills_status CHECK (status IN ('DRAFT', 'POSTED', 'UNPAID', 'PARTIALLY_PAID', 'PAID', 'CANCELLED'))"))
        db.commit()
    except Exception as e:
        logger.warning(f"Failed to adjust table constraints: {e}")
        db.rollback()

    summary = ImportSummary()

    # ── 1. Read the upload bytes ──────────────────────────────────────────────
    content = file.file.read()

    # ── 2. Unzip .vyb → extract .vyp (the actual SQLite DB) ──────────────────
    try:
        zf = zipfile.ZipFile(io.BytesIO(content), mode="r")
        vyp_names = [n for n in zf.namelist() if n.endswith(".vyp")]
        if not vyp_names:
            raise HTTPException(
                status_code=400,
                detail="No .vyp database found inside the .vyb archive.",
            )
        vyp_data = zf.read(vyp_names[0])
        zf.close()
    except zipfile.BadZipFile:
        raise HTTPException(
            status_code=400,
            detail=(
                "Invalid .vyb file — the file must be a valid Vyapar backup "
                "exported from the Vyapar app (File > Backup)."
            ),
        )

    # ── 3. Open the SQLite database from the extracted bytes ──────────────────
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".db")
    tmp.write(vyp_data)
    tmp.close()

    vconn = sqlite3.connect(tmp.name)
    vconn.row_factory = sqlite3.Row

    try:
        # ── 4. Firm / origin state info ───────────────────────────────────────
        firm = vconn.execute("SELECT * FROM kb_firms LIMIT 1").fetchone()
        origin_state_code = "36"  # default Telangana
        origin_state_name = "Telangana"
        if firm and firm["firm_state"]:
            state_map = {
                "Telangana": "36", "Andhra Pradesh": "37", "Arunachal Pradesh": "12",
                "Assam": "18", "Bihar": "10", "Chhattisgarh": "22", "Goa": "30",
                "Gujarat": "24", "Haryana": "06", "Himachal Pradesh": "02",
                "Jharkhand": "20", "Karnataka": "29", "Kerala": "32",
                "Madhya Pradesh": "23", "Maharashtra": "27", "Manipur": "14",
                "Meghalaya": "17", "Mizoram": "15", "Nagaland": "13", "Odisha": "21",
                "Punjab": "03", "Rajasthan": "08", "Sikkim": "11",
                "Tamil Nadu": "33", "Telangana": "36", "Tripura": "16",
                "Uttar Pradesh": "09", "Uttarakhand": "05", "West Bengal": "19",
                "Andaman and Nicobar": "35", "Chandigarh": "04",
                "Dadra and Nagar Haveli and Daman and Diu": "26",
                "Jammu and Kashmir": "01", "Ladakh": "38",
                "Lakshadweep": "31", "Delhi": "07", "Puducherry": "34",
            }
            origin_state_name = firm["firm_state"]
            origin_state_code = state_map.get(firm["firm_state"], "36")

        # ── 5. Build GST rate lookup tables ───────────────────────────────────
        tax_code_rates = _build_tax_rate_map(vconn)
        group_rate_map = _build_group_rate_map(vconn, tax_code_rates)

        # ── 6. Import contacts ────────────────────────────────────────────────
        vy_names = vconn.execute("SELECT * FROM kb_names").fetchall()
        vy_expense_cat_names: Dict[int, str] = {}
        contact_map: Dict[int, str] = {}  # vyapar name_id -> our contact.id str
        contact_state_map: Dict[int, str] = {}  # vyapar name_id -> state_code

        # Common words that signal an expense category, not a real party
        _EXPENSE_KEYWORDS = {
            "petrol", "transport", "salary", "rent", "tea", "electricity",
            "water", "internet", "miscellaneous", "office expenses",
            "travelling", "postage", "printing", "repairs", "maintenance",
            "legal", "professional fees", "advertisement", "insurance",
            "interest", "commission", "bank charges", "fuel", "food",
        }

        for n in vy_names:
            name_str = (n["full_name"] or "").strip()[:150]
            phone = (n["phone_number"] or "").strip()
            email = (n["email"] or "").strip()

            if not name_str or name_str.startswith("("):
                continue

            is_expense_cat = (
                not phone
                and not email
                and name_str.lower() in _EXPENSE_KEYWORDS
            )
            if is_expense_cat:
                vy_expense_cat_names[n["name_id"]] = name_str
                continue

            # Determine contact type from name_type:
            # 1 = customer, 2 = vendor, 0 = both
            name_type = n["name_type"]
            contact_type = "CUSTOMER" if name_type == 1 else (
                "VENDOR" if name_type == 2 else "BOTH"
            )
            gstin = (n["name_gstin_number"] or "").strip().upper() or None

            # Check if contact already exists (dedup by GSTIN first, then normalized name)
            existing = None
            if gstin:
                existing = (
                    db.query(Contact)
                    .filter(
                        Contact.tenant_id == tenant_id,
                        func.upper(Contact.gstin) == gstin,
                        Contact.deleted_at == None,  # noqa: E711
                    )
                    .first()
                )
            if not existing:
                existing = (
                    db.query(Contact)
                    .filter(
                        Contact.tenant_id == tenant_id,
                        func.lower(func.trim(Contact.name)) == name_str.lower(),
                        Contact.deleted_at == None,  # noqa: E711
                    )
                    .first()
                )
            if existing:
                if existing.contact_type != contact_type:
                    existing.contact_type = "BOTH"
                contact_map[n["name_id"]] = str(existing.id)
                contact_state_map[n["name_id"]] = existing.state_code or origin_state_code
                continue
            # Party state — use same map as firm state lookup
            party_state = (n["name_state"] or "").strip()
            party_state_code = state_map.get(party_state, origin_state_code)

            address_str = (n["address"] or "").strip()

            contact = Contact(
                tenant_id=tenant_id,
                name=name_str,
                phone=phone or None,
                email=email or None,
                contact_type=contact_type,
                gstin=gstin,
                state_code=party_state_code,
                billing_address={
                    "street": address_str,
                    "city": "",
                    "state": party_state,
                    "pincode": (n["pincode"] or "").strip(),
                },
                is_active=True,
            )
            db.add(contact)
            db.flush()
            contact_map[n["name_id"]] = str(contact.id)
            contact_state_map[n["name_id"]] = party_state_code
            summary.contacts_imported += 1

        # ── 6b. Set opening balances from kb_names.amount ─────────────────
        for n in vy_names:
            name_id = n["name_id"]
            if name_id not in contact_map:
                continue
            balance = float(n["amount"] or 0)
            if balance == 0:
                continue
            try:
                contact_uuid = uuid.UUID(contact_map[name_id])
                c = db.query(Contact).filter(Contact.id == contact_uuid).first()
                if c:
                    c.opening_balance = Decimal(str(round(balance, 2)))
                    summary.opening_balances_set += 1
            except Exception as e:
                summary.errors.append(f"Opening balance for name#{name_id}: {e}")

        # ── 6c. Import party addresses from kb_address ────────────────────
        try:
            vy_addresses = vconn.execute("SELECT * FROM kb_address").fetchall()
            for addr in vy_addresses:
                name_id = addr["name_id"]
                if name_id not in contact_map:
                    continue
                contact_uuid = uuid.UUID(contact_map[name_id])
                c = db.query(Contact).filter(Contact.id == contact_uuid).first()
                if not c:
                    continue
                addr_parts = []
                for field in ["address_line_1", "address_line_2", "city"]:
                    val = (addr[field] or "").strip() if field in addr.keys() else ""
                    if val:
                        addr_parts.append(val)
                address_str = ", ".join(addr_parts)
                if not address_str:
                    continue
                # Update billing address if we have better data
                existing_addr = c.billing_address or {}
                if address_str and (not existing_addr.get("street") or existing_addr["street"] == ""):
                    c.billing_address = {
                        "street": address_str,
                        "city": (addr["city"] or "").strip() if "city" in addr.keys() else "",
                        "state": (addr["state_name"] or "").strip() if "state_name" in addr.keys() else "",
                        "pincode": (addr["pincode"] or "").strip() if "pincode" in addr.keys() else "",
                    }
                    summary.party_addresses_imported += 1
        except Exception as e:
            summary.errors.append(f"Party address import: {e}")

        # ── 6d. Import custom fields from kb_custom_fields + kb_udf_* ─────
        udf_values_by_ref: Dict[int, dict] = {}
        try:
            vy_custom_fields = vconn.execute("SELECT * FROM kb_custom_fields").fetchall()
            vy_udf_fields = vconn.execute("SELECT * FROM kb_udf_fields").fetchall()
            vy_udf_values = vconn.execute("SELECT * FROM kb_udf_values").fetchall()

            # Build UDF field definitions
            udf_field_defs = {}
            for udf in vy_udf_fields:
                udf_field_defs[udf["udf_field_id"]] = {
                    "name": udf["udf_field_name"],
                    "type": udf["udf_field_type"],
                    "txn_type": udf["udf_txn_type"],
                }

            # Build UDF values by reference
            udf_values_by_ref: Dict[int, dict] = {}
            for uv in vy_udf_values:
                ref_id = uv["udf_ref_id"]
                field_id = uv["udf_value_field_id"]
                if field_id in udf_field_defs:
                    field_name = udf_field_defs[field_id]["name"]
                    udf_values_by_ref.setdefault(ref_id, {})[field_name] = uv["udf_value"]

            # Store custom field definitions on tenant settings
            if vy_custom_fields or vy_udf_fields:
                from src.infrastructure.database.models import TenantSetting
                ts = db.query(TenantSetting).filter(
                    TenantSetting.tenant_id == tenant_id
                ).first()
                if ts:
                    existing_extra = ts.extra_settings or {}
                    if not isinstance(existing_extra, dict):
                        existing_extra = {}
                    existing_extra["vyapar_custom_field_defs"] = [
                        {"id": cf["custom_field_id"], "name": cf["custom_field_display_name"],
                         "type": cf["custom_field_type"], "visibility": cf["custom_field_visibility"]}
                        for cf in vy_custom_fields
                    ]
                    existing_extra["vyapar_udf_defs"] = [
                        {"id": u["udf_field_id"], "name": u["udf_field_name"],
                         "type": u["udf_field_type"], "txn_type": u["udf_txn_type"]}
                        for u in vy_udf_fields
                    ]
                    ts.extra_settings = existing_extra
                    summary.custom_fields_imported = len(vy_custom_fields) + len(vy_udf_fields)

            # Attach UDF values to their respective transactions
            # (will be applied when processing transactions below)
        except Exception as e:
            summary.errors.append(f"Custom field import: {e}")

        # ── 7. Import products ────────────────────────────────────────────────
        vy_items = vconn.execute("SELECT * FROM kb_items").fetchall()
        item_map: Dict[int, str] = {}  # vyapar item_id -> our product.id str

        for i in vy_items:
            name_str = (i["item_name"] or "").strip()[:150]
            if not name_str:
                continue

            existing = (
                db.query(Product)
                .filter(
                    Product.tenant_id == tenant_id,
                    Product.name == name_str,
                    Product.deleted_at == None,  # noqa: E711
                )
                .first()
            )
            if existing:
                item_map[i["item_id"]] = str(existing.id)
                continue

            sale_price = max(0, float(i["item_sale_unit_price"] or 0))
            purchase_price = max(0, float(i["item_purchase_unit_price"] or 0))
            stock = max(0, float(i["item_stock_quantity"] or 0))
            reorder = max(0, float(i["item_min_stock_quantity"] or 0))

            # Determine GST rate from item's tax_id
            item_tax_id = i["item_tax_id"]
            item_gst_rate = group_rate_map.get(item_tax_id or 0, Decimal("18.00")) if item_tax_id else Decimal("18.00")

            # item_type: 1=product, 2=service
            product_type = "SERVICE" if i["item_type"] == 2 else "GOODS"

            hsn = normalize_hsn_sac(i["item_hsn_sac_code"])

            product = Product(
                tenant_id=tenant_id,
                name=name_str,
                hsn_sac=hsn,
                product_type=product_type,
                uom="NOS",
                sales_price=Decimal(str(sale_price)),
                purchase_price=Decimal(str(purchase_price)),
                gst_rate=Decimal(str(item_gst_rate)),
                opening_stock=Decimal(str(stock)),
                current_stock=Decimal(str(stock)),
                reorder_level=Decimal(str(reorder)),
                is_active=True,
            )
            db.add(product)
            db.flush()
            item_map[i["item_id"]] = str(product.id)
            summary.products_imported += 1

        # ── 7b. Import party-item rates from kb_party_item_rate ─────────────
        try:
            vy_pir = vconn.execute("SELECT * FROM kb_party_item_rate").fetchall()
            pir_by_product: Dict[str, dict] = {}  # product_id_str -> {party_name: rate}
            for pir in vy_pir:
                item_id = pir["party_item_rate_item_id"]
                party_id = pir["party_item_rate_party_id"]
                sale_price = pir["party_item_rate_sale_price"]
                purchase_price = pir["party_item_rate_purchase_price"]
                if item_id not in item_map:
                    continue
                prod_id_str = item_map[item_id]
                # Get party name
                party_row = None
                for n in vy_names:
                    if n["name_id"] == party_id:
                        party_row = n
                        break
                party_name = (party_row["full_name"] or "Unknown") if party_row else "Unknown"
                if prod_id_str not in pir_by_product:
                    pir_by_product[prod_id_str] = {}
                pir_by_product[prod_id_str][party_name] = {
                    "sale_price": float(sale_price) if sale_price else None,
                    "purchase_price": float(purchase_price) if purchase_price else None,
                }
            # Update products with party rates
            for prod_id_str, rates in pir_by_product.items():
                try:
                    prod_uuid = uuid.UUID(prod_id_str)
                    p = db.query(Product).filter(Product.id == prod_uuid).first()
                    if p:
                        p.party_item_rates = rates
                        summary.party_item_rates_imported += 1
                except Exception:
                    pass
        except Exception as e:
            summary.errors.append(f"Party-item rate import: {e}")

        # ── 8. Import expense categories ──────────────────────────────────────
        expense_cat_map: Dict[str, str] = {}  # lowercase name -> cat id

        for name_id, cat_name in vy_expense_cat_names.items():
            existing_cat = (
                db.query(ExpenseCategory)
                .filter(
                    ExpenseCategory.tenant_id == tenant_id,
                    ExpenseCategory.name == cat_name,
                    ExpenseCategory.is_active == True,  # noqa: E712
                )
                .first()
            )
            if existing_cat:
                expense_cat_map[cat_name.lower()] = str(existing_cat.id)
            else:
                acct = Account(
                    tenant_id=tenant_id,
                    name=cat_name + " Expenses",
                    code=f"EXP-{abs(hash(cat_name)) % 10000:04d}",
                    account_type="EXPENSE",
                    is_active=True,
                )
                db.add(acct)
                db.flush()
                cat = ExpenseCategory(
                    tenant_id=tenant_id,
                    name=cat_name,
                    description="Imported from Vyapar",
                    linked_account_id=acct.id,
                    is_active=True,
                )
                db.add(cat)
                db.flush()
                expense_cat_map[cat_name.lower()] = str(cat.id)

        # ── 9. Pre-load line-items by transaction ──────────────────────────────
        all_lineitems = vconn.execute(
            """
            SELECT li.*, i.item_name AS _item_name, i.item_hsn_sac_code AS _hsn
            FROM kb_lineitems li
            LEFT JOIN kb_items i ON li.item_id = i.item_id
            """
        ).fetchall()
        lines_by_txn: Dict[int, list] = {}
        for li in all_lineitems:
            txn_id = li["lineitem_txn_id"]
            lines_by_txn.setdefault(txn_id, []).append(li)

        # ── 10. Process transactions ───────────────────────────────────────────
        vy_txns = [
            dict(r)
            for r in vconn.execute(
                "SELECT * FROM kb_transactions ORDER BY txn_date"
            ).fetchall()
        ]

        # Counter for generating unique invoice numbers (per import session)
        _inv_counter = 0
        _bill_counter = 0
        _est_counter = 0

        # Maps: vyapar txn_id -> our entity UUID string (for payments, linked txns)
        inv_map: Dict[int, str] = {}   # txn_id -> invoice.id str
        bill_map: Dict[int, str] = {}  # txn_id -> bill.id str
        est_map: Dict[int, str] = {}   # txn_id -> proforma_invoice.id str

        def _parse_date(val) -> date:
            if not val:
                return date.today()
            try:
                return datetime.strptime(str(val)[:10], "%Y-%m-%d").date()
            except Exception:
                return date.today()

        def _gen_inv_number(existing_ref: Optional[str], prefix: str) -> str:
            nonlocal _inv_counter, _bill_counter, _est_counter
            if existing_ref and existing_ref.strip():
                return existing_ref.strip()
            if prefix == "INV":
                _inv_counter += 1
                return f"VYP-INV-{_inv_counter:04d}"
            elif prefix == "EST":
                _est_counter += 1
                return f"VYP-EST-{_est_counter:04d}"
            else:
                _bill_counter += 1
                return f"VYP-BILL-{_bill_counter:04d}"

        for txn in vy_txns:
            txn_type = txn["txn_type"]
            txn_id = txn["txn_id"]
            txn_date = _parse_date(txn["txn_date"])
            # Use actual due date field; fall back to txn_date if not available
            due_date_raw = txn.get("txn_due_date") or txn.get("txn_po_date") or txn["txn_date"]
            due_date = _parse_date(due_date_raw)
            if due_date < txn_date:
                due_date = txn_date

            name_id = txn["txn_name_id"]
            contact_id_str = contact_map.get(name_id) if name_id else None

            txn_lines = lines_by_txn.get(txn_id, [])

            # Reference number from Vyapar (txn_ref_number_char holds the invoice #)
            ref_number = (txn.get("txn_ref_number_char") or "").strip() or None
            payment_status = txn.get("txn_payment_status", 0)  # 1=paid/2/partial

            # Determine if this transaction is intrastate (party in same state as firm)
            party_state_code = contact_state_map.get(name_id, origin_state_code)
            txn_is_intrastate = (party_state_code == origin_state_code)

            # ── SALES INVOICES (type=1) ─────────────────────────────────────
            if txn_type == 1 and contact_id_str:
                inv_number = _gen_inv_number(ref_number, "INV")
                existing_inv = (
                    db.query(Invoice)
                    .filter(
                        Invoice.tenant_id == tenant_id,
                        Invoice.invoice_number == inv_number,
                        Invoice.deleted_at == None,
                    )
                    .first()
                )
                if existing_inv:
                    continue

                cash_amt = Decimal(str(txn.get("txn_cash_amount") or 0))
                bal_amt = Decimal(str(txn.get("txn_balance_amount") or 0))
                total_from_txn = cash_amt + bal_amt

                # Recalculate from lines for accuracy
                subtotal = Decimal("0")
                total_cgst = Decimal("0")
                total_sgst = Decimal("0")
                total_igst = Decimal("0")
                total_val = Decimal("0")
                discount_total = Decimal("0")

                inv_lines_data = []
                for vl in txn_lines:
                    line_total_d = Decimal(str(vl["total_amount"] or 0))
                    line_tax_d = Decimal(str(vl["lineitem_tax_amount"] or 0))
                    line_disc_d = Decimal(str(vl["lineitem_discount_amount"] or 0))
                    qty_d = Decimal(str(vl["quantity"] or 1))
                    rate_d = Decimal(str(vl["priceperunit"] or 0))
                    line_subtotal_d = line_total_d - line_tax_d

                    line_tax_id = vl["lineitem_tax_id"]
                    cgst_r, cgst_a, sgst_r, sgst_a, igst_r, igst_a = _split_gst(
                        line_tax_d, line_tax_id, group_rate_map, txn_is_intrastate
                    )
                    total_rate_pct = group_rate_map.get(line_tax_id or 0, 18.0) if line_tax_id else 18.0
                    hsn = normalize_hsn_sac(vl["_hsn"])

                    subtotal += max(line_subtotal_d, Decimal("0"))
                    total_cgst += cgst_a
                    total_sgst += sgst_a
                    total_igst += igst_a
                    total_val += line_total_d
                    discount_total += line_disc_d

                    product_id = None
                    if vl["item_id"] and vl["item_id"] in item_map:
                        try:
                            product_id = uuid.UUID(item_map[vl["item_id"]])
                        except Exception:
                            pass

                    inv_lines_data.append(InvoiceLine(
                        product_id=product_id,
                        description=(vl["_item_name"] or "").strip() or "Item",
                        quantity=qty_d,
                        rate=rate_d,
                        discount=line_disc_d,
                        subtotal=max(line_subtotal_d, Decimal("0")),
                        hsn_sac=hsn,
                        gst_rate=Decimal(str(total_rate_pct)),
                        cgst_rate=cgst_r,
                        cgst_amount=cgst_a,
                        sgst_rate=sgst_r,
                        sgst_amount=sgst_a,
                        igst_rate=igst_r,
                        igst_amount=igst_a,
                        utgst_rate=Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_rate=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=line_total_d,
                    ))

                if not inv_lines_data:
                    # No line items — use transaction totals as a single line
                    total_val = Decimal(str(round(total_from_txn, 2)))
                    subtotal = total_val
                    inv_lines_data.append(InvoiceLine(
                        product_id=None,
                        description="Imported from Vyapar",
                        quantity=Decimal("1"),
                        rate=total_val,
                        discount=Decimal("0"),
                        subtotal=total_val,
                        hsn_sac="998313",
                        gst_rate=Decimal("18.00"),
                        cgst_rate=Decimal("9.00"),
                        cgst_amount=Decimal("0"),
                        sgst_rate=Decimal("9.00"),
                        sgst_amount=Decimal("0"),
                        igst_rate=Decimal("0"),
                        igst_amount=Decimal("0"),
                        utgst_rate=Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_rate=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=total_val,
                    ))

                # Determine payment status
                amount_paid = cash_amt
                if amount_paid > total_val:
                    amount_paid = total_val
                if amount_paid >= total_val:
                    inv_status = "PAID"
                elif amount_paid > 0:
                    inv_status = "PARTIALLY_PAID"
                else:
                    inv_status = "POSTED"

                round_off = total_val - (subtotal + total_cgst + total_sgst + total_igst)

                inv = Invoice(
                    tenant_id=tenant_id,
                    contact_id=uuid.UUID(contact_id_str),
                    invoice_number=inv_number,
                    issue_date=txn_date,
                    due_date=due_date,
                    status=inv_status,
                    subtotal=subtotal,
                    discount_total=discount_total,
                    cgst_amount=total_cgst,
                    sgst_amount=total_sgst,
                    igst_amount=total_igst,
                    utgst_amount=Decimal("0"),
                    cess_amount=Decimal("0"),
                    round_off=round_off,
                    total=total_val,
                    amount_paid=amount_paid,
                    pos_state_code=origin_state_code,
                )
                db.add(inv)
                db.flush()
                inv_map[txn_id] = str(inv.id)

                for line in inv_lines_data:
                    line.invoice_id = inv.id
                    db.add(line)

                summary.invoices_imported += 1

            # ── ESTIMATES / QUOTATIONS (type=27) ────────────────────────
            # ALL type=27 in Vyapar are customer-facing quotations/estimates
            elif txn_type == 27 and contact_id_str:
                is_estimate = True
                doc_number = _gen_inv_number(ref_number, "EST" if is_estimate else "BILL")

                if is_estimate:
                    existing_est = (
                        db.query(ProformaInvoice)
                        .filter(
                            ProformaInvoice.tenant_id == tenant_id,
                            ProformaInvoice.proforma_number == doc_number,
                            ProformaInvoice.deleted_at == None,
                        )
                        .first()
                    )
                    if existing_est:
                        continue
                else:
                    existing_bill = (
                        db.query(Bill)
                        .filter(
                            Bill.tenant_id == tenant_id,
                            Bill.bill_number == doc_number,
                            Bill.deleted_at == None,
                        )
                        .first()
                    )
                    if existing_bill:
                        continue

                cash_amt = Decimal(str(txn.get("txn_cash_amount") or 0))
                bal_amt = Decimal(str(txn.get("txn_balance_amount") or 0))
                total_from_txn = cash_amt + bal_amt

                subtotal = Decimal("0")
                total_cgst = Decimal("0")
                total_sgst = Decimal("0")
                total_igst = Decimal("0")
                total_val = Decimal("0")
                discount_total = Decimal("0")

                lines_data = []
                for vl in txn_lines:
                    line_total_d = Decimal(str(vl["total_amount"] or 0))
                    line_tax_d = Decimal(str(vl["lineitem_tax_amount"] or 0))
                    line_disc_d = Decimal(str(vl["lineitem_discount_amount"] or 0))
                    qty_d = Decimal(str(vl["quantity"] or 1))
                    rate_d = Decimal(str(vl["priceperunit"] or 0))
                    line_subtotal_d = line_total_d - line_tax_d

                    line_tax_id = vl["lineitem_tax_id"]
                    cgst_r, cgst_a, sgst_r, sgst_a, igst_r, igst_a = _split_gst(
                        line_tax_d, line_tax_id, group_rate_map, txn_is_intrastate
                    )
                    total_rate_pct = group_rate_map.get(line_tax_id or 0, Decimal("18.00")) if line_tax_id else Decimal("18.00")
                    hsn = normalize_hsn_sac(vl["_hsn"])

                    subtotal += max(line_subtotal_d, Decimal("0"))
                    total_cgst += cgst_a
                    total_sgst += sgst_a
                    total_igst += igst_a
                    total_val += line_total_d
                    discount_total += line_disc_d

                    product_id = None
                    if vl["item_id"] and vl["item_id"] in item_map:
                        try:
                            product_id = uuid.UUID(item_map[vl["item_id"]])
                        except Exception:
                            pass

                    if is_estimate:
                        lines_data.append(ProformaInvoiceLine(
                            product_id=product_id,
                            description=(vl["_item_name"] or "").strip() or "Item",
                            quantity=qty_d,
                            rate=rate_d,
                            discount=line_disc_d,
                            subtotal=max(line_subtotal_d, Decimal("0")),
                            hsn_sac=hsn,
                            gst_rate=Decimal(str(total_rate_pct)),
                            cgst_rate=cgst_r,
                            cgst_amount=cgst_a,
                            sgst_rate=sgst_r,
                            sgst_amount=sgst_a,
                            igst_rate=igst_r,
                            igst_amount=igst_a,
                            utgst_rate=Decimal("0"),
                            utgst_amount=Decimal("0"),
                            cess_rate=Decimal("0"),
                            cess_amount=Decimal("0"),
                            total=line_total_d,
                        ))
                    else:
                        lines_data.append(BillLine(
                            product_id=product_id,
                            description=(vl["_item_name"] or "").strip() or "Item",
                            quantity=qty_d,
                            rate=rate_d,
                            discount=line_disc_d,
                            subtotal=max(line_subtotal_d, Decimal("0")),
                            hsn_sac=hsn,
                            gst_rate=Decimal(str(total_rate_pct)),
                            cgst_rate=cgst_r,
                            cgst_amount=cgst_a,
                            sgst_rate=sgst_r,
                            sgst_amount=sgst_a,
                            igst_rate=igst_r,
                            igst_amount=igst_a,
                            utgst_rate=Decimal("0"),
                            utgst_amount=Decimal("0"),
                            cess_rate=Decimal("0"),
                            cess_amount=Decimal("0"),
                            total=line_total_d,
                        ))

                if not lines_data:
                    if is_estimate:
                        lines_data.append(ProformaInvoiceLine(
                            product_id=None,
                            description="Imported Estimate Transaction",
                            quantity=Decimal("1.00"),
                            rate=Decimal(str(total_val)),
                            discount=Decimal("0"),
                            subtotal=total_val,
                            hsn_sac="998313",
                            gst_rate=Decimal("18.00"),
                            cgst_rate=Decimal("9.00"),
                            cgst_amount=Decimal("0"),
                            sgst_rate=Decimal("9.00"),
                            sgst_amount=Decimal("0"),
                            igst_rate=Decimal("0"),
                            igst_amount=Decimal("0"),
                            utgst_rate=Decimal("0"),
                            utgst_amount=Decimal("0"),
                            cess_rate=Decimal("0"),
                            cess_amount=Decimal("0"),
                            total=total_val,
                        ))
                    else:
                        lines_data.append(BillLine(
                            product_id=None,
                            description="Imported Bill Transaction",
                            quantity=Decimal("1.00"),
                            rate=Decimal(str(total_val)),
                            discount=Decimal("0"),
                            subtotal=total_val,
                            hsn_sac="998313",
                            gst_rate=Decimal("18.00"),
                            cgst_rate=Decimal("9.00"),
                            cgst_amount=Decimal("0"),
                            sgst_rate=Decimal("9.00"),
                            sgst_amount=Decimal("0"),
                            igst_rate=Decimal("0"),
                            igst_amount=Decimal("0"),
                            utgst_rate=Decimal("0"),
                            utgst_amount=Decimal("0"),
                            cess_rate=Decimal("0"),
                            cess_amount=Decimal("0"),
                            total=total_val,
                        ))

                round_off = total_val - (subtotal + total_cgst + total_sgst + total_igst - discount_total)

                if is_estimate:
                    est = ProformaInvoice(
                        tenant_id=tenant_id,
                        contact_id=uuid.UUID(contact_id_str),
                        proforma_number=doc_number,
                        issue_date=txn_date,
                        due_date=due_date,
                        status="ISSUED",
                        subtotal=subtotal,
                        discount_total=discount_total,
                        cgst_amount=total_cgst,
                        sgst_amount=total_sgst,
                        igst_amount=total_igst,
                        utgst_amount=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=total_val,
                        pos_state_code=origin_state_code,
                    )
                    db.add(est)
                    db.flush()
                    est_map[txn_id] = str(est.id)

                    for line in lines_data:
                        line.proforma_invoice_id = est.id
                        db.add(line)

                    summary.estimates_imported += 1
                else:
                    amount_paid = Decimal(str(round(cash_amt, 2)))
                    if amount_paid > total_val:
                        amount_paid = total_val
                    if amount_paid >= total_val:
                        bill_status = "PAID"
                    elif amount_paid > 0:
                        bill_status = "PARTIALLY_PAID"
                    else:
                        bill_status = "UNPAID"

                    bill = Bill(
                        tenant_id=tenant_id,
                        contact_id=uuid.UUID(contact_id_str),
                        bill_number=doc_number,
                        issue_date=txn_date,
                        due_date=due_date,
                        status=bill_status,
                        subtotal=subtotal,
                        discount_total=discount_total,
                        cgst_amount=total_cgst,
                        sgst_amount=total_sgst,
                        igst_amount=total_igst,
                        utgst_amount=Decimal("0"),
                        cess_amount=Decimal("0"),
                        round_off=round_off,
                        total=total_val,
                        amount_paid=amount_paid,
                        pos_state_code=origin_state_code,
                    )
                    db.add(bill)
                    db.flush()
                    bill_map[txn_id] = str(bill.id)

                    for line in lines_data:
                        line.bill_id = bill.id
                        db.add(line)

                    summary.bills_imported += 1

            # ── PURCHASE BILLS (type=28) ──────────────────────────────────────
            elif txn_type == 28 and contact_id_str:
                bill_number = _gen_inv_number(ref_number, "BILL")
                existing_bill = (
                    db.query(Bill)
                    .filter(
                        Bill.tenant_id == tenant_id,
                        Bill.bill_number == bill_number,
                        Bill.deleted_at == None,
                    )
                    .first()
                )
                if existing_bill:
                    continue

                cash_amt = Decimal(str(txn["txn_cash_amount"] or 0))
                bal_amt = Decimal(str(txn["txn_balance_amount"] or 0))
                total_from_txn = cash_amt + bal_amt

                subtotal = Decimal("0")
                total_cgst = Decimal("0")
                total_sgst = Decimal("0")
                total_igst = Decimal("0")
                total_val = Decimal("0")
                discount_total = Decimal("0")

                bill_lines_data = []
                for vl in txn_lines:
                    line_total_d = Decimal(str(vl["total_amount"] or 0))
                    line_tax_d = Decimal(str(vl["lineitem_tax_amount"] or 0))
                    line_disc_d = Decimal(str(vl["lineitem_discount_amount"] or 0))
                    qty_d = Decimal(str(vl["quantity"] or 1))
                    rate_d = Decimal(str(vl["priceperunit"] or 0))
                    line_subtotal_d = line_total_d - line_tax_d

                    line_tax_id = vl["lineitem_tax_id"]
                    cgst_r, cgst_a, sgst_r, sgst_a, igst_r, igst_a = _split_gst(
                        line_tax_d, line_tax_id, group_rate_map, txn_is_intrastate
                    )
                    total_rate_pct = group_rate_map.get(line_tax_id or 0, Decimal("18.00")) if line_tax_id else Decimal("18.00")
                    hsn = normalize_hsn_sac(vl["_hsn"])

                    subtotal += max(line_subtotal_d, Decimal("0"))
                    total_cgst += cgst_a
                    total_sgst += sgst_a
                    total_igst += igst_a
                    total_val += line_total_d
                    discount_total += line_disc_d

                    product_id = None
                    if vl["item_id"] and vl["item_id"] in item_map:
                        try:
                            product_id = uuid.UUID(item_map[vl["item_id"]])
                        except Exception:
                            pass

                    bill_lines_data.append(BillLine(
                        product_id=product_id,
                        description=(vl["_item_name"] or "").strip() or "Item",
                        quantity=qty_d,
                        rate=rate_d,
                        discount=line_disc_d,
                        subtotal=max(line_subtotal_d, Decimal("0")),
                        hsn_sac=hsn,
                        gst_rate=Decimal(str(total_rate_pct)),
                        cgst_rate=cgst_r,
                        cgst_amount=cgst_a,
                        sgst_rate=sgst_r,
                        sgst_amount=sgst_a,
                        igst_rate=igst_r,
                        igst_amount=igst_a,
                        utgst_rate=Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_rate=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=line_total_d,
                    ))

                if not bill_lines_data:
                    total_val = total_from_txn
                    subtotal = total_val
                    bill_lines_data.append(BillLine(
                        product_id=None,
                        description="Imported Purchase Transaction",
                        quantity=Decimal("1"),
                        rate=total_val,
                        discount=Decimal("0"),
                        subtotal=total_val,
                        hsn_sac="998313",
                        gst_rate=Decimal("18.00"),
                        cgst_rate=Decimal("9.00"),
                        cgst_amount=Decimal("0"),
                        sgst_rate=Decimal("9.00"),
                        sgst_amount=Decimal("0"),
                        igst_rate=Decimal("0"),
                        igst_amount=Decimal("0"),
                        utgst_rate=Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_rate=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=total_val,
                    ))

                amount_paid = cash_amt
                if amount_paid > total_val:
                    amount_paid = total_val
                if amount_paid >= total_val:
                    bill_status = "PAID"
                elif amount_paid > 0:
                    bill_status = "PARTIALLY_PAID"
                else:
                    bill_status = "UNPAID"

                round_off = total_val - (subtotal + total_cgst + total_sgst + total_igst - discount_total)

                bill = Bill(
                    tenant_id=tenant_id,
                    contact_id=uuid.UUID(contact_id_str),
                    bill_number=bill_number,
                    issue_date=txn_date,
                    due_date=due_date,
                    status=bill_status,
                    subtotal=subtotal,
                    discount_total=discount_total,
                    cgst_amount=total_cgst,
                    sgst_amount=total_sgst,
                    igst_amount=total_igst,
                    utgst_amount=Decimal("0"),
                    cess_amount=Decimal("0"),
                    round_off=round_off,
                    total=total_val,
                    amount_paid=amount_paid,
                    pos_state_code=origin_state_code,
                )
                db.add(bill)
                db.flush()
                bill_map[txn_id] = str(bill.id)

                for line in bill_lines_data:
                    line.bill_id = bill.id
                    db.add(line)

                summary.bills_imported += 1

            # Other transaction types (payments, credit notes etc.) are
            # informational and don't map directly — skip silently.

        # ── 10b. Fix contact types from transaction data ──────────────────────
        # Contacts appearing in type=28 (purchase) transactions should be VENDOR or BOTH
        purchase_name_ids = set()
        for txn in vy_txns:
            if txn["txn_type"] == 28 and txn["txn_name_id"]:
                purchase_name_ids.add(txn["txn_name_id"])
        for name_id in purchase_name_ids:
            if name_id in contact_map:
                try:
                    c = db.query(Contact).filter(
                        Contact.id == uuid.UUID(contact_map[name_id])
                    ).first()
                    if c and c.contact_type == "CUSTOMER":
                        c.contact_type = "BOTH"
                    elif c and c.contact_type != "BOTH":
                        c.contact_type = "VENDOR"
                except Exception:
                    pass

        # ── 10c. Auto-post journal entries for invoices and bills ──────────────
        from src.domains.accounting.auto_post import auto_post_invoice, auto_post_bill
        posted_invoices = 0
        posted_bills = 0
        for inv_id_str in inv_map.values():
            try:
                inv = db.query(Invoice).filter(Invoice.id == uuid.UUID(inv_id_str)).first()
                if inv and inv.status in ("SENT", "DRAFT"):
                    auto_post_invoice(db, tenant_id, inv, allow_negative_stock=True)
                    posted_invoices += 1
            except Exception as e:
                summary.errors.append(f"Auto-post invoice {inv_id_str}: {e}")
        for bill_id_str in bill_map.values():
            try:
                bill = db.query(Bill).filter(Bill.id == uuid.UUID(bill_id_str)).first()
                if bill and bill.status in ("UNPAID", "DRAFT"):
                    auto_post_bill(db, tenant_id, bill)
                    posted_bills += 1
            except Exception as e:
                summary.errors.append(f"Auto-post bill {bill_id_str}: {e}")

        # ── 11. Import payments from txn_payment_mapping ──────────────────────
        try:
            vy_payments = vconn.execute(
                """
                SELECT pm.*, pt.paymentType_type, pt.paymentType_name,
                       pt.paymentType_bankName, pt.paymentType_accountNumber
                FROM txn_payment_mapping pm
                LEFT JOIN kb_paymentTypes pt ON pm.payment_id = pt.paymentType_id
                """
            ).fetchall()

            # Group payments by transaction
            payments_by_txn: Dict[int, list] = {}
            for pm in vy_payments:
                pm_dict = dict(pm)
                txn_id = pm_dict["txn_id"]
                payments_by_txn.setdefault(txn_id, []).append(pm_dict)

            # Process payments for sale invoices (type=1)
            for pm_list in payments_by_txn.values():
                for pm in pm_list:
                    txn_id = pm["txn_id"]
                    amount = float(pm["amount"] or 0)
                    if amount <= 0:
                        continue

                    # Find the corresponding invoice or bill
                    inv_uuid = inv_map.get(txn_id)
                    bill_uuid = bill_map.get(txn_id)

                    if not inv_uuid and not bill_uuid:
                        continue

                    # Map payment mode
                    vy_mode = (pm["paymentType_type"] or "CASH").upper()
                    mode_map = {"CASH": "CASH", "CHEQUE": "BANK", "BANK": "BANK", "UPI": "UPI"}
                    payment_mode = mode_map.get(vy_mode, "OTHER")

                    # Resolve contact_id from the transaction
                    contact_id_val = None
                    for t in vy_txns:
                        if t["txn_id"] == txn_id and t["txn_name_id"]:
                            cid_str = contact_map.get(t["txn_name_id"])
                            if cid_str:
                                contact_id_val = uuid.UUID(cid_str)
                            break

                    if inv_uuid:
                        # Customer receipt → Payment + PaymentAllocation
                        payment = Payment(
                            tenant_id=tenant_id,
                            contact_id=contact_id_val,
                            payment_number=f"VYP-PAY-{txn_id}",
                            payment_date=_parse_date(pm.get("payment_date") or date.today().isoformat()),
                            payment_mode=payment_mode,
                            amount=Decimal(str(round(amount, 2))),
                            reference_number=pm.get("payment_reference") or "",
                            description=f"Imported from Vyapar ({pm['paymentType_name'] or ''})",
                            status="ACTIVE",
                        )
                        db.add(payment)
                        db.flush()
                        alloc = PaymentAllocation(
                            payment_id=payment.id,
                            invoice_id=uuid.UUID(inv_uuid),
                            amount=Decimal(str(round(amount, 2))),
                        )
                        db.add(alloc)
                    elif bill_uuid:
                        # Vendor payment → BillPayment + BillPaymentAllocation
                        bill_payment = BillPayment(
                            tenant_id=tenant_id,
                            contact_id=contact_id_val,
                            payment_number=f"VYP-BPAY-{txn_id}",
                            payment_date=_parse_date(pm.get("payment_date") or date.today().isoformat()),
                            payment_mode=payment_mode,
                            amount=Decimal(str(round(amount, 2))),
                            reference_number=pm.get("payment_reference") or "",
                            description=f"Imported from Vyapar ({pm['paymentType_name'] or ''})",
                            status="ACTIVE",
                        )
                        db.add(bill_payment)
                        db.flush()
                        alloc = BillPaymentAllocation(
                            payment_id=bill_payment.id,
                            bill_id=uuid.UUID(bill_uuid),
                            amount=Decimal(str(round(amount, 2))),
                        )
                        db.add(alloc)

                    summary.payments_imported += 1

        except Exception as e:
            summary.errors.append(f"Payment import: {e}")

        # ── 12. Import stock from kb_item_stock_tracking + kb_item_adjustments ─
        try:
            vy_stock = vconn.execute("SELECT * FROM kb_item_stock_tracking").fetchall()
            warehouse_id = resolve_default_warehouse_id(db, tenant_id)
            for st in vy_stock:
                item_id = st["ist_item_id"]
                if item_id not in item_map:
                    continue
                prod_uuid = uuid.UUID(item_map[item_id])
                qty = float(st["ist_current_quantity"] or 0)
                quantity = Decimal(str(qty))
                product = db.query(Product).filter(
                    Product.id == prod_uuid,
                    Product.tenant_id == tenant_id,
                    Product.deleted_at == None,
                ).with_for_update().first()
                if not product or product.product_type != "GOODS":
                    continue
                already_imported = db.query(StockLedger.id).filter(
                    StockLedger.tenant_id == tenant_id,
                    StockLedger.product_id == prod_uuid,
                ).first()
                if already_imported:
                    continue
                product.opening_stock = quantity
                product.current_stock = quantity
                db.add(StockLedger(
                    tenant_id=tenant_id,
                    product_id=prod_uuid,
                    warehouse_id=warehouse_id,
                    quantity=quantity,
                    balance_quantity=quantity,
                    reference_type="VYAPAR_OPENING",
                    reference_id=prod_uuid,
                    rate=product.purchase_price or Decimal("0"),
                ))
                summary.stock_entries_imported += 1

            # Historical item adjustments are already included in
            # ist_current_quantity and must not be replayed a second time.

        except Exception as e:
            summary.errors.append(f"Stock import: {e}")

        # ── 13. Import linked transactions (quotation → invoice) ──────────────
        try:
            vy_links = vconn.execute("SELECT * FROM kb_linked_transactions").fetchall()
            for link in vy_links:
                src_id = link["txn_source_id"]
                dst_id = link["txn_destination_id"]
                # Map source quotation to proforma invoice, destination to invoice
                # We stored proforma IDs during import, need to map back
                # For now, set converted_to_invoice_id on proforma invoices
                if src_id in est_map and dst_id in inv_map:
                    try:
                        est_uuid = uuid.UUID(est_map[src_id])
                        inv_uuid = uuid.UUID(inv_map[dst_id])
                        est = db.query(ProformaInvoice).filter(ProformaInvoice.id == est_uuid).first()
                        if est:
                            est.converted_to_invoice_id = inv_uuid
                            est.status = "CONVERTED"
                            summary.linked_transactions_imported += 1
                    except Exception:
                        pass
        except Exception as e:
            summary.errors.append(f"Linked transaction import: {e}")

        # ── 14. Import e-invoice/e-way bill data ──────────────────────────────
        try:
            for txn in vy_txns:
                irn = (txn.get("txn_irn_number") or "").strip()
                eway = (txn.get("txn_eway_bill_number") or "").strip()
                if not irn and not eway:
                    continue

                txn_id = txn["txn_id"]
                # Attach to invoice if it exists
                if txn_id in inv_map:
                    inv_uuid = uuid.UUID(inv_map[txn_id])
                    inv = db.query(Invoice).filter(Invoice.id == inv_uuid).first()
                    if inv:
                        if irn:
                            inv.irn = irn
                            inv.e_invoice_status = "GENERATED"
                        if eway:
                            # Create EWayBill record
                            ew = EWayBill(
                                tenant_id=tenant_id,
                                invoice_id=inv_uuid,
                                eway_bill_number=eway,
                                status="GENERATED",
                                supply_type="OUTWARD",
                            )
                            db.add(ew)
                        summary.e_invoice_data_imported += 1
        except Exception as e:
            summary.errors.append(f"E-invoice/e-way bill import: {e}")

        # ── 15. Apply UDF values to transactions ──────────────────────────────
        try:
            if udf_values_by_ref:
                for txn_id, udf_data in udf_values_by_ref.items():
                    if txn_id in inv_map:
                        inv_uuid = uuid.UUID(inv_map[txn_id])
                        inv = db.query(Invoice).filter(Invoice.id == inv_uuid).first()
                        if inv:
                            inv.vyapar_custom_fields = udf_data
                    elif txn_id in bill_map:
                        bill_uuid = uuid.UUID(bill_map[txn_id])
                        bill = db.query(Bill).filter(Bill.id == bill_uuid).first()
                        if bill:
                            bill.vyapar_custom_fields = udf_data
        except Exception as e:
            summary.errors.append(f"UDF value import: {e}")

        db.commit()

    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Import failed: {str(exc)}",
        )
    finally:
        try:
            vconn.close()
        except Exception:
            logger.exception("Error closing Vyapar SQLite connection")
        try:
            os.unlink(tmp.name)
        except OSError:
            logger.warning("Could not remove temp file %s", tmp.name)

    return summary
