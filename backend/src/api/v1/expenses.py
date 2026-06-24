import uuid
from decimal import Decimal
from typing import List, Optional
from datetime import date, datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status, Query, Request
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session
from sqlalchemy import func
import logging

logger = logging.getLogger(__name__)

from src.api.deps import get_db_session, enforce_permission, get_current_user
from src.infrastructure.database.models import Expense, ExpenseCategory, User
from src.core.rate_limiter import limiter
from src.core.config import settings
from src.schemas.expense_schemas import ExpenseCreate, ExpenseUpdate, ExpenseResponse, ExpenseListResponse, ExpensePreviewRequest, ExpensePreviewResponse
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.accounting.auto_post import auto_post_expense, cancel_expense as cancel_expense_fn
from src.domains.taxation.services import GSTEngine
from src.domains.company.services import resolve_origin_state_code

router = APIRouter(prefix="/expenses", tags=["Expenses"])


def _parse_date(s: Optional[str], param_name: str) -> Optional[date]:
    """Parse a date string in YYYY-MM-DD format. Raises HTTPException on invalid format."""
    if s is None:
        return None
    try:
        return date.fromisoformat(s)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid date format for {param_name}. Use YYYY-MM-DD.")


class BulkDeleteRequest(BaseModel):
    ids: List[uuid.UUID]

    @field_validator('ids')
    @classmethod
    def check_max_ids(cls, v):
        if len(v) > 100:
            raise ValueError("Cannot bulk delete more than 100 items at once.")
        return v


def _compute_expense_totals(db: Session, tenant_id: uuid.UUID, amount: Decimal, gst_rate: Decimal, place_of_supply_state_code: str) -> dict:
    from src.domains.company.services import resolve_origin_state_code
    origin = resolve_origin_state_code(db, tenant_id)
    effective_rate = GSTEngine.resolve_gst_rate(db, tenant_id, gst_rate)
    tax_split = GSTEngine.calculate_tax(
        origin_state_code=origin,
        place_of_supply_state_code=place_of_supply_state_code,
        base_amount=amount,
        gst_rate=effective_rate,
    )
    raw_total = amount + tax_split.cgst_amount + tax_split.sgst_amount + tax_split.igst_amount + tax_split.utgst_amount + tax_split.cess_amount
    rounded_total = raw_total.quantize(Decimal("1"), rounding="ROUND_HALF_UP")
    round_off = rounded_total - raw_total
    return {
        "amount": amount,
        "cgst_amount": tax_split.cgst_amount,
        "sgst_amount": tax_split.sgst_amount,
        "igst_amount": tax_split.igst_amount,
        "utgst_amount": tax_split.utgst_amount,
        "cess_amount": tax_split.cess_amount,
        "round_off": round_off,
        "total": rounded_total,
    }


def _expense_to_response(e: Expense) -> ExpenseResponse:
    return ExpenseResponse(
        id=e.id,
        tenant_id=e.tenant_id,
        expense_number=e.expense_number,
        expense_category_id=e.expense_category_id,
        bank_account_id=e.bank_account_id,
        expense_date=e.expense_date,
        vendor_name=e.vendor_name,
        description=e.description,
        amount=e.amount,
        gst_rate=e.gst_rate,
        cgst_amount=e.cgst_amount,
        sgst_amount=e.sgst_amount,
        igst_amount=e.igst_amount,
        utgst_amount=e.utgst_amount,
        cess_amount=e.cess_amount,
        round_off=e.round_off,
        total=e.total,
        status=e.status,
        category_name=e.category.name if e.category else None,
        created_at=e.created_at,
        updated_at=e.updated_at,
    )


def _gen_expense_number(db: Session, tenant_id: uuid.UUID) -> str:
    prefix = f"EXP-{date.today().strftime('%Y%m')}-"
    rows = db.query(Expense.expense_number).filter(
        Expense.tenant_id == tenant_id,
        Expense.expense_number.like(f"{prefix}%"),
    ).with_for_update().all()
    
    last = None
    if rows:
        last = max(r[0] for r in rows if r[0])
        
    next_num = 1
    if last:
        try:
            next_num = int(last.split("-")[-1]) + 1
        except (ValueError, IndexError):
            pass
    return f"{prefix}{next_num:04d}"


