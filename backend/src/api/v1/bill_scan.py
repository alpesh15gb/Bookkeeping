"""
src/api/v1/bill_scan.py

POST /api/v1/bills/scan-preview
  — Upload a photo or PDF of a vendor invoice.
  — OCR extracts fields.
  — Looks up existing vendor by GSTIN / name.
  — Looks up existing products by name / HSN.
  — Returns everything needed for an editable preview. NO DB writes.

POST /api/v1/bills/scan-save
  — Takes the user-edited payload from the preview.
  — Creates missing vendor contact if needed.
  — Creates missing products if needed.
  — Creates the bill.
  — Returns the created bill.
"""
import logging
import asyncio
import base64
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status, Request
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional, List, Dict, Any
from decimal import Decimal
import uuid
from datetime import date

from src.api.deps import enforce_permission
from src.core.database import get_db_session
from src.domains.scanning.invoice_scanner import get_scanner
from src.infrastructure.database.models import Contact, Product, Bill, BillLine
from src.domains.taxation.services import GSTEngine
from src.domains.accounting.services import AccountResolver
from src.domains.company.services import resolve_origin_state_code, NumberingSeriesService
from src.schemas.bill_schemas import BillCreate, BillResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/bills", tags=["Vendor Bills (Purchases)"])

_ALLOWED_TYPES = {
    "image/jpeg", "image/jpg", "image/png", "image/tiff",
    "image/bmp", "image/webp", "application/pdf",
}
_ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".tiff", ".bmp", ".webp", ".pdf"}
_MAX_SIZE_BYTES = 15 * 1024 * 1024  # 15 MB


# ── Shared helpers ───────────────────────────────────────────────────────────

async def _read_and_validate_file(file: UploadFile) -> bytes:
    content_type = (file.content_type or "").lower()
    filename = file.filename or ""
    ext = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""

    if content_type not in _ALLOWED_TYPES and ext not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported file type '{content_type or ext}'. "
                   "Please upload a JPEG, PNG, or PDF file.",
        )

    file_bytes = await file.read()
    if len(file_bytes) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")
    if len(file_bytes) > _MAX_SIZE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({len(file_bytes) // 1024}KB). Maximum is 15MB.",
        )
    return file_bytes


def _run_ocr(file_bytes: bytes, filename: str, confidence: float) -> dict:
    scanner = get_scanner()
    return scanner.scan(
        file_bytes=file_bytes,
        filename=filename,
        confidence_threshold=confidence,
    )


async def _run_ocr_async(file_bytes: bytes, filename: str, confidence: float) -> dict:
    """Run OCR in a thread pool so it doesn't block the event loop."""
    import asyncio
    loop = asyncio.get_event_loop()
    return await asyncio.wait_for(
        loop.run_in_executor(None, _run_ocr, file_bytes, filename, confidence),
        timeout=120.0,
    )


def _lookup_vendor(db: Session, tenant_id: uuid.UUID, vendor_name: Optional[str], vendor_gstin: Optional[str]) -> Optional[Contact]:
    """Find existing vendor by GSTIN or normalized name."""
    if vendor_gstin:
        contact = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            func.upper(Contact.gstin) == vendor_gstin.upper(),
            Contact.deleted_at == None,
        ).first()
        if contact:
            return contact

    if vendor_name:
        normalized = vendor_name.strip().lower()
        contact = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            func.lower(func.trim(Contact.name)) == normalized,
            Contact.deleted_at == None,
        ).first()
        if contact:
            return contact

    return None


def _lookup_product(db: Session, tenant_id: uuid.UUID, name: str, hsn: Optional[str] = None) -> Optional[Product]:
    """Find existing product by name or HSN."""
    if name:
        product = db.query(Product).filter(
            Product.tenant_id == tenant_id,
            func.lower(func.trim(Product.name)) == name.strip().lower(),
            Product.deleted_at == None,
        ).first()
        if product:
            return product

    if hsn:
        product = db.query(Product).filter(
            Product.tenant_id == tenant_id,
            Product.hsn_sac == hsn,
            Product.deleted_at == None,
        ).first()
        if product:
            return product

    return None


