"""
src/domains/scanning/invoice_scanner.py

OCR-based invoice scanner for extracting GST bill fields from images and PDFs.

Pipeline (mirrors Invoiscope's approach without needing the YOLO model):
  1. Image preprocessing  — deskew, denoise, binarise  (OpenCV)
  2. OCR                  — Tesseract via pytesseract  (same engine as Invoiscope)
  3. Field extraction     — regex patterns for every GST invoice field
  4. Post-processing      — clean, validate, compute confidence scores

Supports: JPEG, PNG, TIFF (images) + PDF (first page converted to image via pdf2image).
"""
from __future__ import annotations

import io
import logging
import re
from datetime import datetime, date
from typing import Optional

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Lazy imports — OCR libs are optional at import time; they raise a clear
# error only when a scan is actually requested.
# ---------------------------------------------------------------------------

def _require_cv2():
    try:
        import cv2
        return cv2
    except ImportError:
        raise RuntimeError(
            "opencv-python-headless is required for bill scanning. "
            "Install it: pip install opencv-python-headless"
        )


def _require_tesseract():
    try:
        import pytesseract
        return pytesseract
    except ImportError:
        raise RuntimeError(
            "pytesseract is required for bill scanning. "
            "Install it: pip install pytesseract  (also install Tesseract binary)"
        )


def _require_numpy():
    try:
        import numpy as np
        return np
    except ImportError:
        raise RuntimeError("numpy is required: pip install numpy")


def _require_pil():
    try:
        from PIL import Image
        return Image
    except ImportError:
        raise RuntimeError("Pillow is required: pip install Pillow")


# ---------------------------------------------------------------------------
# GST regex patterns — each returns the raw matched text
# ---------------------------------------------------------------------------

# GSTIN: 2 digits state + 10 alphanum PAN + 1 digit entity + 1 Z + 1 check
_RE_GSTIN = re.compile(
    r'\b(\d{2}[A-Z]{5}\d{4}[A-Z]{1}\d{1}Z[A-Z\d]{1})\b',
    re.IGNORECASE,
)

# Invoice / Bill number — common patterns seen on Indian invoices
_RE_INV_NUMBER = re.compile(
    r'(?:invoice\s*(?:no|number|#|num)[.:]\s*|bill\s*(?:no|number|#)[.:]\s*|inv\s*(?:no|#)[.:]\s*)'
    r'([A-Z0-9/\-_]+)',
    re.IGNORECASE,
)

# Date patterns: DD/MM/YYYY, DD-MM-YYYY, YYYY-MM-DD, DD MMM YYYY
_RE_DATE_DMY   = re.compile(r'\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})\b')
_RE_DATE_YMD   = re.compile(r'\b(\d{4})[/\-\.](\d{2})[/\-\.](\d{2})\b')
_RE_DATE_WORDS = re.compile(
    r'\b(\d{1,2})\s*(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|'
    r'may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|'
    r'nov(?:ember)?|dec(?:ember)?)\s*(\d{4})\b',
    re.IGNORECASE,
)

_MONTH_MAP = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
}

# Amount — Indian number format: optional ₹/Rs, digits with commas, decimal
_RE_AMOUNT = re.compile(r'(?:Rs\.?|INR|₹)?\s*(\d{1,3}(?:[,\s]\d{2,3})*(?:\.\d{2})?)')

