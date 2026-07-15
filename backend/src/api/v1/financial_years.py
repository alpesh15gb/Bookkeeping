from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func, case, text
from typing import List, Optional
import uuid
from decimal import Decimal
from datetime import date, datetime, timezone, timedelta

from src.core.database import get_db_session
from src.infrastructure.database.models import (
    FinancialYear, FinancialYearAudit, Tenant, JournalEntry, JournalLine, Account,
    Invoice, Bill, Expense, SalesReturn, PurchaseReturn, OpeningBalanceSnapshot,
    InventoryCarryForward, AccountingPeriod, User
)
from src.schemas.accounting_schemas import (
    FinancialYearCreate, FinancialYearResponse, FinancialYearSwitchRequest,
    YearEndDashboardResponse, UnpostedDocument
)
from src.api.deps import enforce_permission, get_current_user
from src.domains.accounting.reports import FinancialReportingService
from src.domains.accounting.services import AccountResolver, update_account_balances
from src.domains.accounting.roll_forward import carry_forward_balances, carry_forward_inventory

router = APIRouter(prefix="/financial-years", tags=["Financial Year Management"])


def _compute_status(fy: FinancialYear, today: date) -> str:
    # CRITICAL: Check stored status first — these override everything
    # This handles LOCKED, ARCHIVED, and READY_TO_CLOSE (set during year-end close)
    if fy.status in ("LOCKED", "ARCHIVED", "READY_TO_CLOSE"):
        return fy.status

    # The one explicitly selected FY is the logical current FY.
    if fy.is_current:
        return "CURRENT"

    if today > fy.end_date:
        return "READY_TO_CLOSE"

    if today < fy.start_date:
        return "UPCOMING"

    # If data is missing a current flag, the in-range FY is still current.
    return "CURRENT"


def _sync_tenant_fy_start(db: Session, tenant_id: uuid.UUID, fy_start: date):
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).first()
    if tenant:
        tenant.financial_year_start = fy_start


def _lock_tenant_for_fy_change(db: Session, tenant_id: uuid.UUID) -> None:
    """Serialize FY create/switch/close operations for a tenant."""
    tenant = db.query(Tenant).filter(Tenant.id == tenant_id).with_for_update().first()
    if tenant is None:
        raise HTTPException(status_code=404, detail="Company not found.")


def _log_audit(db: Session, tenant_id: uuid.UUID, fy_id: uuid.UUID,
               action: str, performed_by: Optional[uuid.UUID], detail: Optional[str] = None):
    audit = FinancialYearAudit(
        id=uuid.uuid4(),
        tenant_id=tenant_id,
        financial_year_id=fy_id,
        action=action,
        detail=detail,
        performed_by=performed_by,
    )
    db.add(audit)


def _enforce_single_current(db: Session, tenant_id: uuid.UUID, exclude_id: uuid.UUID):
    """DB-level guard: only one FY can be is_current=true per tenant."""
    current_count = db.query(func.count(FinancialYear.id)).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.is_current == True,
        FinancialYear.id != exclude_id,
    ).scalar()
    if current_count > 0:
        raise HTTPException(
            status_code=400,
            detail="Another financial year is already marked as current. Switch it first.",
        )


def _normalize_current_flags(fys: list[FinancialYear], today: date, force_fy_id: uuid.UUID = None) -> Optional[FinancialYear]:
    """Ensure only the FY containing today is marked current.
    
    If force_fy_id is provided, that FY is marked as current instead of the
    date-based calculation. This supports explicit user switches.
    """
    # If there's an explicit override, use it
    if force_fy_id is not None:
        for fy in fys:
            if fy.id == force_fy_id and fy.status not in ("LOCKED", "ARCHIVED"):
                correct_current = fy
                break
        else:
            correct_current = None
    else:
        # Check if there is exactly one FY marked as current in the list
        current_fys = [fy for fy in fys if fy.is_current and fy.status not in ("LOCKED", "ARCHIVED")]
        if len(current_fys) == 1:
            correct_current = current_fys[0]
        else:
            # If multiple or none are marked as current, fallback to date-based calculation
            correct_current = None
            for fy in fys:
                if fy.start_date <= today <= fy.end_date and fy.status not in ("LOCKED", "ARCHIVED"):
                    correct_current = fy
                    break
    for fy in fys:
        fy.is_current = (correct_current is not None and fy.id == correct_current.id)

    return correct_current


