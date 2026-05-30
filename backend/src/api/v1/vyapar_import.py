import io
import uuid
import math
from decimal import Decimal
from typing import List, Optional, Dict
from datetime import datetime, date
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.orm import Session
from pydantic import BaseModel

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Contact, Product, Invoice, InvoiceLine, Bill, BillLine,
    Expense, ExpenseCategory, Account, Tenant
)
from src.api.deps import enforce_permission
from src.domains.company.services import NumberingSeriesService

router = APIRouter(prefix="/import", tags=["Data Import"])


class ImportSummary(BaseModel):
    contacts_imported: int = 0
    products_imported: int = 0
    invoices_imported: int = 0
    bills_imported: int = 0
    expenses_imported: int = 0
    errors: List[str] = []


# ---------------------------------------------------------------------------
# Vyapar GST tax_id -> tax rate (%) mapping helper
# Vyapar tax_code_type: 0 = split (CGST/SGST), 1 = combined (treated as IGST)
# tax_mapping groups always come in pairs (SGST + CGST) per rate
# We build a dict: tax_group_id -> (gst_rate_pct, is_intra_state)
# ---------------------------------------------------------------------------
def _build_tax_rate_map(vconn) -> Dict[int, float]:
    """Return dict: kb_tax_code.tax_code_id -> total_gst_rate_pct (float)"""
    rows = vconn.execute("SELECT tax_code_id, tax_rate, tax_code_type FROM kb_tax_code").fetchall()
    return {r[0]: float(r[1] or 0) for r in rows}


def _build_group_rate_map(vconn, tax_code_rates: Dict[int, float]) -> Dict[int, float]:
    """Return dict: tax_mapping_group_id -> total gst rate % (sum of component rates)"""
    mappings = vconn.execute(
        "SELECT tax_mapping_group_id, tax_mapping_code_id FROM kb_tax_mapping"
    ).fetchall()
    group_rates: Dict[int, float] = {}
    for m in mappings:
        gid = m[0]
        code_rate = tax_code_rates.get(m[1], 0)
        group_rates[gid] = group_rates.get(gid, 0) + code_rate
    return group_rates


