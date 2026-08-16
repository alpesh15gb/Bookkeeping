import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Callable, List, Optional

from fastapi import Depends, HTTPException, Request, Response, status
from pydantic import Field
from sqlalchemy import event, text
from sqlalchemy.orm import Session

from src.api.deps import enforce_permission, get_current_user
from src.core.config import settings
from src.core.database import get_db_session
from src.core.rate_limiter import limiter
from src.infrastructure.database.models import Bill, Expense, Invoice, User
from src.schemas.bill_schemas import (
    BillBase,
    BillCreate,
    BillLineCreate,
    BillResponse,
    BillUpdate,
)
from src.schemas.document import (
    InvoiceBase,
    InvoiceCreate,
    InvoiceLineCreate,
    InvoiceResponse,
    InvoiceUpdate,
)
from src.schemas.expense_schemas import ExpenseCreate, ExpenseResponse, ExpenseUpdate
from src.api.v1 import bills as bill_api
from src.api.v1 import expenses as expense_api
from src.api.v1 import invoices as invoice_api


class DirectInvoiceCreate(InvoiceBase):
    """Public invoice create: posts immediately unless post_on_create is false."""

    line_items: List[InvoiceLineCreate] = Field(..., min_length=1)
    discount_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    reference_number: Optional[str] = Field(None, max_length=50)
    sales_person_id: Optional[uuid.UUID] = None
    is_gst_inclusive: Optional[bool] = False
    is_rcm: Optional[bool] = False
    supply_type: Optional[str] = Field(
        default="DOMESTIC",
        pattern="^(DOMESTIC|EXPORT_WITH_TAX|EXPORT_WITHOUT_TAX|SEZ_WITH_TAX|SEZ_WITHOUT_TAX)$",
    )
    tds_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    tcs_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    post_on_create: bool = True


class DirectBillCreate(BillBase):
    """Public bill create: posts immediately unless post_on_create is false."""

    bill_number: Optional[str] = Field(None, max_length=50)
    line_items: List[BillLineCreate] = Field(..., min_length=1)
    discount_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    shipping_charges: Optional[Decimal] = Field(default=Decimal("0.0000"), ge=0)
    notes: Optional[str] = None
    terms_and_conditions: Optional[str] = None
    reference_number: Optional[str] = Field(None, max_length=50)
    tds_rate: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0, le=100)
    is_gst_inclusive: Optional[bool] = False
    itc_eligible: bool = True
    post_on_create: bool = True


