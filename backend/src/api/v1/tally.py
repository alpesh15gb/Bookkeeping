"""
Tally XML import and export endpoints.

Supports:
  - Import: Tally XML (Ledgers → Contacts, StockItems → Products, Vouchers → Invoices/Bills/Payments/Expenses)
  - Export: Tenant data as Tally-compatible XML

Tally XML format uses:
  <ENVELOPE>
    <HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
    <BODY>
      <IMPORTDATA>
        <REQUESTDATA>
          <TALLYMESSAGE ...>
            <LEDGER ...> / <STOCKITEM ...> / <VOUCHER ...>
          </TALLYMESSAGE>
        </REQUESTDATA>
      </IMPORTDATA>
    </BODY>
  </ENVELOPE>
"""
import io
import uuid
import xml.etree.ElementTree as ET
from decimal import Decimal, InvalidOperation
from datetime import datetime, date
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func
from sqlalchemy.orm import Session

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Contact, Product, Invoice, InvoiceLine, Bill, BillLine,
    Expense, ExpenseCategory, Account, Tenant, TenantSetting,
    Payment, PaymentAllocation, BillPayment, BillPaymentAllocation,
    CreditNote, CreditNoteLine, DebitNote, DebitNoteLine,
    BankingProfile, NumberingSeries, JournalEntry, JournalLine,
)
from src.api.deps import enforce_permission
from src.domains.company.services import NumberingSeriesService


