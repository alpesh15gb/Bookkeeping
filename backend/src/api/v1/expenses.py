import uuid
from decimal import Decimal
from typing import List, Optional
from datetime import date
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from src.api.deps import get_db_session, enforce_permission
from src.infrastructure.database.models import Expense, ExpenseCategory
from src.schemas.expense_schemas import ExpenseCreate, ExpenseUpdate, ExpenseResponse, ExpenseListResponse, ExpensePreviewRequest, ExpensePreviewResponse
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances, commit_ledger_draft
from src.domains.taxation.services import GSTEngine

router = APIRouter(prefix="/expenses", tags=["Expenses"])


def _compute_expense_totals(db: Session, tenant_id: uuid.UUID, amount: Decimal, gst_rate: Decimal, place_of_supply_state_code: str) -> dict:
    from src.domains.company.services import resolve_origin_state_code
    origin = resolve_origin_state_code(db, tenant_id)
    tax_split = GSTEngine.calculate_tax(
        origin_state_code=origin,
        place_of_supply_state_code=place_of_supply_state_code,
        base_amount=amount,
        gst_rate=gst_rate,
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
    last = db.query(func.max(Expense.expense_number)).filter(
        Expense.tenant_id == tenant_id,
        Expense.expense_number.like(f"{prefix}%"),
    ).with_for_update().scalar()
    next_num = 1
    if last:
        try:
            next_num = int(last.split("-")[-1]) + 1
        except (ValueError, IndexError):
            pass
    return f"{prefix}{next_num:04d}"


@router.post("/preview", response_model=ExpensePreviewResponse)
def preview_expense(
    payload: ExpensePreviewRequest,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    totals = _compute_expense_totals(db=db, tenant_id=tenant_id, amount=payload.amount, gst_rate=payload.gst_rate, place_of_supply_state_code=payload.place_of_supply_state_code or "27")
    return ExpensePreviewResponse(**totals)


@router.post("", response_model=ExpenseResponse, status_code=status.HTTP_201_CREATED)
def create_expense(
    payload: ExpenseCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:create")),
):
    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == payload.expense_category_id,
        ExpenseCategory.tenant_id == tenant_id,
        ExpenseCategory.is_active == True,
    ).first()
    if not category:
        raise HTTPException(status_code=404, detail="Expense category not found.")

    expense_number = _gen_expense_number(db, tenant_id)
    totals = _compute_expense_totals(db, tenant_id, payload.amount, payload.gst_rate, payload.place_of_supply_state_code or origin_state_code)

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
    )
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return _expense_to_response(expense)


@router.get("", response_model=List[ExpenseListResponse])
def list_expenses(
    status_filter: Optional[str] = None,
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
        totals = _compute_expense_totals(db, tenant_id, expense.amount, expense.gst_rate, expense.pos_state_code or "27")
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
    if expense.status != "DRAFT":
        raise HTTPException(status_code=400, detail="Only draft expenses can be posted.")

    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
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
    db.commit()

    db.refresh(expense)
    return _expense_to_response(expense)


@router.post("/{id}/cancel", response_model=ExpenseResponse)
def cancel_expense(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:finalize")),
):
    """Cancels a posted expense by reversing its journal entry."""
    expense = db.query(Expense).filter(
        Expense.id == id,
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    ).first()
    if not expense:
        raise HTTPException(status_code=404, detail="Expense not found.")
    if expense.status != "POSTED":
        raise HTTPException(status_code=400, detail="Only posted expenses can be cancelled.")

    category = db.query(ExpenseCategory).filter(
        ExpenseCategory.id == expense.expense_category_id,
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
    db.commit()

    db.refresh(expense)
    return _expense_to_response(expense)