def _split_gst(
    total_tax_amount: float,
    line_tax_id: Optional[int],
    group_rate_map: Dict[int, float],
    is_intrastate: bool,
) -> tuple:
    """
    Given the total tax amount for a line, split it into CGST+SGST (intrastate)
    or IGST (interstate).  Returns (cgst_rate, cgst_amt, sgst_rate, sgst_amt, igst_rate, igst_amt).
    All as Decimal.
    """
    tax = round(total_tax_amount, 2)
    total_rate = group_rate_map.get(line_tax_id or 0, 18.0) if line_tax_id else 18.0

    if is_intrastate:
        half_rate = round(total_rate / 2, 2)
        half_tax = round(tax / 2, 2)
        return (
            Decimal(str(half_rate)), Decimal(str(half_tax)),
            Decimal(str(half_rate)), Decimal(str(half_tax)),
            Decimal("0"), Decimal("0"),
        )
    else:
        return (
            Decimal("0"), Decimal("0"),
            Decimal("0"), Decimal("0"),
            Decimal(str(total_rate)), Decimal(str(round(tax, 2))),
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
                "Telangana": "36",
                "Andhra Pradesh": "37",
                "Maharashtra": "27",
                "Karnataka": "29",
                "Tamil Nadu": "33",
                "Delhi": "07",
                "Gujarat": "24",
                "Rajasthan": "08",
                "Uttar Pradesh": "09",
                "Kerala": "32",
                "West Bengal": "19",
                "Haryana": "06",
            }
            origin_state_name = firm["firm_state"]
            origin_state_code = state_map.get(firm["firm_state"], "36")

        # ── 5. Build GST rate lookup tables ───────────────────────────────────
        tax_code_rates = _build_tax_rate_map(vconn)
        group_rate_map = _build_group_rate_map(vconn, tax_code_rates)
        # We assume all transactions are intrastate (same state as the firm)
        is_intrastate = True

        # ── 6. Import contacts ────────────────────────────────────────────────
        vy_names = vconn.execute("SELECT * FROM kb_names").fetchall()
        vy_expense_cat_names: Dict[int, str] = {}
        contact_map: Dict[int, str] = {}  # vyapar name_id -> our contact.id str

        # Common words that signal an expense category, not a real party
        _EXPENSE_KEYWORDS = {
            "petrol", "transport", "salary", "rent", "tea", "electricity",
            "water", "internet", "miscellaneous", "office expenses",
            "travelling", "postage", "printing", "repairs", "maintenance",
            "legal", "professional fees", "advertisement", "insurance",
            "interest", "commission", "bank charges", "fuel", "food",
        }

        for n in vy_names:
            name_str = (n["full_name"] or "").strip()
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

            # Check if contact already exists (dedup by name + tenant)
            existing = (
                db.query(Contact)
                .filter(
                    Contact.tenant_id == tenant_id,
                    Contact.name == name_str,
                    Contact.deleted_at == None,  # noqa: E711
                )
                .first()
            )
            if existing:
                contact_map[n["name_id"]] = str(existing.id)
                continue

            # Determine contact type from name_type:
            # 1 = customer, 2 = vendor, 0 = both
            name_type = n["name_type"]
            contact_type = "CUSTOMER" if name_type == 1 else (
                "VENDOR" if name_type == 2 else "BOTH"
            )
            gstin = (n["name_gstin_number"] or "").strip() or None
            # Party state
            party_state = (n["name_state"] or "").strip()
            state_map2 = {
                "Telangana": "36", "Andhra Pradesh": "37",
                "Maharashtra": "27", "Karnataka": "29",
                "Tamil Nadu": "33", "Delhi": "07",
                "Gujarat": "24", "Rajasthan": "08",
                "Uttar Pradesh": "09", "Kerala": "32",
                "West Bengal": "19", "Haryana": "06",
            }
            party_state_code = state_map2.get(party_state, origin_state_code)

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
            summary.contacts_imported += 1

        # ── 7. Import products ────────────────────────────────────────────────
        vy_items = vconn.execute("SELECT * FROM kb_items").fetchall()
        item_map: Dict[int, str] = {}  # vyapar item_id -> our product.id str

        for i in vy_items:
            name_str = (i["item_name"] or "").strip()
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
            item_gst_rate = group_rate_map.get(item_tax_id or 0, 18.0) if item_tax_id else 18.0

            # item_type: 1=product, 2=service
            product_type = "SERVICE" if (i["item_type"] == 2 or purchase_price == 0) else "GOODS"

            hsn = (i["item_hsn_sac_code"] or "").strip() or "998313"

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

        def _parse_date(val) -> date:
            if not val:
                return date.today()
            try:
                return datetime.strptime(str(val)[:10], "%Y-%m-%d").date()
            except Exception:
                return date.today()

        def _gen_inv_number(existing_ref: Optional[str], prefix: str) -> str:
            nonlocal _inv_counter, _bill_counter
            if existing_ref and existing_ref.strip():
                return existing_ref.strip()
            if prefix == "INV":
                _inv_counter += 1
                return f"VYP-INV-{_inv_counter:04d}"
            else:
                _bill_counter += 1
                return f"VYP-BILL-{_bill_counter:04d}"

        for txn in vy_txns:
            txn_type = txn["txn_type"]
            txn_id = txn["txn_id"]
            txn_date = _parse_date(txn["txn_date"])
            due_date_raw = txn.get("txn_po_date") or txn["txn_date"]
            due_date = _parse_date(due_date_raw)
            if due_date < txn_date:
                due_date = txn_date

            name_id = txn["txn_name_id"]
            contact_id_str = contact_map.get(name_id) if name_id else None

            txn_lines = lines_by_txn.get(txn_id, [])

            # Reference number from Vyapar (txn_ref_number_char holds the invoice #)
            ref_number = (txn.get("txn_ref_number_char") or "").strip() or None
            payment_status = txn.get("txn_payment_status", 0)  # 1=paid/2=partial

            # ── SALES INVOICES (type=1) ─────────────────────────────────────
            if txn_type == 1 and contact_id_str:
                cash_amt = float(txn["txn_cash_amount"] or 0)
                bal_amt = float(txn["txn_balance_amount"] or 0)
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
                    line_total_f = float(vl["total_amount"] or 0)
                    line_tax_f = float(vl["lineitem_tax_amount"] or 0)
                    line_disc_f = float(vl["lineitem_discount_amount"] or 0)
                    qty_f = float(vl["quantity"] or 1)
                    rate_f = float(vl["priceperunit"] or 0)
                    line_subtotal_f = line_total_f - line_tax_f

                    line_tax_id = vl["lineitem_tax_id"]
                    cgst_r, cgst_a, sgst_r, sgst_a, igst_r, igst_a = _split_gst(
                        line_tax_f, line_tax_id, group_rate_map, is_intrastate
                    )
                    total_rate_pct = group_rate_map.get(line_tax_id or 0, 18.0) if line_tax_id else 18.0
                    hsn = (vl["_hsn"] or "").strip() or "998313"

                    subtotal += Decimal(str(round(max(line_subtotal_f, 0), 2)))
                    total_cgst += cgst_a
                    total_sgst += sgst_a
                    total_igst += igst_a
                    total_val += Decimal(str(round(line_total_f, 2)))
                    discount_total += Decimal(str(round(line_disc_f, 2)))

                    product_id = None
                    if vl["item_id"] and vl["item_id"] in item_map:
                        try:
                            product_id = uuid.UUID(item_map[vl["item_id"]])
                        except Exception:
                            pass

                    inv_lines_data.append(InvoiceLine(
                        product_id=product_id,
                        description=(vl["_item_name"] or "").strip() or "Item",
                        quantity=Decimal(str(qty_f)),
                        rate=Decimal(str(round(rate_f, 6))),
                        discount=Decimal(str(round(line_disc_f, 2))),
                        subtotal=Decimal(str(round(max(line_subtotal_f, 0), 2))),
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
                        total=Decimal(str(round(line_total_f, 2))),
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
                amount_paid = Decimal(str(round(cash_amt, 2)))
                if amount_paid > total_val:
                    amount_paid = total_val
                if amount_paid >= total_val:
                    inv_status = "PAID"
                elif amount_paid > 0:
                    inv_status = "PARTIALLY_PAID"
                else:
                    inv_status = "SENT"

                round_off = total_val - (subtotal + total_cgst + total_sgst + total_igst - discount_total)

                inv = Invoice(
                    tenant_id=tenant_id,
                    contact_id=uuid.UUID(contact_id_str),
                    invoice_number=_gen_inv_number(ref_number, "INV"),
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

                for line in inv_lines_data:
                    line.invoice_id = inv.id
                    db.add(line)

                summary.invoices_imported += 1

            # ── PURCHASE BILLS (type=27) ────────────────────────────────────
            elif txn_type == 27 and contact_id_str:
                cash_amt = float(txn["txn_cash_amount"] or 0)
                bal_amt = float(txn["txn_balance_amount"] or 0)
                total_from_txn = cash_amt + bal_amt

                subtotal = Decimal("0")
                total_cgst = Decimal("0")
                total_sgst = Decimal("0")
                total_igst = Decimal("0")
                total_val = Decimal("0")
                discount_total = Decimal("0")

                bill_lines_data = []
                for vl in txn_lines:
                    line_total_f = float(vl["total_amount"] or 0)
                    line_tax_f = float(vl["lineitem_tax_amount"] or 0)
                    line_disc_f = float(vl["lineitem_discount_amount"] or 0)
                    qty_f = float(vl["quantity"] or 1)
                    rate_f = float(vl["priceperunit"] or 0)
                    line_subtotal_f = line_total_f - line_tax_f

                    line_tax_id = vl["lineitem_tax_id"]
                    cgst_r, cgst_a, sgst_r, sgst_a, igst_r, igst_a = _split_gst(
                        line_tax_f, line_tax_id, group_rate_map, is_intrastate
                    )
                    total_rate_pct = group_rate_map.get(line_tax_id or 0, 18.0) if line_tax_id else 18.0
                    hsn = (vl["_hsn"] or "").strip() or "998313"

                    subtotal += Decimal(str(round(max(line_subtotal_f, 0), 2)))
                    total_cgst += cgst_a
                    total_sgst += sgst_a
                    total_igst += igst_a
                    total_val += Decimal(str(round(line_total_f, 2)))
                    discount_total += Decimal(str(round(line_disc_f, 2)))

                    product_id = None
                    if vl["item_id"] and vl["item_id"] in item_map:
                        try:
                            product_id = uuid.UUID(item_map[vl["item_id"]])
                        except Exception:
                            pass

                    bill_lines_data.append(BillLine(
                        product_id=product_id,
                        description=(vl["_item_name"] or "").strip() or "Item",
                        quantity=Decimal(str(qty_f)),
                        rate=Decimal(str(round(rate_f, 6))),
                        discount=Decimal(str(round(line_disc_f, 2))),
                        subtotal=Decimal(str(round(max(line_subtotal_f, 0), 2))),
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
                        total=Decimal(str(round(line_total_f, 2))),
                    ))

                if not bill_lines_data:
                    total_val = Decimal(str(round(total_from_txn, 2)))
                    subtotal = total_val
                    bill_lines_data.append(BillLine(
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

                amount_paid = Decimal(str(round(cash_amt, 2)))
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
                    bill_number=_gen_inv_number(ref_number, "BILL"),
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

                for line in bill_lines_data:
                    line.bill_id = bill.id
                    db.add(line)

                summary.bills_imported += 1

            # ── EXPENSES (type=28) ──────────────────────────────────────────
            elif txn_type == 28:
                cash_amt = float(txn["txn_cash_amount"] or 0)
                bal_amt = float(txn["txn_balance_amount"] or 0)
                total_expense = cash_amt + bal_amt
                if total_expense <= 0:
                    continue

                expense_cat_id = None
                if name_id and name_id in vy_expense_cat_names:
                    cat_key = vy_expense_cat_names[name_id].lower()
                    expense_cat_id = expense_cat_map.get(cat_key)
                if not expense_cat_id and expense_cat_map:
                    expense_cat_id = next(iter(expense_cat_map.values()))

                if not expense_cat_id:
                    summary.errors.append(
                        f"Expense txn#{txn_id} on {txn_date} skipped — no category"
                    )
                    continue

                exp_num = ref_number or f"VYP-EXP-{txn_id}"
                expense = Expense(
                    tenant_id=tenant_id,
                    expense_number=exp_num,
                    expense_category_id=uuid.UUID(expense_cat_id),
                    expense_date=txn_date,
                    vendor_name=None,
                    description="Imported from Vyapar",
                    amount=Decimal(str(round(total_expense, 2))),
                    total=Decimal(str(round(total_expense, 2))),
                    status="DRAFT",
                )
                db.add(expense)
                summary.expenses_imported += 1

            # Other transaction types (payments, credit notes etc.) are
            # informational and don't map directly — skip silently.

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
        vconn.close()
        os.unlink(tmp.name)

    return summary
