import os
import uuid
import logging
from typing import Dict, Any
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from celery import Celery
from celery.schedules import crontab

from src.core.config import settings

logger = logging.getLogger(__name__)

celery_app = Celery("accounting_tasks", broker=settings.REDIS_URL, backend=settings.REDIS_URL)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="Asia/Kolkata",
    enable_utc=True,
    task_acks_late=True,
    task_reject_on_worker_lost=True,
    beat_schedule={
        "send-overdue-invoice-reminders": {
            "task": "tasks.send_overdue_invoice_reminders",
            "schedule": crontab(hour=9, minute=0),  # daily at 9 AM IST
        },
        "gst-filing-deadline-alerts": {
            "task": "tasks.send_gst_filing_alerts",
            "schedule": crontab(day_of_month="10,20", hour=10, minute=0),  # monthly on 10th, 20th
        },
        "generate-monthly-aging-reports": {
            "task": "tasks.generate_monthly_aging_report",
            "schedule": crontab(day_of_month=1, hour=2, minute=0),  # 1st of each month at 2 AM
        },
        "cleanup-expired-invitations": {
            "task": "tasks.cleanup_expired_invitations",
            "schedule": crontab(hour=3, minute=0),  # daily at 3 AM IST
        },
    },
)


@celery_app.task(bind=True, name="tasks.submit_e_invoice_to_irp", max_retries=3, default_retry_delay=60)
def submit_e_invoice_to_irp(self, invoice_id: str) -> Dict[str, Any]:
    """Submits a finalized Invoice payload to the NIC IRP gateway."""
    logger.info(f"Starting e-invoice generation task for Invoice ID: {invoice_id}")
    try:
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import Invoice
        from src.domains.taxation.einvoice_service import EInvoiceService

        # Convert string ID to UUID for SQLAlchemy UUID column compatibility
        invoice_uuid = uuid.UUID(invoice_id) if isinstance(invoice_id, str) else invoice_id

        db = SessionLocal()
        try:
            invoice = db.query(Invoice).filter(Invoice.id == invoice_uuid).first()
            if not invoice:
                logger.error(f"Invoice {invoice_id} not found for e-invoice submission.")
                return {"invoice_id": invoice_id, "status": "FAILED", "error": "Invoice not found"}
            result = EInvoiceService.generate_einvoice(db=db, tenant_id=invoice.tenant_id, invoice_id=invoice.id)
            return {
                "invoice_id": invoice_id,
                "irn": result.get("irn", ""),
                "status": "GENERATED",
            }
        finally:
            db.close()
    except Exception as exc:
        logger.error(f"e-Invoice submission failed for {invoice_id}: {exc}")
        # In eager/test mode, retrying causes infinite loops — skip retry
        if self.request.is_eager:
            raise
        raise self.retry(exc=exc)


@celery_app.task(name="tasks.generate_invoice_pdf")
def generate_invoice_pdf(invoice_id: str) -> str:
    """Generates a PDF copy of the invoice and uploads to S3-compatible storage."""
    logger.info(f"Generating PDF invoice for Invoice ID: {invoice_id}")
    try:
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import Invoice
        from src.domains.printing.invoice_pdf import generate_invoice_pdf as _gen_pdf
        db = SessionLocal()
        try:
            invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
            if not invoice:
                return ""
            pdf_bytes = _gen_pdf(
                invoice_number=invoice.invoice_number,
                issue_date=invoice.issue_date,
                due_date=invoice.due_date,
                customer_name=invoice.contact.name if invoice.contact else "N/A",
                customer_gstin=invoice.contact.gstin if invoice.contact else None,
                items=[],
                subtotal=invoice.subtotal,
                cgst=invoice.cgst_amount,
                sgst=invoice.sgst_amount,
                igst=invoice.igst_amount,
                round_off=invoice.round_off,
                total=invoice.total,
                template="default",
                doc_type="INVOICE",
                tenant_id=invoice.tenant_id,
                db=db,
            )
            # Upload to S3 if configured
            if settings.S3_BUCKET:
                import boto3
                s3 = boto3.client("s3", region_name=settings.S3_REGION)
                key = f"invoices/{invoice_id}.pdf"
                s3.put_object(Bucket=settings.S3_BUCKET, Key=key, Body=pdf_bytes, ContentType="application/pdf")
                return f"s3://{settings.S3_BUCKET}/{key}"
            return f"invoices/{invoice_id}.pdf"
        finally:
            db.close()
    except Exception as e:
        logger.error(f"PDF generation failed for {invoice_id}: {e}")
        return ""