@router.post("/bulk-delete")
def bulk_delete_expenses(
    payload: BulkDeleteRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:delete")),
):
    """Bulk delete multiple expenses."""
    ids = payload.ids
    if not ids:
        raise HTTPException(status_code=400, detail="No IDs provided.")

    deleted = 0
    for expense_id in ids:
        expense = db.query(Expense).filter(
            Expense.id == expense_id,
            Expense.tenant_id == tenant_id,
            Expense.deleted_at == None,
        ).first()
        if expense and expense.status == "DRAFT":
            expense.deleted_at = datetime.now(timezone.utc)
            deleted += 1

    db.commit()
    return {"deleted": deleted}


@router.post("/preview", response_model=ExpensePreviewResponse)
def preview_expense(
    payload: ExpensePreviewRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    totals = _compute_expense_totals(db=db, tenant_id=tenant_id, amount=payload.amount, gst_rate=payload.gst_rate, place_of_supply_state_code=payload.place_of_supply_state_code or "27")
    return ExpensePreviewResponse(**totals)


@router.post("", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(settings.RATE_LIMIT_DEFAULT)
def create_expense(
    request: Request,
    payload: ExpenseCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:create")),
):
    import logging
    logger = logging.getLogger(__name__)
    from src.domains.accounting.period_lock import validate_period_open

    try:
        validate_period_open(db, tenant_id, payload.expense_date)

        category = db.query(ExpenseCategory).filter(
            ExpenseCategory.id == payload.expense_category_id,
            ExpenseCategory.tenant_id == tenant_id,
            ExpenseCategory.is_active == True,
        ).first()
        if not category:
            raise HTTPException(status_code=404, detail="Expense category not found.")

        expense_number = _gen_expense_number(db, tenant_id)
        place_of_supply = payload.place_of_supply_state_code or resolve_origin_state_code(db, tenant_id)
        totals = _compute_expense_totals(db, tenant_id, payload.amount, payload.gst_rate, place_of_supply)

        expense = Expense(
            tenant_id=tenant_id,
            expense_number=expense_number,
            expense_category_id=payload.expense_category_id,
            bank_account_id=payload.bank_account_id,
            expense_date=payload.expense_date,
            vendor_name=payload.vendor_name,
            description=payload.description,
            amount=payload.amount,
            gst_rate=payload.gst_rate,
            cgst_amount=totals["cgst_amount"],
            sgst_amount=totals["sgst_amount"],
            igst_amount=totals["igst_amount"],
            utgst_amount=totals["utgst_amount"],
            cess_amount=totals["cess_amount"],
            round_off=totals["round_off"],
            total=totals["total"],
            status="DRAFT",
            notes=payload.notes,
            reference_number=payload.reference_number,
        )
        db.add(expense)
        db.commit()
        db.refresh(expense)
        return _expense_to_response(expense)
    except Exception as e:
        logger.error(f"Error creating expense: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to create expense: {str(e)}")


@router.get("", response_model=List[ExpenseListResponse])
def list_expenses(
    status_filter: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=100),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    q = db.query(Expense).filter(
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    )
    if status_filter:
        q = q.filter(Expense.status == status_filter)
    date_from_parsed = _parse_date(date_from, "date_from")
    date_to_parsed = _parse_date(date_to, "date_to")
    if date_from_parsed and date_to_parsed:
        q = q.filter(Expense.expense_date >= date_from_parsed, Expense.expense_date <= date_to_parsed)
    offset = (page - 1) * limit
    q = q.order_by(Expense.expense_date.desc(), Expense.created_at.desc())
    q = q.offset(offset).limit(limit)

    results = []
    for e in q.all():
        results.append(ExpenseListResponse(
            id=e.id,
            expense_number=e.expense_number,
            expense_date=e.expense_date,
            vendor_name=e.vendor_name,
            description=e.description,
            amount=e.amount,
            total=e.total,
            status=e.status,
            category_name=e.category.name if e.category else None,
            created_at=e.created_at,
        ))
    return results


@router.get("/{id}", response_model=ExpenseResponse)
def get_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    expense = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found.")
    return _expense_to_response(expense)


@router.put("/{id}", response_model=ExpenseResponse)
def update_expense(
    id: uuid.UUID,
    payload: ExpenseUpdate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:edit")),
):
    expense = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, expense.expense_date)
    if payload.expense_date:
        validate_period_open(db, tenant_id, payload.expense_date)

    if expense.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft expenses can be edited.")

    if payload.expense_category_id is not None:
        category = db.query(ExpenseCategory).filter(
            ExpenseCategory.id == payload.expense_category_id,
            ExpenseCategory.tenant_id == tenant_id,
        ).first()
        if not category:
            raise HTTPException(status_code=404, detail="Expense category not found.")
        expense.expense_category_id = payload.expense_category_id
    if payload.bank_account_id is not None:
        expense.bank_account_id = payload.bank_account_id
    if payload.expense_date is not None:
        expense.expense_date = payload.expense_date
    if payload.vendor_name is not None:
        expense.vendor_name = payload.vendor_name
    if payload.description is not None:
        expense.description = payload.description
    recompute = payload.amount is not None or payload.gst_rate is not None
    if payload.amount is not None:
        expense.amount = payload.amount
    if payload.gst_rate is not None:
        expense.gst_rate = payload.gst_rate

    if recompute:
        pos_state = payload.place_of_supply_state_code or resolve_origin_state_code(db, tenant_id)
        totals = _compute_expense_totals(db, tenant_id, expense.amount, expense.gst_rate, pos_state)
        expense.cgst_amount = totals["cgst_amount"]
        expense.sgst_amount = totals["sgst_amount"]
        expense.igst_amount = totals["igst_amount"]
        expense.utgst_amount = totals["utgst_amount"]
        expense.cess_amount = totals["cess_amount"]
        expense.round_off = totals["round_off"]
        expense.total = totals["total"]

    db.commit()
    db.refresh(expense)
    return _expense_to_response(expense)


@router.delete("/{id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:delete")),
):
    expense = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found.")
    if expense.status == "POSTED":
        raise HTTPException(status_code=400, detail="Posted expenses cannot be deleted. Cancel instead.")
    expense.deleted_at = func.now()
    db.commit()


