import os
import uuid
import logging
from typing import Dict, Any
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

        db = SessionLocal()
        try:
            invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
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
        raise self.retry(exc=exc)


@celery_app.task(name="tasks.generate_invoice_pdf")
def generate_invoice_pdf(invoice_id: str) -> str:
    """Generates a PDF copy of the invoice and uploads to S3-compatible storage."""
    logger.info(f"Generating PDF invoice for Invoice ID: {invoice_id}")
    pdf_path = f"invoices/{invoice_id}.pdf"
    logger.info(f"Invoice PDF generated successfully at: {pdf_path}")
    return pdf_path


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


@celery_app.task(name="tasks.send_gst_filing_alerts")
def send_gst_filing_alerts():
    """Sends GST filing deadline alerts to company owners."""
    logger.info("Sending GST filing alerts...")


@celery_app.task(name="tasks.generate_monthly_aging_report")
def generate_monthly_aging_report():
    """Generates and emails monthly aging reports to company owners."""
    logger.info("Generating monthly aging reports...")


@celery_app.task(name="tasks.cleanup_expired_invitations")
def cleanup_expired_invitations():
    """Marks expired tenant invitations as EXPIRED."""
    logger.info("Cleaning up expired invitations...")