class DeferredCommitSession:
    """Proxy that turns a legacy handler commit into flush.

    Legacy posting/cancellation functions are battle-tested.  Using this proxy
    lets the direct public contract compose them inside one outer transaction,
    so reversal + replacement never land separately.
    """

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
    """Atomically mark the in-flight key committed and point replay at obj.

    This is used after a composed correction has created its replacement.  It
    intentionally runs in the same SQL transaction as reversal/replacement,
    closing the response-loss crash window even when intermediate flushes were
    deferred from the generic Session hook.
    """
    from src.core.idempotency import get_inflight_claim

    claim = get_inflight_claim()
    resource_id = getattr(obj, "id", None)
    if not claim or resource_id is None or db.get_bind().dialect.name != "postgresql":
        return
    result = db.execute(
        text(
            "UPDATE idempotency_keys "
            "SET status='COMMITTED', is_processed=true, "
            "resource_type=:resource_type, resource_id=CAST(:resource_id AS uuid) "
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
    if result.rowcount == 0:
        from src.core.idempotency import IdempotencyClaimLostError

        raise IdempotencyClaimLostError(
            "Idempotency claim disappeared before replacement commit."
        )
    db.info["_idem_marked"] = True


@event.listens_for(Session, "before_flush")
def _attach_replacement_links(session: Session, flush_context, instances) -> None:
    """Attach immutable document replacement links before the replacement flush."""
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
            # Tell the generic after_flush idempotency hook which resource is
            # the user-visible result, and release the intermediate-flush defer.
            session.info["_idempotency_resource"] = obj
            session.info.pop("_defer_idempotency_mark", None)
            session.info.pop("_direct_replacement_context", None)
            break


def _begin_replacement(db: Session, model, original) -> None:
    # Cancellation helpers flush reversal journals before the replacement
    # exists.  Do not let that intermediate flush become the replay resource.
    db.info["_direct_replacement_context"] = (model, original)
    db.info["_defer_idempotency_mark"] = True


def _end_replacement(db: Session) -> None:
    db.info.pop("_direct_replacement_context", None)
    db.info.pop("_defer_idempotency_mark", None)
    db.info.pop("_idempotency_resource", None)


def _invoice_lines(invoice: Invoice) -> List[InvoiceLineCreate]:
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


def _bill_lines(bill: Bill) -> List[BillLineCreate]:
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
    line_discount = sum((line.discount or Decimal("0") for line in bill.lines), Decimal("0"))
    header_discount = max(
        (bill.discount_total or Decimal("0")) - line_discount, Decimal("0")
    )
    return (header_discount * 100 / subtotal).quantize(Decimal("0.0001"))


def _legacy_invoice_payload(payload: DirectInvoiceCreate) -> InvoiceCreate:
    return InvoiceCreate(**payload.model_dump())


def _legacy_bill_payload(
    db: Session, tenant_id: uuid.UUID, payload: DirectBillCreate
) -> BillCreate:
    from src.domains.company.services import NumberingSeriesService

    values = payload.model_dump()
    values["bill_number"] = values.get("bill_number") or NumberingSeriesService.generate_next_number(
        db, tenant_id, "BILL"
    )
    values["post_on_create"] = bool(values.get("post_on_create", True))
    return BillCreate(**values)


@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_create_invoice(
    request: Request,
    payload: DirectInvoiceCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    return _unwrap(invoice_api.create_invoice)(
        request, _legacy_invoice_payload(payload), db, tenant_id
    )


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
            409, "Correct source-derived invoices from their originating document."
        )
    if original.irn:
        raise HTTPException(
            409,
            "This invoice has an IRN. Complete the statutory e-invoice correction workflow first.",
        )
    if original.status == "PAID":
        raise HTTPException(409, "Reverse applied receipt(s) before editing this invoice.")
    if original.status == "DRAFT":
        return _unwrap(invoice_api.update_invoice)(id, payload, db, tenant_id)

    replacement_payload = InvoiceCreate(
        contact_id=payload.contact_id or original.contact_id,
        invoice_number=None,
        issue_date=payload.issue_date or original.issue_date,
        due_date=payload.due_date or original.due_date,
        pos_state_code=payload.pos_state_code or original.pos_state_code,
        line_items=payload.line_items or _invoice_lines(original),
        discount_rate=(
            payload.discount_rate
            if payload.discount_rate is not None
            else _invoice_discount_rate(original)
        ),
        shipping_charges=(
            payload.shipping_charges
            if payload.shipping_charges is not None
            else original.shipping_charges
        ),
        notes=payload.notes if payload.notes is not None else original.notes,
        terms_and_conditions=(
            payload.terms_and_conditions
            if payload.terms_and_conditions is not None
            else original.terms_and_conditions
        ),
        reference_number=(
            payload.reference_number
            if payload.reference_number is not None
            else original.reference_number
        ),
        sales_person_id=(
            payload.sales_person_id
            if payload.sales_person_id is not None
            else original.sales_person_id
        ),
        is_gst_inclusive=(
            payload.is_gst_inclusive
            if payload.is_gst_inclusive is not None
            else original.is_gst_inclusive
        ),
        is_rcm=payload.is_rcm if payload.is_rcm is not None else original.is_rcm,
        supply_type=payload.supply_type or original.supply_type,
        currency=payload.currency or original.currency,
        exchange_rate=payload.exchange_rate or original.exchange_rate,
        tds_rate=payload.tds_rate if payload.tds_rate is not None else original.tds_rate,
        tcs_rate=payload.tcs_rate if payload.tcs_rate is not None else original.tcs_rate,
        post_on_create=True,
    )

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, Invoice, original)
    try:
        if original.status == "DRAFT":
            original.deleted_at = datetime.now(timezone.utc)
        else:
            if original.status == "SENT":
                original.status = "POSTED"
            _unwrap(invoice_api.cancel_invoice)(id, proxy, tenant_id, current_user)
            original.deleted_at = datetime.now(timezone.utc)

        # create_invoice performs the single real commit. The before_flush hook
        # links original/replacement and makes the replacement the idempotent
        # crash-replay resource before that commit.
        replacement = _unwrap(invoice_api.create_invoice)(
            request, replacement_payload, db, tenant_id
        )
        return replacement
    finally:
        _end_replacement(db)


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
        raise HTTPException(409, "Reverse applied receipt(s) before deleting this invoice.")

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


@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_create_bill(
    request: Request,
    payload: DirectBillCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:create")),
):
    return _unwrap(bill_api.create_bill)(
        request, _legacy_bill_payload(db, tenant_id, payload), db, tenant_id
    )


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
        raise HTTPException(
            409, "Reverse applied vendor payment(s) before editing this bill."
        )
    if original.status == "DRAFT":
        return _unwrap(bill_api.update_bill)(id, payload, db, tenant_id)

    from src.domains.company.services import NumberingSeriesService

    replacement_payload = BillCreate(
        contact_id=payload.contact_id or original.contact_id,
        bill_number=NumberingSeriesService.generate_next_number(db, tenant_id, "BILL"),
        issue_date=payload.issue_date or original.issue_date,
        due_date=payload.due_date or original.due_date,
        pos_state_code=payload.pos_state_code or original.pos_state_code,
        line_items=payload.line_items or _bill_lines(original),
        discount_rate=(
            payload.discount_rate
            if payload.discount_rate is not None
            else _bill_discount_rate(original)
        ),
        shipping_charges=(
            payload.shipping_charges
            if payload.shipping_charges is not None
            else original.shipping_charges
        ),
        notes=payload.notes if payload.notes is not None else original.notes,
        terms_and_conditions=(
            payload.terms_and_conditions
            if payload.terms_and_conditions is not None
            else original.terms_and_conditions
        ),
        reference_number=(
            payload.reference_number
            if payload.reference_number is not None
            else original.reference_number
        ),
        tds_rate=payload.tds_rate if payload.tds_rate is not None else original.tds_rate,
        is_gst_inclusive=(
            payload.is_gst_inclusive
            if payload.is_gst_inclusive is not None
            else original.is_gst_inclusive
        ),
        itc_eligible=(
            payload.itc_eligible
            if payload.itc_eligible is not None
            else original.itc_eligible
        ),
        post_on_create=True,
    )

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, Bill, original)
    try:
        if original.status == "DRAFT":
            original.deleted_at = datetime.now(timezone.utc)
        else:
            if original.status == "UNPAID":
                original.status = "POSTED"
            _unwrap(bill_api.cancel_bill_route)(id, proxy, tenant_id, current_user)
            original.deleted_at = datetime.now(timezone.utc)
        return _unwrap(bill_api.create_bill)(
            request, replacement_payload, db, tenant_id
        )
    finally:
        _end_replacement(db)


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
        raise HTTPException(
            409, "Reverse applied vendor payment(s) before deleting this bill."
        )

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