@router.post("/{id}/post", response_model=ExpenseResponse)
def post_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:finalize")),
):
    expense = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, expense.expense_date)

    if expense.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft expenses can be posted.")

    from src.domains.accounting.auto_post import _check_no_existing_posting
    _check_no_existing_posting(db, tenant_id, "EXPENSE", expense.id)

    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.deleted_at == None,
    ).first()
    if not category or not category.linked_account_id:
        raise HTTPException(status_code=400, detail="Expense category must have a linked account to post.")

    resolver = AccountResolver(db, tenant_id)
    if expense.bank_account_id:
        cash_account_id = expense.bank_account_id
    else:
        cash_account_id = resolver.resolve("assets.cash")

    cgst_input_id = resolver.resolve("cgst_input")
    sgst_input_id = resolver.resolve("sgst_input")
    igst_input_id = resolver.resolve("igst_input")
    utgst_input_id = resolver.resolve("utgst_input")
    cess_input_id = resolver.resolve("cess_input")
    round_off_account_id = resolver.resolve("round_off") if expense.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_expense_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        expense_date=expense.expense_date,
        expense_account_id=category.linked_account_id,
        cash_account_id=cash_account_id,
        amount=expense.amount,
        cgst_account_id=cgst_input_id,
        cgst_amount=expense.cgst_amount,
        sgst_account_id=sgst_input_id,
        sgst_amount=expense.sgst_amount,
        igst_account_id=igst_input_id,
        igst_amount=expense.igst_amount,
        utgst_account_id=utgst_input_id,
        utgst_amount=expense.utgst_amount,
        cess_account_id=cess_input_id,
        cess_amount=expense.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=expense.round_off,
    )

    from src.infrastructure.database.models import JournalEntry, JournalLine

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    expense.status = "POSTED"
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        logger = logging.getLogger(__name__)
        logger.error(f"Failed to commit posted expense {expense.id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to post expense: {str(e)}")

    db.refresh(expense)
    return _expense_to_response(expense)