def _clean_hsn(hsn: Optional[str]) -> str:
    if hsn and len(hsn) >= 4 and hsn.isdigit():
        clean = hsn
    else:
        clean = "000000"
    if len(clean) < 6:
        clean = clean.ljust(6, "0")
    return clean


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.post(
    "/scan-preview",
    summary="Submit a bill for async OCR scanning (returns job_id for polling)",
    response_class=JSONResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def scan_preview(
    file: UploadFile = File(..., description="JPEG / PNG / PDF of the vendor invoice"),
    confidence: float = Form(default=0.3, ge=0.0, le=1.0),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:create")),
):
    """
    Submit a vendor invoice for async OCR processing.

    Returns a job_id. Poll GET /bills/scan-status/{job_id} for results.
    """
    file_bytes = await _read_and_validate_file(file)

    # Submit to Celery worker (non-blocking)
    job_id = str(uuid.uuid4())
    file_bytes_b64 = base64.b64encode(file_bytes).decode("utf-8")

    try:
        from src.workers.tasks import run_ocr_scan
        run_ocr_scan.delay(job_id, str(tenant_id), file_bytes_b64, file.filename or "", confidence)
    except Exception as e:
        # Fallback: run synchronously if Celery is down
        logger.warning(f"Celery unavailable, running OCR synchronously: {e}")
        try:
            ocr = await _run_ocr_async(file_bytes, file.filename or "", confidence)
            return _build_preview_response(ocr, db, tenant_id)
        except asyncio.TimeoutError:
            raise HTTPException(status_code=504, detail="Scan timed out.")
        except Exception as e2:
            logger.exception(f"Scan error: {e2}")
            raise HTTPException(status_code=500, detail="Scan failed.")

    return JSONResponse(
        status_code=202,
        content={
            "job_id": job_id,
            "status": "pending",
            "message": "OCR processing started. Poll /bills/scan-status/{job_id} for results.",
            "poll_url": f"/api/v1/bills/scan-status/{job_id}",
        },
    )


@router.get(
    "/scan-status/{job_id}",
    summary="Poll OCR scan result",
    response_class=JSONResponse,
)
async def scan_status(
    job_id: str,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:create")),
):
    """Poll for OCR scan results. Returns status + preview data when done."""
    import redis as redis_lib
    from src.core.config import settings

    r = redis_lib.from_url(settings.REDIS_URL)
    data = r.hgetall(f"scan:{job_id}")

    if not data:
        raise HTTPException(status_code=404, detail="Job not found or expired.")

    scan_status = data.get(b"status", b"unknown").decode()
    scan_result = data.get(b"result", b"null").decode()
    scan_error = data.get(b"error", b"").decode()
    progress = data.get(b"progress", b"").decode()

    if scan_status == "done":
        import json
        ocr = json.loads(scan_result)
        return _build_preview_response(ocr, db, tenant_id)
    elif scan_status == "failed":
        raise HTTPException(status_code=500, detail=f"Scan failed: {scan_error}")
    else:
        return JSONResponse(
            status_code=202,
            content={
                "job_id": job_id,
                "status": scan_status,
                "progress": progress,
            },
        )


def _build_preview_response(ocr: dict, db: Session, tenant_id: uuid.UUID) -> dict:
    """Build the editable preview response from OCR results."""
    vendor_name = ocr.get("vendor_name")
    vendor_gstin = ocr.get("vendor_gstin")
    vendor_address = ocr.get("vendor_address")

    existing_vendor = _lookup_vendor(db, tenant_id, vendor_name, vendor_gstin)

    preview_lines: List[Dict[str, Any]] = []
    for line in ocr.get("line_items", []):
        desc = line.get("product_name", "").strip()
        if not desc:
            continue

        hsn = _clean_hsn(line.get("hsn_sac"))
        existing_product = _lookup_product(db, tenant_id, desc, line.get("hsn_sac"))

        preview_lines.append({
            "product_id": str(existing_product.id) if existing_product else None,
            "product_name": desc,
            "product_type": (
                existing_product.product_type
                if existing_product
                else ("SERVICE" if hsn.startswith("99") else "GOODS")
            ),
            "hsn_sac": hsn,
            "quantity": line.get("quantity", 1),
            "rate": line.get("rate", 0.0),
            "gst_rate": line.get("gst_rate", 0.0),
            "discount": 0.0,
            "amount": line.get("amount", 0.0),
            "product_exists": existing_product is not None,
        })

    bill_date = ocr.get("bill_date") or date.today().isoformat()
    due_date = ocr.get("due_date") or bill_date

    return {
        "vendor": {
            "id": str(existing_vendor.id) if existing_vendor else None,
            "name": existing_vendor.name if existing_vendor else vendor_name,
            "gstin": existing_vendor.gstin if existing_vendor else vendor_gstin,
            "address": (
                (existing_vendor.billing_address or {}).get("street", "")
                if existing_vendor else vendor_address
            ),
            "state_code": existing_vendor.state_code if existing_vendor else None,
            "exists": existing_vendor is not None,
        },
        "bill_number": ocr.get("bill_number"),
        "bill_date": bill_date,
        "due_date": due_date,
        "po_number": ocr.get("po_number"),
        "line_items": preview_lines,
        "subtotal": ocr.get("subtotal"),
        "cgst": ocr.get("cgst"),
        "sgst": ocr.get("sgst"),
        "igst": ocr.get("igst"),
        "total": ocr.get("total"),
        "confidence": ocr.get("overall_confidence", 0.0),
        "confidence_scores": ocr.get("confidence_scores", {}),
        "warnings": ocr.get("warnings", []),
    }


@router.post(
    "/scan-save",
    summary="Save a scanned bill — creates missing vendor/products and the bill",
    response_class=JSONResponse,
    status_code=status.HTTP_201_CREATED,
)
def scan_save(
    payload: dict,
    request: Request,
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:create")),
):
    """
    Takes the user-edited payload from `scan-preview` and:
      1. Creates the vendor contact if it doesn't exist.
      2. Creates missing products.
      3. Builds a proper `BillCreate` payload.
      4. Creates the bill via the existing `create_bill` logic.
    """
    vendor_data = payload.get("vendor", {})
    bill_data = payload.get("bill", {})
    line_items_data = payload.get("line_items", [])

    vendor_name = vendor_data.get("name", "").strip()
    vendor_gstin = (vendor_data.get("gstin") or "").strip().upper() or None
    vendor_address = vendor_data.get("address", "")
    state_code = vendor_data.get("state_code", "")

    if not vendor_name:
        raise HTTPException(status_code=400, detail="Vendor name is required.")

    # ── Resolve / create vendor ────────────────────────────────────────────
    contact_id = vendor_data.get("contact_id") or vendor_data.get("id")
    if contact_id:
        # Validate it exists
        try:
            parsed_contact_id = uuid.UUID(str(contact_id))
        except (TypeError, ValueError, AttributeError):
            raise HTTPException(status_code=422, detail="Selected vendor ID is invalid.")
        existing = db.query(Contact).filter(
            Contact.id == parsed_contact_id,
            Contact.tenant_id == tenant_id,
            Contact.deleted_at == None,
        ).first()
        if not existing:
            contact_id = None  # fall through to creation
        else:
            if existing.contact_type == "CUSTOMER":
                existing.contact_type = "BOTH"
                db.flush()

    if not contact_id:
        # Build address dict
        addr = {"street": vendor_address, "city": "", "state": "", "state_code": state_code, "pincode": "000000", "country": "India"}
        if vendor_address:
            parts = [p.strip() for p in vendor_address.split(",") if p.strip()]
            if len(parts) >= 1:
                addr["street"] = parts[0]
            if len(parts) >= 2:
                addr["city"] = parts[-2]
            if len(parts) >= 1:
                addr["state"] = parts[-1]

        new_vendor = Contact(
            tenant_id=tenant_id,
            name=vendor_name,
            contact_type="VENDOR",
            gstin=vendor_gstin,
            billing_address=addr,
            shipping_address=addr,
            state_code=state_code,
            is_active=True,
        )
        db.add(new_vendor)
        db.flush()
        contact_id = str(new_vendor.id)

        # Auto-create AP account
        try:
            resolver = AccountResolver(db, tenant_id)
            resolver.resolve(f"vendor.{new_vendor.id}")
        except Exception as e:
            logger.warning(f"Could not auto-create AP account for vendor {new_vendor.id}: {e}")

    # ── Resolve / create products ──────────────────────────────────────────
    db_lines: List[dict] = []
    for line in line_items_data:
        product_id = line.get("product_id")
        desc = line.get("product_name", "").strip()
        hsn = _clean_hsn(line.get("hsn_sac"))
        qty = Decimal(str(line.get("quantity", 1)))
        rate = Decimal(str(line.get("rate", 0)))
        gst_rate = Decimal(str(line.get("gst_rate", 0)))
        product_type = str(line.get("product_type") or "GOODS").upper()
        if product_type not in {"GOODS", "SERVICE"}:
            raise HTTPException(
                status_code=422,
                detail=f"Item type for '{desc or 'line item'}' must be GOODS or SERVICE.",
            )

        if not desc:
            continue

        if product_id:
            # Validate it exists
            try:
                parsed_product_id = uuid.UUID(str(product_id))
            except (TypeError, ValueError, AttributeError):
                raise HTTPException(status_code=422, detail=f"Invalid product ID for '{desc}'.")
            existing = db.query(Product).filter(
                Product.id == parsed_product_id,
                Product.tenant_id == tenant_id,
                Product.deleted_at == None,
            ).first()
            if existing:
                db_lines.append({
                    "product_id": str(existing.id),
                    "quantity": str(qty),
                    "rate": str(rate),
                    "discount": "0",
                    "hsn_sac": hsn,
                    "gst_rate": str(gst_rate),
                })
                continue

        # Create product if not found
        new_product = Product(
            tenant_id=tenant_id,
            name=desc,
            hsn_sac=hsn,
            product_type=product_type,
            uom="PCS",
            sales_price=Decimal("0.00"),
            purchase_price=rate,
            gst_rate=gst_rate,
            opening_stock=Decimal("0.00"),
            current_stock=Decimal("0.00"),
            reorder_level=Decimal("0.00"),
            is_active=True,
        )
        db.add(new_product)
        db.flush()

        db_lines.append({
            "product_id": str(new_product.id),
            "quantity": str(qty),
            "rate": str(rate),
            "discount": "0",
            "hsn_sac": hsn,
            "gst_rate": str(gst_rate),
        })

    if not db_lines:
        raise HTTPException(status_code=400, detail="At least one line item is required.")

    # ── Build and validate bill payload ────────────────────────────────────
    bill_number = bill_data.get("bill_number", "").strip()
    if not bill_number:
        bill_number = NumberingSeriesService.generate_next_number(db, tenant_id, "BILL")

    issue_date = bill_data.get("issue_date") or date.today().isoformat()
    due_date = bill_data.get("due_date") or issue_date
    pos_state_code = bill_data.get("pos_state_code", state_code)

    if not pos_state_code or len(pos_state_code) != 2:
        pos_state_code = state_code if len(state_code) == 2 else ""

    bill_create_payload = {
        "contact_id": contact_id,
        "bill_number": bill_number,
        "issue_date": issue_date,
        "due_date": due_date,
        "pos_state_code": pos_state_code,
        "line_items": db_lines,
        "discount_rate": "0",
        "shipping_charges": "0",
        "notes": bill_data.get("notes", ""),
        "terms_and_conditions": bill_data.get("terms_and_conditions"),
        "reference_number": bill_data.get("reference_number") or None,
        "tds_rate": "0",
    }

    # ── Create bill using existing logic ───────────────────────────────────
    from src.api.v1.bills import create_bill as _create_bill_core
    try:
        result = _create_bill_core(
            request=request,
            payload=BillCreate(**bill_create_payload),
            db=db,
            tenant_id=tenant_id,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Failed to create bill from scan: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to create bill: {e}")

    return {
        "detail": "Bill created successfully.",
        "bill_id": str(result.id),
        "bill_number": result.bill_number,
        "vendor_id": contact_id,
        "total": str(result.total),
        "line_items_count": len(db_lines),
    }


@router.post(
    "/scan-image",
    summary="Legacy: Scan a purchase bill image or PDF and extract GST fields",
    response_class=JSONResponse,
    status_code=status.HTTP_200_OK,
)
async def scan_bill_image(
    file: UploadFile = File(..., description="JPEG / PNG / PDF of the vendor invoice"),
    confidence: float = Form(default=0.3, ge=0.0, le=1.0,
                             description="Minimum confidence threshold (0–1)"),
    tenant_id: uuid.UUID = Depends(enforce_permission("bill:create")),
):
    """
    Legacy endpoint — returns raw OCR fields without any DB interaction.
    """
    file_bytes = await _read_and_validate_file(file)

    try:
        scanner = get_scanner()
        result = scanner.scan(
            file_bytes=file_bytes,
            filename=file.filename or "",
            confidence_threshold=confidence,
        )
    except RuntimeError as e:
        logger.error(f"Scanner dependency error: {e}")
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        logger.exception(f"Unexpected scan error: {e}")
        raise HTTPException(
            status_code=500,
            detail="An unexpected error occurred during scanning. Please try again.",
        )

    logger.info(
        f"Bill scan complete for tenant={tenant_id}: "
        f"confidence={result.get('overall_confidence', 0):.0%}, "
        f"lines={len(result.get('line_items', []))}"
    )

    return result