@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def direct_create_expense(
    request: Request,
    payload: ExpenseCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:create")),
):
    return _unwrap(expense_api.create_expense)(request, payload, db, tenant_id)


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
    if original.status == "DRAFT":
        return _unwrap(expense_api.update_expense)(id, payload, db, tenant_id)

    replacement_payload = ExpenseCreate(
        expense_category_id=(
            payload.expense_category_id
            if payload.expense_category_id is not None
            else original.expense_category_id
        ),
        bank_account_id=(
            payload.bank_account_id
            if payload.bank_account_id is not None
            else original.bank_account_id
        ),
        expense_date=payload.expense_date or original.expense_date,
        vendor_name=payload.vendor_name if payload.vendor_name is not None else original.vendor_name,
        description=payload.description if payload.description is not None else original.description,
        amount=payload.amount if payload.amount is not None else original.amount,
        gst_rate=payload.gst_rate if payload.gst_rate is not None else original.gst_rate,
        place_of_supply_state_code=(
            payload.place_of_supply_state_code
            if payload.place_of_supply_state_code is not None
            else original.place_of_supply_state_code
        ),
        notes=payload.notes if payload.notes is not None else original.notes,
        reference_number=(
            payload.reference_number
            if payload.reference_number is not None
            else original.reference_number
        ),
    )

    proxy = DeferredCommitSession(db)
    _begin_replacement(db, Expense, original)
    try:
        if original.status == "DRAFT":
            original.deleted_at = datetime.now(timezone.utc)
        else:
            _unwrap(expense_api.cancel_expense)(id, proxy, tenant_id, current_user)
            original.deleted_at = datetime.now(timezone.utc)

        # create_expense auto-posts on creation, so the replacement is already
        # POSTED with its journal entry inside the same transaction.
        created = _unwrap(expense_api.create_expense)(
            request, replacement_payload, proxy, tenant_id
        )
        replacement = db.query(Expense).filter(
            Expense.id == created.id,
            Expense.tenant_id == tenant_id,
        ).first()
        _set_replay_resource(db, replacement)
        db.commit()
        db.refresh(replacement)
        return expense_api._expense_to_response(replacement)
    finally:
        _end_replacement(db)


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
        ("/invoices/{id}/payment", "POST"),
    ):
        _remove_route(invoice_api.router, path, method)
    invoice_api.router.add_api_route(
        "",
        direct_create_invoice,
        methods=["POST"],
        response_model=InvoiceResponse,
        status_code=status.HTTP_201_CREATED,
    )
    invoice_api.router.add_api_route(
        "/{id}", direct_update_invoice, methods=["PUT"], response_model=InvoiceResponse
    )
    invoice_api.router.add_api_route(
        "/{id}",
        direct_delete_invoice,
        methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    for path, method in (
        ("/bills", "POST"),
        ("/bills/{id}", "PUT"),
        ("/bills/{id}", "DELETE"),
        ("/bills/{id}/payment", "POST"),
    ):
        _remove_route(bill_api.router, path, method)
    bill_api.router.add_api_route(
        "",
        direct_create_bill,
        methods=["POST"],
        response_model=BillResponse,
        status_code=status.HTTP_201_CREATED,
    )
    bill_api.router.add_api_route(
        "/{id}", direct_update_bill, methods=["PUT"], response_model=BillResponse
    )
    bill_api.router.add_api_route(
        "/{id}",
        direct_delete_bill,
        methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )

    for path, method in (
        ("/expenses", "POST"),
        ("/expenses/{id}", "PUT"),
        ("/expenses/{id}", "DELETE"),
        ("/expenses/bulk-delete", "POST"),
    ):
        _remove_route(expense_api.router, path, method)
    expense_api.router.add_api_route(
        "",
        direct_create_expense,
        methods=["POST"],
        response_model=ExpenseResponse,
        status_code=status.HTTP_201_CREATED,
    )
    expense_api.router.add_api_route(
        "/{id}", direct_update_expense, methods=["PUT"], response_model=ExpenseResponse
    )
    expense_api.router.add_api_route(
        "/{id}",
        direct_delete_expense,
        methods=["DELETE"],
        status_code=status.HTTP_204_NO_CONTENT,
    )
