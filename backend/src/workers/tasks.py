import os
import uuid
import logging
from contextlib import contextmanager
from typing import Dict, Any
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from sqlalchemy import text
from celery.schedules import crontab

from src.core.config import settings
from src.core.celery import celery_app
from src.core.database import SessionLocal, set_db_tenant_context, tenant_context

logger = logging.getLogger(__name__)


# Schedule updates to the imported app (idempotent if already set)
celery_app.conf.beat_schedule = celery_app.conf.beat_schedule or {}
celery_app.conf.beat_schedule.update({
    "deliver-cartunez-master-data": {
        "task": "tasks.deliver_cartunez_master_data",
        "schedule": 30.0,
    },
    "send-overdue-invoice-reminders": {
        "task": "tasks.send_overdue_invoice_reminders",
        "schedule": crontab(hour=9, minute=0),
    },
    "gst-filing-deadline-alerts": {
        "task": "tasks.send_gst_filing_alerts",
        "schedule": crontab(day_of_month="10,20", hour=10, minute=0),
    },
    "generate-monthly-aging-reports": {
        "task": "tasks.generate_monthly_aging_report",
        "schedule": crontab(day_of_month=1, hour=2, minute=0),
    },
    "cleanup-expired-invitations": {
        "task": "tasks.cleanup_expired_invitations",
        "schedule": crontab(hour=3, minute=0),
    },
    "send-daily-business-summary": {
        "task": "tasks.send_daily_business_summary",
        "schedule": crontab(hour=21, minute=0),
    },
})


def _find_without_rls(db, model, *filters):
    """Resolve a row when the tenant is not yet known (task entry point).

    Temporarily disables row-level security for the current transaction so an
    object can be located by ID alone, then re-enables it under the object's
    tenant so the remainder of the task runs with RLS enforced.
    ``SET LOCAL row_security = off`` requires table ownership — the migration
    user owns the schema. No-op on SQLite.
    """
    if db.get_bind().dialect.name == "sqlite":
        return db.query(model).filter(*filters).first()
    db.connection().execute(text("SET LOCAL row_security = off"))
    obj = db.query(model).filter(*filters).first()
    if obj is not None:
        db.connection().execute(text("SET LOCAL row_security = on"))
        set_db_tenant_context(db, obj.tenant_id)
    return obj


@contextmanager
def _tenant_scope(db, tenant_id):
    set_db_tenant_context(db, tenant_id)
    try:
        yield
    finally:
        tenant_context.set(None)


@celery_app.task(name="tasks.deliver_cartunez_master_data")
def deliver_cartunez_master_data() -> Dict[str, Any]:
    """Deliver pending Contract v1 ApexBooks-owned master-data events."""
    from src.integrations.cartunez.outbound import CartunezOutboundDispatcher

    db = SessionLocal()
    try:
        # Cross-tenant webhook queue — dispatch regardless of tenant isolation.
        if db.get_bind().dialect.name != "sqlite":
            db.connection().execute(text("SET LOCAL row_security = off"))
        return CartunezOutboundDispatcher().dispatch_pending(db)
    finally:
        tenant_context.set(None)
        db.close()


