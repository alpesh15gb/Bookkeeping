from fastapi import APIRouter, Depends, Query
from sqlalchemy import text, func
from sqlalchemy.orm import Session
import uuid
from decimal import Decimal
from datetime import date, datetime
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
    from sqlalchemy import text as _txt
    _dialect = None
    try:
        _dialect = db.bind.dialect.name if hasattr(db, 'bind') else None
    except Exception:
        pass
    _tid = tenant_id.hex if _dialect == "sqlite" else str(tenant_id)
    params = {"tenant_id": _tid}
    date_filter = ""
    if date_from and date_to:
        date_filter = "AND issue_date >= :date_from AND issue_date <= :date_to"
        params["date_from"] = date.fromisoformat(date_from)
        params["date_to"] = date.fromisoformat(date_to)

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
    from src.infrastructure.database.models import Invoice
    query = db.query(
        func.extract("month", Invoice.issue_date).label("month"),
        func.extract("year", Invoice.issue_date).label("year"),
        func.coalesce(func.sum(Invoice.total), 0).label("total"),
    ).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.status.in_(("POSTED", "PARTIALLY_PAID", "PAID")),
        Invoice.deleted_at == None,
    )
    if date_from and date_to:
        query = query.filter(
            Invoice.issue_date >= date.fromisoformat(date_from),
            Invoice.issue_date <= date.fromisoformat(date_to),
        )
    else:
        today = date.today()
        try:
            cutoff = today.replace(year=today.year - 1)
        except ValueError:
            cutoff = today.replace(year=today.year - 1, day=28)
        query = query.filter(Invoice.issue_date >= cutoff)

    results = query.group_by("year", "month").order_by("year", "month").all()

    return [
        {"month": int(row.month), "year": int(row.year), "total": float(row.total)}
        for row in results
    ]


@router.get("/kpis")
def dashboard_kpis(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    """Returns key performance indicators for the dashboard."""
    from src.infrastructure.database.models import Invoice, Bill, Expense, Payment
    from sqlalchemy import func

    # Total invoiced (current FY)
    from datetime import date
    today = date.today()
    fy_start = date(today.year, 4, 1) if today.month >= 4 else date(today.year - 1, 4, 1)

    total_invoiced = db.query(func.coalesce(func.sum(Invoice.total), 0)).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
        Invoice.status.notin_(["DRAFT", "CANCELLED"]),
        Invoice.issue_date >= fy_start,
    ).scalar() or 0

    total_collected = db.query(func.coalesce(func.sum(Payment.amount), 0)).filter(
        Payment.tenant_id == tenant_id,
        Payment.deleted_at == None,
        Payment.status == "ACTIVE",
        Payment.payment_date >= fy_start,
    ).scalar() or 0

    total_expenses = db.query(func.coalesce(func.sum(Expense.total), 0)).filter(
        Expense.tenant_id == tenant_id,
        Expense.deleted_at == None,
        Expense.status == "POSTED",
        Expense.expense_date >= fy_start,
    ).scalar() or 0

    outstanding = db.query(
        func.coalesce(func.sum(Invoice.total - Invoice.amount_paid), 0)
    ).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
        Invoice.status.in_(["POSTED", "PARTIALLY_PAID"]),
    ).scalar() or 0

    overdue = db.query(
        func.coalesce(func.sum(Invoice.total - Invoice.amount_paid), 0)
    ).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
        Invoice.status.in_(["POSTED", "PARTIALLY_PAID"]),
        Invoice.due_date < func.current_date(),
    ).scalar() or 0

    return {
        "total_invoiced": float(total_invoiced),
        "total_collected": float(total_collected),
        "total_expenses": float(total_expenses),
        "outstanding": float(outstanding),
        "overdue": float(overdue),
        "net_profit": float(round(total_invoiced - total_expenses, 2)),
    }


@router.get("/overdue-alerts")
def get_overdue_alerts(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    """Returns list of overdue invoices for dashboard alert display."""
    from src.infrastructure.database.models import Invoice, Contact
    from sqlalchemy import func

    today = date.today()
    overdue_invoices = db.query(
        Invoice.id,
        Invoice.invoice_number,
        Invoice.total,
        Invoice.amount_paid,
        Invoice.due_date,
        Contact.name.label("contact_name"),
    ).join(Contact, Invoice.contact_id == Contact.id).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.deleted_at == None,
        Invoice.status.in_(["POSTED", "PARTIALLY_PAID"]),
        Invoice.due_date < today,
    ).order_by(Invoice.due_date.asc()).limit(20).all()

    alerts = []
    for inv in overdue_invoices:
        days_overdue = (today - inv.due_date).days
        balance = float(inv.total - inv.amount_paid)
        alerts.append({
            "id": str(inv.id),
            "invoice_number": inv.invoice_number,
            "contact_name": inv.contact_name,
            "balance": balance,
            "due_date": inv.due_date.isoformat(),
            "days_overdue": days_overdue,
            "severity": "critical" if days_overdue > 90 else "high" if days_overdue > 30 else "medium",
        })

    total_overdue_amount = sum(a["balance"] for a in alerts)
    return {
        "alerts": alerts,
        "total_overdue_amount": total_overdue_amount,
        "count": len(alerts),
    }
@router.get("/expense-trend")
def get_expense_trend(
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("expense:view")),
):
    from src.infrastructure.database.models import Expense
    query = db.query(
        func.extract("month", Expense.expense_date).label("month"),
        func.extract("year", Expense.expense_date).label("year"),
        func.coalesce(func.sum(Expense.amount), 0).label("total"),
    ).filter(
        Expense.tenant_id == tenant_id,
        Expense.status == "POSTED",
        Expense.deleted_at == None,
    )
    if date_from and date_to:
        query = query.filter(
            Expense.expense_date >= date.fromisoformat(date_from),
            Expense.expense_date <= date.fromisoformat(date_to),
        )
    else:
        today = date.today()
        try:
            cutoff = today.replace(year=today.year - 1)
        except ValueError:
            cutoff = today.replace(year=today.year - 1, day=28)
        query = query.filter(Expense.expense_date >= cutoff)

    results = query.group_by("year", "month").order_by("year", "month").all()

    return [
        {"month": int(row.month), "year": int(row.year), "total": float(row.total)}
        for row in results
    ]