router = APIRouter(prefix="/tally", tags=["Tally Import/Export"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _safe_decimal(val, default="0") -> Decimal:
    try:
        return Decimal(str(val).strip().replace(",", "")) if val else Decimal(default)
    except (InvalidOperation, ValueError):
        return Decimal(default)


def _safe_str(val) -> Optional[str]:
    if val is None:
        return None
    s = str(val).strip()
    return s if s else None


def _xml_text(parent, tag, default=None) -> Optional[str]:
    """Safely extract text from an XML sub-element."""
    el = parent.find(tag)
    return el.text.strip() if el is not None and el.text else default


def _xml_date(parent, tag) -> Optional[date]:
    """Tally dates are YYYYMMDD or YYYY-MM-DD. Return a date object."""
    raw = _xml_text(parent, tag)
    if not raw:
        return None
    raw = raw.strip().replace("-", "")
    if len(raw) == 8:
        iso = f"{raw[:4]}-{raw[4:6]}-{raw[6:8]}"
    else:
        iso = raw
    try:
        return date.fromisoformat(iso)
    except ValueError:
        return None


def _tally_date_xml(iso_str: str) -> str:
    """Convert ISO date to Tally YYYYMMDD."""
    if not iso_str:
        return ""
    return iso_str.replace("-", "")


def _infer_state_code_from_gstin(gstin: Optional[str]) -> str:
    if gstin and len(gstin) >= 2:
        code = gstin[:2]
        if code.isdigit():
            return code
    return "27"


def _gstin_state_map():
    return {
        "01": "Jammu & Kashmir", "02": "Himachal Pradesh", "03": "Punjab",
        "04": "Chandigarh", "05": "Uttarakhand", "06": "Haryana",
        "07": "Delhi", "08": "Rajasthan", "09": "Uttar Pradesh",
        "10": "Bihar", "11": "Sikkim", "12": "Arunachal Pradesh",
        "13": "Nagaland", "14": "Manipur", "15": "Mizoram",
        "16": "Tripura", "17": "Meghalaya", "18": "Assam",
        "19": "West Bengal", "20": "Jharkhand", "21": "Odisha",
        "22": "Chhattisgarh", "23": "Madhya Pradesh", "24": "Gujarat",
        "25": "Daman & Diu", "26": "Dadra & Nagar Haveli",
        "27": "Maharashtra", "28": "Andhra Pradesh (Old)",
        "29": "Karnataka", "30": "Goa", "31": "Lakshadweep",
        "32": "Kerala", "33": "Tamil Nadu", "34": "Puducherry",
        "35": "Andaman & Nicobar", "36": "Telangana",
        "37": "Andhra Pradesh", "38": "Ladakh",
    }


# ---------------------------------------------------------------------------
# 1. IMPORT
# ---------------------------------------------------------------------------

@router.post("/import")
async def import_tally_xml(
    file: UploadFile = File(...),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("data:import")),
):
    """Import Tally XML backup. Returns summary of imported records."""
    content = await file.read()
    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        raise HTTPException(status_code=400, detail=f"Invalid XML: {e}")

    summary = {
        "contacts_imported": 0,
        "products_imported": 0,
        "invoices_imported": 0,
        "bills_imported": 0,
        "expenses_imported": 0,
        "payments_imported": 0,
        "errors": [],
    }

    # Maps for dedup
    ledger_contact_map: Dict[str, uuid.UUID] = {}   # Tally ledger name → contact.id
    stock_product_map: Dict[str, tuple] = {}     # Tally stock item name → (product.id, gst_rate, hsn_sac)

    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()
    origin_state = setting.origin_state_code if setting and setting.origin_state_code else "27"

    # ── Phase 1: Import Ledgers as Contacts ──────────────────────────────
    for msg in root.iter("TALLYMESSAGE"):
        for ledger in msg.findall("LEDGER"):
            name = _xml_text(ledger, "NAME")
            if not name:
                continue

            # Skip system/round-off/expense-only ledgers
            parent_group = _xml_text(ledger, "PARENT") or ""
            if any(k in parent_group.lower() for k in ["capital", "profit", "reserve", "sundry", "cash"]):
                pass  # keep going, we'll filter by type

            ledger_type = (_xml_text(ledger, "LEDGERALLOCATIONS") or "").lower()
            party_gstin = _xml_text(ledger, "PARTYGSTIN") or _xml_text(ledger, "GSTIN")
            party_state = _xml_text(ledger, "STATE") or _xml_text(ledger, "STATENAME")
            party_phone = _xml_text(ledger, "LEDGERPHONE") or _xml_text(ledger, "PHONE")
            party_email = _xml_text(ledger, "EMAIL")
            address_lines = []
            addr_el = ledger.find("ADDRESS")
            if addr_el is not None and addr_el.text:
                address_lines.append(addr_el.text.strip())
            for a in ledger.findall("ADDRESS.LIST/ADDRESS"):
                if a.text and a.text.strip():
                    address_lines.append(a.text.strip())
            address_str = ", ".join(address_lines) if address_lines else ""

            # Determine contact type from parent group
            pgl = parent_group.lower()
            if "sundry debtor" in pgl or "debtor" in pgl:
                contact_type = "CUSTOMER"
            elif "sundry creditor" in pgl or "creditor" in pgl:
                contact_type = "VENDOR"
            else:
                contact_type = "BOTH"

            # Dedup by GSTIN or name
            existing = None
            if party_gstin:
                existing = db.query(Contact).filter(
                    Contact.tenant_id == tenant_id,
                    func.upper(Contact.gstin) == party_gstin.strip().upper(),
                    Contact.deleted_at == None,
                ).first()
            if not existing:
                existing = db.query(Contact).filter(
                    Contact.tenant_id == tenant_id,
                    func.lower(func.trim(Contact.name)) == name.lower(),
                    Contact.deleted_at == None,
                ).first()

            if existing:
                if existing.contact_type != contact_type:
                    existing.contact_type = "BOTH"
                ledger_contact_map[name] = existing.id
                continue

            state_code = _infer_state_code_from_gstin(party_gstin) if party_gstin else origin_state

            contact = Contact(
                tenant_id=tenant_id,
                name=name,
                email=_safe_str(party_email),
                phone=_safe_str(party_phone),
                contact_type=contact_type,
                gstin=_safe_str(party_gstin),
                registration_type="REGULAR" if party_gstin else "CONSUMER",
                billing_address={
                    "street": address_str,
                    "city": "",
                    "state": _gstin_state_map().get(state_code, ""),
                    "state_code": state_code,
                    "pincode": "",
                    "country": "India",
                },
                state_code=state_code,
                is_active=True,
            )
            db.add(contact)
            db.flush()
            ledger_contact_map[name] = contact.id
            summary["contacts_imported"] += 1

    # ── Phase 2: Import Stock Items as Products ──────────────────────────
    for msg in root.iter("TALLYMESSAGE"):
        for item in msg.findall("STOCKITEM"):
            name = _xml_text(item, "NAME")
            if not name:
                continue

            hsn = _xml_text(item, "HSNCODE") or _xml_text(item, "GSTHSNCODE") or "00000000"
            uom = (_xml_text(item, "BASEUNITS") or "PCS").upper()
            rate_el = item.find("RATE")
            sales_price = _safe_decimal(_xml_text(item, "SELLINGPRICE") or _xml_text(item, "MRP") or "0")

            # GST rate from GSTDETAILS
            gst_rate = Decimal("0")
            gst_details = item.find("GSTDETAILS")
            if gst_details is not None:
                rate_str = _xml_text(gst_details, "GSTINTEGRATEDRATE") or _xml_text(gst_details, "APPLICABLEFROM")
                for slab in gst_details.findall("GSTSLABLIST/GSTSLAB"):
                    r = _xml_text(slab, "GSTRATE")
                    if r:
                        gst_rate = _safe_decimal(r)
                        break

            # Dedup by name
            existing = db.query(Product).filter(
                Product.tenant_id == tenant_id,
                func.lower(func.trim(Product.name)) == name.lower(),
                Product.deleted_at == None,
            ).first()
            if existing:
                stock_product_map[name] = (existing.id, existing.gst_rate, existing.hsn_sac or "00000000")
                continue

            product = Product(
                tenant_id=tenant_id,
                name=name,
                hsn_sac=hsn.replace(" ", "")[:8],
                product_type="GOODS",
                uom=uom if uom in ("PCS", "NOS", "KGS", "GMS", "LTR", "MTR", "SQF", "BOX", "SET", "BAG", "BTL", "CTN", "DOZ", "DZN", "HRS", "HOUR", "RFT", "ROL", "SQM", "SQY", "TON", "TUB", "UNT", "YDS") else "PCS",
                sales_price=sales_price,
                purchase_price=sales_price,
                gst_rate=gst_rate,
                is_active=True,
            )
            db.add(product)
            db.flush()
            stock_product_map[name] = (product.id, product.gst_rate, product.hsn_sac or "00000000")
            summary["products_imported"] += 1

    # ── Phase 3: Import Vouchers as Invoices/Bills/Payments/Expenses ─────
    # NumberingSeriesService is a static-method service; document types map
    # to the generate_next_number TYPE keys, not legacy column names.
    _NUMBERING_KEYS = {
        "invoice_number": "INVOICE",
        "bill_number": "BILL",
        "payment_number": "PAYMENT",
        "bill_payment_number": "DISBURSEMENT",
    }
    def _next_number(document_type: str) -> str:
        return NumberingSeriesService.generate_next_number(
            db, tenant_id, _NUMBERING_KEYS.get(document_type, "INVOICE"))

    for msg in root.iter("TALLYMESSAGE"):
        for voucher in msg.findall("VOUCHER"):
            vtype = (_xml_text(voucher, "VOUCHERTYPENAME") or _xml_text(voucher, "VCHTYPE") or "").upper()
            vdate = _xml_date(voucher, "DATE") or _xml_date(voucher, "EFFECTIVEDATE")
            vnumber = _xml_text(voucher, "VOUCHERNUMBER") or _xml_text(voucher, "REFERENCE")
            party_name = _xml_text(voucher, "PARTYLEDGERNAME") or _xml_text(voucher, "PARTYNAME")

            if not vdate:
                continue

            # ── SALES VOUCHER → Invoice ──────────────────────────────────
            if vtype in ("SALES", "SALES INVOICE", "CREDIT NOTE"):
                # Skip if it's actually a credit note
                if vtype == "CREDIT NOTE":
                    continue

                contact_id = ledger_contact_map.get(party_name) if party_name else None
                inv_number = vnumber or _next_number("invoice_number")

                lines = []
                total_subtotal = Decimal("0")

                # Accumulate voucher-level GST outside the line loop
                voucher_cgst = Decimal("0")
                voucher_sgst = Decimal("0")
                voucher_igst = Decimal("0")
                for alloc in voucher.findall("LEDGERENTRIES.LIST"):
                    alloc_ledger = _xml_text(alloc, "LEDGERNAME") or ""
                    alloc_amount = _safe_decimal(_xml_text(alloc, "AMOUNT") or "0")
                    al = alloc_ledger.lower()
                    if "cgst" in al:
                        voucher_cgst += abs(alloc_amount)
                    elif "sgst" in al or "utgst" in al:
                        voucher_sgst += abs(alloc_amount)
                    elif "igst" in al:
                        voucher_igst += abs(alloc_amount)

                for inv_line in voucher.findall("ALLINVENTORYENTRIES.LIST/INVENTORYENTRIES.LIST"):
                    stock_name = _xml_text(inv_line, "STOCKITEMNAME")
                    qty = _safe_decimal(_xml_text(inv_line, "ACTUALQTY") or _xml_text(inv_line, "BILLEDQTY") or "1")
                    rate_el = inv_line.find("RATE")
                    rate = _safe_decimal(rate_el.text if rate_el is not None and rate_el.text else "0")
                    amount = _safe_decimal(_xml_text(inv_line, "AMOUNT") or "0")

                    prod_info = stock_product_map.get(stock_name) if stock_name else None
                    product_id = prod_info[0] if prod_info else None
                    prod_gst_rate = prod_info[1] if prod_info and len(prod_info) > 1 else Decimal("0")
                    prod_hsn = prod_info[2] if prod_info and len(prod_info) > 2 else "00000000"

                    line_data = {
                        "product_id": str(product_id) if product_id else None,
                        "product_name": stock_name or "Item",
                        "quantity": float(qty) if qty > 0 else 1,
                        "rate": float(rate) if rate > 0 else float(abs(amount)),
                        "total": float(abs(amount)),
                        "gst_rate": float(prod_gst_rate),
                        "hsn_sac": prod_hsn,
                    }
                    lines.append(line_data)
                    total_subtotal += abs(amount)

                if not lines:
                    continue

                # Distribute GST proportionally across lines based on subtotal
                for line in lines:
                    if total_subtotal > 0:
                        ratio = Decimal(str(line["total"])) / total_subtotal
                        line["cgst"] = float(voucher_cgst * ratio)
                        line["sgst"] = float(voucher_sgst * ratio)
                        line["igst"] = float(voucher_igst * ratio)
                    else:
                        line["cgst"] = 0.0
                        line["sgst"] = 0.0
                        line["igst"] = 0.0

                grand_total = total_subtotal + voucher_cgst + voucher_sgst + voucher_igst

                invoice = Invoice(
                    tenant_id=tenant_id,
                    contact_id=contact_id,
                    invoice_number=inv_number,
                    issue_date=vdate,
                    due_date=vdate,
                    pos_state_code=origin_state,
                    status="POSTED",
                    subtotal=total_subtotal,
                    discount_total=Decimal("0"),
                    cgst_amount=voucher_cgst,
                    sgst_amount=voucher_sgst,
                    igst_amount=voucher_igst,
                    utgst_amount=Decimal("0"),
                    cess_amount=Decimal("0"),
                    round_off=Decimal("0"),
                    total=grand_total,
                    amount_paid=Decimal("0"),
                )
                db.add(invoice)
                db.flush()

                # Get document-level tax totals to know which tax type applies
                has_igst = voucher_igst > 0

                for line in lines:
                    line_total = Decimal(str(line["total"]))
                    line_gst_rate = Decimal(str(line["gst_rate"]))
                    il = InvoiceLine(
                        invoice_id=invoice.id,
                        product_id=uuid.UUID(line["product_id"]) if line["product_id"] else None,
                        hsn_sac=line["hsn_sac"],
                        description=line["product_name"],
                        quantity=Decimal(str(line["quantity"])),
                        rate=Decimal(str(line["rate"])),
                        discount=Decimal("0"),
                        subtotal=line_total,
                        gst_rate=line_gst_rate,
                        cgst_amount=Decimal(str(line["cgst"])) if not has_igst else Decimal("0"),
                        sgst_amount=Decimal(str(line["sgst"])) if not has_igst else Decimal("0"),
                        igst_amount=Decimal(str(line["igst"])) if has_igst else Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=line_total + Decimal(str(line["cgst"])) + Decimal(str(line["sgst"])) + Decimal(str(line["igst"])),
                    )
                    db.add(il)

                db.flush()
                summary["invoices_imported"] += 1

            # ── PURCHASE VOUCHER → Bill ──────────────────────────────────
            elif vtype in ("PURCHASE", "PURCHASE INVOICE", "DEBIT NOTE"):
                if vtype == "DEBIT NOTE":
                    continue

                contact_id = ledger_contact_map.get(party_name) if party_name else None
                bill_number = vnumber or _next_number("bill_number")

                lines = []
                total_subtotal = Decimal("0")

                # Accumulate voucher-level GST outside the line loop
                voucher_cgst = Decimal("0")
                voucher_sgst = Decimal("0")
                voucher_igst = Decimal("0")
                for alloc in voucher.findall("LEDGERENTRIES.LIST"):
                    alloc_ledger = _xml_text(alloc, "LEDGERNAME") or ""
                    alloc_amount = _safe_decimal(_xml_text(alloc, "AMOUNT") or "0")
                    al = alloc_ledger.lower()
                    if "cgst" in al:
                        voucher_cgst += abs(alloc_amount)
                    elif "sgst" in al or "utgst" in al:
                        voucher_sgst += abs(alloc_amount)
                    elif "igst" in al:
                        voucher_igst += abs(alloc_amount)

                for inv_line in voucher.findall("ALLINVENTORYENTRIES.LIST/INVENTORYENTRIES.LIST"):
                    stock_name = _xml_text(inv_line, "STOCKITEMNAME")
                    qty = _safe_decimal(_xml_text(inv_line, "ACTUALQTY") or _xml_text(inv_line, "BILLEDQTY") or "1")
                    rate_el = inv_line.find("RATE")
                    rate = _safe_decimal(rate_el.text if rate_el is not None and rate_el.text else "0")
                    amount = _safe_decimal(_xml_text(inv_line, "AMOUNT") or "0")

                    prod_info = stock_product_map.get(stock_name) if stock_name else None
                    product_id = prod_info[0] if prod_info else None
                    prod_gst_rate = prod_info[1] if prod_info and len(prod_info) > 1 else Decimal("0")
                    prod_hsn = prod_info[2] if prod_info and len(prod_info) > 2 else "00000000"

                    line_data = {
                        "product_id": str(product_id) if product_id else None,
                        "product_name": stock_name or "Item",
                        "quantity": float(qty) if qty > 0 else 1,
                        "rate": float(rate) if rate > 0 else float(abs(amount)),
                        "total": float(abs(amount)),
                        "gst_rate": float(prod_gst_rate),
                        "hsn_sac": prod_hsn,
                    }
                    lines.append(line_data)
                    total_subtotal += abs(amount)

                if not lines:
                    continue

                # Distribute GST proportionally across lines
                for line in lines:
                    if total_subtotal > 0:
                        ratio = Decimal(str(line["total"])) / total_subtotal
                        line["cgst"] = float(voucher_cgst * ratio)
                        line["sgst"] = float(voucher_sgst * ratio)
                        line["igst"] = float(voucher_igst * ratio)
                    else:
                        line["cgst"] = 0.0
                        line["sgst"] = 0.0
                        line["igst"] = 0.0

                grand_total = total_subtotal + voucher_cgst + voucher_sgst + voucher_igst
                has_igst = voucher_igst > 0

                bill = Bill(
                    tenant_id=tenant_id,
                    contact_id=contact_id,
                    bill_number=bill_number,
                    issue_date=vdate,
                    due_date=vdate,
                    pos_state_code=origin_state,
                    status="POSTED",
                    subtotal=total_subtotal,
                    discount_total=Decimal("0"),
                    cgst_amount=voucher_cgst if not has_igst else Decimal("0"),
                    sgst_amount=voucher_sgst if not has_igst else Decimal("0"),
                    igst_amount=voucher_igst if has_igst else Decimal("0"),
                    utgst_amount=Decimal("0"),
                    cess_amount=Decimal("0"),
                    round_off=Decimal("0"),
                    total=grand_total,
                    amount_paid=Decimal("0"),
                )
                db.add(bill)
                db.flush()

                for line in lines:
                    line_total = Decimal(str(line["total"]))
                    line_gst_rate = Decimal(str(line["gst_rate"]))
                    bl = BillLine(
                        bill_id=bill.id,
                        product_id=uuid.UUID(line["product_id"]) if line["product_id"] else None,
                        hsn_sac=line["hsn_sac"],
                        description=line["product_name"],
                        quantity=Decimal(str(line["quantity"])),
                        rate=Decimal(str(line["rate"])),
                        discount=Decimal("0"),
                        subtotal=line_total,
                        gst_rate=line_gst_rate,
                        cgst_amount=Decimal(str(line["cgst"])) if not has_igst else Decimal("0"),
                        sgst_amount=Decimal(str(line["sgst"])) if not has_igst else Decimal("0"),
                        igst_amount=Decimal(str(line["igst"])) if has_igst else Decimal("0"),
                        utgst_amount=Decimal("0"),
                        cess_amount=Decimal("0"),
                        total=line_total + Decimal(str(line["cgst"])) + Decimal(str(line["sgst"])) + Decimal(str(line["igst"])),
                    )
                    db.add(bl)

                db.flush()
                summary["bills_imported"] += 1

            # ── RECEIPT VOUCHER → Payment ────────────────────────────────
            elif vtype in ("RECEIPT",):
                amount = Decimal("0")
                party_ledger = ""
                for alloc in voucher.findall("LEDGERENTRIES.LIST"):
                    alloc_amount = _safe_decimal(_xml_text(alloc, "AMOUNT") or "0")
                    alloc_ledger = _xml_text(alloc, "LEDGERNAME") or ""
                    if alloc_amount > 0 and alloc_ledger.lower() not in ("cash", "bank", "bank account", "cash account"):
                        amount = alloc_amount
                        party_ledger = alloc_ledger
                        break

                if amount <= 0:
                    for alloc in voucher.findall("LEDGERENTRIES.LIST"):
                        alloc_amount = _safe_decimal(_xml_text(alloc, "AMOUNT") or "0")
                        if alloc_amount < 0:
                            amount = abs(alloc_amount)
                            party_ledger = _xml_text(alloc, "LEDGERNAME") or ""
                            break

                if amount > 0:
                    payment = Payment(
                        tenant_id=tenant_id,
                        contact_id=ledger_contact_map.get(party_ledger),
                        payment_number=_next_number("payment_number"),
                        payment_date=vdate,
                        payment_mode="BANK",
                        amount=amount,
                        reference_number=_safe_str(vnumber),
                    )
                    db.add(payment)
                    db.flush()
                    summary["payments_imported"] += 1

            # ── PAYMENT VOUCHER → Bill Payment ───────────────────────────
            elif vtype in ("PAYMENT",):
                amount = Decimal("0")
                party_ledger = ""
                for alloc in voucher.findall("LEDGERENTRIES.LIST"):
                    alloc_amount = _safe_decimal(_xml_text(alloc, "AMOUNT") or "0")
                    alloc_ledger = _xml_text(alloc, "LEDGERNAME") or ""
                    if alloc_amount > 0 and alloc_ledger.lower() not in ("cash", "bank", "bank account", "cash account"):
                        amount = alloc_amount
                        party_ledger = alloc_ledger
                        break

                if amount <= 0:
                    for alloc in voucher.findall("LEDGERENTRIES.LIST"):
                        alloc_amount = _safe_decimal(_xml_text(alloc, "AMOUNT") or "0")
                        if alloc_amount < 0:
                            amount = abs(alloc_amount)
                            party_ledger = _xml_text(alloc, "LEDGERNAME") or ""
                            break

                if amount > 0:
                    bp = BillPayment(
                        tenant_id=tenant_id,
                        contact_id=ledger_contact_map.get(party_ledger),
                        payment_number=_next_number("bill_payment_number"),
                        payment_date=vdate,
                        payment_mode="BANK",
                        amount=amount,
                        reference_number=_safe_str(vnumber),
                    )
                    db.add(bp)
                    db.flush()
                    summary["payments_imported"] += 1

            # ── JOURNAL VOUCHER → Expense (if simple) ────────────────────
            elif vtype in ("JOURNAL", "CONTRA"):
                pass  # Journal entries are complex; skip for now

    # ── Post ledger entries for imported documents ──────────────────────
    # State-preserving posting: creates the missing journal entry without
    # touching document status, amount_paid, allocations or stock.
    from src.core.posting_context import set_session_posting_channel
    from src.domains.accounting.backfill_posting import (
        post_invoice_if_missing, post_bill_if_missing,
        post_payment_if_missing, post_bill_payment_if_missing,
    )
    set_session_posting_channel(db, "IMPORT")
    for inv in db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id, Invoice.deleted_at.is_(None),
    ).all():
        try:
            with db.begin_nested():
                post_invoice_if_missing(db, tenant_id, inv)
        except Exception as e:
            summary["errors"].append(f"Auto-post invoice {inv.invoice_number}: {e}")
    for bill in db.query(Bill).filter(
        Bill.tenant_id == tenant_id, Bill.deleted_at.is_(None),
    ).all():
        try:
            with db.begin_nested():
                post_bill_if_missing(db, tenant_id, bill)
        except Exception as e:
            summary["errors"].append(f"Auto-post bill {bill.bill_number}: {e}")
    for pay in db.query(Payment).filter(
        Payment.tenant_id == tenant_id, Payment.deleted_at.is_(None),
    ).all():
        try:
            with db.begin_nested():
                post_payment_if_missing(db, tenant_id, pay)
        except Exception as e:
            summary["errors"].append(f"Auto-post payment {pay.payment_number}: {e}")
    for bp in db.query(BillPayment).filter(
        BillPayment.tenant_id == tenant_id, BillPayment.deleted_at.is_(None),
    ).all():
        try:
            with db.begin_nested():
                post_bill_payment_if_missing(db, tenant_id, bp)
        except Exception as e:
            summary["errors"].append(f"Auto-post bill payment {bp.payment_number}: {e}")

    db.commit()
    return summary