@celery_app.task(bind=True, name="tasks.submit_e_invoice_to_irp", max_retries=3, default_retry_delay=60)
def submit_e_invoice_to_irp(self, invoice_id: str) -> Dict[str, Any]:
    """Submits a finalized Invoice payload to the NIC IRP gateway."""
    logger.info(f"Starting e-invoice generation task for Invoice ID: {invoice_id}")
    try:
        from src.infrastructure.database.models import Invoice
        from src.domains.taxation.einvoice_service import EInvoiceService

        # Convert string ID to UUID for SQLAlchemy UUID column compatibility
        invoice_uuid = uuid.UUID(invoice_id) if isinstance(invoice_id, str) else invoice_id

        db = SessionLocal()
        try:
            invoice = _find_without_rls(db, Invoice, Invoice.id == invoice_uuid)
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
        from src.infrastructure.database.models import Invoice
        from src.domains.printing.invoice_pdf import generate_invoice_pdf as _gen_pdf
        db = SessionLocal()
        try:
            invoice = _find_without_rls(db, Invoice, Invoice.id == invoice_id)
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
                customer_address=invoice.contact.billing_address if invoice.contact else None,
            )
            # Upload to S3 if configured
            if settings.S3_BUCKET:
                try:
                    import boto3
                    s3 = boto3.client("s3", region_name=settings.S3_REGION)
                    key = f"invoices/{invoice_id}.pdf"
                    s3.put_object(Bucket=settings.S3_BUCKET, Key=key, Body=pdf_bytes, ContentType="application/pdf")
                    return f"s3://{settings.S3_BUCKET}/{key}"
                except ImportError:
                    logger.warning(f"boto3 not installed; skipping S3 upload for invoice {invoice_id}")
            return f"invoices/{invoice_id}.pdf"
        finally:
            db.close()
    except Exception as e:
        logger.error(f"PDF generation failed for {invoice_id}: {e}")
        raise


@celery_app.task(bind=True, name="tasks.send_invoice_email", max_retries=3, default_retry_delay=60, time_limit=300, soft_time_limit=280)
def send_invoice_email(self, invoice_id: str, recipient_email: str) -> bool:
    """Sends the generated PDF invoice to the customer via SMTP."""
    logger.info(f"Sending invoice email to {recipient_email} for Invoice ID: {invoice_id}")
    try:
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText
        from src.infrastructure.database.models import Invoice
        from src.common.email_helper import invoice_email, send_email_smtp

        db = SessionLocal()
        try:
            invoice = _find_without_rls(db, Invoice, Invoice.id == invoice_id)
            if not invoice:
                logger.error(f"Invoice {invoice_id} not found for email notification.")
                return False
            company_name = invoice.tenant.legal_name if invoice.tenant else "ApexBooks"
            subject, html_body = invoice_email(invoice.invoice_number, company_name)
            msg = MIMEMultipart()
            msg["From"] = settings.EMAIL_FROM
            msg["To"] = recipient_email
            msg["Subject"] = subject
            msg.attach(MIMEText(html_body, "html"))

            send_email_smtp(msg)
            logger.info(f"Invoice email dispatched to {recipient_email}")
            return True
        finally:
            db.close()
    except Exception as exc:
        logger.error(f"Failed to send invoice email: {exc}")
        try:
            raise self.retry(exc=exc, countdown=2 ** self.request.retries * 60)
        except self.MaxRetriesExceededError:
            logger.error(f"Max retries exceeded for invoice email to {recipient_email}")
            return False


# ---------------------------------------------------------------------------
# Scheduled Tasks
# ---------------------------------------------------------------------------

@celery_app.task(name="tasks.send_overdue_invoice_reminders")
def send_overdue_invoice_reminders():
    """Sends overdue invoice reminders to customers daily at 9 AM IST."""
    logger.info("Sending overdue invoice reminders...")
    try:
        from src.infrastructure.database.models import Invoice, Contact, Tenant
        from src.common.email_helper import send_email_smtp
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        db = SessionLocal()
        try:
            today = date.today()
            tenants = db.query(Tenant).filter(Tenant.deleted_at == None).all()
            for tenant in tenants:
                with _tenant_scope(db, tenant.id):
                    overdue_invoices = db.query(Invoice).filter(
                        Invoice.status.in_(["POSTED", "PARTIALLY_PAID"]),
                        Invoice.due_date < today,
                        Invoice.deleted_at == None,
                    ).all()

                for invoice in overdue_invoices:
                    contact = invoice.contact
                    if not contact or not contact.email:
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
                        send_email_smtp(msg)
                        logger.info(f"Overdue reminder sent to {contact.email} for invoice {invoice.invoice_number}")
                    except Exception as e:
                        logger.error(f"Failed to send reminder to {contact.email}: {e}")
        finally:
            tenant_context.set(None)
            db.close()
    except Exception as e:
        logger.error(f"Overdue reminder task failed: {e}")


