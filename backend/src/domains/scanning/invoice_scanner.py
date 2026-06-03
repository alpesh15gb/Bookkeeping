"""
src/domains/scanning/invoice_scanner.py

OCR-based invoice scanner for extracting GST bill fields from images and PDFs.

New pipeline (simpler, layout-aware):
  1. Image preprocessing  — deskew, denoise, adaptive threshold
  2. OCR                  — Single high-quality Tesseract pass + image_to_data
  3. Layout analysis      — Use word positions to identify header/table/footer regions
  4. Field extraction     — Extract fields from appropriate regions using regex + position
  5. Post-processing      — Clean, validate, compute confidence scores

Supports: JPEG, PNG, TIFF (images) + PDF (all pages via pdf2image).
"""
from __future__ import annotations

import io
import logging
import re
from datetime import date
from typing import Optional, List, Dict, Any, Tuple

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Lazy imports
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
# Regex patterns
# ---------------------------------------------------------------------------

_RE_GSTIN = re.compile(
    r'\b(\d{2}[A-Z]{5}\d{4}[A-Z]{1}\d{1}Z[A-Z\d]{1})\b',
    re.IGNORECASE,
)

_RE_INV_NUMBER = re.compile(
    r'(?:invoice\s*(?:no|number|#|num|\.|:)?\s*|bill\s*(?:no|number|#)?\s*|'
    r'inv\s*(?:no|#)?\s*|inv\.?\s*|invoice\s*#?\s*)'
    r'[:\-]?\s*'
    r'([A-Z0-9/\-_\.]{3,})',
    re.IGNORECASE,
)

_RE_INV_NUMBER_FALLBACK = re.compile(
    r'(?:invoice|bill)[^\n]{0,60}?([A-Z]?\d{3,}[A-Z0-9/\-_]*)',
    re.IGNORECASE,
)

_RE_DATE_DMY = re.compile(r'\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})\b')
_RE_DATE_YMD = re.compile(r'\b(\d{4})[/\-\.](\d{2})[/\-\.](\d{2})\b')
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

_RE_AMOUNT = re.compile(
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    re.IGNORECASE,
)

