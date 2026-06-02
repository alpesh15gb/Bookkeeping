"""
src/domains/scanning/invoice_scanner.py

OCR-based invoice scanner for extracting GST bill fields from images and PDFs.

Pipeline (mirrors Invoiscope's approach without needing the YOLO model):
  1. Image preprocessing  — deskew, denoise, edge-preserve, adaptive threshold
  2. OCR                  — Tesseract via pytesseract with structured data
  3. Field extraction     — regex patterns + structured data fallback
  4. Post-processing      — clean, validate, compute confidence scores

Supports: JPEG, PNG, TIFF (images) + PDF (first page converted to image via pdf2image).
"""
from __future__ import annotations

import io
import logging
import re
from datetime import datetime, date
from typing import Optional, List, Dict, Any
from decimal import Decimal, ROUND_HALF_UP

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

# Invoice / Bill number — many real-world formats
_RE_INV_NUMBER = re.compile(
    r'(?:invoice\s*(?:no|number|#|num|\.|:)?\s*|bill\s*(?:no|number|#)?\s*|'
    r'inv\s*(?:no|#)?\s*|inv\.?\s*|invoice\s*#?\s*)'
    r'[:\-]?\s*'
    r'([A-Z0-9/\-_\.]{3,})',
    re.IGNORECASE,
)

