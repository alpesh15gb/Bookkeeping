from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy.orm import Session, joinedload
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date, datetime, timezone, timedelta
from dateutil.relativedelta import relativedelta

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    RecurringInvoice, RecurringInvoiceItem, Contact, Product, Invoice, InvoiceLine, TenantSetting
)
from src.schemas.document import (
    RecurringInvoiceCreate, RecurringInvoiceUpdate, RecurringInvoiceResponse,
    RecurringInvoiceListResponse
)
from src.domains.company.services import NumberingSeriesService, resolve_origin_state_code
from src.domains.taxation.services import GSTEngine
from src.api.deps import enforce_permission
from src.core.rate_limiter import limiter
from src.core.config import settings

router = APIRouter(prefix="/recurring-invoices", tags=["Recurring Invoices"])


@router.post("", response_model=RecurringInvoiceResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_recurring_invoice(
    request: Request,
    payload: RecurringInvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    contact = db.query(Contact).filter(
        Contact.id == payload.contact_id,
        Contact.tenant_id == tenant_id,
        Contact.deleted_at == None
    ).first()
    if not contact:
        raise HTTPException(status_code=404, detail="Contact not found.")

    db_items = []
    for item in payload.items:
        product = db.query(Product).filter(
            Product.id == item.product_id,
            Product.tenant_id == tenant_id,
            Product.deleted_at == None
        ).first()
        if not product:
            raise HTTPException(status_code=400, detail=f"Product {item.product_id} not found.")

        db_items.append(RecurringInvoiceItem(
            product_id=item.product_id,
            description=item.description or product.name,
            quantity=item.quantity,
            rate=item.rate,
            discount=item.discount or Decimal("0.0000"),
            hsn_sac=item.hsn_sac,
            gst_rate=item.gst_rate,
        ))

    recurring = RecurringInvoice(
        tenant_id=tenant_id,
        contact_id=payload.contact_id,
        template_name=payload.template_name,
        frequency=payload.frequency,
        interval_count=payload.interval_count,
        next_date=payload.next_date,
        end_mode=payload.end_mode,
        end_date=payload.end_date,
        max_occurrences=payload.max_occurrences,
        currency=payload.currency or "INR",
        exchange_rate=payload.exchange_rate or Decimal("1.000000"),
        pos_state_code=payload.pos_state_code,
        notes=payload.notes,
        terms_and_conditions=payload.terms_and_conditions,
        items=db_items,
    )

    db.add(recurring)
    db.commit()
    db.refresh(recurring)
    return recurring


@router.get("", response_model=List[RecurringInvoiceListResponse])
def list_recurring_invoices(
    active_only: bool = Query(False),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    q = db.query(RecurringInvoice, Contact.name.label("contact_name"))\
        .options(joinedload(RecurringInvoice.contact))\
        .join(Contact, RecurringInvoice.contact_id == Contact.id)\
        .filter(RecurringInvoice.tenant_id == tenant_id, RecurringInvoice.deleted_at == None)

    if active_only:
        q = q.filter(RecurringInvoice.is_active == True)

    results = q.order_by(RecurringInvoice.next_date.asc()).all()

    return [
        RecurringInvoiceListResponse(
            id=r.id,
            contact_id=r.contact_id,
            template_name=r.template_name,
            is_active=r.is_active,
            frequency=r.frequency,
            next_date=r.next_date,
            occurrences_created=r.occurrences_created,
            currency=r.currency,
            created_at=r.created_at,
            contact_name=contact_name,
        )
        for r, contact_name in results
    ]


@router.get("/{id}", response_model=RecurringInvoiceResponse)
def get_recurring_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    recurring = db.query(RecurringInvoice).options(
        joinedload(RecurringInvoice.items),
        joinedload(RecurringInvoice.contact),
    ).filter(
        RecurringInvoice.id == id,
        RecurringInvoice.tenant_id == tenant_id,
        RecurringInvoice.deleted_at == None,
    ).first()
    if not recurring:
        raise HTTPException(status_code=404, detail="Recurring invoice not found.")
    return recurring


@router.put("/{id}", response_model=RecurringInvoiceResponse)
def update_recurring_invoice(
    id: uuid.UUID,
    payload: RecurringInvoiceUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update")),
):
    recurring = db.query(RecurringInvoice).options(
        joinedload(RecurringInvoice.items),
    ).filter(
        RecurringInvoice.id == id,
        RecurringInvoice.tenant_id == tenant_id,
        RecurringInvoice.deleted_at == None,
    ).first()
    if not recurring:
        raise HTTPException(status_code=404, detail="Recurring invoice not found.")

    update_data = payload.model_dump(exclude_unset=True)
    items_data = update_data.pop("items", None)

    if "contact_id" in update_data:
        contact = db.query(Contact).filter(
            Contact.id == update_data["contact_id"],
            Contact.tenant_id == tenant_id,
            Contact.deleted_at == None,
        ).first()
        if not contact:
            raise HTTPException(status_code=404, detail="Contact not found.")

    product_by_id = {}
    if items_data is not None:
        for item_data in items_data:
            product = db.query(Product).filter(
                Product.id == item_data["product_id"],
                Product.tenant_id == tenant_id,
                Product.deleted_at == None,
            ).first()
            if not product:
                raise HTTPException(status_code=400, detail=f"Product {item_data['product_id']} not found.")
            product_by_id[item_data["product_id"]] = product

    for field, value in update_data.items():
        setattr(recurring, field, value)

    if items_data is not None:
        # Delete old items and create new ones
        for item in recurring.items:
            db.delete(item)
        db.flush()

        for item_data in items_data:
            product = product_by_id[item_data["product_id"]]
            db_item = RecurringInvoiceItem(
                recurring_invoice_id=recurring.id,
                product_id=item_data["product_id"],
                description=item_data.get("description") or product.name,
                quantity=item_data["quantity"],
                rate=item_data["rate"],
                discount=item_data.get("discount") or Decimal("0.0000"),
                hsn_sac=item_data["hsn_sac"],
                gst_rate=item_data["gst_rate"],
            )
            db.add(db_item)

    db.commit()
    db.refresh(recurring)
    return recurring


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_recurring_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
):
    recurring = db.query(RecurringInvoice).filter(
        RecurringInvoice.id == id,
        RecurringInvoice.tenant_id == tenant_id,
        RecurringInvoice.deleted_at == None,
    ).first()
    if not recurring:
        raise HTTPException(status_code=404, detail="Recurring invoice not found.")

    recurring.deleted_at = datetime.now(timezone.utc)
    db.commit()


@router.post("/{id}/generate", response_model=dict)
def generate_invoice_now(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """Manually trigger invoice generation from a recurring template."""
    recurring = db.query(RecurringInvoice).options(
        joinedload(RecurringInvoice.items),
        joinedload(RecurringInvoice.contact),
    ).filter(
        RecurringInvoice.id == id,
        RecurringInvoice.tenant_id == tenant_id,
        RecurringInvoice.deleted_at == None,
    ).with_for_update().first()
    if not recurring:
        raise HTTPException(status_code=404, detail="Recurring invoice not found.")

    if not recurring.is_active:
        raise HTTPException(status_code=400, detail="Recurring invoice is not active.")
    if recurring.end_mode == "AFTER_N" and recurring.max_occurrences is not None:
        if recurring.occurrences_created >= recurring.max_occurrences:
            raise HTTPException(status_code=400, detail="This recurring invoice has already reached its maximum occurrences.")
    if recurring.end_mode == "ON_DATE" and recurring.end_date and date.today() > recurring.end_date:
        raise HTTPException(status_code=400, detail="This recurring invoice has already ended.")

    from src.domains.accounting.auto_post import auto_post_invoice
    origin_state_code = resolve_origin_state_code(db, tenant_id)
    invoice_number = NumberingSeriesService.generate_next_number(db, tenant_id, "INVOICE")

    today = date.today()
    db_lines = []
    inv_subtotal = Decimal("0.0000")
    inv_cgst = Decimal("0.0000")
    inv_sgst = Decimal("0.0000")
    inv_igst = Decimal("0.0000")
    inv_utgst = Decimal("0.0000")
    inv_cess = Decimal("0.0000")

    for item in recurring.items:
        resolved_gst_rate = GSTEngine.resolve_gst_rate(db, tenant_id, item.gst_rate)
        line_subtotal = (item.quantity * item.rate) - item.discount
        if line_subtotal < 0:
            line_subtotal = Decimal("0.0000")

        tax_split = GSTEngine.calculate_tax(
            origin_state_code=origin_state_code,
            place_of_supply_state_code=recurring.pos_state_code,
            base_amount=line_subtotal,
            gst_rate=resolved_gst_rate,
            is_rcm=False,
            force_igst=False
        )

        db_line = InvoiceLine(
            product_id=item.product_id,
            description=item.description,
            quantity=item.quantity,
            rate=item.rate,
            discount=item.discount,
            subtotal=line_subtotal,
            hsn_sac=item.hsn_sac,
            gst_rate=resolved_gst_rate,
            cgst_rate=tax_split.cgst_rate,
            cgst_amount=tax_split.cgst_amount,
            sgst_rate=tax_split.sgst_rate,
            sgst_amount=tax_split.sgst_amount,
            igst_rate=tax_split.igst_rate,
            igst_amount=tax_split.igst_amount,
            utgst_rate=tax_split.utgst_rate,
            utgst_amount=tax_split.utgst_amount,
            cess_rate=tax_split.cess_rate,
            cess_amount=tax_split.cess_amount,
            total=tax_split.total_amount
        )
        db_lines.append(db_line)
        inv_subtotal += db_line.subtotal
        inv_cgst += db_line.cgst_amount
        inv_sgst += db_line.sgst_amount
        inv_igst += db_line.igst_amount
        inv_utgst += db_line.utgst_amount
        inv_cess += db_line.cess_amount

    raw_total = inv_subtotal + inv_cgst + inv_sgst + inv_igst + inv_utgst + inv_cess
    rounded_total = raw_total.quantize(Decimal("0.01"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total

    invoice = Invoice(
        tenant_id=tenant_id,
        contact_id=recurring.contact_id,
        invoice_number=invoice_number,
        issue_date=today,
        due_date=today + timedelta(days=30),
        status="DRAFT",
        subtotal=inv_subtotal,
        discount_total=Decimal("0.0000"),
        cgst_amount=inv_cgst,
        sgst_amount=inv_sgst,
        igst_amount=inv_igst,
        utgst_amount=inv_utgst,
        cess_amount=inv_cess,
        round_off=round_off,
        shipping_charges=Decimal("0.0000"),
        total=rounded_total,
        amount_paid=Decimal("0.0000"),
        pos_state_code=recurring.pos_state_code,
        e_invoice_status="PENDING",
        notes=recurring.notes,
        terms_and_conditions=recurring.terms_and_conditions,
        is_gst_inclusive=False,
        is_rcm=False,
        supply_type="DOMESTIC",
        currency=recurring.currency,
        exchange_rate=recurring.exchange_rate,
        lines=db_lines
    )

    db.add(invoice)
    db.flush()

    from src.core.posting_context import set_session_posting_channel
    set_session_posting_channel(db, "RECURRING")
    auto_post_invoice(db, tenant_id, invoice)

    # Update recurring template
    recurring.occurrences_created += 1
    recurring.last_generated = today
    schedule_from = recurring.next_date or today
    recurring.next_date = _calculate_next_date(schedule_from, recurring.frequency, recurring.interval_count)

    # Check end conditions
    if recurring.end_mode == "ON_DATE" and recurring.end_date and recurring.next_date > recurring.end_date:
        recurring.is_active = False
    elif recurring.end_mode == "AFTER_N" and recurring.max_occurrences and recurring.occurrences_created >= recurring.max_occurrences:
        recurring.is_active = False

    db.commit()
    return {"invoice_id": str(invoice.id), "invoice_number": invoice_number}


def _calculate_next_date(current: date, frequency: str, interval: int) -> date:
    if frequency == "WEEKLY":
        return current + timedelta(weeks=interval)
    elif frequency == "MONTHLY":
        return current + relativedelta(months=interval)
    elif frequency == "QUARTERLY":
        return current + relativedelta(months=3 * interval)
    elif frequency == "YEARLY":
        return current + relativedelta(years=interval)
    return current + relativedelta(months=interval)
