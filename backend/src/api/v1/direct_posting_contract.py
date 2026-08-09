from __future__ import annotations

import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Callable

from fastapi import Depends, HTTPException, Request, Response, status
from sqlalchemy import event, text
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.database import get_db_session
from src.infrastructure.database.models import Invoice, Bill, Expense, User
from src.schemas.document import InvoiceCreate, InvoiceUpdate, InvoiceResponse, InvoiceLineCreate
from src.schemas.bill_schemas import BillCreate, BillUpdate, BillResponse, BillLineCreate
from src.schemas.expense_schemas import ExpenseCreate, ExpenseUpdate, ExpenseResponse
from src.api.v1 import invoices as invoice_api
from src.api.v1 import bills as bill_api
from src.api.v1 import expenses as expense_api


class DeferredCommitSession:
    """Session proxy used to keep legacy multi-step handlers in one transaction."""
    def __init__(self, session: Session):
        self._session = session

    def __getattr__(self, name: str) -> Any:
        return getattr(self._session, name)

    def commit(self) -> None:
        self._session.flush()


def _unwrap(fn: Callable) -> Callable:
    while hasattr(fn, "__wrapped__"):
        fn = fn.__wrapped__
    return fn


def _remove_route(router, path: str, method: str) -> None:
    method = method.upper()
    kept = []
    for route in router.routes:
        methods = set(getattr(route, "methods", set()) or set())
        if getattr(route, "path", None) == path and method in methods:
            remaining = methods - {method}
            if remaining:
                route.methods = remaining
                kept.append(route)
        else:
            kept.append(route)
    router.routes[:] = kept


def _set_replay_resource(db: Session, obj: Any) -> None:
    from src.core.idempotency import get_inflight_claim

    claim = get_inflight_claim()
    resource_id = getattr(obj, "id", None)
    if (
        not claim
        or resource_id is None
        or db.get_bind().dialect.name != "postgresql"
    ):
        return
    db.execute(
        text(
            "UPDATE idempotency_keys "
            "SET resource_type=:resource_type, resource_id=CAST(:resource_id AS uuid) "
            "WHERE idempotency_key=:key AND tenant_id=:tenant "
            "AND method=:method AND path=:path"
        ),
        {
            "resource_type": type(obj).__name__,
            "resource_id": str(resource_id),
            "key": claim["key"],
            "tenant": claim["tenant"],
            "method": claim["method"],
            "path": claim["path"],
        },
    )


@event.listens_for(Session, "before_flush")
def _attach_replacement_links(session: Session, flush_context, instances) -> None:
    context = session.info.get("_direct_replacement_context")
    if not context:
        return
    model, original = context
    for obj in list(session.new):
        if isinstance(obj, model):
            if getattr(obj, "id", None) is None:
                obj.id = uuid.uuid4()
            if hasattr(obj, "replaces_id"):
                obj.replaces_id = original.id
            if hasattr(original, "replaced_by_id"):
                original.replaced_by_id = obj.id
            _set_replay_resource(session, obj)
            session.info.pop("_direct_replacement_context", None)
            break


def _invoice_lines(invoice: Invoice):
    return [
        InvoiceLineCreate(
            product_id=line.product_id,
            description=line.description,
            quantity=line.quantity,
            rate=line.rate,
            discount=line.discount or Decimal("0"),
            hsn_sac=line.hsn_sac,
            gst_rate=line.gst_rate,
        )
        for line in invoice.lines
    ]


def _bill_lines(bill: Bill):
    return [
        BillLineCreate(
            product_id=line.product_id,
            description=line.description,
            quantity=line.quantity,
            rate=line.rate,
            discount=line.discount or Decimal("0"),
            hsn_sac=line.hsn_sac,
            gst_rate=line.gst_rate,
        )
        for line in bill.lines
    ]


def _invoice_discount_rate(invoice: Invoice) -> Decimal:
    subtotal = invoice.subtotal or Decimal("0")
    if subtotal <= 0:
        return Decimal("0")
    return ((invoice.discount_total or Decimal("0")) * 100 / subtotal).quantize(
        Decimal("0.0001")
    )