# Fallback: standalone invoice numbers near invoice keyword
_RE_INV_NUMBER_FALLBACK = re.compile(
    r'(?:invoice|bill)[^\n]{0,60}?([A-Z]?\d{3,}[A-Z0-9/\-_]*)',
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

# Amount — Indian number format with proper comma grouping
# Handles: ₹1,234.56  Rs. 1234  INR 1,23,456.78  1234.56
_RE_AMOUNT_STANDALONE = re.compile(
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    re.IGNORECASE,
)

# Total / Grand total / Net Amount / Bill Amount — more comprehensive
_RE_TOTAL = re.compile(
    r'(?:grand\s*total|total\s*amount|amount\s*payable|net\s*(?:amount|payable|total)|'
    r'invoice\s*total|bill\s*total|net\s*payable|total\s*payable|'
    r'amount\s*due|total\s*due|bill\s*amount|net\s*amount|'
    r'final\s*amount|total\s*value|amount)\s*[:\-]?\s*'
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

# Taxable amount / subtotal
_RE_SUBTOTAL = re.compile(
    r'(?:taxable\s*(?:amount|value)|subtotal|sub\s*total|value\s*before\s*tax|'
    r'taxable\s*value|total\s*before\s*tax|amount\s*before\s*tax)'
    r'\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

# CGST, SGST, IGST amounts with more flexible patterns
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
    r'(?:p\.?o\.?\s*(?:no|number|#)[.:]?\s*|purchase\s*order\s*(?:no|#)[.:]?\s*)'
    r'([A-Z0-9/\-_]+)',
    re.IGNORECASE,
)

# Due date with better boundary
_RE_DUE = re.compile(
    r'(?:due\s*date|payment\s*due)[\s:]+([0-9/\-\.A-Za-z]+)',
    re.IGNORECASE,
)

# HSN code (4–8 digits, standalone)
_RE_HSN = re.compile(r'\b(\d{4,8})\b')

# GST rate patterns
_RE_GST_RATE = re.compile(r'(\d+(?:\.\d+)?)\s*%')

# Company suffixes for vendor detection
_RE_COMPANY_SUFFIX = re.compile(
    r'\b(pvt\s+ltd|private\s+limited|ltd|limited|llp|'
    r'enterprises|enterprise|corporation|corp|'
    r'solutions|services|consultants|traders|trading|'
    r'industries|industry|works|engineering|'
    r'goods|suppliers|dealers|distributors)\b',
    re.IGNORECASE,
)

# Common words to skip for vendor name
_RE_VENDOR_SKIP = re.compile(
    r'^(?:tax|gst|invoice|bill|date|gstin|pan|address|phone|mob|tel|fax|email|'
    r'original|duplicate|copy|for|buyer|supplier|vendor|seller|'
    r'ship|to|bill|to|from|qty|quantity|rate|amount|total|subtotal|'
    r'cgst|sgst|igst|tax|hsn|sr|no|item|description|particulars)$',
    re.IGNORECASE,
)


# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

def _clean_amount(raw: str) -> Optional[float]:
    """Remove commas/spaces and convert to float. Handles Indian number format."""
    if not raw:
        return None
    try:
        # Remove all non-digit/non-dot chars
        cleaned = re.sub(r'[^\d.]', '', raw.strip())
        # Handle multiple dots (keep first)
        parts = cleaned.split('.')
        if len(parts) > 2:
            cleaned = parts[0] + '.' + ''.join(parts[1:])
        return float(cleaned) if cleaned else None
    except (ValueError, AttributeError):
        return None


def _parse_date(text: str) -> Optional[str]:
    """Try multiple date formats and return ISO YYYY-MM-DD string or None."""
    if not text:
        return None
    text = text.strip()
    
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


def _extract_all_dates(text: str) -> List[str]:
    """Extract all valid dates from text, deduplicated and sorted."""
    dates = []
    for m in _RE_DATE_DMY.finditer(text):
        d = _parse_date(m.group(0))
        if d and d not in dates:
            dates.append(d)
    for m in _RE_DATE_YMD.finditer(text):
        d = _parse_date(m.group(0))
        if d and d not in dates:
            dates.append(d)
    for m in _RE_DATE_WORDS.finditer(text):
        d = _parse_date(m.group(0))
        if d and d not in dates:
            dates.append(d)
    return sorted(set(dates))


def _extract_vendor_name(lines: list[str], gstin_line_idx: Optional[int] = None) -> Optional[str]:
    """
    Multi-strategy vendor name extraction:
    1. Look for line with company suffix (Pvt Ltd, etc.) before GSTIN
    2. Look for longest all-caps line before GSTIN
    3. First substantial non-skipped line before GSTIN
    """
    candidates = lines[:gstin_line_idx] if gstin_line_idx else lines[:15]
    
    # Strategy 1: Line with company suffix
    for line in candidates:
        stripped = line.strip()
        if (len(stripped) > 4
                and _RE_COMPANY_SUFFIX.search(stripped)
                and not _RE_VENDOR_SKIP.match(stripped)):
            return stripped
    
    # Strategy 2: Longest all-caps/mixed-case line (likely company name)
    best_caps = None
    best_caps_len = 0
    for line in candidates:
        stripped = line.strip()
        if (len(stripped) > 4
                and not re.fullmatch(r'[\d\s/\-.,]+', stripped)
                and not _RE_VENDOR_SKIP.match(stripped)):
            # Prefer lines with more uppercase letters (company names often in caps)
            caps_count = sum(1 for c in stripped if c.isupper())
            if caps_count > best_caps_len:
                best_caps_len = caps_count
                best_caps = stripped
    
    if best_caps and len(best_caps) >= 3:
        return best_caps
    
    # Strategy 3: First substantial line
    for line in candidates:
        stripped = line.strip()
        words = stripped.split()
        if (len(stripped) > 4
                and len(words) >= 2
                and not re.fullmatch(r'[\d\s/\-.,]+', stripped)
                and not _RE_VENDOR_SKIP.match(stripped)):
            return stripped
    
    return None


def _find_gstin_line_idx(lines: list[str]) -> Optional[int]:
    for i, line in enumerate(lines):
        if _RE_GSTIN.search(line):
            return i
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
# Image pre-processing (improved pipeline)
# ---------------------------------------------------------------------------

def _preprocess_image(image_bytes: bytes):
    """
    Return a pre-processed grayscale image (numpy array) optimised for OCR.
    Steps: decode → grayscale → bilateral filter (edge-preserving denoise) →
           deskew → contrast boost → upscale → adaptive threshold → mild denoise.
    """
    cv2 = _require_cv2()
    np = _require_numpy()

    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image bytes — unsupported format?")

    # Grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Deskew if needed
    gray = _deskew(gray)

    # Bilateral filter: removes noise while keeping edges sharp
    denoised = cv2.bilateralFilter(gray, 11, 17, 17)

    # Mild contrast enhancement
    enhanced = cv2.convertScaleAbs(denoised, alpha=1.2, beta=5)

    # Upscale 2× for better character recognition
    h, w = enhanced.shape
    resized = cv2.resize(enhanced, (w * 2, h * 2), interpolation=cv2.INTER_CUBIC)

    # Adaptive thresholding with smaller block for finer control
    binary = cv2.adaptiveThreshold(
        resized, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY, 15, 9,
    )

    # Very mild noise removal
    final = cv2.medianBlur(binary, 3)
    return final


def _deskew(gray):
    """Deskew an image if the skew angle is significant (> 0.5 degrees)."""
    cv2 = _require_cv2()
    np = _require_numpy()
    
    # Detect all non-zero pixels
    coords = np.column_stack(np.where(gray < 255))
    if len(coords) < 100:
        return gray
    
    angle = cv2.minAreaRect(coords)[-1]
    if angle < -45:
        angle = -(90 + angle)
    else:
        angle = -angle
    
    # Only deskew if angle is significant
    if abs(angle) < 0.5:
        return gray
    
    (h, w) = gray.shape[:2]
    center = (w // 2, h // 2)
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    rotated = cv2.warpAffine(gray, M, (w, h),
        flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    return rotated


def _pdf_to_image_bytes(pdf_bytes: bytes) -> bytes:
    """Convert first page of PDF to JPEG bytes using pdf2image / poppler."""
    try:
        from pdf2image import convert_from_bytes
    except ImportError:
        raise RuntimeError(
            "pdf2image is required for PDF scanning: pip install pdf2image  "
            "(also install poppler-utils in Docker)"
        )

    pages = convert_from_bytes(pdf_bytes, dpi=300, first_page=1, last_page=1)
    if not pages:
        raise ValueError("PDF appears to be empty — no pages found.")

    buf = io.BytesIO()
    pages[0].save(buf, format="JPEG", quality=95)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Main scanner class
# ---------------------------------------------------------------------------

class InvoiceScanner:
    """
    Stateless invoice scanner.  Instantiate once and call `scan()` many times.
    """

    def scan(self, file_bytes: bytes, filename: str = "", confidence_threshold: float = 0.3) -> dict:
        """
        Scan a purchase bill image or PDF and return extracted GST fields.
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
                image_bytes = file_bytes
        else:
            image_bytes = file_bytes

        # ── 2. Preprocess ──────────────────────────────────────────────────
        try:
            processed = _preprocess_image(image_bytes)
        except Exception as e:
            logger.error(f"Image preprocessing failed: {e}")
            return self._empty_result([f"Image could not be processed: {e}"])

        # ── 3. OCR with structured data ──────────────────────────────────
        pytesseract = _require_tesseract()
        Image = _require_pil()
        import numpy as np

        pil_img = Image.fromarray(processed)

        # Try multiple configs: PSM 6 (block) is best for structured docs
        raw_text = ""
        best_config = ""
        configs = [
            "--psm 6 --oem 3 -l eng preserve_interword_spaces=1",
            "--psm 3 --oem 3 -l eng preserve_interword_spaces=1",
            "--psm 4 --oem 3 -l eng preserve_interword_spaces=1",
            "--psm 6 --oem 1 -l eng preserve_interword_spaces=1",  # LSTM only
        ]
        
        for config in configs:
            try:
                text = pytesseract.image_to_string(pil_img, config=config)
                stripped = text.strip()
                # Prefer structured text (has newlines) over plain text
                score = len(stripped) + (stripped.count('\n') * 20)
                if score > len(raw_text.strip()) + (raw_text.count('\n') * 20):
                    raw_text = text
                    best_config = config
            except Exception as e:
                logger.debug(f"OCR config {config} failed: {e}")

        if not raw_text.strip():
            return self._empty_result(["OCR produced no text — check image quality or Tesseract installation."])

        logger.debug(f"OCR text ({len(raw_text)} chars, config={best_config}):\n{raw_text[:500]}")

        # Also get structured data for table detection
        structured_data = None
        try:
            structured_data = pytesseract.image_to_data(
                pil_img, 
                config="--psm 6 -l eng",
                output_type=pytesseract.Output.DICT
            )
        except Exception as e:
            logger.debug(f"Structured OCR failed: {e}")

        # ── 4. Extract fields ──────────────────────────────────────────────
        lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
        result = self._extract_fields(raw_text, lines, structured_data, warnings)

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
    def _extract_fields(self, text: str, lines: list[str], structured_data: Optional[dict], warnings: list[str]) -> dict:
        """Run all extraction strategies and return structured dict."""
        
        gstin_line_idx = _find_gstin_line_idx(lines)

        # ── Vendor name ───────────────────────────────────────────────────
        vendor_name = _extract_vendor_name(lines, gstin_line_idx)

        # ── GSTIN ─────────────────────────────────────────────────────────
        gstins = _RE_GSTIN.findall(text)
        vendor_gstin = gstins[0].upper() if gstins else None

        # ── Vendor address ──────────────────────────────────────────────
        vendor_address = self._extract_address(lines, gstin_line_idx)

        # ── Bill / Invoice number ───────────────────────────────────────
        bill_number = self._extract_bill_number(text, lines)

        # ── Dates ───────────────────────────────────────────────────────
        all_dates = _extract_all_dates(text)
        bill_date = all_dates[0] if all_dates else None

        # Due date
        due_date = None
        m = _RE_DUE.search(text)
        if m:
            due_date = _parse_date(m.group(1))
        if not due_date and len(all_dates) >= 2:
            due_date = all_dates[-1]

        # ── PO number ───────────────────────────────────────────────────
        m = _RE_PO.search(text)
        po_number = m.group(1).strip() if m else None

        # ── Tax amounts ────────────────────────────────────────────────
        total = self._extract_amount(_RE_TOTAL, text)
        subtotal = self._extract_amount(_RE_SUBTOTAL, text)
        cgst = self._extract_amount(_RE_CGST, text)
        sgst = self._extract_amount(_RE_SGST, text)
        igst = self._extract_amount(_RE_IGST, text)

        # Fallback: if no total found, look for largest amount in text
        if total is None:
            total = self._find_largest_amount(text)

        # Derive subtotal if missing
        if subtotal is None and total is not None:
            tax_sum = (cgst or 0) + (sgst or 0) + (igst or 0)
            if tax_sum > 0:
                subtotal = round(total - tax_sum, 2)

        # ── Line items ────────────────────────────────────────────────────
        line_items = self._extract_line_items(text, lines, structured_data, warnings)

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
    def _extract_bill_number(self, text: str, lines: list[str]) -> Optional[str]:
        """Extract invoice/bill number with multiple strategies."""
        # Primary regex
        m = _RE_INV_NUMBER.search(text)
        if m:
            val = m.group(1).strip()
            if len(val) >= 2:
                return val
        
        # Fallback: look for pattern near "Invoice" keyword
        m = _RE_INV_NUMBER_FALLBACK.search(text)
        if m:
            val = m.group(1).strip()
            if len(val) >= 2 and not val.lower() in ('date', 'no', 'number'):
                return val
        
        # Fallback 2: look for any alphanumeric pattern with numbers after invoice keyword
        for i, line in enumerate(lines):
            if re.search(r'\binvoice\b', line, re.I):
                # Check next 3 lines
                for j in range(i, min(i+3, len(lines))):
                    m = re.search(r'([A-Z]*\d+[A-Z0-9/\-_\.]+)', lines[j], re.I)
                    if m:
                        val = m.group(1).strip()
                        if len(val) >= 2:
                            return val
        
        return None

    # ------------------------------------------------------------------
    def _extract_amount(self, pattern: re.Pattern, text: str) -> Optional[float]:
        m = pattern.search(text)
        if not m:
            return None
        return _clean_amount(m.group(1))

    # ------------------------------------------------------------------
    def _find_largest_amount(self, text: str) -> Optional[float]:
        """Find the largest standalone amount in text — useful as total fallback."""
        amounts = []
        for m in _RE_AMOUNT_STANDALONE.finditer(text):
            val = _clean_amount(m.group(1))
            if val is not None and val > 0:
                amounts.append(val)
        return max(amounts) if amounts else None

    # ------------------------------------------------------------------
    def _extract_address(self, lines: list[str], gstin_line_idx: Optional[int]) -> Optional[str]:
        """
        Extract vendor address: lines between vendor name and GSTIN / phone.
        """
        addr_parts = []
        collecting = False
        
        for i, line in enumerate(lines):
            if collecting:
                if _RE_GSTIN.search(line) or re.search(r'(?:ph|phone|mob|tel|email|fax)[:\s]', line, re.I):
                    break
                stripped = line.strip()
                if len(stripped) > 3 and not _RE_VENDOR_SKIP.match(stripped):
                    addr_parts.append(stripped)
                if len(addr_parts) >= 5:
                    break
            elif re.search(r'(?:address|add\.?)[:\s]', line, re.I):
                collecting = True
            # Also start collecting a few lines after vendor name area
            elif gstin_line_idx and i > 0 and i < gstin_line_idx and not addr_parts:
                stripped = line.strip()
                if (len(stripped) > 8 
                        and not _RE_GSTIN.search(stripped)
                        and not _RE_VENDOR_SKIP.match(stripped)
                        and not re.search(r'(?:gstin|pan|phone|email)', stripped, re.I)):
                    addr_parts.append(stripped)
        
        # Limit to first 4 lines
        return ", ".join(addr_parts[:4]) if addr_parts else None

    # ------------------------------------------------------------------
    def _extract_line_items(self, text: str, lines: list[str], structured_data: Optional[dict], warnings: list[str]) -> list:
        """
        Parse line items from the invoice table using multiple strategies.
        """
        items = []
        
        # Strategy 1: Structured data (Tesseract image_to_data) for table detection
        if structured_data:
            items = self._extract_line_items_from_structured(structured_data, warnings)
            if items:
                return items
        
        # Strategy 2: Regex-based line matching
        items = self._extract_line_items_regex(text, lines, warnings)
        if items:
            return items
        
        # Strategy 3: Simple amount-only extraction for fallback
        items = self._extract_line_items_fallback(text, lines)
        
        if not items:
            warnings.append(
                "Line items could not be automatically extracted — "
                "please add them manually after reviewing the other fields."
            )
        
        return items

    # ------------------------------------------------------------------
    def _extract_line_items_from_structured(self, data: dict, warnings: list[str]) -> list:
        """Extract line items using Tesseract's structured word data with bounding boxes."""
        items = []
        n_boxes = len(data.get('text', []))
        if n_boxes == 0:
            return items
        
        # Group words by line (same 'line_num')
        lines_dict: Dict[int, List[Dict]] = {}
        for i in range(n_boxes):
            text = data['text'][i].strip()
            conf = int(data['conf'][i])
            if not text or conf < 30:  # Skip low-confidence words
                continue
            line_num = data['line_num'][i]
            if line_num not in lines_dict:
                lines_dict[line_num] = []
            lines_dict[line_num].append({
                'text': text,
                'conf': conf,
                'left': data['left'][i],
                'width': data['width'][i],
            })
        
        # Sort words in each line by x position
        for line_num in lines_dict:
            lines_dict[line_num].sort(key=lambda w: w['left'])
        
        # Try to detect table rows: lines with multiple numeric values
        for line_num in sorted(lines_dict.keys()):
            words = lines_dict[line_num]
            line_text = ' '.join(w['text'] for w in words)
            
            # Skip header/footer lines
            lower = line_text.lower()
            if re.search(r'(?:subtotal|total|tax|cgst|sgst|igst|amount\s*payable|grand\s*total)', lower):
                continue
            if re.search(r'(?:description|item|particulars|goods|product|sr\.?\s*no)', lower):
                continue
            
            # Look for numeric patterns (amounts, quantities)
            numbers = []
            for w in words:
                m = re.match(r'^(\d+(?:\.\d+)?)$', w['text'].replace(',', ''))
                if m:
                    numbers.append(float(m.group(1)))
            
            if len(numbers) >= 2:
                # Try to identify description, HSN, qty, rate, amount
                desc_words = []
                hsn = ""
                qty = 0.0
                rate = 0.0
                amount = 0.0
                
                for w in words:
                    wtext = w['text']
                    # HSN code
                    if re.match(r'^\d{4,8}$', wtext) and not hsn:
                        hsn = wtext
                        continue
                    # Number
                    m = re.match(r'^(\d+(?:\.\d+)?)$', wtext.replace(',', ''))
                    if m:
                        num = float(m.group(1))
                        if qty == 0:
                            qty = num
                        elif rate == 0:
                            rate = num
                        else:
                            amount = num
                    else:
                        desc_words.append(wtext)
                
                desc = ' '.join(desc_words).strip()
                if desc and qty > 0:
                    # Calculate rate if not found but amount is present
                    if rate == 0 and amount > 0 and qty > 0:
                        rate = round(amount / qty, 2)
                    # Calculate amount if not found
                    if amount == 0 and rate > 0:
                        amount = round(qty * rate, 2)
                    
                    gst_rate = 0.0
                    gst_m = _RE_GST_RATE.search(desc)
                    if gst_m:
                        gst_rate = float(gst_m.group(1))
                        desc = _RE_GST_RATE.sub('', desc).strip()
                    
                    items.append({
                        "description": desc,
                        "hsn": hsn,
                        "qty": qty,
                        "rate": rate if rate > 0 else amount / qty if qty > 0 else 0,
                        "gst_rate": gst_rate,
                        "amount": amount if amount > 0 else qty * rate if rate > 0 else 0,
                    })
        
        return items

    # ------------------------------------------------------------------
    def _extract_line_items_regex(self, text: str, lines: list[str], warnings: list[str]) -> list:
        """Extract line items using regex patterns."""
        items = []
        
        # Improved regex: handles variable spacing, optional HSN, descriptions with spaces
        # Pattern: description (with possible numbers)  [HSN]  Qty  Rate  Amount
        line_pattern = re.compile(
            r'^(.+?)\s+'                    # description
            r'(?:HSN\s*[\-/]?\s*(\d{4,8}))?\s*'  # optional HSN label+code
            r'(\d+(?:\.\d+)?)\s*'            # quantity
            r'([\d,]+(?:\.\d+)?)\s*'        # rate  
            r'([\d,]+(?:\.\d+)?)\s*'        # amount
            r'(?:\d+(?:\.\d+)?%)?\s*$',     # optional GST rate at end
            re.IGNORECASE,
        )
        
        # Simpler fallback pattern
        simple_pattern = re.compile(
            r'^(.+?)\s+(\d+(?:\.\d+)?)\s+([\d,]+(?:\.\d+)?)\s+([\d,]+(?:\.\d+)?)$'
        )
        
        in_table = False
        for line in lines:
            line_lower = line.lower()
            
            # Table boundaries
            if re.search(r'\b(?:description|item|particulars|goods|product|sr\.?\s*no|sl\.?\s*no)\b', line_lower):
                in_table = True
                continue
            if in_table and re.search(r'\b(?:subtotal|total|taxable|cgst|sgst|igst|amount\s*payable|grand\s*total)\b', line_lower):
                break
            if not in_table:
                continue
            
            # Try detailed pattern
            m = line_pattern.match(line)
            if m:
                desc = m.group(1).strip()
                hsn = m.group(2) or ""
                qty = float(m.group(3))
                rate = _clean_amount(m.group(4)) or 0.0
                amount = _clean_amount(m.group(5)) or 0.0
                
                if qty > 0:
                    gst_rate = 0.0
                    gst_m = _RE_GST_RATE.search(desc)
                    if gst_m:
                        gst_rate = float(gst_m.group(1))
                        desc = _RE_GST_RATE.sub('', desc).strip()
                    
                    items.append({
                        "description": desc,
                        "hsn": hsn,
                        "qty": qty,
                        "rate": rate,
                        "gst_rate": gst_rate,
                        "amount": amount if amount > 0 else qty * rate,
                    })
                continue
            
            # Try simple pattern
            m = simple_pattern.match(line)
            if m:
                desc = m.group(1).strip()
                qty = float(m.group(2))
                rate = _clean_amount(m.group(3)) or 0.0
                amount = _clean_amount(m.group(4)) or 0.0
                
                if qty > 0:
                    gst_rate = 0.0
                    gst_m = _RE_GST_RATE.search(desc)
                    if gst_m:
                        gst_rate = float(gst_m.group(1))
                        desc = _RE_GST_RATE.sub('', desc).strip()
                    
                    items.append({
                        "description": desc,
                        "hsn": "",
                        "qty": qty,
                        "rate": rate,
                        "gst_rate": gst_rate,
                        "amount": amount if amount > 0 else qty * rate,
                    })
        
        return items

    # ------------------------------------------------------------------
    def _extract_line_items_fallback(self, text: str, lines: list[str]) -> list:
        """Fallback: find any lines that look like qty × rate = amount."""
        items = []
        
        for line in lines:
            # Look for pattern: number number number (qty rate amount)
            nums = re.findall(r'([\d,]+(?:\.\d+)?)', line)
            if len(nums) >= 3:
                try:
                    values = [_clean_amount(n) for n in nums]
                    values = [v for v in values if v is not None]
                    if len(values) >= 3:
                        # Get description: everything before the first number
                        desc_match = re.match(r'^(.+?)\s+\d', line)
                        if desc_match:
                            desc = desc_match.group(1).strip()
                            if len(desc) > 2 and not _RE_VENDOR_SKIP.match(desc):
                                qty = values[0]
                                rate = values[1]
                                amount = values[-1]
                                if qty > 0 and amount > 0:
                                    items.append({
                                        "description": desc,
                                        "hsn": "",
                                        "qty": qty,
                                        "rate": rate if rate > 0 else amount / qty,
                                        "gst_rate": 0.0,
                                        "amount": amount,
                                    })
                except Exception:
                    pass
        
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
