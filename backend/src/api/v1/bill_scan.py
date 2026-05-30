"""
src/api/v1/bill_scan.py

POST /api/v1/bills/scan-image
  — Upload a photo or PDF of a vendor invoice.
  — OCR extracts fields; returns structured JSON preview.
  — Does NOT create a bill.  The Flutter form pre-fills from this response
    and the user reviews before calling POST /api/v1/bills to save.
"""
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from fastapi.responses import JSONResponse
from typing import Optional
import uuid

from src.api.deps import enforce_permission
from src.domains.scanning.invoice_scanner import get_scanner

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/bills", tags=["Vendor Bills (Purchases)"])

# Accepted MIME types / file extensions
_ALLOWED_TYPES = {
    "image/jpeg", "image/jpg", "image/png", "image/tiff",
    "image/bmp", "image/webp", "application/pdf",
}
_ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".tiff", ".bmp", ".webp", ".pdf"}
_MAX_SIZE_BYTES = 15 * 1024 * 1024  # 15 MB


@router.post(
    "/scan-image",
    summary="Scan a purchase bill image or PDF and extract GST fields",
    response_class=JSONResponse,
    status_code=status.HTTP_200_OK,
)
async def scan_bill_image(
    file: UploadFile = File(..., description="JPEG / PNG / PDF of the vendor invoice"),
    confidence: float = Form(default=0.3, ge=0.0, le=1.0,
                             description="Minimum confidence threshold (0–1)"),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """
    Scan a vendor invoice image or PDF using OCR and return extracted fields.

    The response can be used to pre-populate the Create Bill form in the app.
    The bill is **not** saved — the user reviews the data and submits separately.

    ### Extracted fields
    - `vendor_name`, `vendor_gstin`, `vendor_address`
    - `bill_number`, `bill_date`, `due_date`, `po_number`
    - `line_items[]` — description, HSN, qty, rate, gst_rate, amount
    - `subtotal`, `cgst`, `sgst`, `igst`, `total`
    - `confidence_scores` — per-field confidence (0–1)
    - `overall_confidence` — fraction of fields successfully extracted
    - `warnings` — any issues encountered during extraction
    """

    # ── Validate content type ──────────────────────────────────────────────
    content_type = (file.content_type or "").lower()
    filename = file.filename or ""
    ext = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""

    if content_type not in _ALLOWED_TYPES and ext not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=(
                f"Unsupported file type '{content_type or ext}'. "
                "Please upload a JPEG, PNG, or PDF file."
            ),
        )

    # ── Read and size-check ────────────────────────────────────────────────
    file_bytes = await file.read()
    if len(file_bytes) == 0:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")
    if len(file_bytes) > _MAX_SIZE_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File too large ({len(file_bytes) // 1024}KB). Maximum is 15MB.",
        )

    # ── Run OCR pipeline ───────────────────────────────────────────────────
    try:
        scanner = get_scanner()
        result = scanner.scan(
            file_bytes=file_bytes,
            filename=filename,
            confidence_threshold=confidence,
        )
    except RuntimeError as e:
        # Missing system dependency (Tesseract / poppler not installed)
        logger.error(f"Scanner dependency error: {e}")
        raise HTTPException(
            status_code=503,
            detail=str(e),
        )
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