def _bill_discount_rate(bill: Bill) -> Decimal:
    subtotal = bill.subtotal or Decimal("0")
    if subtotal <= 0:
        return Decimal("0")
    line_discount = sum((x.discount or Decimal("0") for x in bill.lines), Decimal("0"))
    header = max((bill.discount_total or Decimal("0")) - line_discount, Decimal("0"))
    return (header * 100 / subtotal).quantize(Decimal("0.0001"))


def direct_create_invoice(
    request: Request,
    payload: InvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    # post_on_create is kept only as a legacy input compatibility field; callers
    # can no longer create a persistent accounting draft.
    payload = payload.model_copy(update={"post_on_create": True})
    return _unwrap(invoice_api.create_invoice)(request, payload, db, tenant_id)


def direct_update_invoice(
    request: Request,
    id: uuid.UUID,
    payload: InvoiceUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Invoice not found in this company context.")
    if original.source_document_type:
        raise HTTPException(
            409,
            "Correct invoices created from another source document from that source workflow.",
        )
    if original.irn:
        raise HTTPException(
            409,
            "This invoice has an IRN. Complete the statutory e-invoice correction workflow first.",
        )
    if original.status == "PAID":
        raise HTTPException(409, "Reverse the applied receipt(s) before editing this invoice.")

    replacement_payload = InvoiceCreate(
        contact_id=payload.contact_id or original.contact_id,
        invoice_number=None,
        issue_date=payload.issue_date or original.issue_date,
        due_date=payload.due_date or original.due_date,
        pos_state_code=payload.pos_state_code or original.pos_state_code,
        line_items=payload.line_items or _invoice_lines(original),
        discount_rate=payload.discount_rate if payload.discount_rate is not None else _invoice_discount_rate(original),
        shipping_charges=payload.shipping_charges if payload.shipping_charges is not None else original.shipping_charges,
        notes=payload.notes if payload.notes is not None else original.notes,
        terms_and_conditions=payload.terms_and_conditions if payload.terms_and_conditions is not None else original.terms_and_conditions,
        reference_number=payload.reference_number if payload.reference_number is not None else original.reference_number,
        sales_person_id=payload.sales_person_id if payload.sales_person_id is not None else original.sales_person_id,
        is_gst_inclusive=payload.is_gst_inclusive if payload.is_gst_inclusive is not None else original.is_gst_inclusive,
        is_rcm=payload.is_rcm if payload.is_rcm is not None else original.is_rcm,
        supply_type=payload.supply_type or original.supply_type,
        currency=payload.currency or original.currency,
        exchange_rate=payload.exchange_rate or original.exchange_rate,
        tds_rate=payload.tds_rate if payload.tds_rate is not None else original.tds_rate,
        tcs_rate=payload.tcs_rate if payload.tcs_rate is not None else original.tcs_rate,
        post_on_create=True,
    )

    proxy = DeferredCommitSession(db)
    if original.status == "DRAFT":
        original.deleted_at = datetime.now(timezone.utc)
    else:
        if original.status == "SENT":
            original.status = "POSTED"
        _unwrap(invoice_api.cancel_invoice)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)

    db.info["_direct_replacement_context"] = (Invoice, original)
    try:
        # create_invoice performs the one real commit, making reversal,
        # soft-delete, replacement document and replacement posting atomic.
        replacement = _unwrap(invoice_api.create_invoice)(
            request, replacement_payload, db, tenant_id
        )
    finally:
        db.info.pop("_direct_replacement_context", None)
    return replacement


def direct_delete_invoice(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Invoice).filter(
        Invoice.id == id,
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Invoice not found.")
    if original.irn:
        raise HTTPException(409, "Complete the statutory e-invoice cancellation workflow first.")
    if original.status == "PAID":
        raise HTTPException(409, "Reverse the applied receipt(s) before deleting this invoice.")

    proxy = DeferredCommitSession(db)
    if original.status == "DRAFT":
        original.deleted_at = datetime.now(timezone.utc)
    else:
        if original.status == "SENT":
            original.status = "POSTED"
        _unwrap(invoice_api.cancel_invoice)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def direct_create_bill(
    request: Request,
    payload: BillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:create")),
):
    payload = payload.model_copy(update={"post_on_create": True})
    return _unwrap(bill_api.create_bill)(request, payload, db, tenant_id)


def direct_update_bill(
    request: Request,
    id: uuid.UUID,
    payload: BillUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:update")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Vendor Bill not found in this company context.")
    if original.status == "PAID":
        raise HTTPException(409, "Reverse the applied vendor payment(s) before editing this bill.")

    from src.domains.company.services import NumberingSeriesService

    replacement_payload = BillCreate(
        contact_id=payload.contact_id or original.contact_id,
        bill_number=NumberingSeriesService.generate_next_number(db, tenant_id, "BILL"),
        issue_date=payload.issue_date or original.issue_date,
        due_date=payload.due_date or original.due_date,
        pos_state_code=payload.pos_state_code or original.pos_state_code,
        line_items=payload.line_items or _bill_lines(original),
        discount_rate=payload.discount_rate if payload.discount_rate is not None else _bill_discount_rate(original),
        shipping_charges=payload.shipping_charges if payload.shipping_charges is not None else original.shipping_charges,
        notes=payload.notes if payload.notes is not None else original.notes,
        terms_and_conditions=payload.terms_and_conditions if payload.terms_and_conditions is not None else original.terms_and_conditions,
        reference_number=payload.reference_number if payload.reference_number is not None else original.reference_number,
        tds_rate=payload.tds_rate if payload.tds_rate is not None else original.tds_rate,
        is_gst_inclusive=payload.is_gst_inclusive if payload.is_gst_inclusive is not None else original.is_gst_inclusive,
        itc_eligible=payload.itc_eligible if payload.itc_eligible is not None else original.itc_eligible,
        post_on_create=True,
    )

    proxy = DeferredCommitSession(db)
    if original.status == "DRAFT":
        original.deleted_at = datetime.now(timezone.utc)
    else:
        if original.status == "UNPAID":
            original.status = "POSTED"
        _unwrap(bill_api.cancel_bill_route)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)

    db.info["_direct_replacement_context"] = (Bill, original)
    try:
        replacement = _unwrap(bill_api.create_bill)(
            request, replacement_payload, db, tenant_id
        )
    finally:
        db.info.pop("_direct_replacement_context", None)
    return replacement


def direct_delete_bill(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Bill).filter(
        Bill.id == id,
        Bill.tenant_id == tenant_id,
        Bill.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Vendor Bill not found.")
    if original.status == "PAID":
        raise HTTPException(409, "Reverse the applied vendor payment(s) before deleting this bill.")

    proxy = DeferredCommitSession(db)
    if original.status == "DRAFT":
        original.deleted_at = datetime.now(timezone.utc)
    else:
        if original.status == "UNPAID":
            original.status = "POSTED"
        _unwrap(bill_api.cancel_bill_route)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def direct_create_expense(
    request: Request,
    payload: ExpenseCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:create")),
):
    proxy = DeferredCommitSession(db)
    expense = _unwrap(expense_api.create_expense)(request, payload, proxy, tenant_id)
    posted = _unwrap(expense_api.post_expense)(expense.id, proxy, tenant_id)
    db.commit()
    db.refresh(posted)
    return posted


def direct_update_expense(
    request: Request,
    id: uuid.UUID,
    payload: ExpenseUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:edit")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Expense not found.")

    replacement_payload = ExpenseCreate(
        expense_category_id=payload.expense_category_id if payload.expense_category_id is not None else original.expense_category_id,
        bank_account_id=payload.bank_account_id if payload.bank_account_id is not None else original.bank_account_id,
        expense_date=payload.expense_date or original.expense_date,
        vendor_name=payload.vendor_name if payload.vendor_name is not None else original.vendor_name,
        description=payload.description if payload.description is not None else original.description,
        amount=payload.amount if payload.amount is not None else original.amount,
        gst_rate=payload.gst_rate if payload.gst_rate is not None else original.gst_rate,
        place_of_supply_state_code=payload.place_of_supply_state_code if payload.place_of_supply_state_code is not None else original.place_of_supply_state_code,
        notes=payload.notes if payload.notes is not None else original.notes,
        reference_number=payload.reference_number if payload.reference_number is not None else original.reference_number,
    )

    proxy = DeferredCommitSession(db)
    if original.status == "DRAFT":
        original.deleted_at = datetime.now(timezone.utc)
    else:
        _unwrap(expense_api.cancel_expense)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)

    db.info["_direct_replacement_context"] = (Expense, original)
    try:
        replacement = _unwrap(expense_api.create_expense)(
            request, replacement_payload, proxy, tenant_id
        )
        replacement = _unwrap(expense_api.post_expense)(
            replacement.id, proxy, tenant_id
        )
        db.commit()
        db.refresh(replacement)
    finally:
        db.info.pop("_direct_replacement_context", None)
    return expense_api._expense_to_response(replacement)


def direct_delete_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:delete")),
    current_user: User = Depends(get_current_user),
):
    original = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).with_for_update().first()
    if not original:
        raise HTTPException(404, "Expense not found.")

    proxy = DeferredCommitSession(db)
    if original.status == "DRAFT":
        original.deleted_at = datetime.now(timezone.utc)
    else:
        _unwrap(expense_api.cancel_expense)(id, proxy, tenant_id, current_user)
        original.deleted_at = datetime.now(timezone.utc)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