@router.get("", response_model=List[FinancialYearResponse])
def list_financial_years(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    today = date.today()
    fys = (
        db.query(FinancialYear)
        .filter(FinancialYear.tenant_id == tenant_id)
        .order_by(FinancialYear.start_date.desc())
        .all()
    )

    _normalize_current_flags(fys, today)

    results = []
    for fy in fys:
        computed = _compute_status(fy, today)
        # Update last_accessed_at for analytics
        fy.last_accessed_at = datetime.now(timezone.utc)
        results.append(FinancialYearResponse(
            id=fy.id, tenant_id=fy.tenant_id, name=fy.name,
            start_date=fy.start_date, end_date=fy.end_date,
            status=computed, is_current=fy.is_current,
            closed_at=fy.closed_at, closed_by=fy.closed_by,
            reopened_at=fy.reopened_at, reopened_by=fy.reopened_by,
            reopen_reason=fy.reopen_reason,
            journal_entry_id=fy.journal_entry_id,
            transaction_count=fy.transaction_count,
            created_by=fy.created_by, switched_by=fy.switched_by,
            created_at=fy.created_at, updated_at=fy.updated_at,
        ))
    db.commit()
    return results


@router.post("", response_model=FinancialYearResponse, status_code=status.HTTP_201_CREATED)
def create_financial_year(
    payload: FinancialYearCreate,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    actor_id = current_user.id
    _lock_tenant_for_fy_change(db, tenant_id)
    existing = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.name == payload.name,
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"Financial year '{payload.name}' already exists.")

    overlap = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.start_date <= payload.end_date,
        FinancialYear.end_date >= payload.start_date,
    ).first()
    if overlap:
        raise HTTPException(status_code=400, detail=f"Date range overlaps with existing FY '{overlap.name}'.")

    fy = FinancialYear(
        id=uuid.uuid4(),
        tenant_id=tenant_id,
        name=payload.name,
        start_date=payload.start_date,
        end_date=payload.end_date,
        status="CURRENT",
        is_current=False,
        transaction_count=0,
        created_by=actor_id,
    )
    db.add(fy)
    db.flush()
    db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.id != fy.id,
        FinancialYear.is_current == True,
    ).update({"is_current": False}, synchronize_session=False)
    db.flush()
    fy.is_current = True
    _log_audit(db, tenant_id, fy.id, "CREATED", actor_id, f"FY {fy.name} created")
    db.commit()
    db.refresh(fy)
    today = date.today()
    computed = _compute_status(fy, today)

    return FinancialYearResponse(
        id=fy.id, tenant_id=fy.tenant_id, name=fy.name,
        start_date=fy.start_date, end_date=fy.end_date,
        status=computed, is_current=fy.is_current,
        transaction_count=0, created_by=fy.created_by,
        created_at=fy.created_at, updated_at=fy.updated_at,
    )


@router.post("/switch", response_model=FinancialYearResponse)
def switch_financial_year(
    payload: FinancialYearSwitchRequest,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    actor_id = current_user.id
    _lock_tenant_for_fy_change(db, tenant_id)
    target = db.query(FinancialYear).filter(
        FinancialYear.id == payload.financial_year_id,
        FinancialYear.tenant_id == tenant_id,
    ).first()
    if not target:
        raise HTTPException(status_code=404, detail="Financial year not found.")
    if target.status in ("LOCKED", "ARCHIVED"):
        raise HTTPException(status_code=400, detail=f"Cannot switch to a {target.status.lower()} financial year.")

    today = date.today()
    db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.id != target.id,
        FinancialYear.is_current == True,
    ).update({"is_current": False}, synchronize_session=False)
    db.flush()
    target.is_current = True
    target.switched_by = actor_id
    target.last_accessed_at = datetime.now(timezone.utc)
    db.flush()
    _log_audit(db, tenant_id, target.id, "SWITCHED", actor_id, f"Switched to FY {target.name}")
    _sync_tenant_fy_start(db, tenant_id, target.start_date)
    db.commit()
    db.refresh(target)

    computed = _compute_status(target, today)
    return FinancialYearResponse(
        id=target.id, tenant_id=target.tenant_id, name=target.name,
        start_date=target.start_date, end_date=target.end_date,
        status=computed, is_current=target.is_current,
        closed_at=target.closed_at, closed_by=target.closed_by,
        reopened_at=target.reopened_at, reopened_by=target.reopened_by,
        journal_entry_id=target.journal_entry_id,
        transaction_count=target.transaction_count,
        created_by=target.created_by, switched_by=target.switched_by,
        created_at=target.created_at, updated_at=target.updated_at,
    )


