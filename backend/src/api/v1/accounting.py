from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import case, func, and_
from sqlalchemy.orm import selectinload
from typing import List, Optional
import uuid
from datetime import date, datetime
from decimal import Decimal

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    Account, JournalEntry, JournalLine, NumberingSeries
)
from src.schemas.accounting_schemas import (
    JournalEntryCreate, JournalEntryResponse, JournalLineResponse,
    LedgerReportResponse, LedgerLine,
    TrialBalanceResponse, TrialBalanceLine,
    ProfitLossResponse, ProfitLossItem,
    BalanceSheetResponse, BalanceSheetSection
)
from src.domains.company.services import NumberingSeriesService
from src.domains.accounting.services import update_account_balances
from src.api.deps import enforce_permission

router = APIRouter(prefix="/accounting", tags=["Accounting & Ledger"])

@router.post("/journals", response_model=JournalEntryResponse, status_code=status.HTTP_201_CREATED)
def create_manual_journal_entry(
    payload: JournalEntryCreate,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:manual_post"))
):
    """Creates a manual Journal Entry, updating the current balances of the affected accounts."""
    if len(payload.lines) < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A double-entry journal entry must contain at least two lines."
        )

    # Validate double-entry balancing
    debits_sum = Decimal("0.00")
    credits_sum = Decimal("0.00")
    for line in payload.lines:
        if line.direction == "DEBIT":
            debits_sum += line.amount
        else:
            credits_sum += line.amount

    if debits_sum != credits_sum:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Journal entry is out of balance. Debits ({debits_sum}) must equal Credits ({credits_sum})."
        )

    # Verify accounts belong to active tenant and are active
    db_lines = []
    for line in payload.lines:
        account = db.query(Account).filter(
            Account.id == line.account_id,
            Account.tenant_id == tenant_id,
            Account.deleted_at == None
        ).with_for_update().first()
        if not account:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Account with ID {line.account_id} not found."
            )
        if not account.is_active:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Account '{account.name}' is inactive."
            )

        db_lines.append(
            JournalLine(
                account_id=line.account_id,
                amount=line.amount,
                direction=line.direction,
                narration=line.narration
            )
        )

    # Numbering series auto-generation
    ref_num = payload.reference_number
    if not ref_num:
        ref_num = NumberingSeriesService.generate_next_number(db, tenant_id, "JOURNAL")

    # Check duplicate reference number under same tenant (with row lock to prevent races)
    dup = db.query(JournalEntry).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.reference_number == ref_num
    ).with_for_update().first()
    if dup:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Journal Entry reference number '{ref_num}' already exists."
        )

    # Build draft to enforce double-entry validation explicitly
    from src.domains.accounting.services import JournalEntryDraft, JournalLineDraft
    draft_lines = [
        JournalLineDraft(line.account_id, line.amount, line.direction, line.narration)
        for line in db_lines
    ]
    draft = JournalEntryDraft(
        tenant_id=tenant_id,
        entry_date=payload.entry_date,
        reference_number=ref_num,
        description=payload.description,
        source_type="MANUAL",
        source_id=uuid.UUID(int=0),  # placeholder, will be replaced after commit
        lines=draft_lines
    )

    journal_entry = JournalEntry(
        tenant_id=tenant_id,
        entry_date=payload.entry_date,
        reference_number=ref_num,
        description=payload.description,
        source_type="MANUAL",
        lines=db_lines
    )

    db.add(journal_entry)
    db.flush()
    # Update source_id to the real ID now that it's generated
    journal_entry.source_id = journal_entry.id
    affected = {line.account_id for line in db_lines}
    update_account_balances(db, tenant_id, affected)
    db.commit()

    # Re-fetch lines with account details to build response
    lines_with_acc = db.query(
        JournalLine.id,
        JournalLine.account_id,
        Account.name.label("account_name"),
        Account.code.label("account_code"),
        JournalLine.amount,
        JournalLine.direction,
        JournalLine.narration
    ).join(Account, JournalLine.account_id == Account.id)\
     .filter(JournalLine.entry_id == journal_entry.id, Account.deleted_at == None).all()

    return JournalEntryResponse(
        id=journal_entry.id,
        tenant_id=journal_entry.tenant_id,
        entry_date=journal_entry.entry_date,
        reference_number=journal_entry.reference_number,
        description=journal_entry.description,
        source_type=journal_entry.source_type,
        source_id=journal_entry.source_id,
        created_at=journal_entry.created_at,
        updated_at=journal_entry.updated_at,
        lines=[
            JournalLineResponse(
                id=row.id,
                account_id=row.account_id,
                account_name=row.account_name,
                account_code=row.account_code,
                amount=row.amount,
                direction=row.direction,
                narration=row.narration
            )
            for row in lines_with_acc
        ]
    )