@celery_app.task(name="tasks.send_invoice_email")
def send_invoice_email(invoice_id: str, recipient_email: str) -> bool:
    """Sends the generated PDF invoice to the customer via SMTP."""
    logger.info(f"Sending invoice email to {recipient_email} for Invoice ID: {invoice_id}")
    try:
        import smtplib
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText
        from src.common.email_helper import invoice_email

        subject, html_body = invoice_email(invoice_id)
        msg = MIMEMultipart()
        msg["From"] = settings.EMAIL_FROM
        msg["To"] = recipient_email
        msg["Subject"] = subject
        msg.attach(MIMEText(html_body, "html"))

        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                server.starttls()
                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.send_message(msg)

        logger.info(f"Invoice email dispatched to {recipient_email}")
        return True
    except Exception as e:
        logger.error(f"Failed to send invoice email: {e}")
        return False


# ---------------------------------------------------------------------------
# Scheduled Tasks
# ---------------------------------------------------------------------------

@celery_app.task(name="tasks.send_overdue_invoice_reminders")
def send_overdue_invoice_reminders():
    """Sends overdue invoice reminders to customers daily at 9 AM IST."""
    logger.info("Sending overdue invoice reminders...")
    try:
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import Invoice, Contact, Tenant, TenantSetting
        from src.common.email_helper import invoice_email
        import smtplib
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        db = SessionLocal()
        try:
            today = date.today()
            overdue_invoices = db.query(Invoice, Contact, Tenant).join(
                Contact, Invoice.contact_id == Contact.id
            ).join(
                Tenant, Invoice.tenant_id == Tenant.id
            ).filter(
                Invoice.status.in_(["POSTED", "PARTIALLY_PAID"]),
                Invoice.due_date < today,
                Invoice.deleted_at == None,
            ).all()

            for invoice, contact, tenant in overdue_invoices:
                if not contact.email:
                    continue
                days_overdue = (today - invoice.due_date).days
                subject = f"Payment Reminder: Invoice {invoice.invoice_number} is {days_overdue} days overdue"
                body = f"""
                <p>Dear {contact.name},</p>
                <p>This is a friendly reminder that Invoice <strong>{invoice.invoice_number}</strong>
                for <strong>₹{invoice.total}</strong> is <strong>{days_overdue} days overdue</strong>.</p>
                <p>Please arrange payment at your earliest convenience.</p>
                <p>Regards,<br>{tenant.legal_name}</p>
                """
                msg = MIMEMultipart()
                msg["From"] = settings.EMAIL_FROM
                msg["To"] = contact.email
                msg["Subject"] = subject
                msg.attach(MIMEText(body, "html"))
                try:
                    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
                        if settings.SMTP_USER and settings.SMTP_PASSWORD:
                            server.starttls()
                            server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                        server.send_message(msg)
                    logger.info(f"Overdue reminder sent to {contact.email} for invoice {invoice.invoice_number}")
                except Exception as e:
                    logger.error(f"Failed to send reminder to {contact.email}: {e}")
        finally:
            db.close()
    except Exception as e:
        logger.error(f"Overdue reminder task failed: {e}")