@router.get("/current", response_model=FinancialYearResponse)
def get_current_financial_year(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    today = date.today()
    fys = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
    ).order_by(FinancialYear.start_date.desc()).all()
    fy = _normalize_current_flags(fys, today)
    if not fy:
        fy_year = today.year if today.month >= 4 else today.year - 1
        fy = db.query(FinancialYear).filter(
            FinancialYear.tenant_id == tenant_id,
            FinancialYear.start_date == date(fy_year, 4, 1),
        ).first()
        if not fy:
            raise HTTPException(status_code=404, detail="No current financial year found. Create one first.")
    
    fy.is_current = True
    for other_fy in fys:
        if other_fy.id != fy.id:
            other_fy.is_current = False

    computed = _compute_status(fy, today)
    db.commit()
    return FinancialYearResponse(
        id=fy.id, tenant_id=fy.tenant_id, name=fy.name,
        start_date=fy.start_date, end_date=fy.end_date,
        status=computed, is_current=fy.is_current,
        closed_at=fy.closed_at, closed_by=fy.closed_by,
        reopened_at=fy.reopened_at, reopened_by=fy.reopened_by,
        journal_entry_id=fy.journal_entry_id,
        transaction_count=fy.transaction_count,
        created_by=fy.created_by, switched_by=fy.switched_by,
        created_at=fy.created_at, updated_at=fy.updated_at,
    )