@router.get("/journals", response_model=List[JournalEntryResponse])
def list_journal_entries(
    source_type: Optional[str] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    page: int = 1,
    limit: int = 50,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    """Lists journal entries with date and source filters."""
    offset = (page - 1) * limit
    q = db.query(JournalEntry).filter(JournalEntry.tenant_id == tenant_id)

    if source_type:
        q = q.filter(JournalEntry.source_type == source_type)
    if start_date:
        q = q.filter(JournalEntry.entry_date >= start_date)
    if end_date:
        q = q.filter(JournalEntry.entry_date <= end_date)

    entries = q.options(
        selectinload(JournalEntry.lines).selectinload(JournalLine.account)
    ).order_by(JournalEntry.entry_date.desc(), JournalEntry.created_at.desc())\
     .offset(offset).limit(limit).all()

    response = []
    for entry in entries:
        lines_with_acc = []
        for line in entry.lines:
            if line.account:
                lines_with_acc.append(
                    (line.id, line.account_id, line.account.name, line.account.code,
                     line.amount, line.direction, line.narration)
                )

        response.append(
            JournalEntryResponse(
                id=entry.id,
                tenant_id=entry.tenant_id,
                entry_date=entry.entry_date,
                reference_number=entry.reference_number,
                description=entry.description,
                source_type=entry.source_type,
                source_id=entry.source_id,
                created_at=entry.created_at,
                updated_at=entry.updated_at,
                lines=[
                    JournalLineResponse(
                        id=row.id,
                        account_id=row.account_id,
                        account_name=row.account_name,
                        account_code=row.account_code,
                        amount=row.amount,
                        direction=row.direction,
                        narration=row.narration
                    )
                    for row in lines_with_acc
                ]
            )
        )
    return response

@router.get("/journals/{id}", response_model=JournalEntryResponse)
def get_journal_entry(
    id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    """Retrieves a single journal entry by ID."""
    entry = db.query(JournalEntry).options(
        selectinload(JournalEntry.lines).selectinload(JournalLine.account)
    ).filter(
        JournalEntry.id == id,
        JournalEntry.tenant_id == tenant_id
    ).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Journal entry not found.")

    return JournalEntryResponse(
        id=entry.id,
        tenant_id=entry.tenant_id,
        entry_date=entry.entry_date,
        reference_number=entry.reference_number,
        description=entry.description,
        source_type=entry.source_type,
        source_id=entry.source_id,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
        lines=[
            JournalLineResponse(
                id=line.id,
                account_id=line.account_id,
                account_name=line.account.name if line.account else "",
                account_code=line.account.code if line.account else "",
                amount=line.amount,
                direction=line.direction,
                narration=line.narration
            )
            for line in entry.lines
        ]
    )

@router.get("/ledger/{account_id}", response_model=LedgerReportResponse)
def get_ledger_statement(
    account_id: uuid.UUID,
    page: int = 1,
    limit: int = 100,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    """Generates a ledger card/transaction statement for a specific account with running balance."""
    account = db.query(Account).filter(
        Account.id == account_id,
        Account.tenant_id == tenant_id,
        Account.deleted_at == None
    ).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found.")

    offset = (page - 1) * limit

    # Retrieve paginated journal lines for this account chronologically
    base_q = db.query(
        JournalLine.amount,
        JournalLine.direction,
        JournalLine.narration,
        JournalEntry.entry_date,
        JournalEntry.reference_number,
        JournalEntry.description
    ).join(JournalEntry, JournalLine.entry_id == JournalEntry.id)\
     .filter(JournalLine.account_id == account_id, JournalEntry.tenant_id == tenant_id)

    total_lines = base_q.count()
    lines = base_q.order_by(JournalEntry.entry_date.asc(), JournalEntry.created_at.asc())\
                  .offset(offset).limit(limit).all()

    # Compute the opening balance before this page
    prior_q = base_q.order_by(JournalEntry.entry_date.asc(), JournalEntry.created_at.asc())
    if offset > 0:
        prior_lines = prior_q.limit(offset).all()
        op_bal = Decimal(str(account.opening_balance))
        for pl in prior_lines:
            if pl.direction == "DEBIT":
                if account.account_type in ("ASSET", "EXPENSE"):
                    op_bal += pl.amount
                else:
                    op_bal -= pl.amount
            else:
                if account.account_type in ("ASSET", "EXPENSE"):
                    op_bal -= pl.amount
                else:
                    op_bal += pl.amount
    else:
        op_bal = Decimal(str(account.opening_balance))

    run_bal = op_bal
    report_lines = []

    for line in lines:
        amount = Decimal(str(line.amount))
        deb = Decimal("0.00")
        cred = Decimal("0.00")

        if line.direction == "DEBIT":
            deb = amount
            if account.account_type in ("ASSET", "EXPENSE"):
                run_bal += amount
            else:
                run_bal -= amount
        else:
            cred = amount
            if account.account_type in ("ASSET", "EXPENSE"):
                run_bal -= amount
            else:
                run_bal += amount

        report_lines.append(
            LedgerLine(
                entry_date=line.entry_date,
                reference_number=line.reference_number,
                description=line.description,
                debit_amount=deb,
                credit_amount=cred,
                narration=line.narration,
                running_balance=run_bal
            )
        )

    return LedgerReportResponse(
        account_id=account.id,
        account_name=account.name,
        account_code=account.code,
        opening_balance=op_bal,
        closing_balance=run_bal,
        lines=report_lines,
        total_lines=total_lines
    )

@router.get("/trial-balance", response_model=TrialBalanceResponse)
def get_trial_balance(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    """Compiles the Trial Balance for all accounts under the tenant."""
    # Query accounts and group summing of journal movements
    results = db.query(
        Account.id,
        Account.name,
        Account.code,
        Account.account_type,
        Account.opening_balance,
        func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
        func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits")
    ).outerjoin(JournalLine, Account.id == JournalLine.account_id)\
     .filter(Account.tenant_id == tenant_id, Account.deleted_at == None)\
     .group_by(Account.id, Account.name, Account.code, Account.account_type, Account.opening_balance)\
     .order_by(Account.code.asc()).all()

    total_opening_debits = Decimal("0.00")
    total_opening_credits = Decimal("0.00")
    total_debits = Decimal("0.00")
    total_credits = Decimal("0.00")
    total_closing_debits = Decimal("0.00")
    total_closing_credits = Decimal("0.00")

    lines = []
    for row in results:
        op = Decimal(str(row.opening_balance))
        deb = Decimal(str(row.debits))
        cred = Decimal(str(row.credits))
        acc_type = row.account_type

        if acc_type in ("ASSET", "EXPENSE"):
            closing = op + deb - cred
            total_opening_debits += op
            if closing >= 0:
                total_closing_debits += closing
            else:
                total_closing_credits += abs(closing)
        else:
            closing = op + cred - deb
            total_opening_credits += op
            if closing >= 0:
                total_closing_credits += closing
            else:
                total_closing_debits += abs(closing)

        total_debits += deb
        total_credits += cred

        lines.append(
            TrialBalanceLine(
                account_id=row.id,
                account_name=row.name,
                account_code=row.code,
                account_type=acc_type,
                opening_balance=op,
                total_debits=deb,
                total_credits=cred,
                closing_balance=closing
            )
        )

    return TrialBalanceResponse(
        lines=lines,
        total_opening_debits=total_opening_debits,
        total_opening_credits=total_opening_credits,
        total_debits=total_debits,
        total_credits=total_credits,
        total_closing_debits=total_closing_debits,
        total_closing_credits=total_closing_credits
    )

@router.get("/profit-loss", response_model=ProfitLossResponse)
def get_profit_loss_report(
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    """Generates the Profit & Loss statement for a given date range."""
    # Query journal movements restricted to REVENUE and EXPENSE accounts
    q = db.query(
        Account.id,
        Account.name,
        Account.code,
        Account.account_type,
        func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
        func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits")
    ).outerjoin(JournalLine, Account.id == JournalLine.account_id)\
     .outerjoin(JournalEntry, JournalLine.entry_id == JournalEntry.id)\
     .filter(Account.tenant_id == tenant_id, Account.account_type.in_(["REVENUE", "EXPENSE"]), Account.deleted_at == None)

    if start_date:
        q = q.filter(JournalEntry.entry_date >= start_date)
    if end_date:
        q = q.filter(JournalEntry.entry_date <= end_date)

    results = q.group_by(Account.id, Account.name, Account.code, Account.account_type)\
               .order_by(Account.code.asc()).all()

    revenue_lines = []
    expense_lines = []
    total_revenue = Decimal("0.00")
    total_expenses = Decimal("0.00")

    for row in results:
        deb = Decimal(str(row.debits))
        cred = Decimal(str(row.credits))
        acc_type = row.account_type

        # P&L computes dynamic movement only (no opening balance roll-forward)
        if acc_type == "REVENUE":
            amount = cred - deb
            total_revenue += amount
            revenue_lines.append(
                ProfitLossItem(
                    account_name=row.name,
                    account_code=row.code,
                    amount=amount
                )
            )
        else:
            amount = deb - cred
            total_expenses += amount
            expense_lines.append(
                ProfitLossItem(
                    account_name=row.name,
                    account_code=row.code,
                    amount=amount
                )
            )

    net_profit = total_revenue - total_expenses

    return ProfitLossResponse(
        revenue_lines=revenue_lines,
        total_revenue=total_revenue,
        expense_lines=expense_lines,
        total_expenses=total_expenses,
        net_profit=net_profit
    )


@router.post("/recalculate-balances")
def recalculate_account_balances(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage"))
):
    """Recalculate current_balance for all accounts from journal entries."""
    update_account_balances(db, tenant_id)
    return {"message": "Account balances recalculated from journal entries."}


@router.get("/balance-sheet", response_model=BalanceSheetResponse)
def get_balance_sheet(
    as_on_date: Optional[date] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("ledger:view"))
):
    """Generates a Balance Sheet as on a given date (defaults to today)."""

    cutoff = as_on_date or date.today()

    from sqlalchemy import func, case

    accounts = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.deleted_at == None,
        Account.account_type.in_(["ASSET", "LIABILITY", "EQUITY"]),
    ).order_by(Account.code.asc()).all()

    # Compute net movement per account up to cutoff date
    movement_subq = db.query(
        JournalLine.account_id,
        func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=-JournalLine.amount)), 0).label("net_movement")
    ).join(JournalEntry, JournalLine.entry_id == JournalEntry.id).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.entry_date <= cutoff
    ).group_by(JournalLine.account_id).subquery()

    movement_map = {row.account_id: row.net_movement for row in db.query(movement_subq).all()}

    assets = []
    liabilities = []
    equity = []
    total_assets = Decimal("0.00")
    total_liabilities = Decimal("0.00")
    total_equity = Decimal("0.00")

    for a in accounts:
        op = a.opening_balance or Decimal("0.00")
        net_movement = movement_map.get(a.id, Decimal("0.00"))
        if a.account_type in ("ASSET", "EXPENSE"):
            bal = op + net_movement
        else:
            bal = op - net_movement
        bal = bal.quantize(Decimal("0.01"))

        if a.account_type == "ASSET":
            assets.append(BalanceSheetSection(account_name=a.name, account_code=a.code, balance=bal))
            total_assets += bal
        elif a.account_type == "LIABILITY":
            liabilities.append(BalanceSheetSection(account_name=a.name, account_code=a.code, balance=bal))
            total_liabilities += bal
        else:
            equity.append(BalanceSheetSection(account_name=a.name, account_code=a.code, balance=bal))
            total_equity += bal

    # Include net profit in equity
    pnl = db.query(
        func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
        func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits"),
    ).outerjoin(JournalEntry, JournalLine.entry_id == JournalEntry.id)\
     .outerjoin(Account, JournalLine.account_id == Account.id)\
     .filter(Account.tenant_id == tenant_id, Account.account_type.in_(["REVENUE", "EXPENSE"]), Account.deleted_at == None)\
     .filter(JournalEntry.entry_date <= cutoff).first()

    if pnl:
        revenue = Decimal(str(pnl.credits)) - Decimal(str(pnl.debits))
    else:
        revenue = Decimal("0.00")

    net_profit = revenue
    if net_profit != 0:
        equity.append(BalanceSheetSection(account_name="Net Profit", account_code="--", balance=net_profit))
        total_equity += net_profit

    return BalanceSheetResponse(
        assets=assets,
        total_assets=total_assets.quantize(Decimal("0.01")),
        liabilities=liabilities,
        total_liabilities=total_liabilities.quantize(Decimal("0.01")),
        equity=equity,
        total_equity=total_equity.quantize(Decimal("0.01")),
        net_profit=net_profit.quantize(Decimal("0.01")),
    )