@router.post("/{id}/cancel", response_model=ExpenseResponse)
def cancel_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:finalize")),
    current_user: User = Depends(get_current_user),
):
    """Cancels a posted expense by reversing its journal entry."""
    expense = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found.")

    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    if expense.status != "POSTED":
        raise HTTPException(status_code=400, detail="Only posted expenses can be cancelled.")

    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.deleted_at == None,
    ).first()
    if not category or not category.linked_account_id:
        raise HTTPException(status_code=400, detail="Expense category must have a linked account to cancel.")

    resolver = AccountResolver(db, tenant_id)
    if expense.bank_account_id:
        cash_account_id = expense.bank_account_id
    else:
        cash_account_id = resolver.resolve("assets.cash")

    cgst_input_id = resolver.resolve("cgst_input")
    sgst_input_id = resolver.resolve("sgst_input")
    igst_input_id = resolver.resolve("igst_input")
    utgst_input_id = resolver.resolve("utgst_input")
    cess_input_id = resolver.resolve("cess_input")
    round_off_account_id = resolver.resolve("round_off") if expense.round_off != 0 else None

    ledger_draft = LedgerPostingEngine.create_expense_reversal_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        cancel_date=date.today(),
        expense_account_id=category.linked_account_id,
        cash_account_id=cash_account_id,
        amount=expense.amount,
        cgst_account_id=cgst_input_id,
        cgst_amount=expense.cgst_amount,
        sgst_account_id=sgst_input_id,
        sgst_amount=expense.sgst_amount,
        igst_account_id=igst_input_id,
        igst_amount=expense.igst_amount,
        utgst_account_id=utgst_input_id,
        utgst_amount=expense.utgst_amount,
        cess_account_id=cess_input_id,
        cess_amount=expense.cess_amount,
        round_off_account_id=round_off_account_id,
        round_off_amount=expense.round_off,
    )

    from src.infrastructure.database.models import JournalEntry, JournalLine

    journal_entry = commit_ledger_draft(db, tenant_id, ledger_draft)

    expense.status = "CANCELLED"
    from datetime import datetime, timezone
    expense.cancelled_at = datetime.now(timezone.utc)
    if current_user:
        expense.cancelled_by = current_user.id
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        logger.error(f"Failed to cancel expense {expense.id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to cancel expense: {str(e)}")

    db.refresh(expense)
    return _expense_to_response(expense)


@router.post("/{id}/clone", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
def clone_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:create")),
):
    """Clone an existing expense into a new DRAFT expense."""
    from src.domains.accounting.period_lock import validate_period_open
    validate_period_open(db, tenant_id, date.today())

    original = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None
    ).first()
    if not original:
        raise HTTPException(status_code=404, detail="Expense not found.")

    new_number = _gen_expense_number(db, tenant_id)

    place_of_supply = original.place_of_supply_state_code or resolve_origin_state_code(db, tenant_id)
    totals = _compute_expense_totals(db, tenant_id, original.amount, original.gst_rate, place_of_supply)

    cloned = Expense(
        tenant_id=tenant_id,
        expense_number=new_number,
        expense_category_id=original.expense_category_id,
        bank_account_id=original.bank_account_id,
        expense_date=date.today(),
        vendor_name=original.vendor_name,
        description=original.description,
        amount=original.amount,
        gst_rate=original.gst_rate,
        cgst_amount=totals["cgst_amount"],
        sgst_amount=totals["sgst_amount"],
        igst_amount=totals["igst_amount"],
        utgst_amount=totals["utgst_amount"],
        cess_amount=totals["cess_amount"],
        round_off=totals["round_off"],
        total=totals["total"],
        status="DRAFT",
        notes=original.notes,
        reference_number=original.reference_number,
    )

    db.add(cloned)
    db.commit()
    db.refresh(cloned)
    return _expense_to_response(cloned)
