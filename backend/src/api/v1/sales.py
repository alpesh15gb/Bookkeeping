from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import text, func
import uuid
from decimal import Decimal
from typing import List, Optional

from src.core.database import get_db_session, tenant_context
from src.infrastructure.database.models import Invoice, Contact
from src.api.deps import enforce_permission

router = APIRouter(prefix="/sales", tags=["Sales Analytics"])

FINALIZED_STATUSES = ["POSTED", "PARTIALLY_PAID", "PAID"]

@router.get("/summary")
def get_sales_summary(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """
    Compiles overall sales KPI metrics from finalized invoices.
    Uses database-level SUM aggregations.
    """
    query = text("""
        SELECT 
            COALESCE(SUM(total), 0) AS total_sales,
            COALESCE(SUM(amount_paid), 0) AS total_received,
            COALESCE(SUM(cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount), 0) AS total_gst
        FROM invoices
        WHERE status IN ('POSTED', 'PARTIALLY_PAID', 'PAID')
          AND deleted_at IS NULL
          AND tenant_id = :tenant_id
    """)
    result = db.execute(query, {'tenant_id': str(tenant_id)}).fetchone()

    total_sales = Decimal(str(result.total_sales)) if result else Decimal("0.00")
    total_received = Decimal(str(result.total_received)) if result else Decimal("0.00")
    total_gst = Decimal(str(result.total_gst)) if result else Decimal("0.00")
    outstanding = total_sales - total_received

    return {
        "total_sales": str(total_sales.quantize(Decimal("0.01"))),
        "total_received": str(total_received.quantize(Decimal("0.01"))),
        "outstanding": str(outstanding.quantize(Decimal("0.01"))),
        "total_gst_liability": str(total_gst.quantize(Decimal("0.01")))
    }

@router.get("/customer-wise")
def get_customer_wise_sales(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """
    Groups finalized sales figures by customer.
    """
    query = text("""
        SELECT 
            c.name AS customer_name,
            COUNT(i.id) AS invoice_count,
            COALESCE(SUM(i.subtotal), 0) AS taxable_amount,
            COALESCE(SUM(i.cgst_amount + i.sgst_amount + i.igst_amount + i.utgst_amount + i.cess_amount), 0) AS tax_amount,
            COALESCE(SUM(i.total), 0) AS total_sales
        FROM contacts c
        JOIN invoices i ON c.id = i.contact_id
        WHERE i.status IN ('POSTED', 'PARTIALLY_PAID', 'PAID')
          AND i.deleted_at IS NULL
          AND c.deleted_at IS NULL
          AND i.tenant_id = :tenant_id
        GROUP BY c.id, c.name
        ORDER BY total_sales DESC
    """)
    results = db.execute(query, {'tenant_id': str(tenant_id)}).fetchall()

    response = []
    for row in results:
        response.append({
            "customer_name": row.customer_name,
            "invoice_count": row.invoice_count,
            "taxable_amount": float(Decimal(str(row.taxable_amount)).quantize(Decimal("0.01"))),
            "tax_amount": float(Decimal(str(row.tax_amount)).quantize(Decimal("0.01"))),
            "total_sales": float(Decimal(str(row.total_sales)).quantize(Decimal("0.01")))
        })
    return response

@router.get("/period-wise")
def get_period_wise_sales(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """
    Groups finalized sales transactions monthly.
    """
    # Dialect-aware query mapping (SQLite for local testing, PostgreSQL for production)
    if db.bind.dialect.name == "sqlite":
        query = text("""
            SELECT 
                strftime('%Y-%m', issue_date) AS month_key,
                COUNT(id) AS invoice_count,
                COALESCE(SUM(total), 0) AS total_sales
            FROM invoices
            WHERE status IN ('POSTED', 'PARTIALLY_PAID', 'PAID')
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
            GROUP BY strftime('%Y-%m', issue_date)
            ORDER BY month_key ASC
        """)
    else:
        query = text("""
            SELECT 
                TO_CHAR(DATE_TRUNC('month', issue_date), 'YYYY-MM') AS month_key,
                COUNT(id) AS invoice_count,
                COALESCE(SUM(total), 0) AS total_sales
            FROM invoices
            WHERE status IN ('POSTED', 'PARTIALLY_PAID', 'PAID')
              AND deleted_at IS NULL
              AND tenant_id = :tenant_id
            GROUP BY DATE_TRUNC('month', issue_date)
            ORDER BY month_key ASC
        """)
        
    results = db.execute(query, {'tenant_id': str(tenant_id)}).fetchall()

    response = []
    for row in results:
        response.append({
            "period": row.month_key,
            "invoice_count": row.invoice_count,
            "total_sales": float(Decimal(str(row.total_sales)).quantize(Decimal("0.01")))
        })
    return response

@router.get("/transactions")
def get_sales_transactions(
    page: int = 1,
    limit: int = 50,
    contact_id: Optional[uuid.UUID] = None,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view"))
):
    """
    Lists paginated details of finalized sales invoices.
    """
    offset = (page - 1) * limit
    q = db.query(Invoice, Contact.name.label("contact_name"))\
        .join(Contact, Invoice.contact_id == Contact.id)\
        .filter(Invoice.tenant_id == tenant_id, Invoice.status.in_(FINALIZED_STATUSES), Invoice.deleted_at == None)

    if contact_id:
        q = q.filter(Invoice.contact_id == contact_id)

    results = q.order_by(Invoice.issue_date.desc()).offset(offset).limit(limit).all()

    response = []
    for inv, contact_name in results:
        response.append({
            "id": inv.id,
            "invoice_number": inv.invoice_number,
            "issue_date": inv.issue_date.isoformat(),
            "customer_name": contact_name,
            "subtotal": float(inv.subtotal.quantize(Decimal("0.01"))),
            "tax_total": float((inv.cgst_amount + inv.sgst_amount + inv.igst_amount + inv.utgst_amount + inv.cess_amount).quantize(Decimal("0.01"))),
            "total": float(inv.total.quantize(Decimal("0.01"))),
            "amount_paid": float(inv.amount_paid.quantize(Decimal("0.01"))),
            "status": inv.status
        })
    return response