# ---------------------------------------------------------------------------
# 2. EXPORT
# ---------------------------------------------------------------------------

@router.get("/export")
def export_tally_xml(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("data:export")),
):
    """Export tenant data as Tally-compatible XML."""
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant_id).first()

    root = ET.Element("ENVELOPE")
    header = ET.SubElement(root, "HEADER")
    ET.SubElement(header, "TALLYREQUEST").text = "Export Data"
    ET.SubElement(header, "TYPE").text = "Data"
    ET.SubElement(header, "ID").text = "All Masters and Transactions"

    body = ET.SubElement(root, "BODY")
    export_data = ET.SubElement(body, "EXPORTDATA")
    request_desc = ET.SubElement(export_data, "REQUESTDESC")
    ET.SubElement(request_desc, "REPORTNAME").text = "All Masters and Vouchers"
    request_data = ET.SubElement(export_data, "REQUESTDATA")

    # ── Contacts as Ledgers ──────────────────────────────────────────────
    contacts = db.query(Contact).filter(
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None,
    ).all()

    for c in contacts:
        msg = ET.SubElement(request_data, "TALLYMESSAGE", {"UDF": "TallyAdmin"})
        ledger = ET.SubElement(msg, "LEDGER", {"NAME": c.name})
        ET.SubElement(ledger, "NAME").text = c.name
        ET.SubElement(ledger, "PARENT").text = (
            "Sundry Debtors" if c.contact_type == "CUSTOMER"
            else "Sundry Creditors" if c.contact_type == "VENDOR"
            else "Sundry Debtors"
        )
        ET.SubElement(ledger, "ISBILLWISEON").text = "Yes"
        ET.SubElement(ledger, "ISCOSTCENTRESON").text = "No"
        if c.gstin:
            ET.SubElement(ledger, "PARTYGSTIN").text = c.gstin
        if c.state_code:
            ET.SubElement(ledger, "STATE").text = c.state_code
        if c.phone:
            ET.SubElement(ledger, "LEDGERPHONE").text = c.phone
        if c.email:
            ET.SubElement(ledger, "EMAIL").text = c.email
        addr = c.billing_address or {}
        if addr.get("street"):
            ET.SubElement(ledger, "ADDRESS").text = addr["street"]

    # ── Products as Stock Items ──────────────────────────────────────────
    products = db.query(Product).filter(
        Product.tenant_id == tenant_id,
        Product.deleted_at == None,
    ).all()

    for p in products:
        msg = ET.SubElement(request_data, "TALLYMESSAGE", {"UDF": "TallyAdmin"})
        item = ET.SubElement(msg, "STOCKITEM", {"NAME": p.name})
        ET.SubElement(item, "NAME").text = p.name
        ET.SubElement(item, "PARENT").text = "Primary"
        ET.SubElement(item, "BASEUNITS").text = p.uom or "PCS"
        ET.SubElement(item, "HSNCODE").text = p.hsn_sac or ""
        if p.gst_rate and p.gst_rate > 0:
            gst_el = ET.SubElement(item, "GSTDETAILS")
            ET.SubElement(gst_el, "GSTINTEGRATEDRATE").text = str(p.gst_rate)

    # ── Invoices as Sales Vouchers ───────────────────────────────────────
    invoices = db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
        Invoice.status != "CANCELLED",
    ).all()

    for inv in invoices:
        msg = ET.SubElement(request_data, "TALLYMESSAGE", {"UDF": "TallyAdmin"})
        v = ET.SubElement(msg, "VOUCHER", {"VCHTYPE": "Sales", "ACTION": "Create"})
        ET.SubElement(v, "DATE").text = _tally_date_xml(inv.issue_date.isoformat() if hasattr(inv.issue_date, 'isoformat') else str(inv.issue_date))
        ET.SubElement(v, "VOUCHERTYPENAME").text = "Sales"
        ET.SubElement(v, "VOUCHERNUMBER").text = inv.invoice_number
        ET.SubElement(v, "REFERENCE").text = inv.invoice_number
        if inv.contact:
            ET.SubElement(v, "PARTYLEDGERNAME").text = inv.contact.name

        # Line items
        for line in inv.lines:
            inv_entries = ET.SubElement(v, "ALLINVENTORYENTRIES.LIST")
            entry = ET.SubElement(inv_entries, "INVENTORYENTRIES.LIST")
            product_name = line.product.name if line.product else (line.product_name or "Item")
            ET.SubElement(entry, "STOCKITEMNAME").text = product_name
            ET.SubElement(entry, "ISDEEMEDPOSITIVE").text = "Yes"
            ET.SubElement(entry, "RATE").text = f"{line.rate:.2f}/PCS"
            ET.SubElement(entry, "ACTUALQTY").text = f"{line.quantity:.0f} PCS"
            ET.SubElement(entry, "BILLEDQTY").text = f"{line.quantity:.0f} PCS"
            ET.SubElement(entry, "AMOUNT").text = f"-{line.total:.2f}"

        # Tax entries
        if inv.cgst_amount > 0:
            le = ET.SubElement(v, "LEDGERENTRIES.LIST")
            ET.SubElement(le, "LEDGERNAME").text = "CGST"
            ET.SubElement(le, "ISDEEMEDPOSITIVE").text = "No"
            ET.SubElement(le, "AMOUNT").text = str(inv.cgst_amount)
        if inv.sgst_amount > 0:
            le = ET.SubElement(v, "LEDGERENTRIES.LIST")
            ET.SubElement(le, "LEDGERNAME").text = "SGST"
            ET.SubElement(le, "ISDEEMEDPOSITIVE").text = "No"
            ET.SubElement(le, "AMOUNT").text = str(inv.sgst_amount)
        if inv.igst_amount > 0:
            le = ET.SubElement(v, "LEDGERENTRIES.LIST")
            ET.SubElement(le, "LEDGERNAME").text = "IGST"
            ET.SubElement(le, "ISDEEMEDPOSITIVE").text = "No"
            ET.SubElement(le, "AMOUNT").text = str(inv.igst_amount)

        # Sales ledger entry
        le = ET.SubElement(v, "LEDGERENTRIES.LIST")
        ET.SubElement(le, "LEDGERNAME").text = "Sales"
        ET.SubElement(le, "ISDEEMEDPOSITIVE").text = "No"
        ET.SubElement(le, "AMOUNT").text = str(inv.subtotal)

    # ── Bills as Purchase Vouchers ───────────────────────────────────────
    bills = db.query(Bill).filter(
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None,
        Bill.status != "CANCELLED",
    ).all()

    for bill in bills:
        msg = ET.SubElement(request_data, "TALLYMESSAGE", {"UDF": "TallyAdmin"})
        v = ET.SubElement(msg, "VOUCHER", {"VCHTYPE": "Purchase", "ACTION": "Create"})
        ET.SubElement(v, "DATE").text = _tally_date_xml(bill.issue_date.isoformat() if hasattr(bill.issue_date, 'isoformat') else str(bill.issue_date))
        ET.SubElement(v, "VOUCHERTYPENAME").text = "Purchase"
        ET.SubElement(v, "VOUCHERNUMBER").text = bill.bill_number
        ET.SubElement(v, "REFERENCE").text = bill.bill_number
        if bill.contact:
            ET.SubElement(v, "PARTYLEDGERNAME").text = bill.contact.name

        for line in bill.lines:
            inv_entries = ET.SubElement(v, "ALLINVENTORYENTRIES.LIST")
            entry = ET.SubElement(inv_entries, "INVENTORYENTRIES.LIST")
            product_name = line.product.name if line.product else (line.product_name or "Item")
            ET.SubElement(entry, "STOCKITEMNAME").text = product_name
            ET.SubElement(entry, "ISDEEMEDPOSITIVE").text = "No"
            ET.SubElement(entry, "RATE").text = f"{line.rate:.2f}/PCS"
            ET.SubElement(entry, "ACTUALQTY").text = f"{line.quantity:.0f} PCS"
            ET.SubElement(entry, "BILLEDQTY").text = f"{line.quantity:.0f} PCS"
            ET.SubElement(entry, "AMOUNT").text = str(line.total)

        le = ET.SubElement(v, "LEDGERENTRIES.LIST")
        ET.SubElement(le, "LEDGERNAME").text = "Purchase"
        ET.SubElement(le, "ISDEEMEDPOSITIVE").text = "Yes"
        ET.SubElement(le, "AMOUNT").text = f"-{bill.subtotal}"

    # ── Serialize to XML ─────────────────────────────────────────────────
    tree = ET.ElementTree(root)
    ET.indent(tree, space="  ")
    buf = io.BytesIO()
    tree.write(buf, encoding="utf-8", xml_declaration=True)
    buf.seek(0)

    filename = f"tally_export_{tenant.trade_name or 'company'}_{datetime.now().strftime('%Y%m%d')}.xml"
    return StreamingResponse(
        buf,
        media_type="application/xml",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
