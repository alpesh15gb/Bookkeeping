"""
src/api/v1/bill_scan.py

POST /api/v1/bills/scan-image
  — Upload a photo or PDF of a vendor invoice.
  — OCR extracts fields; returns structured JSON preview.
  — Does NOT create a bill.  The Flutter form pre-fills from this response
    and the user reviews before calling POST /api/v1/bills to save.

POST /api/v1/bills/scan-and-create
  — Same as scan-image, but also looks up / auto-creates the vendor contact
    and products so the returned payload is ready to POST to /bills.
"""
import logging
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
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
from src.infrastructure.database.models import Contact, Product, Account
from src.domains.accounting.services import AccountResolver

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


@router.post(
    "/scan-and-create",
    summary="Scan a bill, auto-create missing vendor & products, return a ready-to-save bill payload",
    response_class=JSONResponse,
    status_code=status.HTTP_200_OK,
)
async def scan_and_create_bill(
    file: UploadFile = File(..., description="JPEG / PNG / PDF of the vendor invoice"),
    confidence: float = Form(default=0.3, ge=0.0, le=1.0,
                             description="Minimum confidence threshold (0–1)"),
    db: Session = Depends(get_db_session),
    tenant_id: uuid.UUID = Depends(enforce_permission("invoice:create")),
):
    """
    Scan a vendor invoice, then auto-resolve or create:
      • vendor contact (by GSTIN)
      • products (by name + HSN)
    Returns a dict that can be sent straight to POST /api/v1/bills.
    """
    # ── Validate content type ──────────────────────────────────────────────
    content_type = (file.content_type or "").lower()
    filename = file.filename or ""
    ext = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""

    if content_type not in _ALLOWED_TYPES and ext not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Unsupported file type '{content_type or ext}'. "
                   "Please upload a JPEG, PNG, or PDF file.",
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
        ocr_result = scanner.scan(
            file_bytes=file_bytes,
            filename=filename,
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

    created_vendor = None
    created_products: List[dict] = []
    line_item_payloads: List[dict] = []
    warnings = list(ocr_result.get("warnings", []))

    # ── Resolve / create vendor ────────────────────────────────────────────
    vendor_id = None
    vendor_name = ocr_result.get("vendor_name")
    vendor_gstin = ocr_result.get("vendor_gstin")
    vendor_address = ocr_result.get("vendor_address")

    # Try GSTIN lookup first
    if vendor_gstin:
        existing_vendor = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            func.upper(Contact.gstin) == vendor_gstin.upper(),
            Contact.deleted_at == None,
        ).first()
        if existing_vendor:
            vendor_id = existing_vendor.id
            # Ensure type is VENDOR or BOTH
            if existing_vendor.contact_type == "CUSTOMER":
                existing_vendor.contact_type = "BOTH"
                db.commit()
                db.refresh(existing_vendor)

    # Fallback to name lookup
    if vendor_id is None and vendor_name:
        normalized_name = vendor_name.strip().lower()
        existing_vendor = db.query(Contact).filter(
            Contact.tenant_id == tenant_id,
            func.lower(func.trim(Contact.name)) == normalized_name,
            Contact.deleted_at == None,
        ).first()
        if existing_vendor:
            vendor_id = existing_vendor.id
            if existing_vendor.contact_type == "CUSTOMER":
                existing_vendor.contact_type = "BOTH"
                db.commit()
                db.refresh(existing_vendor)

    # Create vendor if still not found
    if vendor_id is None:
        if not vendor_name:
            vendor_name = "Unknown Vendor"

        # Parse state code from GSTIN (first 2 digits)
        state_code = ""
        if vendor_gstin and len(vendor_gstin) >= 2:
            state_code = vendor_gstin[:2]

        # Build address dict
        addr_parts = {"street": vendor_address or "", "city": "", "state": "", "state_code": state_code or "", "pincode": "000000", "country": "India"}
        if vendor_address:
            parts = [p.strip() for p in vendor_address.split(",") if p.strip()]
            if len(parts) >= 1:
                addr_parts["street"] = parts[0]
            if len(parts) >= 2:
                addr_parts["city"] = parts[-2]
            if len(parts) >= 1:
                addr_parts["state"] = parts[-1]

        new_vendor = Contact(
            tenant_id=tenant_id,
            name=vendor_name,
            contact_type="VENDOR",
            gstin=vendor_gstin.upper() if vendor_gstin else None,
            billing_address=addr_parts,
            shipping_address=addr_parts,
            state_code=state_code or "",
            is_active=True,
        )
        db.add(new_vendor)
        db.commit()
        db.refresh(new_vendor)
        vendor_id = new_vendor.id
        created_vendor = {
            "id": str(new_vendor.id),
            "name": new_vendor.name,
            "gstin": new_vendor.gstin,
            "message": "Vendor auto-created from scanned bill.",
        }

        # Auto-create AP account via AccountResolver
        try:
            resolver = AccountResolver(db, tenant_id)
            resolver.resolve(f"vendor.{vendor_id}")
        except Exception as e:
            logger.warning(f"Could not auto-create AP account for vendor {vendor_id}: {e}")

    # ── Resolve / create products ──────────────────────────────────────────
    for line in ocr_result.get("line_items", []):
        desc = line.get("description", "").strip()
        hsn = line.get("hsn", "").strip()
        qty = line.get("qty", 1)
        rate = line.get("rate", 0.0)
        gst_rate = line.get("gst_rate", 0.0)

        if not desc:
            continue

        product_id = None
        # Try exact name match
        existing_product = db.query(Product).filter(
            Product.tenant_id == tenant_id,
            func.lower(func.trim(Product.name)) == desc.lower(),
            Product.deleted_at == None,
        ).first()
        if existing_product:
            product_id = existing_product.id
        else:
            # Try HSN match if available
            if hsn:
                existing_product = db.query(Product).filter(
                    Product.tenant_id == tenant_id,
                    Product.hsn_sac == hsn,
                    Product.deleted_at == None,
                ).first()
                if existing_product:
                    product_id = existing_product.id

        # Create product if not found
        if product_id is None:
            # Clean HSN
            clean_hsn = hsn if (hsn and len(hsn) >= 4 and hsn.isdigit()) else "000000"
            if len(clean_hsn) < 6:
                clean_hsn = clean_hsn.ljust(6, "0")

            new_product = Product(
                tenant_id=tenant_id,
                name=desc,
                hsn_sac=clean_hsn,
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("0.00"),
                purchase_price=Decimal(str(rate)) if rate else Decimal("0.00"),
                gst_rate=Decimal(str(gst_rate)) if gst_rate else Decimal("0.00"),
                opening_stock=Decimal("0.00"),
                current_stock=Decimal("0.00"),
                reorder_level=Decimal("0.00"),
                is_active=True,
            )
            db.add(new_product)
            db.commit()
            db.refresh(new_product)
            product_id = new_product.id
            created_products.append({
                "id": str(new_product.id),
                "name": new_product.name,
                "hsn_sac": new_product.hsn_sac,
                "message": "Product auto-created from scanned bill.",
            })

        line_item_payloads.append({
            "product_id": str(product_id),
            "quantity": str(qty) if qty else "1",
            "rate": str(rate) if rate else "0",
            "discount": "0",
            "hsn_sac": clean_hsn if 'clean_hsn' in dir() else (hsn if hsn else "000000"),
            "gst_rate": str(gst_rate) if gst_rate else "0",
        })

    # ── Build bill payload ─────────────────────────────────────────────────
    bill_date = ocr_result.get("bill_date") or date.today().isoformat()
    due_date = ocr_result.get("due_date") or bill_date

    payload = {
        "contact_id": str(vendor_id),
        "bill_number": ocr_result.get("bill_number") or "",
        "issue_date": bill_date,
        "due_date": due_date,
        "pos_state_code": (vendor_gstin[:2] if vendor_gstin else ""),
        "line_items": line_item_payloads,
        "discount_rate": "0",
        "shipping_charges": "0",
        "notes": f"Auto-created from scanned bill. Vendor: {vendor_name or 'Unknown'}",
        "terms_and_conditions": None,
        "reference_number": ocr_result.get("po_number") or None,
        "tds_rate": "0",
    }

    logger.info(
        f"Scan-and-create for tenant={tenant_id}: vendor={vendor_name} "
        f"(created={created_vendor is not None}), products_created={len(created_products)}, "
        f"line_items={len(line_item_payloads)}"
    )

    return {
        "ocr": ocr_result,
        "bill_payload": payload,
        "created_vendor": created_vendor,
        "created_products": created_products,
        "warnings": warnings,
    }