@celery_app.task(name="tasks.send_gst_filing_alerts")
def send_gst_filing_alerts():
    """Sends GST filing deadline alerts to company owners."""
    logger.info("Sending GST filing alerts...")
    try:
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import Tenant, TenantSetting, User, TenantMembership
        import smtplib
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        db = SessionLocal()
        try:
            today = date.today()
            # GSTR-1 due on 11th/13th/31st depending on turnover
            # GSTR-3B due on 20th
            # Simple alert: remind on 5th, 10th, 15th, 18th, 20th
            alert_days = {5: "GST filing approaching", 10: "GSTR-1 due soon", 15: "Mid-month reminder", 18: "GSTR-3B due in 2 days", 20: "GSTR-3B due today"}
            if today.day in alert_days:
                message = alert_days[today.day]
                tenants = db.query(Tenant).filter(Tenant.is_active == True).all()
                for tenant in tenants:
                    owner = db.query(User).join(TenantMembership).filter(
                        TenantMembership.tenant_id == tenant.id,
                        TenantMembership.role == "owner"
                    ).first()
                    if owner and owner.email:
                        body = f"""
                        <p>Hi {owner.full_name},</p>
                        <p><strong>{message}</strong> for {tenant.legal_name}.</p>
                        <p>Please log in to ApexBooks to file your GST returns.</p>
                        """
                        msg = MIMEMultipart()
                        msg["From"] = settings.EMAIL_FROM
                        msg["To"] = owner.email
                        msg["Subject"] = f"GST Filing Alert — {tenant.legal_name}"
                        msg.attach(MIMEText(body, "html"))
                        try:
                            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
                                if settings.SMTP_USER and settings.SMTP_PASSWORD:
                                    server.starttls()
                                    server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                                server.send_message(msg)
                        except Exception as e:
                            logger.error(f"Failed to send GST alert to {owner.email}: {e}")
        finally:
            db.close()
    except Exception as e:
        logger.error(f"GST filing alert task failed: {e}")


@celery_app.task(name="tasks.generate_monthly_aging_report")
def generate_monthly_aging_report():
    """Generates and emails monthly aging reports to company owners."""
    logger.info("Generating monthly aging reports...")
    try:
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import Invoice, Contact, Tenant, TenantMembership, User
        from src.domains.accounting.report_services import AgingService
        import smtplib
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        db = SessionLocal()
        try:
            tenants = db.query(Tenant).filter(Tenant.is_active == True).all()
            for tenant in tenants:
                report = AgingService(db, tenant.id).generate_receivables_aging()
                owner = db.query(User).join(TenantMembership).filter(
                    TenantMembership.tenant_id == tenant.id,
                    TenantMembership.role == "owner"
                ).first()
                if owner and owner.email and report:
                    total_outstanding = sum(bucket.get("total", Decimal("0")) for bucket in report.values())
                    body = f"""
                    <p>Hi {owner.full_name},</p>
                    <p>Your monthly aging report for <strong>{tenant.legal_name}</strong>:</p>
                    <table border="1" cellpadding="8">
                    <tr><th>Bucket</th><th>Amount</th></tr>
                    """
                    for bucket, data in report.items():
                        body += f"<tr><td>{bucket}</td><td>₹{data.get('total', 0)}</td></tr>"
                    body += f"""
                    </table>
                    <p><strong>Total Outstanding: ₹{total_outstanding}</strong></p>
                    """
                    msg = MIMEMultipart()
                    msg["From"] = settings.EMAIL_FROM
                    msg["To"] = owner.email
                    msg["Subject"] = f"Monthly Aging Report — {tenant.legal_name}"
                    msg.attach(MIMEText(body, "html"))
                    try:
                        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
                            if settings.SMTP_USER and settings.SMTP_PASSWORD:
                                server.starttls()
                                server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
                            server.send_message(msg)
                        logger.info(f"Aging report sent to {owner.email}")
                    except Exception as e:
                        logger.error(f"Failed to send aging report to {owner.email}: {e}")
        finally:
            db.close()
    except Exception as e:
        logger.error(f"Monthly aging report task failed: {e}")


@celery_app.task(name="tasks.cleanup_expired_invitations")
def cleanup_expired_invitations():
    """Marks expired tenant invitations as EXPIRED."""
    logger.info("Cleaning up expired invitations...")
    try:
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import TenantInvitation

        db = SessionLocal()
        try:
            expired = db.query(TenantInvitation).filter(
                TenantInvitation.status == "PENDING",
                TenantInvitation.expires_at < datetime.now(timezone.utc)
            ).all()
            for inv in expired:
                inv.status = "EXPIRED"
            db.commit()
            logger.info(f"Expired {len(expired)} invitations")
        finally:
            db.close()
    except Exception as e:
        logger.error(f"Cleanup invitations task failed: {e}")