_RE_TOTAL = re.compile(
    r'(?:grand\s*total|total\s*amount|amount\s*payable|net\s*(?:amount|payable|total)|'
    r'invoice\s*total|bill\s*total|net\s*payable|total\s*payable|'
    r'amount\s*due|total\s*due|bill\s*amount|net\s*amount|'
    r'final\s*amount|total\s*value|amount)\s*[:\-]?\s*'
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

_RE_SUBTOTAL = re.compile(
    r'(?:taxable\s*(?:amount|value)|subtotal|sub\s*total|value\s*before\s*tax|'
    r'taxable\s*value|total\s*before\s*tax|amount\s*before\s*tax)'
    r'\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)',
    re.IGNORECASE,
)

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

_RE_PO = re.compile(
    r'(?:p\.?o\.?\s*(?:no|number|#)[.:]?\s*|purchase\s*order\s*(?:no|#)[.:]?\s*)'
    r'([A-Z0-9/\-_]+)',
    re.IGNORECASE,
)

_RE_DUE = re.compile(
    r'(?:due\s*date|payment\s*due)[\s:]+([0-9/\-\.A-Za-z]+)',
    re.IGNORECASE,
)

_RE_GST_RATE = re.compile(r'(\d+(?:\.\d+)?)\s*%')

_RE_COMPANY_SUFFIX = re.compile(
    r'\b(pvt\s+ltd|private\s+limited|ltd|limited|llp|'
    r'enterprises|enterprise|corporation|corp|'
    r'solutions|services|consultants|traders|trading|'
    r'industries|industry|works|engineering|'
    r'goods|suppliers|dealers|distributors)\b',
    re.IGNORECASE,
)

_RE_VENDOR_SKIP = re.compile(
    r'^(?:tax|gst|invoice|bill|date|gstin|pan|address|phone|mob|tel|fax|email|'
    r'original|duplicate|copy|for|buyer|supplier|vendor|seller|'
    r'ship|to|bill|to|from|qty|quantity|rate|amount|total|subtotal|'
    r'cgst|sgst|igst|tax|hsn|sr|no|item|description|particulars)$',
    re.IGNORECASE,
)

_RE_OCR_NOISE = re.compile(r'[^\w\s\d.,/\-₹@#:&\(\)\[\]\{\}%*+=_]')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _clean_amount(raw: str) -> Optional[float]:
    if not raw:
        return None
    try:
        cleaned = re.sub(r'[^\d.]', '', raw.strip())
        parts = cleaned.split('.')
        if len(parts) > 2:
            cleaned = parts[0] + '.' + ''.join(parts[1:])
        return float(cleaned) if cleaned else None
    except (ValueError, AttributeError):
        return None


def _parse_date(text: str) -> Optional[str]:
    if not text:
        return None
    text = text.strip()
    
    m = _RE_DATE_DMY.search(text)
    if m:
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if 1 <= d <= 31 and 1 <= mo <= 12 and 2000 <= y <= 2099:
            try:
                return date(y, mo, d).isoformat()
            except ValueError:
                pass

    m = _RE_DATE_YMD.search(text)
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if 2000 <= y <= 2099 and 1 <= mo <= 12 and 1 <= d <= 31:
            try:
                return date(y, mo, d).isoformat()
            except ValueError:
                pass

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


def _clean_ocr_text(text: str) -> str:
    """Remove common OCR garbage characters."""
    # Remove control chars and weird symbols
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', text)
    # Remove lines that are just noise
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if len(stripped) < 1:
            continue
        # Skip lines that are mostly non-alphanumeric garbage
        alpha_num_count = sum(1 for c in stripped if c.isalnum() or c in '.,/-₹')
        if alpha_num_count < len(stripped) * 0.3 and len(stripped) < 10:
            continue
        lines.append(line)
    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Image preprocessing
# ---------------------------------------------------------------------------

def _preprocess_image(image_bytes: bytes):
    cv2 = _require_cv2()
    np = _require_numpy()

    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image bytes")

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    gray = _deskew(gray)
    
    # Denoise while preserving edges
    denoised = cv2.bilateralFilter(gray, 11, 17, 17)
    
    # Enhance contrast
    enhanced = cv2.convertScaleAbs(denoised, alpha=1.3, beta=10)
    
    # Upscale 1.5x for better recognition (2x was too much, creates noise)
    h, w = enhanced.shape
    resized = cv2.resize(enhanced, (int(w * 1.5), int(h * 1.5)), interpolation=cv2.INTER_CUBIC)
    
    # Adaptive threshold
    binary = cv2.adaptiveThreshold(
        resized, 255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY, 13, 7,
    )
    
    final = cv2.medianBlur(binary, 3)
    return final


def _deskew(gray):
    cv2 = _require_cv2()
    np = _require_numpy()
    
    coords = np.column_stack(np.where(gray < 255))
    if len(coords) < 100:
        return gray
    
    angle = cv2.minAreaRect(coords)[-1]
    if angle < -45:
        angle = -(90 + angle)
    else:
        angle = -angle
    
    if abs(angle) < 0.5:
        return gray
    
    (h, w) = gray.shape[:2]
    center = (w // 2, h // 2)
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    rotated = cv2.warpAffine(gray, M, (w, h),
        flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    return rotated


def _pdf_to_image_bytes(pdf_bytes: bytes, page: int = 1) -> bytes:
    try:
        from pdf2image import convert_from_bytes
    except ImportError:
        raise RuntimeError(
            "pdf2image is required for PDF scanning: pip install pdf2image  "
            "(also install poppler-utils in Docker)"
        )

    pages = convert_from_bytes(pdf_bytes, dpi=300, first_page=page, last_page=page)
    if not pages:
        raise ValueError("PDF appears to be empty")

    buf = io.BytesIO()
    pages[0].save(buf, format="JPEG", quality=95)
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Layout-aware word data
# ---------------------------------------------------------------------------

def _build_word_data(structured_data: dict) -> List[Dict]:
    """Convert pytesseract image_to_data dict into a clean list of word dicts."""
    words = []
    n = len(structured_data.get("text", []))
    for i in range(n):
        text = structured_data["text"][i].strip()
        conf = int(structured_data["conf"][i])
        if not text or conf < 15:
            continue
        words.append({
            "text": text,
            "conf": conf,
            "x": structured_data["left"][i],
            "y": structured_data["top"][i],
            "w": structured_data["width"][i],
            "h": structured_data["height"][i],
            "line_num": structured_data["line_num"][i],
            "block_num": structured_data["block_num"][i],
            "par_num": structured_data["par_num"][i],
        })
    return words


def _group_words_into_lines(words: List[Dict]) -> Dict[int, List[Dict]]:
    """Group words by line_num, sort by x within each line."""
    lines_dict = {}
    for w in words:
        ln = w["line_num"]
        if ln not in lines_dict:
            lines_dict[ln] = []
        lines_dict[ln].append(w)
    for ln in lines_dict:
        lines_dict[ln].sort(key=lambda w: w["x"])
    return lines_dict


def _get_region_bounds(words: List[Dict]) -> Tuple[int, int, int, int]:
    """Return (min_x, min_y, max_x, max_y) for a set of words."""
    if not words:
        return 0, 0, 0, 0
    min_x = min(w["x"] for w in words)
    min_y = min(w["y"] for w in words)
    max_x = max(w["x"] + w["w"] for w in words)
    max_y = max(w["y"] + w["h"] for w in words)
    return min_x, min_y, max_x, max_y


def _line_text(words: List[Dict]) -> str:
    return " ".join(w["text"] for w in words)


# ---------------------------------------------------------------------------
# Main scanner
# ---------------------------------------------------------------------------

class InvoiceScanner:
    def scan(self, file_bytes: bytes, filename: str = "", confidence_threshold: float = 0.3) -> dict:
        warnings: list[str] = []

        # ── 1. Convert PDF if needed ─────────────────────────────────────
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

        # ── 2. Preprocess ──────────────────────────────────────────────
        try:
            processed = _preprocess_image(image_bytes)
        except Exception as e:
            logger.error(f"Image preprocessing failed: {e}")
            return self._empty_result([f"Image could not be processed: {e}"])

        pytesseract = _require_tesseract()
        Image = _require_pil()
        cv2 = _require_cv2()

        pil_img = Image.fromarray(processed)
        img_h, img_w = processed.shape[:2]

        # ── 3. Single high-quality OCR pass ────────────────────────────
        # PSM 6 = uniform block of text (best for documents)
        # OEM 3 = default engine mode (LSTM + legacy)
        raw_text = ""
        try:
            raw_text = pytesseract.image_to_string(
                pil_img,
                config="--psm 6 --oem 3 -l eng"
            )
        except Exception as e:
            logger.error(f"OCR failed: {e}")
            return self._empty_result([f"OCR engine error: {e}"])

        if not raw_text.strip():
            return self._empty_result(["OCR produced no text — check image quality or Tesseract installation."])

        # Clean OCR noise
        raw_text = _clean_ocr_text(raw_text)
        lines = [l.strip() for l in raw_text.splitlines() if l.strip()]

        # ── 4. Structured data for layout ──────────────────────────────
        words = []
        lines_dict = {}
        try:
            structured_data = pytesseract.image_to_data(
                pil_img,
                config="--psm 6 -l eng",
                output_type=pytesseract.Output.DICT
            )
            words = _build_word_data(structured_data)
            lines_dict = _group_words_into_lines(words)
        except Exception as e:
            logger.debug(f"Structured OCR failed: {e}")

        # ── 5. Layout analysis ─────────────────────────────────────────
        # Divide page into regions using Y coordinates
        header_words = [w for w in words if w["y"] < img_h * 0.30]
        table_words = [w for w in words if img_h * 0.25 <= w["y"] <= img_h * 0.75]
        footer_words = [w for w in words if w["y"] > img_h * 0.70]

        header_text = " ".join(w["text"] for w in header_words)
        footer_text = " ".join(w["text"] for w in footer_words)

        # ── 6. Extract fields ──────────────────────────────────────────
        result = self._extract_fields(
            raw_text=raw_text,
            lines=lines,
            words=words,
            lines_dict=lines_dict,
            header_text=header_text,
            footer_text=footer_text,
            img_h=img_h,
            warnings=warnings,
        )

        # ── 7. Confidence scoring ─────────────────────────────────────
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
    def _extract_fields(
        self,
        raw_text: str,
        lines: list[str],
        words: List[Dict],
        lines_dict: Dict[int, List[Dict]],
        header_text: str,
        footer_text: str,
        img_h: int,
        warnings: list[str],
    ) -> dict:

        # ── Vendor name ─────────────────────────────────────────────────
        vendor_name = self._extract_vendor_name(words, lines_dict, img_h)

        # ── GSTIN ───────────────────────────────────────────────────────
        # Search full text first, then header specifically
        vendor_gstin = None
        gstins = _RE_GSTIN.findall(raw_text)
        if gstins:
            vendor_gstin = gstins[0].upper()
        
        # If multiple GSTINs, prefer the one in the header (vendor) not buyer
        if len(gstins) > 1:
            header_gstins = _RE_GSTIN.findall(header_text)
            if header_gstins:
                vendor_gstin = header_gstins[0].upper()

        # ── Vendor address ─────────────────────────────────────────────
        vendor_address = self._extract_address(words, lines_dict, img_h, vendor_gstin)

        # ── Bill number ───────────────────────────────────────────────
        bill_number = self._extract_bill_number(raw_text, lines, header_text)

        # ── Dates ───────────────────────────────────────────────────────
        all_dates = _extract_all_dates(raw_text)
        
        # Bill date: first date in header area, or first date overall
        header_dates = _extract_all_dates(header_text)
        bill_date = header_dates[0] if header_dates else (all_dates[0] if all_dates else None)
        
        # Due date: look for "due" keyword, or use last date
        due_date = None
        m = _RE_DUE.search(raw_text)
        if m:
            due_date = _parse_date(m.group(1))
        if not due_date and len(all_dates) >= 2:
            # Use the later date as due date if bill_date is the earlier one
            remaining = [d for d in all_dates if d != bill_date]
            if remaining:
                due_date = remaining[-1]

        # ── PO number ───────────────────────────────────────────────────
        po_number = None
        m = _RE_PO.search(raw_text)
        if m:
            po_number = m.group(1).strip()

        # ── Tax amounts (from footer area only to avoid confusion) ─────
        total = self._extract_amount(_RE_TOTAL, footer_text) or self._extract_amount(_RE_TOTAL, raw_text)
        subtotal = self._extract_amount(_RE_SUBTOTAL, footer_text) or self._extract_amount(_RE_SUBTOTAL, raw_text)
        cgst = self._extract_amount(_RE_CGST, footer_text) or self._extract_amount(_RE_CGST, raw_text)
        sgst = self._extract_amount(_RE_SGST, footer_text) or self._extract_amount(_RE_SGST, raw_text)
        igst = self._extract_amount(_RE_IGST, footer_text) or self._extract_amount(_RE_IGST, raw_text)

        # Fallback: largest amount in footer as total
        if total is None:
            total = self._find_largest_amount(footer_text)
        if total is None:
            total = self._find_largest_amount(raw_text)

        # Derive subtotal if missing
        if subtotal is None and total is not None:
            tax_sum = (cgst or 0) + (sgst or 0) + (igst or 0)
            if tax_sum > 0 and tax_sum < total:
                subtotal = round(total - tax_sum, 2)

        # ── Line items (from table area) ────────────────────────────────
        line_items = self._extract_line_items_layout(raw_text, lines, words, lines_dict, img_h, warnings)

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
    def _extract_vendor_name(self, words: List[Dict], lines_dict: Dict[int, List[Dict]], img_h: int) -> Optional[str]:
        """
        Extract vendor name using layout + content heuristics.
        Priority: top-of-page words with company suffixes, or high-confidence long text.
        """
        candidates = []
        
        # Collect words from top 25% of page
        top_words = [w for w in words if w["y"] < img_h * 0.25]
        top_lines = {}
        for w in top_words:
            ln = w["line_num"]
            if ln not in top_lines:
                top_lines[ln] = []
            top_lines[ln].append(w)
        
        for ln in sorted(top_lines.keys()):
            words_in_line = sorted(top_lines[ln], key=lambda w: w["x"])
            text = " ".join(w["text"] for w in words_in_line)
            conf = sum(w["conf"] for w in words_in_line) / len(words_in_line)
            
            stripped = text.strip()
            if len(stripped) < 3:
                continue
            if _RE_VENDOR_SKIP.match(stripped):
                continue
            if re.fullmatch(r'[\d\s/\-.,]+', stripped):
                continue
            
            score = conf  # base score from OCR confidence
            
            # Boost for company suffixes
            if _RE_COMPANY_SUFFIX.search(stripped):
                score += 50
            
            # Boost for all-caps (common for Indian company names)
            caps_ratio = sum(1 for c in stripped if c.isupper()) / max(len(stripped), 1)
            if caps_ratio > 0.5:
                score += 20
            
            # Boost for length (company names are usually 2-6 words)
            word_count = len(stripped.split())
            if 2 <= word_count <= 8:
                score += 15
            
            candidates.append((score, stripped, text))
        
        if candidates:
            # Sort by score descending, pick best
            candidates.sort(key=lambda x: x[0], reverse=True)
            return candidates[0][1]
        
        # Fallback: use first few lines of raw text
        for line in lines_dict.values():
            text = _line_text(line)
            stripped = text.strip()
            if len(stripped) > 3 and not _RE_VENDOR_SKIP.match(stripped) and not re.fullmatch(r'[\d\s/\-.,]+', stripped):
                return stripped
        
        return None

    # ------------------------------------------------------------------
    def _extract_address(self, words: List[Dict], lines_dict: Dict[int, List[Dict]], img_h: int, gstin: Optional[str]) -> Optional[str]:
        """Extract vendor address from lines near the vendor name and before GSTIN."""
        addr_parts = []
        
        # Find GSTIN line
        gstin_line = None
        for ln, line_words in lines_dict.items():
            text = _line_text(line_words)
            if gstin and gstin in text:
                gstin_line = ln
                break
        
        # Look for address-like lines before GSTIN
        for ln in sorted(lines_dict.keys()):
            if gstin_line and ln >= gstin_line:
                break
            
            text = _line_text(lines_dict[ln])
            stripped = text.strip()
            
            # Skip obvious non-address lines
            if _RE_VENDOR_SKIP.match(stripped):
                continue
            if re.search(r'(?:gstin|pan|phone|mob|tel|email|fax|invoice|bill)\s*[:\-]?\s*\w', stripped, re.I):
                continue
            
            # Address indicators
            addr_indicators = [
                r'\b\d{6}\b',  # PIN code
                r'\b(road|street|nagar|colony|sector|phase|block|complex|building|tower|floor|shop|plot)\b',
                r'\b(mumbai|delhi|bangalore|chennai|kolkata|pune|hyderabad|ahmedabad|jaipur|lucknow|kanpur|nagpur|indore|thane|bhopal|visakhapatnam|vadodara|firozabad|ludhiana|rajkot|agra|faridabad|meerut|nashik|jodhpur|gwalior|jabalpur|raipur|kota|guwahati|solapur|hubli|mysore|salem|tiruchirappalli|tiruppur|ambattur|nellore|tirunelveli|malegaon|gaya|jalgaon|udaipur|maheshtala|davanagere|kozhikode|akola|kurnool|rajpur|sonarpur|rajahmundry|bhiwandi|gopalpur|bhubaneswar|warangal|mira|bhayander|durgapur|asansol|kolhapur|ajmer|gulbarga|jamnagar|bhilwara|saharanpur|guntur|bikaner|amravati|noida|jamshedpur|bhilai|cuttack|firozabad|kochi|nellore|bhavnagar|dehradun|dhanbad|aurangabad|amritsar|navi\s+mumbai|allahabad|ranchi|howrah|coimbatore|jabalpur|srinagar|solapur|chandigarh|patna|trichy|madurai|varanasi|agra|meerut|faridabad|ghaziabad)\b',
            ]
            
            is_addr = any(re.search(p, stripped, re.I) for p in addr_indicators)
            
            # Also accept multi-word lines in the top half that look like addresses
            if is_addr or (len(stripped) > 10 and len(stripped.split()) >= 3 and not re.fullmatch(r'[\d\s/\-.,]+', stripped)):
                # Avoid GSTIN
                if not _RE_GSTIN.search(stripped):
                    addr_parts.append(stripped)
        
        return ", ".join(addr_parts[:4]) if addr_parts else None

    # ------------------------------------------------------------------
    def _extract_bill_number(self, raw_text: str, lines: list[str], header_text: str) -> Optional[str]:
        """Extract invoice/bill number with multiple strategies."""
        # Try header first (bill number usually in header)
        m = _RE_INV_NUMBER.search(header_text)
        if m:
            val = m.group(1).strip()
            if len(val) >= 2:
                return val

        m = _RE_INV_NUMBER.search(raw_text)
        if m:
            val = m.group(1).strip()
            if len(val) >= 2:
                return val

        m = _RE_INV_NUMBER_FALLBACK.search(raw_text)
        if m:
            val = m.group(1).strip()
            if len(val) >= 2 and val.lower() not in ('date', 'no', 'number'):
                return val

        # Look for pattern near "Invoice" keyword
        for i, line in enumerate(lines):
            if re.search(r'\binvoice\b', line, re.I):
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
        amounts = []
        for m in _RE_AMOUNT.finditer(text):
            val = _clean_amount(m.group(1))
            if val is not None and val > 0:
                amounts.append(val)
        return max(amounts) if amounts else None

    # ------------------------------------------------------------------
    def _extract_line_items_layout(
        self,
        raw_text: str,
        lines: list[str],
        words: List[Dict],
        lines_dict: Dict[int, List[Dict]],
        img_h: int,
        warnings: list[str],
    ) -> list:
        """
        Extract line items using layout-aware table detection.
        Uses word positions to identify table columns, then reads each row.
        """
        items = []
        
        if not words or not lines_dict:
            # Fallback to regex
            return self._extract_line_items_regex(raw_text, lines)

        # Find table region: middle of page, lines with multiple numbers
        table_lines = {}
        for ln, line_words in lines_dict.items():
            y = line_words[0]["y"] if line_words else 0
            # Only consider lines in the middle 50% of the page
            if y < img_h * 0.20 or y > img_h * 0.85:
                continue
            
            text = _line_text(line_words)
            lower = text.lower()
            
            # Skip header/footer keywords
            if re.search(r'\b(?:subtotal|total|tax|cgst|sgst|igst|amount\s*payable|grand\s*total|taxable)\b', lower):
                continue
            if re.search(r'\b(?:description|item|particulars|goods|product|sr\.?\s*no|sl\.?\s*no|s\.?no)\b', lower):
                continue
            
            # Look for numeric values in this line
            nums = []
            desc_words = []
            hsn = ""
            
            for w in line_words:
                wtext = w["text"]
                # Check if it's a pure number (could be qty, rate, amount)
                if re.match(r'^[\d,]+(?:\.\d+)?$', wtext.replace(',', '')):
                    val = _clean_amount(wtext)
                    if val is not None:
                        nums.append(val)
                elif re.match(r'^\d{4,8}$', wtext) and not hsn:
                    hsn = wtext
                else:
                    desc_words.append(wtext)
            
            # A table row needs at least 2 numbers (qty + amount, or qty + rate + amount)
            if len(nums) >= 2 and desc_words:
                desc = " ".join(desc_words).strip()
                # Clean description
                desc = re.sub(r'\s+', ' ', desc)
                if len(desc) > 1 and not _RE_VENDOR_SKIP.match(desc):
                    table_lines[ln] = {
                        "desc": desc,
                        "hsn": hsn,
                        "nums": nums,
                        "y": y,
                    }

        if not table_lines:
            return self._extract_line_items_regex(raw_text, lines)

        # Sort by Y position (top to bottom)
        sorted_lines = sorted(table_lines.items(), key=lambda x: x[0])

        for ln, row in sorted_lines:
            nums = row["nums"]
            desc = row["desc"]
            
            # Heuristic: assign numbers to qty, rate, amount based on typical patterns
            # Common patterns: [qty, rate, amount] or [qty, amount] or [qty, rate, tax, amount]
            qty = 1.0
            rate = 0.0
            amount = 0.0
            
            if len(nums) == 2:
                # Likely [qty, amount] or [rate, amount]
                if nums[0] < nums[1] and nums[0] < 1000:
                    qty = nums[0]
                    amount = nums[1]
                    rate = round(amount / qty, 2) if qty > 0 else 0
                else:
                    qty = 1.0
                    rate = nums[0]
                    amount = nums[1]
            elif len(nums) >= 3:
                # Likely [qty, rate, amount] or [qty, rate, tax, amount]
                # qty is usually the smallest integer-like number
                qty = nums[0]
                amount = nums[-1]
                if len(nums) == 3:
                    rate = nums[1]
                else:
                    # More numbers: pick the one that makes qty * rate ≈ amount
                    best_rate = 0
                    best_diff = float('inf')
                    for i in range(1, len(nums) - 1):
                        r = nums[i]
                        diff = abs(qty * r - amount)
                        if diff < best_diff:
                            best_diff = diff
                            best_rate = r
                    rate = best_rate
                
                # Validate: if qty * rate is way off from amount, recalculate
                if qty > 0 and rate > 0:
                    calc_amount = round(qty * rate, 2)
                    if abs(calc_amount - amount) > amount * 0.1:
                        # Try alternative assignment
                        rate = round(amount / qty, 2)
            
            if qty > 0 and amount > 0:
                gst_rate = 0.0
                gst_m = _RE_GST_RATE.search(desc)
                if gst_m:
                    gst_rate = float(gst_m.group(1))
                    desc = _RE_GST_RATE.sub('', desc).strip()
                
                items.append({
                    "description": desc,
                    "hsn": row["hsn"],
                    "qty": qty,
                    "rate": rate if rate > 0 else round(amount / qty, 2),
                    "gst_rate": gst_rate,
                    "amount": amount,
                })

        if not items:
            return self._extract_line_items_regex(raw_text, lines)
        
        return items

    # ------------------------------------------------------------------
    def _extract_line_items_regex(self, text: str, lines: list[str]) -> list:
        """Regex-based fallback for line item extraction."""
        items = []
        
        # Pattern: description [optional HSN] qty rate amount [optional GST%]
        line_pattern = re.compile(
            r'^(.+?)\s+'
            r'(?:HSN\s*[\-/]?\s*(\d{4,8}))?\s*'
            r'(\d+(?:\.\d+)?)\s*'
            r'([\d,]+(?:\.\d+)?)\s*'
            r'([\d,]+(?:\.\d+)?)\s*'
            r'(?:\d+(?:\.\d+)?%)?\s*$',
            re.IGNORECASE,
        )
        
        simple_pattern = re.compile(
            r'^(.+?)\s+(\d+(?:\.\d+)?)\s+([\d,]+(?:\.\d+)?)\s+([\d,]+(?:\.\d+)?)$'
        )
        
        in_table = False
        for line in lines:
            line_lower = line.lower()
            
            if re.search(r'\b(?:description|item|particulars|goods|product|sr\.?\s*no|sl\.?\s*no)\b', line_lower):
                in_table = True
                continue
            if in_table and re.search(r'\b(?:subtotal|total|taxable|cgst|sgst|igst|amount\s*payable|grand\s*total)\b', line_lower):
                break
            if not in_table:
                continue
            
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
# Confidence scoring
# ---------------------------------------------------------------------------

def _compute_confidence(data: dict) -> dict:
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
# Singleton
# ---------------------------------------------------------------------------

_scanner: Optional[InvoiceScanner] = None


def get_scanner() -> InvoiceScanner:
    global _scanner
    if _scanner is None:
        _scanner = InvoiceScanner()
        logger.info("InvoiceScanner initialised (layout-aware Tesseract OCR pipeline)")
    return _scanner