_INSTALLED = False


def install_direct_posting_contract() -> None:
    global _INSTALLED
    if _INSTALLED:
        return
    _INSTALLED = True

    for path, method in (
        ("/invoices", "POST"),
        ("/invoices/{id}", "PUT"),
        ("/invoices/{id}", "DELETE"),
        ("/invoices/{id}/finalize", "POST"),
        ("/invoices/{id}/cancel", "POST"),
        ("/invoices/{id}/payment", "POST"),
    ):
        _remove_route(invoice_api.router, path, method)

    invoice_api.router.add_api_route(
        "", direct_create_invoice, methods=["POST"],
        response_model=InvoiceResponse, status_code=status.HTTP_201_CREATED,
    )
    invoice_api.router.add_api_route(
        "/{id}", direct_update_invoice, methods=["PUT"], response_model=InvoiceResponse,
    )
    invoice_api.router.add_api_route(
        "/{id}", direct_delete_invoice, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    for path, method in (
        ("/bills", "POST"),
        ("/bills/{id}", "PUT"),
        ("/bills/{id}", "DELETE"),
        ("/bills/{id}/finalize", "POST"),
        ("/bills/{id}/cancel", "POST"),
        ("/bills/{id}/payment", "POST"),
    ):
        _remove_route(bill_api.router, path, method)

    bill_api.router.add_api_route(
        "", direct_create_bill, methods=["POST"],
        response_model=BillResponse, status_code=status.HTTP_201_CREATED,
    )
    bill_api.router.add_api_route(
        "/{id}", direct_update_bill, methods=["PUT"], response_model=BillResponse,
    )
    bill_api.router.add_api_route(
        "/{id}", direct_delete_bill, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    for path, method in (
        ("/expenses", "POST"),
        ("/expenses/{id}", "PUT"),
        ("/expenses/{id}", "DELETE"),
        ("/expenses/{id}/post", "POST"),
        ("/expenses/{id}/cancel", "POST"),
        ("/expenses/bulk-delete", "POST"),
    ):
        _remove_route(expense_api.router, path, method)

    expense_api.router.add_api_route(
        "", direct_create_expense, methods=["POST"],
        response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED,
    )
    expense_api.router.add_api_route(
        "/{id}", direct_update_expense, methods=["PUT"], response_model=ExpenseResponse,
    )
    expense_api.router.add_api_route(
        "/{id}", direct_delete_expense, methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
