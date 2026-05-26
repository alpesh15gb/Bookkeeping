import uuid
from decimal import Decimal
from typing import List, Optional
from datetime import date
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from src.api.deps import get_db_session, enforce_permission
from src.infrastructure.database.models import Expense, ExpenseCategory
from src.schemas.expense_schemas import ExpenseCreate, ExpenseUpdate, ExpenseResponse, ExpenseListResponse
from src.domains.accounting.services import AccountResolver, LedgerPostingEngine, update_account_balances

router = APIRouter(prefix="/expenses", tags=["Expenses"])


def _expense_to_response(e: Expense) -> ExpenseResponse:
    return ExpenseResponse(
        id=e.id,
        tenant_id=e.tenant_id,
        expense_number=e.expense_number,
        expense_category_id=e.expense_category_id,
        expense_date=e.expense_date,
        vendor_name=e.vendor_name,
        description=e.description,
        amount=e.amount,
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
    ).scalar()
    next_num = 1
    if last:
        try:
            next_num = int(last.split("-")[-1]) + 1
        except (ValueError, IndexError):
            pass
    return f"{prefix}{next_num:04d}"


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

    expense = Expense(
        tenant_id=tenant_id,
        expense_number=expense_number,
        expense_category_id=payload.expense_category_id,
        expense_date=payload.expense_date,
        vendor_name=payload.vendor_name,
        description=payload.description,
        amount=payload.amount,
        total=payload.amount,
        status="DRAFT",
    )
    db.add(expense)
    db.commit()
    db.refresh(expense)
    return _expense_to_response(expense)


@router.get("", response_model=List[ExpenseListResponse])
def list_expenses(
    status_filter: Optional[str] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    q = db.query(Expense).filter(
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
    )
    if status_filter:
        q = q.filter(Expense.status == status_filter)
    q = q.order_by(Expense.expense_date.desc(), Expense.created_at.desc())

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
    if payload.expense_date is not None:
        expense.expense_date = payload.expense_date
    if payload.vendor_name is not None:
        expense.vendor_name = payload.vendor_name
    if payload.description is not None:
        expense.description = payload.description
    if payload.amount is not None:
        expense.amount = payload.amount
        expense.total = payload.amount

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
    cash_account_id = resolver.resolve("assets.cash")

    ledger_draft = LedgerPostingEngine.create_expense_posting(
        tenant_id=tenant_id,
        expense_id=expense.id,
        expense_number=expense.expense_number,
        expense_date=expense.expense_date,
        expense_account_id=category.linked_account_id,
        cash_account_id=cash_account_id,
        amount=expense.amount,
    )

    from src.infrastructure.database.models import JournalEntry, JournalLine

    journal_entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=expense.expense_date,
        reference_number=expense.expense_number,
        description=f"Expense: {expense.description or 'No description'}",
        source_type="EXPENSE",
        source_id=expense.id,
    )
    db.add(journal_entry)

    for line in ledger_draft.lines:
        jl = JournalLine(
            entry_id=journal_entry.id,
            account_id=line.account_id,
            direction=line.direction,
            amount=line.amount,
            description=line.narration,
        )
        db.add(jl)

    expense.status = "POSTED"

    account_ids = {line.account_id for line in ledger_draft.lines}
    update_account_balances(db, tenant_id, account_ids)
    db.commit()

    db.refresh(expense)
    return _expense_to_response(expense)