@router.get("/{fy_id}/dashboard", response_model=YearEndDashboardResponse)
def year_end_dashboard(
    fy_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    fy = db.query(FinancialYear).filter(
        FinancialYear.id == fy_id,
        FinancialYear.tenant_id == tenant_id,
    ).first()
    if not fy:
        raise HTTPException(status_code=404, detail="Financial year not found.")

    today = date.today()
    computed = _compute_status(fy, today)

    tb = FinancialReportingService.get_trial_balance(db, fy.end_date, tenant_id)
    tb_balanced = tb['is_balanced']

    unposted = []
    for model_cls, doc_type, date_field, num_field, amount_field in [
        (Invoice, "INVOICE", "issue_date", "invoice_number", "total"),
        (Bill, "BILL", "issue_date", "bill_number", "total"),
        (Expense, "EXPENSE", "expense_date", "expense_number", "total"),
        (SalesReturn, "SALES_RETURN", "issue_date", "return_number", "total"),
        (PurchaseReturn, "PURCHASE_RETURN", "issue_date", "return_number", "total"),
    ]:
        rows = db.query(model_cls).filter(
            model_cls.tenant_id == tenant_id,
            getattr(model_cls, date_field) >= fy.start_date,
            getattr(model_cls, date_field) <= fy.end_date,
            model_cls.status == "DRAFT",
            model_cls.deleted_at == None,
        ).all()
        for r in rows:
            unposted.append(UnpostedDocument(
                id=r.id, document_type=doc_type,
                document_number=getattr(r, num_field),
                date=getattr(r, date_field),
                amount=getattr(r, amount_field),
            ))

    pnl = FinancialReportingService.get_profit_and_loss(db, fy.start_date, fy.end_date, tenant_id)
    net_profit = pnl['net_profit']

    blocking_items = []
    if not tb_balanced:
        blocking_items.append("Trial Balance is not balanced")
    if len(unposted) > 0:
        blocking_items.append(f"{len(unposted)} draft/unposted document(s) exist")
    if computed in ("LOCKED", "ARCHIVED"):
        blocking_items.append("Financial year is already closed/locked")

    score = 100
    if not tb_balanced:
        score -= 40
    if len(unposted) > 0:
        score -= min(40, len(unposted) * 10)
    if computed in ("LOCKED", "ARCHIVED"):
        score = 100

    readiness_score = max(0, score)
    closing_allowed = len(blocking_items) == 0

    return YearEndDashboardResponse(
        financial_year=FinancialYearResponse(
            id=fy.id, tenant_id=fy.tenant_id, name=fy.name,
            start_date=fy.start_date, end_date=fy.end_date,
            status=computed, is_current=fy.is_current,
            closed_at=fy.closed_at, closed_by=fy.closed_by,
            journal_entry_id=fy.journal_entry_id,
            transaction_count=fy.transaction_count,
            created_at=fy.created_at, updated_at=fy.updated_at,
        ),
        readiness_score=readiness_score,
        trial_balance_balanced=tb_balanced,
        unposted_documents_count=len(unposted),
        unposted_documents=unposted,
        net_profit=net_profit,
        closing_allowed=closing_allowed,
        blocking_items=blocking_items,
    )


@router.post("/{fy_id}/close")
def close_financial_year(
    fy_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    actor_id = current_user.id
    _lock_tenant_for_fy_change(db, tenant_id)
    # CRITICAL #5: Concurrency protection - lock the FY row
    fy = db.query(FinancialYear).filter(
        FinancialYear.id == fy_id,
        FinancialYear.tenant_id == tenant_id,
    ).with_for_update().first()
    if not fy:
        raise HTTPException(status_code=404, detail="Financial year not found.")

    today = date.today()
    computed = _compute_status(fy, today)
    if computed in ("LOCKED", "ARCHIVED"):
        raise HTTPException(status_code=400, detail="Financial year is already closed.")

    # RACE CONDITION FIX: Set status to READY_TO_CLOSE immediately to block
    # new transactions from being posted during the close process.
    # validate_period_open checks status and will reject DRAFT->POSTED transitions.
    fy.status = "READY_TO_CLOSE"
    db.flush()

    # Run readiness check
    dashboard = year_end_dashboard(fy_id=fy_id, db=db, tenant_id=tenant_id)
    if not dashboard.closing_allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot close: {'; '.join(dashboard.blocking_items)}",
        )

    # Zero REVENUE and EXPENSE accounts
    accounts = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.account_type.in_(["REVENUE", "EXPENSE"]),
        Account.deleted_at == None,
    ).all()

    movements = db.query(
        JournalLine.account_id,
        func.coalesce(func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)), 0).label("debits"),
        func.coalesce(func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)), 0).label("credits"),
    ).join(JournalEntry, JournalLine.entry_id == JournalEntry.id) \
     .filter(JournalEntry.tenant_id == tenant_id, JournalEntry.entry_date >= fy.start_date, JournalEntry.entry_date <= fy.end_date) \
     .group_by(JournalLine.account_id).all()

    movement_map = {row.account_id: (row.debits, row.credits) for row in movements}
    closing_lines = []
    total_debits = Decimal("0.0000")
    total_credits = Decimal("0.0000")

    for account in accounts:
        debits, credits = movement_map.get(account.id, (Decimal("0.0000"), Decimal("0.0000")))
        if account.account_type == "REVENUE":
            bal = credits - debits
            if bal != 0:
                direction = "DEBIT" if bal > 0 else "CREDIT"
                closing_lines.append(JournalLine(
                    account_id=account.id, amount=abs(bal), direction=direction,
                    narration=f"Closing entry: Revenue '{account.name}' to Retained Earnings",
                ))
                if direction == "DEBIT":
                    total_debits += abs(bal)
                else:
                    total_credits += abs(bal)
        elif account.account_type == "EXPENSE":
            bal = debits - credits
            if bal != 0:
                direction = "CREDIT" if bal > 0 else "DEBIT"
                closing_lines.append(JournalLine(
                    account_id=account.id, amount=abs(bal), direction=direction,
                    narration=f"Closing entry: Expense '{account.name}' to Retained Earnings",
                ))
                if direction == "CREDIT":
                    total_credits += abs(bal)
                else:
                    total_debits += abs(bal)

    # Post net profit/loss to Retained Earnings
    # CRITICAL #3: Use Decimal for net_profit, not float
    resolver = AccountResolver(db, tenant_id)
    retained_account_id = resolver.resolve("equity.retained")
    pnl = FinancialReportingService.get_profit_and_loss(db, fy.start_date, fy.end_date, tenant_id)
    net_profit = Decimal(str(pnl['net_profit']))

    if net_profit != 0:
        direction = "CREDIT" if net_profit > 0 else "DEBIT"
        closing_lines.append(JournalLine(
            account_id=retained_account_id, amount=abs(net_profit), direction=direction,
            narration="Closing entry: Net Profit to Retained Earnings" if net_profit > 0 else "Closing entry: Net Loss to Retained Earnings",
        ))
        if direction == "CREDIT":
            total_credits += abs(net_profit)
        else:
            total_debits += abs(net_profit)

    # CRITICAL: Validate debits == credits before creating closing JE
    if len(closing_lines) >= 2 and total_debits.quantize(Decimal("0.0001")) != total_credits.quantize(Decimal("0.0001")):
        raise HTTPException(
            status_code=400,
            detail=f"Closing journal does not balance: debits={total_debits}, credits={total_credits}",
        )

    entry_id = uuid.uuid4()
    ref_num = f"YEC-{fy.start_date.year}-{fy.end_date.year % 100:02d}"
    journal_entry = None

    if len(closing_lines) >= 2:
        journal_entry = JournalEntry(
            id=entry_id, tenant_id=tenant_id, entry_date=fy.end_date,
            reference_number=ref_num,
            description=f"Year-End closing journal entry for {fy.name}",
            source_type="YEAR_END", source_id=entry_id, is_locked=True,
            lines=closing_lines,
        )
        db.add(journal_entry)
        db.flush()
        affected = {line.account_id for line in closing_lines}
        update_account_balances(db, tenant_id, affected)

    # Update FY status → LOCKED (immediately, no CLOSED intermediate)
    fy.status = "LOCKED"
    fy.closed_at = datetime.now(timezone.utc)
    fy.closed_by = actor_id
    fy.journal_entry_id = entry_id if journal_entry else None

    # Sync AccountingPeriod: close the period covering this FY
    period = db.query(AccountingPeriod).filter(
        AccountingPeriod.tenant_id == tenant_id,
        AccountingPeriod.start_date <= fy.end_date,
        AccountingPeriod.end_date >= fy.start_date,
    ).first()
    if period:
        period.is_closed = True
    else:
        period = AccountingPeriod(
            tenant_id=tenant_id,
            period_name=f"FY {fy.name}",
            start_date=fy.start_date,
            end_date=fy.end_date,
            is_closed=True,
        )
        db.add(period)
    _log_audit(db, tenant_id, fy.id, "CLOSED", actor_id,
               f"FY closed. Journal: {ref_num}. Net profit: {net_profit}")

    # Advance current FY
    db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.is_current == True,
    ).update({"is_current": False})

    next_fy_start = fy.end_date + timedelta(days=1)
    try:
        next_fy_end = date(next_fy_start.year + 1, next_fy_start.month, 1) - timedelta(days=1)
    except ValueError:
        next_fy_end = date(next_fy_start.year + 1, next_fy_start.month, 28) - timedelta(days=1)

    # Onboarding may already have created the adjacent year. Reuse an exact
    # match for roll-forward; only a partial/misaligned overlap is invalid.
    overlap = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.start_date <= next_fy_end,
        FinancialYear.end_date >= next_fy_start,
    ).first()
    if overlap and (overlap.start_date != next_fy_start or overlap.end_date != next_fy_end):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot create next FY: overlaps with existing FY '{overlap.name}'",
        )

    if overlap:
        if overlap.status in ("LOCKED", "ARCHIVED"):
            raise HTTPException(
                status_code=400,
                detail=f"Cannot roll forward into {overlap.status.lower()} FY '{overlap.name}'.",
            )
        next_fy = overlap
        next_fy.status = "CURRENT"
        next_fy.is_current = True
        _log_audit(db, tenant_id, next_fy.id, "REUSED_FOR_ROLL_FORWARD", actor_id,
                   f"Reused existing FY during year-end close of {fy.name}")
    else:
        next_fy = FinancialYear(
            id=uuid.uuid4(), tenant_id=tenant_id,
            name=f"{next_fy_start.year}-{((next_fy_start.year + 1) % 100):02d}",
            start_date=next_fy_start, end_date=next_fy_end,
            status="CURRENT", is_current=True, transaction_count=0,
            created_by=actor_id,
        )
        db.add(next_fy)
        db.flush()
        _log_audit(db, tenant_id, next_fy.id, "CREATED", actor_id,
                   f"Auto-created from year-end close of {fy.name}")

    # Roll-forward: carry opening balances to new FY
    balance_result = carry_forward_balances(db, tenant_id, fy, next_fy)
    _log_audit(db, tenant_id, next_fy.id, "OPENING_BALANCE_CARRY_FORWARD", actor_id,
               f"Carried forward {balance_result['accounts_carried']} accounts. "
               f"JE: {balance_result.get('journal_entry_id', 'none')}")

    # Roll-forward: carry inventory to new FY
    inventory_result = carry_forward_inventory(db, tenant_id, fy, next_fy)
    _log_audit(db, tenant_id, next_fy.id, "INVENTORY_CARRY_FORWARD", actor_id,
               f"Carried forward {inventory_result['products_carried']} products. "
               f"Total value: {inventory_result['total_value']}")

    _sync_tenant_fy_start(db, tenant_id, next_fy_start)
    db.commit()

    return {
        "financial_year_id": str(fy.id),
        "status": "LOCKED",
        "journal_entry_id": str(entry_id) if journal_entry else None,
        "reference_number": ref_num,
        "new_financial_year_id": str(next_fy.id),
        "new_financial_year_name": next_fy.name,
        "roll_forward": {
            "accounts_carried": balance_result["accounts_carried"],
            "products_carried": inventory_result["products_carried"],
            "opening_journal_entry_id": balance_result.get("journal_entry_id"),
        },
    }