@celery_app.task(name="tasks.send_gst_filing_alerts")
def send_gst_filing_alerts():
    """Sends GST filing deadline alerts to company owners."""
    logger.info("Sending GST filing alerts...")
    try:
        from src.infrastructure.database.models import Tenant, User, TenantMembership
        from src.common.email_helper import send_email_smtp
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
                tenants = db.query(Tenant).filter(Tenant.deleted_at == None).all()
                for tenant in tenants:
                    with _tenant_scope(db, tenant.id):
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
                            send_email_smtp(msg)
                        except Exception as e:
                            logger.error(f"Failed to send GST alert to {owner.email}: {e}")
        finally:
            tenant_context.set(None)
            db.close()
    except Exception as e:
        logger.error(f"GST filing alert task failed: {e}")


@celery_app.task(name="tasks.generate_monthly_aging_report")
def generate_monthly_aging_report():
    """Generates and emails monthly aging reports to company owners."""
    logger.info("Generating monthly aging reports...")
    try:
        from src.infrastructure.database.models import Tenant, User, TenantMembership
        from src.domains.accounting.report_services import AgingService
        from src.common.email_helper import send_email_smtp
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        db = SessionLocal()
        try:
            today = date.today()
            tenants = db.query(Tenant).filter(Tenant.deleted_at == None).all()
            for tenant in tenants:
                with _tenant_scope(db, tenant.id):
                    receivables = AgingService.get_receivables(db, tenant.id, today)
                    payables = AgingService.get_payables(db, tenant.id, today)
                    owner = db.query(User).join(TenantMembership).filter(
                        TenantMembership.tenant_id == tenant.id,
                        TenantMembership.role == "owner"
                    ).first()

                if not owner or not owner.email:
                    continue

                def _table(section_title, report):
                    rows = "".join(
                        f"<tr><td>{bucket.label}</td><td>₹{bucket.amount:,.2f}</td></tr>"
                        for bucket in report.bucket_totals
                    )
                    return (
                        f"<p><strong>{section_title}</strong></p>"
                        f"<table border=\"1\" cellpadding=\"8\">"
                        f"<tr><th>Bucket</th><th>Amount</th></tr>{rows}"
                        f"<tr><td><strong>Total Outstanding</strong></td>"
                        f"<td><strong>₹{report.total_outstanding:,.2f}</strong></td></tr></table>"
                    )

                body = f"""
                <p>Hi {owner.full_name},</p>
                <p>Your monthly aging report for <strong>{tenant.legal_name}</strong> as of {today.strftime('%d-%b-%Y')}:</p>
                {_table("Receivables (Customers)", receivables)}
                {_table("Payables (Vendors)", payables)}
                """
                msg = MIMEMultipart()
                msg["From"] = settings.EMAIL_FROM
                msg["To"] = owner.email
                msg["Subject"] = f"Monthly Aging Report — {tenant.legal_name}"
                msg.attach(MIMEText(body, "html"))
                try:
                    send_email_smtp(msg)
                    logger.info(f"Aging report sent to {owner.email}")
                except Exception as e:
                    logger.error(f"Failed to send aging report to {owner.email}: {e}")
        finally:
            tenant_context.set(None)
            db.close()
    except Exception as e:
        logger.error(f"Monthly aging report task failed: {e}")


@celery_app.task(name="tasks.cleanup_expired_invitations")
def cleanup_expired_invitations():
    """Marks expired tenant invitations as EXPIRED."""
    logger.info("Cleaning up expired invitations...")
    try:
        from src.infrastructure.database.models import Tenant, TenantInvitation

        db = SessionLocal()
        try:
            tenants = db.query(Tenant).filter(Tenant.deleted_at == None).all()
            expired_count = 0
            for tenant in tenants:
                with _tenant_scope(db, tenant.id):
                    expired = db.query(TenantInvitation).filter(
                        TenantInvitation.status == "PENDING",
                        TenantInvitation.expires_at < datetime.now(timezone.utc)
                    ).all()
                    for inv in expired:
                        inv.status = "EXPIRED"
                    if expired:
                        db.commit()  # RLS WITH CHECK re-evaluates per tenant — commit in scope
                        expired_count += len(expired)
            logger.info(f"Expired {expired_count} invitations")
        finally:
            tenant_context.set(None)
            db.close()
    except Exception as e:
        logger.error(f"Cleanup invitations task failed: {e}")


