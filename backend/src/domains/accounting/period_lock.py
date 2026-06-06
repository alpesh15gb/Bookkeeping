import uuid
from datetime import date
from fastapi import HTTPException, status
from sqlalchemy.orm import Session


def validate_period_open(db: Session, tenant_id: uuid.UUID, entry_date: date) -> None:
    from src.infrastructure.database.models import AccountingPeriod, FinancialYear

    # Check if any FY is in READY_TO_CLOSE (year-end close in progress)
    closing_fy = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant_id,
        FinancialYear.status == "READY_TO_CLOSE",
        FinancialYear.start_date <= entry_date,
        FinancialYear.end_date >= entry_date,
    ).first()

    if closing_fy:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Cannot post: Financial year '{closing_fy.name}' is being closed. Please try again after the close completes.",
        )

    # Check AccountingPeriod
    closed = db.query(AccountingPeriod).filter(
        AccountingPeriod.tenant_id == tenant_id,
        AccountingPeriod.start_date <= entry_date,
        AccountingPeriod.end_date >= entry_date,
        AccountingPeriod.is_closed == True,
    ).first()

    if closed:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Cannot post to a closed accounting period '{closed.period_name}' ({closed.start_date} to {closed.end_date}).",
        )