@router.post("/{fy_id}/reopen")
def reopen_financial_year(
    fy_id: uuid.UUID,
    reason: str = "",
    db: Session = Depends(get_db_session),
    current_user: User = Depends(get_current_user),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    actor_id = current_user.id
    _lock_tenant_for_fy_change(db, tenant_id)
    """Reopen a locked/archived FY. Requires a reason. Logs audit trail.
    
    CRITICAL: Reverses roll-forward:
    - Deletes next FY's opening journal entry (source_type=OPENING_BALANCE)
    - Resets opening_balance on permanent accounts
    - Deletes OpeningBalanceSnapshot rows
    - Deletes InventoryCarryForward rows
    """
    # Lock the FY row for concurrency protection
    fy = db.query(FinancialYear).filter(
        FinancialYear.id == fy_id,
        FinancialYear.tenant_id == tenant_id,
    ).with_for_update().first()
    if not fy:
        raise HTTPException(status_code=404, detail="Financial year not found.")
    if fy.status not in ("LOCKED", "ARCHIVED"):
        raise HTTPException(status_code=400, detail="Only locked or archived FYs can be reopened.")
    if not reason or not reason.strip():
        raise HTTPException(status_code=400, detail="A reason is required to reopen a financial year.")

    # Check if closing journal exists and delete it
    if fy.journal_entry_id:
        je = db.query(JournalEntry).filter(JournalEntry.id == fy.journal_entry_id).first()
        if je:
            # Delete journal lines first
            db.query(JournalLine).filter(JournalLine.entry_id == je.id).delete()
            db.delete(je)

    # CRITICAL #4: Reverse roll-forward
    # Find the next FY (created during close)
    next_fy = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.start_date > fy.end_date,
    ).order_by(FinancialYear.start_date.asc()).first()

    if next_fy:
        # Delete opening journal entry in next FY (source_type=OPENING_BALANCE)
        opening_je = db.query(JournalEntry).filter(
            JournalEntry.tenant_id == tenant_id,
            JournalEntry.source_type == "OPENING_BALANCE",
            JournalEntry.entry_date == next_fy.start_date,
        ).first()
        if opening_je:
            db.query(JournalLine).filter(JournalLine.entry_id == opening_je.id).delete()
            db.delete(opening_je)

        # Delete OpeningBalanceSnapshot rows for next FY
        db.query(OpeningBalanceSnapshot).filter(
            OpeningBalanceSnapshot.tenant_id == tenant_id,
            OpeningBalanceSnapshot.financial_year_id == fy.id,
        ).delete()

        # Delete InventoryCarryForward rows for next FY
        db.query(InventoryCarryForward).filter(
            InventoryCarryForward.tenant_id == tenant_id,
            InventoryCarryForward.financial_year_id == fy.id,
        ).delete()

        # Reset opening_balance on permanent accounts
        accounts = db.query(Account).filter(
            Account.tenant_id == tenant_id,
            Account.account_type.in_(["ASSET", "LIABILITY", "EQUITY"]),
            Account.deleted_at == None,
        ).all()
        for account in accounts:
            account.opening_balance = Decimal("0.0000")

        # Recalculate account balances
        account_ids = {a.id for a in accounts}
        update_account_balances(db, tenant_id, account_ids)

    fy.status = "CURRENT"
    fy.is_current = False
    fy.closed_at = None
    fy.closed_by = None
    fy.journal_entry_id = None
    fy.reopened_at = datetime.now(timezone.utc)
    fy.reopened_by = actor_id
    fy.reopen_reason = reason.strip()

    # Sync AccountingPeriod: reopen the period covering this FY
    period = db.query(AccountingPeriod).filter(
        AccountingPeriod.tenant_id == tenant_id,
        AccountingPeriod.start_date <= fy.end_date,
        AccountingPeriod.end_date >= fy.start_date,
    ).first()
    if period:
        period.is_closed = False

    _log_audit(db, tenant_id, fy.id, "REOPENED", actor_id, f"Reason: {reason.strip()}")
    db.commit()
    db.refresh(fy)
    computed = _compute_status(fy, date.today())

    return FinancialYearResponse(
        id=fy.id, tenant_id=fy.tenant_id, name=fy.name,
        start_date=fy.start_date, end_date=fy.end_date,
        status=computed, is_current=fy.is_current,
        closed_at=fy.closed_at, closed_by=fy.closed_by,
        reopened_at=fy.reopened_at, reopened_by=fy.reopened_by,
        reopen_reason=fy.reopen_reason,
        journal_entry_id=fy.journal_entry_id,
        transaction_count=fy.transaction_count,
        created_by=fy.created_by, switched_by=fy.switched_by,
        created_at=fy.created_at, updated_at=fy.updated_at,
    )