@celery_app.task(name="tasks.send_daily_business_summary")
def send_daily_business_summary():
    """Computes and emails daily business summaries to company owners at 9 PM night."""
    logger.info("Generating daily business summaries...")
    try:
        from sqlalchemy import func
        from src.infrastructure.database.models import Tenant, TenantMembership, User, Invoice, Payment, Bill
        from src.common.email_helper import send_email_smtp
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        db = SessionLocal()
        try:
            today = date.today()
            tenants = db.query(Tenant).filter(Tenant.deleted_at == None).all()
            for tenant in tenants:
                with _tenant_scope(db, tenant.id):
                    owner = db.query(User).join(TenantMembership).filter(
                        TenantMembership.tenant_id == tenant.id,
                        TenantMembership.role == "owner"
                    ).first()

                    # Sales today
                    sales_today = db.query(func.coalesce(func.sum(Invoice.total), 0)).filter(
                        Invoice.tenant_id == tenant.id,
                        Invoice.issue_date == today,
                        Invoice.status.notin_(["DRAFT", "CANCELLED"]),
                        Invoice.deleted_at == None
                    ).scalar()

                    # Receipts today
                    receipts_today = db.query(func.coalesce(func.sum(Payment.amount), 0)).filter(
                        Payment.tenant_id == tenant.id,
                        Payment.payment_date == today,
                        Payment.status == "ACTIVE",
                        Payment.deleted_at == None
                    ).scalar()

                    # Expenses today
                    expenses_today = db.query(func.coalesce(func.sum(Bill.total), 0)).filter(
                        Bill.tenant_id == tenant.id,
                        Bill.issue_date == today,
                        Bill.status.notin_(["DRAFT", "CANCELLED"]),
                        Bill.deleted_at == None
                    ).scalar()

                if not owner or not owner.email:
                    continue

                body = f"""
                <p>Hi {owner.full_name},</p>
                <p>Here is tonight's daily business summary for <strong>{tenant.legal_name}</strong> ({today.strftime('%d-%b-%Y')}):</p>
                <ul>
                    <li><strong>Total Sales Invoiced:</strong> ₹{sales_today:,.2f}</li>
                    <li><strong>Total Payments Received:</strong> ₹{receipts_today:,.2f}</li>
                    <li><strong>Total Expenses / Bills:</strong> ₹{expenses_today:,.2f}</li>
                </ul>
                <p>Log in to ApexBooks to view detailed reports.</p>
                <p>Regards,<br>ApexBooks Automated Summary</p>
                """
                msg = MIMEMultipart()
                msg["From"] = settings.EMAIL_FROM
                msg["To"] = owner.email
                msg["Subject"] = f"Daily Business Summary — {tenant.legal_name}"
                msg.attach(MIMEText(body, "html"))
                try:
                    send_email_smtp(msg)
                    logger.info(f"Daily summary sent to {owner.email}")
                except Exception as e:
                    logger.error(f"Failed to send daily summary to {owner.email}: {e}")
        finally:
            tenant_context.set(None)
            db.close()
    except Exception as e:
        logger.error(f"Daily summary task failed: {e}")


# ---------------------------------------------------------------------------
# OCR / Bill Scanning (async via Celery)
# ---------------------------------------------------------------------------

