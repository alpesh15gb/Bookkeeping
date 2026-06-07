"""
Reminders CRUD — returns empty data for now.
Frontend handles empty arrays gracefully.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import uuid
from typing import List, Optional

from src.core.database import get_db_session
from src.api.deps import enforce_permission

router = APIRouter(prefix="/reminders", tags=["Reminders"])


@router.get("")
def list_reminders(
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:view")),
):
    from src.infrastructure.database.models import Invoice, Payment, Bill
    from datetime import date
    from sqlalchemy import func
    
    reminders = []
    today = date.today()
    
    # 1. Overdue invoices (payment reminders)
    overdue_invoices = db.query(Invoice).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.status.in_(["POSTED", "PARTIALLY_PAID"]),
        Invoice.due_date < today,
        Invoice.deleted_at == None,
    ).all()
    
    for inv in overdue_invoices:
        contact_name = inv.contact.name if inv.contact else "Customer"
        outstanding = inv.total - inv.amount_paid
        reminders.append({
            "title": f"Payment Overdue: Invoice {inv.invoice_number}",
            "message": f"Invoice for {contact_name} is overdue since {inv.due_date.strftime('%d-%b-%Y')}. Outstanding: ₹{outstanding:,.2f}."
        })
        
    # 2. Daily business summary
    sales_today = db.query(func.coalesce(func.sum(Invoice.total), 0)).filter(
        Invoice.tenant_id == tenant_id,
        Invoice.issue_date == today,
        Invoice.status.notin_(["DRAFT", "CANCELLED"]),
        Invoice.deleted_at == None
    ).scalar()

    receipts_today = db.query(func.coalesce(func.sum(Payment.amount), 0)).filter(
        Payment.tenant_id == tenant_id,
        Payment.payment_date == today,
        Payment.status == "ACTIVE",
        Payment.deleted_at == None
    ).scalar()

    expenses_today = db.query(func.coalesce(func.sum(Bill.total), 0)).filter(
        Bill.tenant_id == tenant_id,
        Bill.issue_date == today,
        Bill.status.notin_(["DRAFT", "CANCELLED"]),
        Bill.deleted_at == None
    ).scalar()
    
    reminders.append({
        "title": f"Daily Business Summary — {today.strftime('%d-%b-%Y')}",
        "message": f"Today's Sales: ₹{sales_today:,.2f} | Receipts: ₹{receipts_today:,.2f} | Expenses/Bills: ₹{expenses_today:,.2f}."
    })
    
    return reminders


@router.post("", status_code=status.HTTP_201_CREATED)
def create_reminder(
):
    return {"message": "Reminder created (stub)"}