@router.get("/{fy_id}/audit", response_model=List[dict])
def get_fy_audit_trail(
    fy_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    """Return the audit trail for a specific financial year."""
    audits = (
        db.query(FinancialYearAudit)
        .filter(
            FinancialYearAudit.tenant_id == tenant_id,
            FinancialYearAudit.financial_year_id == fy_id,
        )
        .order_by(FinancialYearAudit.created_at.desc())
        .all()
    )
    return [
        {
            "id": str(a.id),
            "action": a.action,
            "detail": a.detail,
            "performed_by": str(a.performed_by) if a.performed_by else None,
            "created_at": a.created_at.isoformat() if a.created_at else None,
        }
        for a in audits
    ]


@router.get("/{fy_id}/opening-balances", response_model=List[dict])
def get_opening_balances(
    fy_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    """Return the opening balance snapshots for a specific financial year.
    These are the balances that were carried forward from the previous FY."""
    snapshots = (
        db.query(OpeningBalanceSnapshot)
        .filter(
            OpeningBalanceSnapshot.tenant_id == tenant_id,
            OpeningBalanceSnapshot.financial_year_id == fy_id,
        )
        .order_by(OpeningBalanceSnapshot.account_type, OpeningBalanceSnapshot.account_code)
        .all()
    )
    return [
        {
            "id": str(s.id),
            "account_id": str(s.account_id),
            "account_type": s.account_type,
            "account_name": s.account_name,
            "account_code": s.account_code,
            "closing_balance": str(s.closing_balance),
            "direction": s.direction,
            "created_at": s.created_at.isoformat() if s.created_at else None,
        }
        for s in snapshots
    ]


@router.get("/{fy_id}/inventory-carry-forward", response_model=List[dict])
def get_inventory_carry_forward(
    fy_id: uuid.UUID,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("accounts:manage")),
):
    """Return the inventory carry-forward snapshots for a specific financial year.
    These are the stock quantities/values that were carried forward from the previous FY."""
    carry_forwards = (
        db.query(InventoryCarryForward)
        .filter(
            InventoryCarryForward.tenant_id == tenant_id,
            InventoryCarryForward.financial_year_id == fy_id,
        )
        .order_by(InventoryCarryForward.product_name)
        .all()
    )
    return [
        {
            "id": str(cf.id),
            "product_id": str(cf.product_id),
            "product_name": cf.product_name,
            "product_sku": cf.product_sku,
            "closing_quantity": str(cf.closing_quantity),
            "closing_value": str(cf.closing_value),
            "unit_rate": str(cf.unit_rate),
            "created_at": cf.created_at.isoformat() if cf.created_at else None,
        }
        for cf in carry_forwards
    ]
