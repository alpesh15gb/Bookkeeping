from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.orm import Session
import uuid
from decimal import Decimal
from datetime import datetime
from typing import Optional

from src.core.database import get_db_session
from src.core.cache import cache_get, cache_set, make_cache_key
from src.api.deps import enforce_permission

router = APIRouter(prefix="/dashboard", tags=["Dashboard Analytics"])


@router.get("/metrics")
def get_dashboard_metrics(
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    params = {"tenant_id": str(tenant_id)}
    date_filter = ""
    if date_from and date_to:
        date_filter = "AND issue_date >= :date_from AND issue_date <= :date_to"
        params["date_from"] = date_from
        params["date_to"] = date_to

    cache_key = make_cache_key("dashboard_metrics", str(tenant_id), date_from or "", date_to or "")
    cached = cache_get(cache_key)
    if cached is not None:
        return cached

    result = db.execute(
        text(f"""
            SELECT
                COALESCE(SUM(cgst_amount), 0) AS cgst_total,
                COALESCE(SUM(sgst_amount), 0) AS sgst_total,
                COALESCE(SUM(igst_amount), 0) AS igst_total,
                COALESCE(SUM(cess_amount), 0) AS cess_total
            FROM invoices
            WHERE status IN ('POSTED', 'PARTIALLY_PAID', 'PAID')
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
              {date_filter}
        """),
        params,
    ).fetchone()

    response = {
        "cgst_total": float(result.cgst_total) if result else 0,
        "sgst_total": float(result.sgst_total) if result else 0,
        "igst_total": float(result.igst_total) if result else 0,
        "cess_total": float(result.cess_total) if result else 0,
    }

    cache_set(cache_key, response, ttl_seconds=60)
    return response


@router.get("/revenue-trend")
def get_revenue_trend(
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    params = {"tenant_id": str(tenant_id)}
    if date_from and date_to:
        params["date_from"] = date_from
        params["date_to"] = date_to
        date_filter = "AND issue_date >= :date_from AND issue_date <= :date_to"
    else:
        date_filter = "AND issue_date >= :cutoff"
        params["cutoff"] = datetime.now().replace(year=datetime.now().year - 1)

    results = db.execute(
        text(f"""
            SELECT
                EXTRACT(MONTH FROM issue_date) AS month,
                EXTRACT(YEAR FROM issue_date) AS year,
                COALESCE(SUM(total), 0) AS total
            FROM invoices
            WHERE status IN ('POSTED', 'PARTIALLY_PAID', 'PAID')
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
              {date_filter}
            GROUP BY year, month
            ORDER BY year, month
        """),
        params,
    ).fetchall()

    return [
        {"month": int(row.month), "year": int(row.year), "total": float(row.total)}
        for row in results
    ]


@router.get("/expense-trend")
def get_expense_trend(
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    params = {"tenant_id": str(tenant_id)}
    if date_from and date_to:
        params["date_from"] = date_from
        params["date_to"] = date_to
        date_filter = "AND expense_date >= :date_from AND expense_date <= :date_to"
    else:
        date_filter = "AND expense_date >= :cutoff"
        params["cutoff"] = datetime.now().replace(year=datetime.now().year - 1)

    results = db.execute(
        text(f"""
            SELECT
                EXTRACT(MONTH FROM expense_date) AS month,
                EXTRACT(YEAR FROM expense_date) AS year,
                COALESCE(SUM(amount), 0) AS total
            FROM expenses
            WHERE status = 'POSTED'
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
              {date_filter}
            GROUP BY year, month
            ORDER BY year, month
        """),
        params,
    ).fetchall()

    return [
        {"month": int(row.month), "year": int(row.year), "total": float(row.total)}
        for row in results
    ]