@celery_app.task(name="tasks.run_ocr_scan", time_limit=120, soft_time_limit=110)
def run_ocr_scan(job_id: str, file_bytes_b64: str, filename: str, confidence: float) -> dict:
    """Run OCR in a Celery worker — completely async, never blocks the API server.

    Stores result in Redis for the API to poll.
    """
    import base64
    import json
    import redis as redis_lib

    r = redis_lib.from_url(settings.REDIS_URL)

    try:
        # Update status: processing
        r.hset(f"scan:{job_id}", mapping={"status": "processing", "progress": "OCR started"})
        r.expire(f"scan:{job_id}", 600)  # 10 min TTL

        file_bytes = base64.b64decode(file_bytes_b64)

        # Choose OCR engine
        engine = settings.OCR_ENGINE.lower()

        if engine == "google_vision" and settings.GOOGLE_VISION_API_KEY:
            ocr_result = _run_google_vision(file_bytes, filename, confidence)
        else:
            # PaddleOCR (self-hosted)
            os.environ["FLAGS_enable_pir_in_executor"] = "0"
            os.environ["FLAGS_enable_pir_api"] = "0"
            os.environ["FLAGS_pir_apply_inplace_pass"] = "0"

            from src.domains.scanning.invoice_scanner import InvoiceScanner
            scanner = InvoiceScanner()
            ocr_result = scanner.scan(
                file_bytes=file_bytes,
                filename=filename,
                confidence_threshold=confidence,
            )

        # Store result
        r.hset(f"scan:{job_id}", mapping={
            "status": "done",
            "result": json.dumps(ocr_result, default=str),
        })
        r.expire(f"scan:{job_id}", 600)

        return {"job_id": job_id, "status": "done"}

    except Exception as e:
        logger.error(f"OCR task failed for job {job_id}: {e}")
        r.hset(f"scan:{job_id}", mapping={
            "status": "failed",
            "error": str(e),
        })
        r.expire(f"scan:{job_id}", 600)
        return {"job_id": job_id, "status": "failed", "error": str(e)}


def _run_google_vision(file_bytes: bytes, filename: str, confidence: float) -> dict:
    """Use Google Cloud Vision API for fast (1-3s) OCR."""
    import requests

    # Keep the credential out of URLs, which are commonly logged and cached.
    url = "https://vision.googleapis.com/v1/images:annotate"
    img_b64 = base64.b64encode(file_bytes).decode("utf-8")

    payload = {
        "requests": [{
            "image": {"content": img_b64},
            "features": [
                {"type": "TEXT_DETECTION", "maxResults": 100},
            ],
        }]
    }

    resp = requests.post(
        url,
        headers={"x-goog-api-key": settings.GOOGLE_VISION_API_KEY},
        json=payload,
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()

    annotations = data.get("responses", [{}])[0].get("textAnnotations", [])
    if not annotations:
        return {
            "vendor_name": None, "vendor_gstin": None, "vendor_address": None,
            "bill_number": None, "bill_date": None, "due_date": None,
            "po_number": None, "line_items": [],
            "subtotal": None, "cgst": None, "sgst": None, "igst": None,
            "total": None,
            "confidence_scores": {}, "overall_confidence": 0.0,
            "warnings": ["Google Vision detected no text."],
        }

    # Build word list from Google Vision output
    words = []
    for ann in annotations[1:]:  # skip first (full text)
        text = ann.get("description", "").strip()
        if not text:
            continue
        verts = ann.get("boundingPoly", {}).get("vertices", [])
        if len(verts) >= 2:
            xs = [v.get("x", 0) for v in verts]
            ys = [v.get("y", 0) for v in verts]
            x1, y1, x2, y2 = min(xs), min(ys), max(xs), max(ys)
        else:
            x1, y1, x2, y2 = 0, 0, 0, 0
        words.append({
            "text": text,
            "conf": 0.95,
            "x": x1, "y": y1,
            "w": x2 - x1, "h": y2 - y1,
            "cx": (x1 + x2) // 2,
            "cy": (y1 + y2) // 2,
        })

    # Use same extraction pipeline as PaddleOCR
    from src.domains.scanning.invoice_scanner import InvoiceScanner
    scanner = InvoiceScanner.__new__(InvoiceScanner)
    scanner._ocr_version = 0  # Google Vision

    img_h = max(w["y"] + w["h"] for w in words) if words else 1000
    lines_dict = scanner._group_words_into_lines(words)
    result_data = scanner._extract_fields(words, lines_dict, img_h, [])
    result_data["confidence_scores"] = {"_engine": "google_vision"}
    result_data["overall_confidence"] = 0.95

    return result_data