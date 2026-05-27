from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session
import uuid
from decimal import Decimal
from datetime import datetime

from src.core.database import get_db_session
from src.api.deps import enforce_permission

router = APIRouter(prefix="/dashboard", tags=["Dashboard Analytics"])


@router.get("/metrics")
def get_dashboard_metrics(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    result = db.execute(
        text("""
            SELECT
                COALESCE(SUM(cgst_amount), 0) AS cgst_total,
                COALESCE(SUM(sgst_amount), 0) AS sgst_total,
                COALESCE(SUM(igst_amount), 0) AS igst_total,
                COALESCE(SUM(cess_amount), 0) AS cess_total
            FROM invoices
            WHERE status IN ('SENT', 'PARTIALLY_PAID', 'PAID')
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
        """),
        {"tenant_id": str(tenant_id)},
    ).fetchone()

    return {
        "cgst_total": float(result.cgst_total) if result else 0,
        "sgst_total": float(result.sgst_total) if result else 0,
        "igst_total": float(result.igst_total) if result else 0,
        "cess_total": float(result.cess_total) if result else 0,
    }


@router.get("/revenue-trend")
def get_revenue_trend(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    results = db.execute(
        text("""
            SELECT
                EXTRACT(MONTH FROM issue_date) AS month,
                EXTRACT(YEAR FROM issue_date) AS year,
                COALESCE(SUM(total), 0) AS total
            FROM invoices
            WHERE status IN ('SENT', 'PARTIALLY_PAID', 'PAID')
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
              AND issue_date >= :cutoff
            GROUP BY year, month
            ORDER BY year, month
        """),
        {
            "tenant_id": str(tenant_id),
            "cutoff": datetime.now().replace(year=datetime.now().year - 1),
        },
    ).fetchall()

    return [
        {"month": int(row.month), "year": int(row.year), "total": float(row.total)}
        for row in results
    ]


@router.get("/expense-trend")
def get_expense_trend(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    results = db.execute(
        text("""
            SELECT
                EXTRACT(MONTH FROM expense_date) AS month,
                EXTRACT(YEAR FROM expense_date) AS year,
                COALESCE(SUM(amount), 0) AS total
            FROM expenses
            WHERE status = 'POSTED'
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
              AND expense_date >= :cutoff
            GROUP BY year, month
            ORDER BY year, month
        """),
        {
            "tenant_id": str(tenant_id),
            "cutoff": datetime.now().replace(year=datetime.now().year - 1),
        },
    ).fetchall()

    return [
        {"month": int(row.month), "year": int(row.year), "total": float(row.total)}
        for row in results
    ]