# Total / Grand total line
_RE_TOTAL = re.compile(
    r'(?:grand\s*total|total\s*amount|amount\s*payable|net\s*payable|'
    r'invoice\s*total|bill\s*total)\s*[:\-]?\s*'
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

# Taxable amount / subtotal
_RE_SUBTOTAL = re.compile(
    r'(?:taxable\s*(?:amount|value)|subtotal|sub\s*total|value\s*before\s*tax)'
    r'\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

# CGST, SGST, IGST amounts
_RE_CGST = re.compile(
    r'cgst\s*(?:@\s*[\d.]+%?)?\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)
_RE_SGST = re.compile(
    r'sgst\s*(?:@\s*[\d.]+%?)?\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)
_RE_IGST = re.compile(
    r'igst\s*(?:@\s*[\d.]+%?)?\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

# PO number
_RE_PO = re.compile(
    r'(?:p\.?o\.?\s*(?:no|number|#)[.:]\s*|purchase\s*order\s*(?:no|#)[.:]\s*)'
    r'([A-Z0-9/\-_]+)',
    re.IGNORECASE,
)

# Due date
_RE_DUE = re.compile(
    r'(?:due\s*date|payment\s*due)[:\s]+([^\n]+)',
    re.IGNORECASE,
)

# HSN code (4–8 digits)
_RE_HSN = re.compile(r'\b(\d{4,8})\b')

# Company / Vendor name — first non-empty line of OCR output often contains it
# (heuristic: take first line with >= 3 words or line before "GSTIN")


# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

def _clean_amount(raw: str) -> Optional[float]:
    """Remove commas/spaces and convert to float."""
    try:
        return float(raw.replace(',', '').replace(' ', ''))
    except (ValueError, AttributeError):
        return None


def _parse_date(text: str) -> Optional[str]:
    """Try multiple date formats and return ISO YYYY-MM-DD string or None."""
    # DD/MM/YYYY or DD-MM-YYYY
    m = _RE_DATE_DMY.search(text)
    if m:
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if 1 <= d <= 31 and 1 <= mo <= 12 and 2000 <= y <= 2099:
            try:
                return date(y, mo, d).isoformat()
            except ValueError:
                pass

    # YYYY-MM-DD
    m = _RE_DATE_YMD.search(text)
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if 2000 <= y <= 2099 and 1 <= mo <= 12 and 1 <= d <= 31:
            try:
                return date(y, mo, d).isoformat()
            except ValueError:
                pass

    # DD MMM YYYY
    m = _RE_DATE_WORDS.search(text)
    if m:
        d = int(m.group(1))
        mo = _MONTH_MAP.get(m.group(2)[:3].lower(), 0)
        y = int(m.group(3))
        if 1 <= d <= 31 and mo and 2000 <= y <= 2099:
            try:
                return date(y, mo, d).isoformat()
            except ValueError:
                pass

    return None


def _extract_vendor_name(lines: list[str]) -> Optional[str]:
    """
    Heuristic: look for the first substantial line that appears before
    the GSTIN line.  On most Indian invoices the vendor name is at the top.
    """
    gstin_line_idx = None
    for i, line in enumerate(lines):
        if _RE_GSTIN.search(line):
            gstin_line_idx = i
            break

    candidates = lines[:gstin_line_idx] if gstin_line_idx else lines[:10]
    for line in candidates:
        line = line.strip()
        # Skip if it's a label keyword, too short, or all digits
        if (len(line) > 4
                and not re.fullmatch(r'[\d\s/\-.,]+', line)
                and not re.match(r'(?:tax|gst|invoice|bill|date|gstin|pan|address|phone|mob|tel|fax|email)', line, re.I)):
            return line

    return None


def _compute_confidence(data: dict) -> dict:
    """
    Simple confidence: number of found fields / total expected fields.
    Returns per-field confidence (1.0 if found, 0.0 if not).
    """
    key_fields = [
        'vendor_name', 'vendor_gstin', 'bill_number', 'bill_date',
        'subtotal', 'cgst', 'sgst', 'igst', 'total',
    ]
    scores = {}
    for f in key_fields:
        val = data.get(f)
        scores[f] = 1.0 if val not in (None, '', [], 0.0, 0) else 0.0
    return scores


# ---------------------------------------------------------------------------
# Image pre-processing (same pipeline as Invoiscope's ocr_processor.py)
# ---------------------------------------------------------------------------

def _preprocess_image(image_bytes: bytes):
    """
    Return a pre-processed grayscale image (numpy array) optimised for OCR.
    Steps: decode → grayscale → contrast boost → upscale → adaptive threshold.
    """
    cv2 = _require_cv2()
    np = _require_numpy()

    # Decode from bytes
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image bytes — unsupported format?")

    # Grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Contrast enhancement (alpha=1.3 brightness=10)
    enhanced = cv2.convertScaleAbs(gray, alpha=1.3, beta=10)

    # Upscale 2× for better character recognition (same as Invoiscope)
    h, w = enhanced.shape
    resized = cv2.resize(enhanced, (w * 2, h * 2), interpolation=cv2.INTER_CUBIC)

    # Adaptive thresholding to binarise
    binary = cv2.adaptiveThreshold(
        resized, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY, 31, 11,
    )

    # Noise removal
    denoised = cv2.medianBlur(binary, 3)
    return denoised


def _pdf_to_image_bytes(pdf_bytes: bytes) -> bytes:
    """Convert first page of PDF to JPEG bytes using pdf2image / poppler."""
    try:
        from pdf2image import convert_from_bytes
    except ImportError:
        raise RuntimeError(
            "pdf2image is required for PDF scanning: pip install pdf2image  "
            "(also install poppler-utils in Docker)"
        )

    pages = convert_from_bytes(pdf_bytes, dpi=200, first_page=1, last_page=1)
    if not pages:
        raise ValueError("PDF appears to be empty — no pages found.")

    buf = io.BytesIO()
    pages[0].save(buf, format="JPEG", quality=90)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Main scanner class
# ---------------------------------------------------------------------------

class InvoiceScanner:
    """
    Stateless invoice scanner.  Instantiate once and call `scan()` many times.

    Mirrors the Invoiscope OCR pipeline:
      preprocess → tesseract OCR → regex field extraction → confidence scoring

    Does NOT require the YOLOv9c model — runs entirely on Tesseract + regex,
    which is sufficient for structured Indian GST bills.
    """

    # Tesseract page-segmentation modes to try (most bills are full pages)
    _PSM_MODES = ["--psm 6", "--psm 3", "--psm 4"]

    def scan(self, file_bytes: bytes, filename: str = "", confidence_threshold: float = 0.3) -> dict:
        """
        Scan a purchase bill image or PDF and return extracted GST fields.

        Args:
            file_bytes:           Raw bytes of JPEG / PNG / TIFF / PDF file.
            filename:             Original filename (used to detect PDF).
            confidence_threshold: Minimum overall confidence to include result
                                  (0–1 float; lower = more permissive).

        Returns:
            dict with keys:
              vendor_name, vendor_gstin, vendor_address,
              bill_number, bill_date, due_date, po_number,
              line_items (list), subtotal, cgst, sgst, igst, total,
              confidence_scores (dict), overall_confidence (float), warnings (list)
        """
        warnings: list[str] = []

        # ── 1. Convert PDF to image if needed ──────────────────────────────
        lower_name = filename.lower()
        if lower_name.endswith(".pdf") or file_bytes[:4] == b"%PDF":
            try:
                image_bytes = _pdf_to_image_bytes(file_bytes)
            except Exception as e:
                logger.warning(f"PDF conversion failed: {e}")
                warnings.append(f"PDF conversion warning: {e}")
                image_bytes = file_bytes  # try anyway
        else:
            image_bytes = file_bytes

        # ── 2. Preprocess ──────────────────────────────────────────────────
        try:
            processed = _preprocess_image(image_bytes)
        except Exception as e:
            logger.error(f"Image preprocessing failed: {e}")
            return self._empty_result([f"Image could not be processed: {e}"])

        # ── 3. OCR — try multiple PSM modes, pick best result ──────────────
        pytesseract = _require_tesseract()
        Image = _require_pil()
        import numpy as np

        # Convert numpy array back to PIL Image for pytesseract
        pil_img = Image.fromarray(processed)

        raw_text = ""
        for psm in self._PSM_MODES:
            config = f"{psm} --oem 3 -l eng"
            try:
                text = pytesseract.image_to_string(pil_img, config=config)
                if len(text.strip()) > len(raw_text.strip()):
                    raw_text = text
            except Exception as e:
                logger.debug(f"OCR PSM mode {psm} failed: {e}")

        if not raw_text.strip():
            return self._empty_result(["OCR produced no text — check image quality or Tesseract installation."])

        logger.debug(f"OCR text ({len(raw_text)} chars):\n{raw_text[:500]}")

        # ── 4. Extract fields via regex ────────────────────────────────────
        lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
        result = self._extract_fields(raw_text, lines, warnings)

        # ── 5. Confidence scoring ──────────────────────────────────────────
        scores = _compute_confidence(result)
        found = sum(1 for v in scores.values() if v > 0)
        overall = round(found / max(len(scores), 1), 2)
        result["confidence_scores"] = scores
        result["overall_confidence"] = overall
        result["warnings"] = warnings

        if overall < confidence_threshold:
            warnings.append(
                f"Low confidence ({overall:.0%}) — the image may be blurry, "
                "skewed, or the bill format is unusual. Please verify all fields."
            )

        return result

    # ------------------------------------------------------------------
    def _extract_fields(self, text: str, lines: list[str], warnings: list[str]) -> dict:
        """Run all regex patterns and return structured dict."""

        # ── Vendor name (heuristic first-line) ────────────────────────────
        vendor_name = _extract_vendor_name(lines)

        # ── GSTIN ─────────────────────────────────────────────────────────
        gstins = _RE_GSTIN.findall(text)
        # Usually 2 GSTINs: vendor (first) and buyer (second)
        vendor_gstin = gstins[0].upper() if gstins else None

        # ── Vendor address ─────────────────────────────────────────────────
        vendor_address = self._extract_address(lines, vendor_gstin)

        # ── Bill / Invoice number ──────────────────────────────────────────
        m = _RE_INV_NUMBER.search(text)
        bill_number = m.group(1).strip() if m else None

        # ── Dates ──────────────────────────────────────────────────────────
        # Find all date-like strings in text; first is usually invoice date
        all_dates = []
        for m in _RE_DATE_DMY.finditer(text):
            d = _parse_date(m.group(0))
            if d:
                all_dates.append(d)
        for m in _RE_DATE_YMD.finditer(text):
            d = _parse_date(m.group(0))
            if d and d not in all_dates:
                all_dates.append(d)
        for m in _RE_DATE_WORDS.finditer(text):
            d = _parse_date(m.group(0))
            if d and d not in all_dates:
                all_dates.append(d)

        all_dates = sorted(set(all_dates))
        bill_date = all_dates[0] if all_dates else None

        # Due date — look for explicit label first
        due_date = None
        m = _RE_DUE.search(text)
        if m:
            due_date = _parse_date(m.group(1))
        if not due_date and len(all_dates) >= 2:
            due_date = all_dates[-1]  # last date is often due date

        # ── PO number ─────────────────────────────────────────────────────
        m = _RE_PO.search(text)
        po_number = m.group(1).strip() if m else None

        # ── Tax amounts ────────────────────────────────────────────────────
        total   = self._extract_amount(_RE_TOTAL, text)
        subtotal = self._extract_amount(_RE_SUBTOTAL, text)
        cgst    = self._extract_amount(_RE_CGST, text)
        sgst    = self._extract_amount(_RE_SGST, text)
        igst    = self._extract_amount(_RE_IGST, text)

        # If we got CGST+SGST but no subtotal, try to derive it
        if subtotal is None and total is not None and cgst is not None and sgst is not None:
            subtotal = round(total - cgst - sgst - (igst or 0), 2)

        # ── Line items (table rows) ────────────────────────────────────────
        line_items = self._extract_line_items(text, lines, warnings)

        return {
            "vendor_name":    vendor_name,
            "vendor_gstin":   vendor_gstin,
            "vendor_address": vendor_address,
            "bill_number":    bill_number,
            "bill_date":      bill_date,
            "due_date":       due_date,
            "po_number":      po_number,
            "line_items":     line_items,
            "subtotal":       subtotal,
            "cgst":           cgst,
            "sgst":           sgst,
            "igst":           igst,
            "total":          total,
        }

    # ------------------------------------------------------------------
    def _extract_amount(self, pattern: re.Pattern, text: str) -> Optional[float]:
        m = pattern.search(text)
        if not m:
            return None
        return _clean_amount(m.group(1))

    # ------------------------------------------------------------------
    def _extract_address(self, lines: list[str], gstin: Optional[str]) -> Optional[str]:
        """
        Extract vendor address: lines between vendor name and GSTIN / phone.
        """
        if not gstin:
            return None

        addr_parts = []
        collecting = False
        for line in lines:
            if collecting:
                if _RE_GSTIN.search(line) or re.search(r'(?:ph|phone|mob|tel|email|fax)[:\s]', line, re.I):
                    break
                if len(line) > 4:
                    addr_parts.append(line)
                if len(addr_parts) >= 4:
                    break
            elif re.search(r'(?:address|add\.?)[:\s]', line, re.I):
                collecting = True

        return ", ".join(addr_parts) if addr_parts else None

    # ------------------------------------------------------------------
    def _extract_line_items(self, text: str, lines: list[str], warnings: list[str]) -> list:
        """
        Parse line items from the invoice table.
        Strategy: look for lines that have qty × rate × amount pattern.
        """
        items = []

        # Pattern: description  HSN  Qty  Rate  Amount  (common Indian GST invoice layout)
        # We look for lines with at least 2 numeric groups
        line_pattern = re.compile(
            r'^(.+?)\s+'           # description (greedy up to numbers)
            r'(\d{4,8})?\s*'       # optional HSN
            r'(\d+(?:\.\d+)?)\s+'  # quantity
            r'(\d[\d,]+(?:\.\d+)?)\s+'  # rate
            r'(\d[\d,]+(?:\.\d+)?)$',   # amount
        )

        # Find the table section — look for header keywords
        in_table = False
        for line in lines:
            line_lower = line.lower()

            # Start of table
            if re.search(r'(?:description|item|particulars|goods|product)', line_lower):
                in_table = True
                continue

            # End of table
            if in_table and re.search(r'(?:subtotal|total|taxable|cgst|sgst|igst)', line_lower):
                break

            if not in_table:
                continue

            m = line_pattern.match(line)
            if m:
                desc   = m.group(1).strip()
                hsn    = m.group(2) or ""
                qty    = float(m.group(3))
                rate   = _clean_amount(m.group(4)) or 0.0
                amount = _clean_amount(m.group(5)) or 0.0

                if qty > 0 and rate > 0:
                    gst_rate = 0.0
                    # Try to get GST rate from the description line or next line
                    # Common: "18%" or "@18%" or "GST 18%"
                    gst_m = re.search(r'@?\s*(\d+(?:\.\d+)?)\s*%', desc)
                    if gst_m:
                        gst_rate = float(gst_m.group(1))
                        desc = desc[:gst_m.start()].strip()

                    items.append({
                        "description": desc,
                        "hsn":         hsn,
                        "qty":         qty,
                        "rate":        rate,
                        "gst_rate":    gst_rate,
                        "amount":      amount,
                    })

        if not items:
            warnings.append(
                "Line items could not be automatically extracted — "
                "please add them manually after reviewing the other fields."
            )

        return items

    # ------------------------------------------------------------------
    @staticmethod
    def _empty_result(warnings: list[str]) -> dict:
        return {
            "vendor_name":       None,
            "vendor_gstin":      None,
            "vendor_address":    None,
            "bill_number":       None,
            "bill_date":         None,
            "due_date":          None,
            "po_number":         None,
            "line_items":        [],
            "subtotal":          None,
            "cgst":              None,
            "sgst":              None,
            "igst":              None,
            "total":             None,
            "confidence_scores": {},
            "overall_confidence": 0.0,
            "warnings":          warnings,
        }


# ---------------------------------------------------------------------------
# Module-level singleton (loaded once at startup via FastAPI lifespan)
# ---------------------------------------------------------------------------

_scanner: Optional[InvoiceScanner] = None


def get_scanner() -> InvoiceScanner:
    """Return the singleton InvoiceScanner, creating it if necessary."""
    global _scanner
    if _scanner is None:
        _scanner = InvoiceScanner()
        logger.info("InvoiceScanner initialised (Tesseract OCR pipeline)")
    return _scanner
