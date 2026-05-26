import uuid
from decimal import Decimal
from typing import List, Optional
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


@router.post("/vyapar", response_model=ImportSummary)
def import_vyapar_backup(
    file: UploadFile = File(...),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("tenant:update")),
):
    """Import data from a Vyapar .vyb backup file."""
    import zipfile, sqlite3, tempfile, os, math

    summary = ImportSummary()

    # 1. Extract .vyp from .vyb ZIP
    content = file.file.read()
    try:
        zf = zipfile.ZipFile(content, mode="r")
        vyp_names = [n for n in zf.namelist() if n.endswith(".vyp")]
        if not vyp_names:
            raise HTTPException(status_code=400, detail="No .vyp file found inside .vyb backup.")
        vyp_data = zf.read(vyp_names[0])
        zf.close()
    except zipfile.BadZipFile:
        raise HTTPException(status_code=400, detail="Invalid .vyb file. Must be a valid Vyapar backup ZIP.")

    # 2. Open SQLite database
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.write(vyp_data)
    tmp.close()
    vconn = sqlite3.connect(tmp.name)
    vconn.row_factory = sqlite3.Row

    try:
        # 3. Get firm info for state code
        firm = vconn.execute("SELECT * FROM kb_firms LIMIT 1").fetchone()
        origin_state_code = "36"  # default Telangana
        if firm and firm["firm_state"]:
            state_map = {
                "Telangana": "36", "Andhra Pradesh": "37", "Maharashtra": "27",
                "Karnataka": "29", "Tamil Nadu": "33", "Delhi": "07",
                "Gujarat": "24", "Rajasthan": "08", "Uttar Pradesh": "09",
                "Kerala": "32", "West Bengal": "19", "Haryana": "06",
            }
            origin_state_code = state_map.get(firm["firm_state"], "36")

        # 4. Resolve vendor accounts
        from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances

        # 5. Read all names (parties and expense categories)
        vy_names = vconn.execute("SELECT * FROM kb_names").fetchall()
        vy_expense_cat_names = {}  # name_id -> name for expense-only names

        # 6. Import contacts (skip expense categories)
        contact_map = {}  # vyapar name_id -> our contact_id
        for n in vy_names:
            name_str = (n["full_name"] or "").strip()
            phone = (n["phone_number"] or "").strip()
            email = (n["email"] or "").strip()

            # Skip expense-only names (Petrol, Transport, Salary, Rent, Tea)
            is_expense_cat = not phone and not email and name_str.lower() in (
                "petrol", "transport", "salary", "rent", "tea", "electricity",
                "water", "internet", "miscellaneous", "office expenses",
                "travelling", "postage", "printing", "repairs", "maintenance",
                "legal", "professional fees", "advertisement", "insurance",
                "interest", "commission", "bank charges",
            )
            if is_expense_cat:
                vy_expense_cat_names[n["name_id"]] = name_str
                continue
            if not name_str or name_str.startswith("("):
                continue

            existing = db.query(Contact).filter(
                Contact.tenant_id == tenant_id,
                Contact.name == name_str,
                Contact.deleted_at == None,
            ).first()
            if existing:
                contact_map[n["name_id"]] = str(existing.id)
                continue

            contact = Contact(
                tenant_id=tenant_id,
                name=name_str,
                phone=phone or None,
                email=email or None,
                contact_type="BOTH",
                gstin=None,
                state_code=origin_state_code,
                billing_address={"street": "", "city": "", "state": "", "pincode": ""},
                is_active=True,
            )
            db.add(contact)
            db.flush()
            contact_map[n["name_id"]] = str(contact.id)
            summary.contacts_imported += 1

        # 7. Import products
        vy_items = vconn.execute("SELECT * FROM kb_items").fetchall()
        item_map = {}  # vyapar item_id -> our product_id
        for i in vy_items:
            name_str = (i["item_name"] or "").strip()
            if not name_str:
                continue
            existing = db.query(Product).filter(
                Product.tenant_id == tenant_id,
                Product.name == name_str,
                Product.deleted_at == None,
            ).first()
            if existing:
                item_map[i["item_id"]] = str(existing.id)
                # Update stock
                qty = float(i["item_stock_quantity"] or 0)
                if qty < 0:
                    existing.current_stock = max(0, existing.current_stock + abs(qty))
                continue

            sale_price = max(0, float(i["item_sale_unit_price"] or 0))
            purchase_price = max(0, float(i["item_purchase_unit_price"] or 0))
            stock = max(0, float(i["item_stock_quantity"] or 0))

            product = Product(
                tenant_id=tenant_id,
                name=name_str,
                hsn_sac="998313",
                product_type="GOODS" if purchase_price > 0 else "SERVICE",
                uom="NOS",
                sales_price=Decimal(str(sale_price)),
                purchase_price=Decimal(str(purchase_price)),
                gst_rate=Decimal("18.00"),
                opening_stock=Decimal(str(stock)),
                current_stock=Decimal(str(stock)),
                reorder_level=Decimal(str(max(0, float(i["item_min_stock_quantity"] or 0)))),
                is_active=True,
            )
            db.add(product)
            db.flush()
            item_map[i["item_id"]] = str(product.id)
            summary.products_imported += 1

        # 8. Import expense categories from Vyapar expense names
        expense_cat_map = {}
        for cat_name in vy_expense_cat_names.values():
            existing_cat = db.query(ExpenseCategory).filter(
                ExpenseCategory.tenant_id == tenant_id,
                ExpenseCategory.name == cat_name,
                ExpenseCategory.deleted_at == None,
            ).first()
            if existing_cat:
                expense_cat_map[cat_name.lower()] = str(existing_cat.id)
            else:
                # Create an expense account for this category
                resolver = AccountResolver(db, tenant_id)
                from src.infrastructure.database.models import Account as Acct
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
                    description=f"Imported from Vyapar",
                    linked_account_id=acct.id,
                    is_active=True,
                )
                db.add(cat)
                db.flush()
                expense_cat_map[cat_name.lower()] = str(cat.id)

        # 9. Import transactions
        vy_txns = vconn.execute("SELECT * FROM kb_transactions").fetchall()

        # Helper: generate number
        def gen_number(prefix: str) -> str:
            return f"{prefix}-{datetime.now().strftime('%Y%m')}-{uuid.uuid4().hex[:6].upper()}"

        for txn in vy_txns:
            txn_type = txn["txn_type"]
            txn_id = txn["txn_id"]
            txn_date_str = txn["txn_date"]
            if txn_date_str:
                try:
                    txn_date = datetime.strptime(str(txn_date_str)[:10], "%Y-%m-%d").date()
                except:
                    txn_date = date.today()
            else:
                txn_date = date.today()

            cash_amt = float(txn["txn_cash_amount"] or 0)
            bal_amt = float(txn["txn_balance_amount"] or 0)
            total = cash_amt + bal_amt

            if total <= 0:
                continue

            name_id = txn["txn_name_id"]
            contact_id = contact_map.get(name_id) if name_id else None

            # Get line items
            vy_lines = vconn.execute(
                "SELECT li.*, i.item_name FROM kb_lineitems li LEFT JOIN kb_items i ON li.item_id=i.item_id WHERE li.lineitem_txn_id=?",
                (txn_id,)
            ).fetchall()

            # --- SALES INVOICES (type=1) ---
            if txn_type == 1 and contact_id:
                inv = Invoice(
                    tenant_id=tenant_id,
                    contact_id=uuid.UUID(contact_id),
                    invoice_number=gen_number("INV"),
                    issue_date=txn_date,
                    due_date=txn_date,
                    status="SENT",
                    subtotal=Decimal(str(round(total, 2))),
                    discount_total=Decimal("0.00"),
                    cgst_amount=Decimal("0.00"),
                    sgst_amount=Decimal("0.00"),
                    igst_amount=Decimal("0.00"),
                    utgst_amount=Decimal("0.00"),
                    cess_amount=Decimal("0.00"),
                    round_off=Decimal("0.00"),
                    total=Decimal(str(round(total, 2))),
                    amount_paid=Decimal(str(round(cash_amt, 2))),
                    pos_state_code=origin_state_code,
                )
                db.add(inv)
                db.flush()

                for vl in vy_lines:
                    line_total = float(vl["total_amount"] or 0)
                    line_tax = float(vl["lineitem_tax_amount"] or 0)
                    line_disc = float(vl["lineitem_discount_amount"] or 0)
                    qty = float(vl["quantity"] or 1)
                    rate = float(vl["priceperunit"] or 0)
                    subtotal = line_total - line_tax
                    item_name = vl["item_name"] or ""

                    inv_line = InvoiceLine(
                        invoice_id=inv.id,
                        product_id=uuid.UUID(item_map.get(vl["item_id"], uuid.uuid4())) if vl["item_id"] and vl["item_id"] in item_map else None,
                        description=item_name,
                        quantity=Decimal(str(qty)),
                        rate=Decimal(str(rate)),
                        discount=Decimal(str(line_disc)),
                        subtotal=Decimal(str(round(max(subtotal, 0), 2))),
                        hsn_sac="998313",
                        gst_rate=Decimal("18.00"),
                        cgst_rate=Decimal("9.00"),
                        cgst_amount=Decimal(str(round(line_tax / 2, 2))) if line_tax > 0 else Decimal("0.00"),
                        sgst_rate=Decimal("9.00"),
                        sgst_amount=Decimal(str(round(line_tax / 2, 2))) if line_tax > 0 else Decimal("0.00"),
                        igst_rate=Decimal("0"),
                        igst_amount=Decimal("0"),
                        utgst_rate=Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_rate=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=Decimal(str(round(line_total, 2))),
                    )
                    db.add(inv_line)

                summary.invoices_imported += 1

            # --- PURCHASE BILLS (type=27) ---
            elif txn_type == 27 and contact_id:
                bill = Bill(
                    tenant_id=tenant_id,
                    contact_id=uuid.UUID(contact_id),
                    bill_number=gen_number("BILL"),
                    issue_date=txn_date,
                    due_date=txn_date,
                    status="UNPAID",
                    subtotal=Decimal(str(round(total, 2))),
                    discount_total=Decimal("0.00"),
                    cgst_amount=Decimal("0.00"),
                    sgst_amount=Decimal("0.00"),
                    igst_amount=Decimal("0.00"),
                    utgst_amount=Decimal("0.00"),
                    cess_amount=Decimal("0.00"),
                    total=Decimal(str(round(total, 2))),
                    amount_paid=Decimal(str(round(cash_amt, 2))),
                    pos_state_code=origin_state_code,
                )
                db.add(bill)
                db.flush()

                for vl in vy_lines:
                    line_total = float(vl["total_amount"] or 0)
                    line_tax = float(vl["lineitem_tax_amount"] or 0)
                    qty = float(vl["quantity"] or 1)
                    rate = float(vl["priceperunit"] or 0)
                    subtotal = line_total - line_tax
                    item_name = vl["item_name"] or ""

                    bill_line = BillLine(
                        bill_id=bill.id,
                        product_id=uuid.UUID(item_map.get(vl["item_id"], uuid.uuid4())) if vl["item_id"] and vl["item_id"] in item_map else None,
                        description=item_name,
                        quantity=Decimal(str(qty)),
                        rate=Decimal(str(rate)),
                        discount=Decimal("0"),
                        subtotal=Decimal(str(round(max(subtotal, 0), 2))),
                        hsn_sac="998313",
                        gst_rate=Decimal("18.00"),
                        cgst_rate=Decimal("9.00"),
                        cgst_amount=Decimal(str(round(line_tax / 2, 2))) if line_tax > 0 else Decimal("0.00"),
                        sgst_rate=Decimal("9.00"),
                        sgst_amount=Decimal(str(round(line_tax / 2, 2))) if line_tax > 0 else Decimal("0.00"),
                        igst_rate=Decimal("0"),
                        igst_amount=Decimal("0"),
                        utgst_rate=Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_rate=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=Decimal(str(round(line_total, 2))),
                    )
                    db.add(bill_line)

                summary.bills_imported += 1

            # --- EXPENSES (type=28) ---
            elif txn_type == 28:
                # Determine expense category from name
                expense_cat_id = None
                if name_id and name_id in vy_expense_cat_names:
                    cat_name_lower = vy_expense_cat_names[name_id].lower()
                    expense_cat_id = expense_cat_map.get(cat_name_lower)
                if not expense_cat_id and expense_cat_map:
                    expense_cat_id = list(expense_cat_map.values())[0]

                if expense_cat_id:
                    expense = Expense(
                        tenant_id=tenant_id,
                        expense_number=gen_number("EXP"),
                        expense_category_id=uuid.UUID(expense_cat_id),
                        expense_date=txn_date,
                        vendor_name=None,
                        description=f"Imported from Vyapar",
                        amount=Decimal(str(round(total, 2))),
                        total=Decimal(str(round(total, 2))),
                        status="DRAFT",
                    )
                    db.add(expense)
                    summary.expenses_imported += 1

        db.commit()

    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Import failed: {str(exc)}")
    finally:
        vconn.close()
        os.unlink(tmp.name)

    return summary
