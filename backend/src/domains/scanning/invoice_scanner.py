"""
src/domains/scanning/invoice_scanner.py

OCR-based invoice scanner using PaddleOCR for extracting line items from
vendor bills / purchase invoices.

Pipeline:
  1. Image preprocessing  — decode, grayscale, deskew, denoise
  2. OCR                  — PaddleOCR (text detection + recognition)
  3. Layout analysis      — group words into rows, detect table region
  4. Line item extraction  — parse table rows into structured items
  5. Post-processing      — validate amounts, compute confidence

Supports: JPEG, PNG, TIFF (images) + PDF (all pages via pdf2image).
"""
from __future__ import annotations

import io
import logging
import re
import warnings
from datetime import date
from typing import Optional, List, Dict, Any, Tuple
from src.core.config import settings

# Suppress PaddleOCR model/lang warnings, Pydantic model_ protected namespace warnings, and requests/urllib3 version warnings
warnings.filterwarnings("ignore", category=UserWarning, message=".*lang and ocr_version will be ignored.*")
warnings.filterwarnings("ignore", category=UserWarning, message=".*Field.*has conflict with protected namespace.*")
warnings.filterwarnings("ignore", message=".*urllib3.*doesn't match a supported version.*")

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Disable PaddlePaddle PIR before any paddle import (CPU crash workaround)
# ---------------------------------------------------------------------------
import os as _os
_os.environ.setdefault("FLAGS_enable_pir_in_executor", "0")
_os.environ.setdefault("FLAGS_enable_pir_api", "0")
_os.environ.setdefault("FLAGS_pir_apply_inplace_pass", "0")


# ---------------------------------------------------------------------------
# Lazy imports — PaddleOCR is heavy; raise clear error only on actual use
# ---------------------------------------------------------------------------

def _require_paddleocr():
    try:
        from paddleocr import PaddleOCR
        return PaddleOCR
    except ImportError:
        raise RuntimeError(
            "PaddleOCR is required for bill scanning. "
            "Install it: pip install paddlepaddle paddleocr"
        )


def _require_cv2():
    try:
        import cv2
        return cv2
    except ImportError:
        raise RuntimeError(
            "opencv-python-headless is required for bill scanning. "
            "Install it: pip install opencv-python-headless"
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
# Regex patterns for line item parsing
# ---------------------------------------------------------------------------

_RE_GSTIN = re.compile(
    r'\b(\d{2}[A-Z]{5}\d{4}[A-Z]{1}\d{1}Z[A-Z\d]{1})\b',
    re.IGNORECASE,
)

_RE_DATE_DMY = re.compile(r'\b(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})\b')
_RE_DATE_YMD = re.compile(r'\b(\d{4})[/\-\.](\d{2})[/\-\.](\d{2})\b')

_RE_AMOUNT = re.compile(
    r'(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{1,2})?)',
    re.IGNORECASE,
)

_RE_TOTAL_KEYWORDS = re.compile(
    r'(?:grand\s*total|total\s*amount|amount\s*payable|net\s*(?:amount|payable|total)|'
    r'invoice\s*total|bill\s*total|total\s*payable|amount\s*due|total\s*due|'
    r'bill\s*amount|net\s*amount|final\s*amount|total\s*value|amount)',
    re.IGNORECASE,
)

_RE_SUBTOTAL_KEYWORDS = re.compile(
    r'(?:taxable\s*(?:amount|value)|subtotal|sub\s*total|value\s*before\s*tax|'
    r'taxable\s*value|total\s*before\s*tax|amount\s*before\s*tax)',
    re.IGNORECASE,
)

_RE_CGST = re.compile(r'cgst\s*(?:@\s*[\d.]+%?)?\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)', re.IGNORECASE)
_RE_SGST = re.compile(r'sgst\s*(?:@\s*[\d.]+%?)?\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)', re.IGNORECASE)
_RE_IGST = re.compile(r'igst\s*(?:@\s*[\d.]+%?)?\s*[:\-]?\s*(?:Rs\.?|INR|₹)?\s*([\d,]+(?:\.\d{2})?)', re.IGNORECASE)

_RE_GST_RATE = re.compile(r'(\d+(?:\.\d+)?)\s*%')

_RE_INV_NUMBER = re.compile(
    r'(?:invoice\s*(?:no|number|#|num|\.|:)?\s*|bill\s*(?:no|number|#)?\s*|'
    r'inv\s*(?:no|#)?\s*|inv\.?\s*|invoice\s*#?\s*)'
    r'[:\-]?\s*'
    r'([A-Z0-9/\-_\.]{3,})',
    re.IGNORECASE,
)

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
    r'ship|to|from|qty|quantity|rate|amount|total|subtotal|'
    r'cgst|sgst|igst|hsn|sr|no|item|description|particulars|'
    r'sl\.?\s*no|s\.?\s*no|sr\.?\s*no|hsn\/sac|uom|unit)$',
    re.IGNORECASE,
)

# Words that indicate a table header row
_RE_TABLE_HEADER = re.compile(
    r'\b(?:description|item|particulars|goods|product|hsn|sac|'
    r'qty|quantity|rate|amount|tax|gst|sr\.?\s*no|sl\.?\s*no|'
    r'uom|unit|disc|discount)\b',
    re.IGNORECASE,
)

# Words that indicate totals/footer region
_RE_TABLE_FOOTER = re.compile(
    r'\b(?:subtotal|total|taxable|cgst|sgst|igst|cess|'
    r'amount\s*payable|grand\s*total|round\s*off|discount)\b',
    re.IGNORECASE,
)


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


def _clean_json_string(s: str) -> str:
    result = []
    i = 0
    n = len(s)
    in_string = False
    while i < n:
        c = s[i]
        if c == '"':
            # Check if this quote is escaped
            backslashes = 0
            j = len(result) - 1
            while j >= 0 and result[j] == '\\':
                backslashes += 1
                j -= 1
            if backslashes % 2 == 0:
                in_string = not in_string
            result.append(c)
            i += 1
        elif c == '\\' and in_string:
            if i + 1 < n:
                next_c = s[i+1]
                if next_c in ['"', '\\', '/', 'b', 'f', 'n', 'r', 't']:
                    result.append(c)
                    result.append(next_c)
                    i += 2
                elif next_c == 'u':
                    # Check if followed by 4 hex digits
                    if i + 5 < n and all(ch in '0123456789abcdefABCDEF' for ch in s[i+2:i+6]):
                        result.append(c)
                        result.append(next_c)
                        result.extend(s[i+2:i+6])
                        i += 6
                    else:
                        result.append('\\')
                        result.append(c)
                        result.append(next_c)
                        i += 2
                else:
                    result.append('\\')
                    result.append(c)
                    result.append(next_c)
                    i += 2
            else:
                result.append('\\')
                result.append(c)
                i += 1
        else:
            result.append(c)
            i += 1
    return "".join(result)


def _parse_json_via_regex(s: str) -> dict:
    import re
    parsed = {}
    
    # Clean up whitespace and newlines to make matching simpler
    s_clean = re.sub(r'\s+', ' ', s)

    # Helper to find standard key-value pairs
    def get_scalar_field(key: str) -> Optional[str]:
        # Try double quotes: "key": "value"
        pattern_str = f'"{key}"\\s*:\\s*"(.*?)"(?=\\s*(?:,|\\}}))'
        m = re.search(pattern_str, s_clean)
        if m:
            return m.group(1).strip()
            
        # Try single quotes: 'key': 'value'
        pattern_str = f"'{key}'\\s*:\\s*'(.*?)'(?=\\s*(?:,|\\}}))"
        m = re.search(pattern_str, s_clean)
        if m:
            return m.group(1).strip()
            
        # Try unquoted string or number or null: "key": value
        pattern_str = f'"{key}"\\s*:\\s*([^,\\}}\\]]+)'
        m = re.search(pattern_str, s_clean)
        if m:
            val = m.group(1).strip()
            if val.lower() == 'null':
                return None
            val = val.strip(' "\'')
            return val
            
        # Try single quote key unquoted value: 'key': value
        pattern_str = f"'{key}'\\s*:\\s*([^,\\}}\\]]+)"
        m = re.search(pattern_str, s_clean)
        if m:
            val = m.group(1).strip()
            if val.lower() == 'null':
                return None
            val = val.strip(' "\'')
            return val
            
        return None

    parsed["vendor_name"] = get_scalar_field("vendor_name")
    parsed["vendor_gstin"] = get_scalar_field("vendor_gstin")
    parsed["vendor_address"] = get_scalar_field("vendor_address")
    parsed["buyer_name"] = get_scalar_field("buyer_name")
    parsed["buyer_gstin"] = get_scalar_field("buyer_gstin")
    parsed["buyer_address"] = get_scalar_field("buyer_address")
    parsed["bill_number"] = get_scalar_field("bill_number")
    parsed["bill_date"] = get_scalar_field("bill_date")
    parsed["due_date"] = get_scalar_field("due_date")
    parsed["po_number"] = get_scalar_field("po_number")

    # Numeric fields
    for num_field in ["subtotal", "cgst", "sgst", "igst", "total"]:
        val = get_scalar_field(num_field)
        if val is not None:
            parsed[num_field] = _clean_amount(str(val))
        else:
            parsed[num_field] = 0.0

    # Extract line items
    line_items = []
    items_match = re.search(r'"line_items"\s*:\s*\[(.*?)\]', s_clean, re.IGNORECASE)
    if not items_match:
        items_match = re.search(r"'line_items'\s*:\s*\[(.*?)\]", s_clean, re.IGNORECASE)
        
    if items_match:
        items_block = items_match.group(1)
        # Find all objects inside the list: { ... }
        object_matches = re.findall(r'\{(.*?)\}', items_block)
        for obj_str in object_matches:
            def get_obj_field(key: str) -> Optional[str]:
                pattern_str = f'"{key}"\\s*:\\s*"(.*?)"(?=\\s*(?:,|\\}}|$))'
                m = re.search(pattern_str, obj_str)
                if m:
                    return m.group(1).strip()
                pattern_str = f"'{key}'\\s*:\\s*'(.*?)'(?=\\s*(?:,|\\}}|$))"
                m = re.search(pattern_str, obj_str)
                if m:
                    return m.group(1).strip()
                pattern_str = f'"{key}"\\s*:\\s*([^,\\}}]+)'
                m = re.search(pattern_str, obj_str)
                if m:
                    val = m.group(1).strip().strip(' "\'')
                    return val if val.lower() != 'null' else None
                pattern_str = f"'{key}'\\s*:\\s*([^,\\}}]+)"
                m = re.search(pattern_str, obj_str)
                if m:
                    val = m.group(1).strip().strip(' "\'')
                    return val if val.lower() != 'null' else None
                return None

            prod_name = get_obj_field("product_name")
            if prod_name:
                hsn = get_obj_field("hsn_sac")
                
                qty = 1.0
                qty_str = get_obj_field("quantity")
                if qty_str:
                    try:
                        qty = float(qty_str)
                    except ValueError:
                        pass
                        
                rate = 0.0
                rate_str = get_obj_field("rate")
                if rate_str:
                    try:
                        rate = float(rate_str)
                    except ValueError:
                        pass
                        
                gst = 0.0
                gst_str = get_obj_field("gst_rate")
                if gst_str:
                    try:
                        gst = float(gst_str)
                    except ValueError:
                        pass
                        
                amt = qty * rate
                amt_str = get_obj_field("amount")
                if amt_str:
                    try:
                        amt = float(amt_str)
                    except ValueError:
                        pass
                        
                line_items.append({
                    "product_name": prod_name,
                    "hsn_sac": hsn,
                    "quantity": qty,
                    "rate": rate,
                    "gst_rate": gst,
                    "amount": amt
                })
                
    parsed["line_items"] = line_items
    return parsed


def _robust_json_loads(s: str) -> dict:
    import json
    import re
    import ast

    try:
        return json.loads(s)
    except Exception as e:
        orig_err = e

    # Fallback to ast.literal_eval for python-like literals (single quotes, trailing commas)
    # Map json boolean/null tokens to Python counterparts
    s_py = re.sub(r'\btrue\b', 'True', s)
    s_py = re.sub(r'\bfalse\b', 'False', s_py)
    s_py = re.sub(r'\bnull\b', 'None', s_py)

    try:
        val = ast.literal_eval(s_py)
        if isinstance(val, dict):
            return val
    except Exception:
        pass

    # Fallback to regex-based JSON-like parsing
    try:
        val = _parse_json_via_regex(s)
        # Verify it has at least some meaningful fields (e.g. line_items or vendor_name or total)
        if val and (val.get("vendor_name") or val.get("line_items") or val.get("total")):
            return val
    except Exception:
        pass

    raise orig_err


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

    # Fallback for dd-MMM-yy, dd-MMM-yyyy, or MMM dd, yyyy (e.g. 27-Mar-26 or March 27, 2026)
    months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        'january': 1, 'february': 2, 'march': 3, 'april': 4, 'june': 6,
        'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
    }
    
    # dd-MMM-yy or dd-MMM-yyyy (e.g. 27-Mar-26)
    m = re.search(r'\b(\d{1,2})[-\s/]+([a-zA-Z]{3,9})[-\s/]+(\d{2,4})\b', text)
    if m:
        d = int(m.group(1))
        mon_str = m.group(2).lower()
        y_str = m.group(3)
        if mon_str in months:
            mon = months[mon_str]
            y = int(y_str)
            if len(y_str) == 2:
                y += 2000
            try:
                return date(y, mon, d).isoformat()
            except ValueError:
                pass
                
    # MMM dd, yyyy or Month dd, yyyy (e.g. March 27, 2026)
    m = re.search(r'\b([a-zA-Z]{3,9})[-\s/]+(\d{1,2})[,\s/]+(\d{2,4})\b', text)
    if m:
        mon_str = m.group(1).lower()
        d = int(m.group(2))
        y_str = m.group(3)
        if mon_str in months:
            mon = months[mon_str]
            y = int(y_str)
            if len(y_str) == 2:
                y += 2000
            try:
                return date(y, mon, d).isoformat()
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
    return sorted(set(dates))


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
    denoised = cv2.bilateralFilter(gray, 11, 17, 17)
    enhanced = cv2.convertScaleAbs(denoised, alpha=1.2, beta=8)
    return enhanced


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
# PaddleOCR-based scanner
# ---------------------------------------------------------------------------

class InvoiceScanner:
    """
    Stateless invoice scanner using PaddleOCR.

    Focuses on extracting line items from the invoice table.
    Other fields (vendor name, GSTIN, dates) are extracted opportunistically
    but the primary goal is line item extraction.
    """

    def __init__(self):
        self._ocr = None
        self._ocr_version = 3

    def _init_paddleocr(self):
        PaddleOCR = _require_paddleocr()
        try:
            self._ocr = PaddleOCR(
                lang='en',
                device='cpu',
                enable_mkldnn=False,
                use_doc_orientation_classify=False,
                use_doc_unwarping=False,
                use_textline_orientation=False,
                text_detection_model_name='PP-OCRv5_mobile_det',
                text_recognition_model_name='en_PP-OCRv5_mobile_rec',
            )
        except TypeError:
            # Fallback for PaddleOCR 2.x
            self._ocr_version = 2
            self._ocr = PaddleOCR(
                use_angle_cls=True,
                lang='en',
                show_log=False,
                use_gpu=False,
            )

    def scan(self, file_bytes: bytes, filename: str = "", confidence_threshold: float = 0.3) -> dict:
        # ── Nvidia NIM integration ───────────────────────────────────────
        if getattr(settings, "NVIDIA_NIM_API_KEY", None):
            logger.info("Nvidia NIM key found. Running Nvidia NIM standalone multimodal extractor.")
            return self._scan_with_nvidia_nim(file_bytes, filename)

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

        # ── 3. Run PaddleOCR ───────────────────────────────────────────
        try:
            import numpy as np
            cv2 = _require_cv2()
            Image = _require_pil()

            if self._ocr is None:
                self._init_paddleocr()

            # PaddleOCR expects a numpy array or file path
            # Convert grayscale back to 3-channel for PaddleOCR
            if len(processed.shape) == 2:
                ocr_input = cv2.cvtColor(processed, cv2.COLOR_GRAY2RGB)
            else:
                ocr_input = processed

            if self._ocr_version >= 3:
                # PaddleOCR 3.x: use predict() — returns list of result objects
                result = self._ocr.predict(ocr_input)
                logger.info(f"PaddleOCR 3.x returned {len(result)} results, type={type(result[0]) if result else 'empty'}")
                # Debug: dump first result structure
                if result:
                    r0 = result[0]
                    logger.info(f"Result keys/attrs: {list(r0.keys()) if isinstance(r0, dict) else [a for a in dir(r0) if not a.startswith('_')][:30]}")
                    # Try to access rec_text
                    for attr in ['rec_text', 'rec_texts', 'text', 'texts', 'ocr_res']:
                        try:
                            val = r0[attr] if isinstance(r0, dict) else getattr(r0, attr, 'N/A')
                            if val != 'N/A' and val is not None:
                                logger.info(f"  .{attr} = {str(val)[:200]}")
                        except Exception:
                            pass
            else:
                # PaddleOCR 2.x: use ocr() — returns nested list
                result = self._ocr.ocr(ocr_input, cls=True)
        except Exception as e:
            logger.error(f"PaddleOCR failed: {e}", exc_info=True)
            return self._empty_result([f"OCR engine error: {e}"])

        # ── 3b. Check for empty result ────────────────────────────────
        if self._ocr_version >= 3:
            # PaddleOCR 3.x predict() returns list of dicts
            if not result or (isinstance(result, list) and not result):
                return self._empty_result(["OCR produced no text — check image quality."])
        else:
            # PaddleOCR 2.x ocr() returns [[...]]
            if not result or not result[0]:
                return self._empty_result(["OCR produced no text — check image quality."])

        # ── 4. Parse OCR results into words with positions ─────────────
        words = self._parse_ocr_result(result)
        logger.info(f"Parsed {len(words)} words from OCR results")

        if not words:
            return self._empty_result(["No text detected in image."])

        # ── 5. Layout analysis ─────────────────────────────────────────
        img_h = processed.shape[0]
        lines_dict = self._group_words_into_lines(words)
        logger.info(f"Grouped into {len(lines_dict)} lines")

        # ── 6. Extract fields ──────────────────────────────────────────
        result_data = self._extract_fields(words, lines_dict, img_h, warnings)
        logger.info(f"Extracted {len(result_data.get('line_items', []))} line items: {result_data.get('line_items')}")

        # ── 7. Confidence scoring ─────────────────────────────────────
        scores = _compute_confidence(result_data)
        overall = round(sum(scores.values()), 2)
        result_data["confidence_scores"] = scores
        result_data["overall_confidence"] = overall
        result_data["warnings"] = warnings

        if overall < confidence_threshold:
            warnings.append(
                f"Low confidence ({overall:.0%}) — the image may be blurry, "
                "skewed, or the bill format is unusual. Please verify all fields."
            )

        return result_data

    # ------------------------------------------------------------------
    def _parse_ocr_result(self, raw_result: list) -> List[Dict]:
        """Convert PaddleOCR output to a flat list of word dicts.

        Supports both PaddleOCR 2.x and 3.x output formats:
        - 2.x: [[bbox, (text, score)], ...]
        - 3.x: list of result objects/dicts with rec_text, rec_score, dt_polys
        """
        words = []
        if not raw_result:
            return words

        # Detect format: PaddleOCR 3.x returns list of dicts or objects
        sample = raw_result[0]
        is_v3 = False
        if isinstance(sample, dict):
            is_v3 = True  # Any dict is v3 format
        elif isinstance(sample, (list, tuple)):
            is_v3 = False  # Nested list = v2 format
        else:
            # Unknown object (OCRResult from PaddleOCR 3.x) — treat as v3
            is_v3 = True
            logger.info(f"OCR result is object type {type(sample).__name__}, treating as v3")

        if is_v3:
            return self._parse_ocr_result_v3(raw_result)

        # PaddleOCR 2.x format
        return self._parse_ocr_result_v2(raw_result)

    def _parse_ocr_result_v2(self, raw_result: list) -> List[Dict]:
        """Parse PaddleOCR 2.x output: [[bbox, (text, score)], ...]"""
        words = []
        if not raw_result or not raw_result[0]:
            return words

        for line in raw_result[0]:
            bbox = line[0]  # [[x1,y1], [x2,y2], [x3,y3], [x4,y4]]
            text = line[1][0]
            conf = float(line[1][1])

            if not text.strip() or conf < 0.3:
                continue

            # Get bounding box coordinates
            x1 = int(min(p[0] for p in bbox))
            y1 = int(min(p[1] for p in bbox))
            x2 = int(max(p[0] for p in bbox))
            y2 = int(max(p[1] for p in bbox))

            words.append({
                "text": text.strip(),
                "conf": conf,
                "x": x1,
                "y": y1,
                "w": x2 - x1,
                "h": y2 - y1,
                "cx": (x1 + x2) // 2,
                "cy": (y1 + y2) // 2,
            })

        return words

    def _parse_ocr_result_v3(self, raw_result: list) -> List[Dict]:
        """Parse PaddleOCR 3.x output: list of result objects/dicts.

        PaddleOCR 3.x (.json()) returns:
          {'res': {'rec_texts': [...], 'rec_scores': [...], 'dt_polys': [...]}}

        Falls back through dict / attribute / __getitem__ / iteration access.
        """
        words = []
        import numpy as np

        for page in raw_result:
            try:
                logger.info(f"OCRResult type: {type(page).__name__}, has_json={hasattr(page, 'json')}")

                rec_texts: list = []
                rec_scores: list = []
                dt_polys: list = []
                extracted = False

                # ── Strategy 1 (Preferred): Direct Attribute Access (Aligned) ──────
                # ── Strategy 1 (Preferred): Dictionary-style or Attribute Access ──────
                rt = None
                dp = None
                rs = None
                
                if hasattr(page, '__getitem__'):
                    try:
                        rt = page['rec_texts']
                    except (KeyError, TypeError):
                        pass
                    try:
                        dp = page['dt_polys']
                    except (KeyError, TypeError):
                        pass
                    try:
                        rs = page['rec_scores']
                    except (KeyError, TypeError):
                        pass

                # Fallback to getattr if dict-style access failed or was incomplete
                if rt is None:
                    rt = getattr(page, 'rec_texts', None) or getattr(page, 'rec_text', None)
                if dp is None:
                    dp = getattr(page, 'dt_polys', None) or getattr(page, 'rec_polys', None) or getattr(page, 'rec_boxes', None)
                if rs is None:
                    rs = getattr(page, 'rec_scores', None) or getattr(page, 'rec_score', None)

                if rt is not None and dp is not None and len(rt) > 0 and len(rt) == len(dp):
                    rec_texts  = rt
                    rec_scores = rs or []
                    dt_polys   = dp
                    extracted = True
                    logger.info(f"Direct aligned access succeeded: {len(rec_texts)} entries.")

                # ── Strategy 2: .json() method (PaddleOCR 3.x / PaddleX) ───────
                # NOTE: rec_texts/rec_scores survive JSON fine (strings/floats).
                # dt_polys are numpy arrays and do NOT survive JSON serialization —
                # they come back as empty lists. We ALWAYS fetch bboxes directly
                # from the object attributes after getting texts from json().
                if not extracted and hasattr(page, 'json') and callable(page.json):
                    try:
                        data = page.json()
                        logger.info(f"page.json() type={type(data).__name__}, "
                                    f"keys={list(data.keys()) if isinstance(data, dict) else 'N/A'}")
                        if isinstance(data, dict):
                            # PaddleOCR 3.x wraps results under 'res'
                            inner = data.get('res', data)
                            rec_texts  = inner.get('rec_texts',  inner.get('rec_text',  []))
                            rec_scores = inner.get('rec_scores', inner.get('rec_score', []))
                            extracted = bool(rec_texts)
                    except Exception as e:
                        logger.warning(f"page.json() failed: {e}")

                # If Strategy 2 was used and we don't have bboxes, get them from object attributes
                if extracted and not dt_polys:
                    for bbox_attr in ('dt_polys', 'rec_polys', 'rec_boxes'):
                        raw = getattr(page, bbox_attr, None)
                        if raw is not None and hasattr(raw, '__len__') and len(raw) > 0:
                            dt_polys = raw
                            logger.info(f"  Got bboxes from .{bbox_attr}: {len(dt_polys)} entries")
                            break
                    if not dt_polys and hasattr(page, '__getitem__'):
                        for bbox_key in ('dt_polys', 'rec_polys', 'rec_boxes'):
                            try:
                                raw = page[bbox_key]
                                if raw is not None and hasattr(raw, '__len__') and len(raw) > 0:
                                    dt_polys = raw
                                    logger.info(f"  Got bboxes from ['{bbox_key}']: {len(dt_polys)} entries")
                                    break
                            except (KeyError, TypeError):
                                pass

                logger.info(f"  rec_texts={len(rec_texts)}, dt_polys={len(dt_polys)}, extracted={extracted}")

                # ── Strategy 3: plain dict ───────────────────────────────────────
                if not extracted and isinstance(page, dict):
                    inner = page.get('res', page)
                    rec_texts  = inner.get('rec_texts',  inner.get('rec_text',  []))
                    rec_scores = inner.get('rec_scores', inner.get('rec_score', []))
                    dt_polys   = inner.get('dt_polys',  [])
                    ocr_res    = inner.get('ocr_res', [])
                    if ocr_res:
                        for item in ocr_res:
                            if isinstance(item, dict):
                                t = item.get('text', '') or item.get('rec_text', '')
                                s = float(item.get('score', 0) or item.get('rec_score', 0))
                                b = item.get('dt_polys', []) or item.get('bbox', [])
                                if t.strip():
                                    words.append(self._make_word(t.strip(), s, b, np))
                        continue
                    extracted = True

                # ── Strategy 4: __getitem__ with string keys ──────────────────────
                if not extracted and hasattr(page, '__getitem__'):
                    for txt_key in ('rec_texts', 'rec_text'):
                        try:
                            val = page[txt_key]
                            if val is not None:
                                rec_texts = val
                                break
                        except (KeyError, TypeError):
                            pass
                    for scr_key in ('rec_scores', 'rec_score'):
                        try:
                            val = page[scr_key]
                            if val is not None:
                                rec_scores = val
                                break
                        except (KeyError, TypeError):
                            pass
                    try:
                        dt_polys = page['dt_polys']
                    except (KeyError, TypeError):
                        pass
                    if rec_texts:
                        extracted = True

                # ── Strategy 5: direct iteration (per-region items) ───────────────
                if not extracted or not rec_texts:
                    count_before = len(words)
                    try:
                        for item in page:
                            if isinstance(item, dict):
                                t = item.get('rec_text', '') or item.get('text', '')
                                s = float(item.get('rec_score', 0) or item.get('score', 0))
                                b = item.get('dt_polys', []) or item.get('bbox', [])
                            elif isinstance(item, (list, tuple)) and len(item) >= 2:
                                if isinstance(item[0], (list, tuple)):
                                    b = item[0]
                                    t = str(item[1][0]) if isinstance(item[1], (list, tuple)) else str(item[1])
                                    s = float(item[1][1]) if isinstance(item[1], (list, tuple)) and len(item[1]) > 1 else 0.9
                                elif isinstance(item[0], str):
                                    t, s = str(item[0]), float(item[1])
                                    b = item[2] if len(item) > 2 else []
                                else:
                                    continue
                            else:
                                continue
                            if str(t).strip():
                                words.append(self._make_word(str(t).strip(), s, b, np))
                        if len(words) > count_before:
                            logger.info(f"Strategy 5 (iter) extracted {len(words) - count_before} words")
                            continue
                    except (TypeError, StopIteration):
                        logger.warning("OCRResult not iterable")

                    # Diagnosis dump for unknown formats
                    if hasattr(page, 'keys'):
                        try:
                            keys = list(page.keys())
                            logger.warning(f"Unrecognised OCRResult keys: {keys}")
                            for k in keys:
                                if any(x in k.lower() for x in ('text', 'rec', 'ocr', 'poly')):
                                    logger.warning(f"  key '{k}' = {str(page[k])[:300]}")
                        except Exception:
                            pass

                # ── Materialise words from rec_texts / dt_polys ───────────────────
                if rec_texts:
                    rec_texts  = list(rec_texts)
                    rec_scores = list(rec_scores)
                    dt_polys   = list(dt_polys)

                    for i, text in enumerate(rec_texts):
                        conf = float(rec_scores[i]) if i < len(rec_scores) else 0.9
                        if not str(text).strip() or conf < 0.2:
                            continue
                        bbox = dt_polys[i] if i < len(dt_polys) else []
                        words.append(self._make_word(str(text).strip(), conf, bbox, np))

                    logger.info("DIAG: first 10 parsed words coordinates:")
                    for w in words[:10]:
                        logger.info(f"  DIAG_COORD {repr(w['text'])}: x={w['x']}, y={w['y']}, cx={w['cx']}, cy={w['cy']}")

                    logger.info(f"Materialised {len(words)} words total from page")
                elif not extracted:
                    logger.warning(f"Could not extract text from OCRResult type {type(page).__name__}")

            except Exception as e:
                logger.error(f"Error parsing OCRResult page: {e}", exc_info=True)
                continue

        return words



    @staticmethod
    def _make_word(text: str, conf: float, bbox, np) -> dict:
        """Build a word dict from text, confidence, and bounding box.

        Handles numpy dt_polys (shape [N,2] polygon) and rec_boxes (flat [x1,y1,x2,y2]).
        """
        x1, y1, x2, y2 = 0, 0, 0, 0

        if bbox is not None:
            try:
                if isinstance(bbox, np.ndarray):
                    flat = bbox.flatten().tolist()
                    if len(flat) == 4:
                        # rec_boxes: [x1, y1, x2, y2]
                        x1, y1, x2, y2 = int(flat[0]), int(flat[1]), int(flat[2]), int(flat[3])
                    elif len(flat) >= 6:
                        # dt_polys polygon: x0,y0,x1,y1,...
                        xs = [flat[k] for k in range(0, len(flat), 2)]
                        ys = [flat[k] for k in range(1, len(flat), 2)]
                        x1, y1 = int(min(xs)), int(min(ys))
                        x2, y2 = int(max(xs)), int(max(ys))
                elif isinstance(bbox, (list, tuple)) and len(bbox) >= 2:
                    # Check if it is a flat numeric list [x1,y1,x2,y2]
                    if all(isinstance(v, (int, float)) for v in bbox) and len(bbox) == 4:
                        x1, y1, x2, y2 = int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3])
                    elif all(isinstance(v, (int, float)) for v in bbox) and len(bbox) >= 6:
                        nums = [float(v) for v in bbox]
                        xs = [nums[k] for k in range(0, len(nums), 2)]
                        ys = [nums[k] for k in range(1, len(nums), 2)]
                        x1, y1 = int(min(xs)), int(min(ys))
                        x2, y2 = int(max(xs)), int(max(ys))
                    else:
                        # List of [x,y] points or mixed
                        pts_x, pts_y = [], []
                        for p in bbox:
                            if isinstance(p, np.ndarray):
                                f = p.flatten().tolist()
                                if len(f) >= 2:
                                    pts_x.append(f[0]); pts_y.append(f[1])
                            elif isinstance(p, (list, tuple)) and len(p) >= 2:
                                pts_x.append(float(p[0])); pts_y.append(float(p[1]))
                            elif isinstance(p, (int, float)):
                                pts_x.append(float(p))
                        if pts_x and pts_y:
                            x1, y1 = int(min(pts_x)), int(min(pts_y))
                            x2, y2 = int(max(pts_x)), int(max(pts_y))
            except Exception:
                pass

        return {
            "text": text,
            "conf": conf,
            "x": x1,
            "y": y1,
            "w": x2 - x1,
            "h": y2 - y1,
            "cx": (x1 + x2) // 2,
            "cy": (y1 + y2) // 2,
        }

    # ------------------------------------------------------------------
    def _group_words_into_lines(self, words: List[Dict]) -> Dict[int, List[Dict]]:
        """Group words by Y-position into logical lines."""
        if not words:
            return {}

        # Sort by Y position
        sorted_words = sorted(words, key=lambda w: w["cy"])

        lines_dict: Dict[int, List[Dict]] = {}
        current_line_num = 0
        current_y = sorted_words[0]["cy"]
        # Dynamic threshold: 2% of average word height, min 8px
        avg_h = max(sum(w["h"] for w in words) / max(len(words), 1), 8)
        line_threshold = max(int(avg_h * 0.5), 8)  # words within this Y range are on same line

        for word in sorted_words:
            if abs(word["cy"] - current_y) > line_threshold:
                current_line_num += 1
                current_y = word["cy"]
            if current_line_num not in lines_dict:
                lines_dict[current_line_num] = []
            lines_dict[current_line_num].append(word)

        # Sort words within each line by X position
        for ln in lines_dict:
            lines_dict[ln].sort(key=lambda w: w["cx"])

        return lines_dict

    # ------------------------------------------------------------------
    def _extract_fields(
        self,
        words: List[Dict],
        lines_dict: Dict[int, List[Dict]],
        img_h: int,
        warnings: list[str],
    ) -> dict:
        """Extract all fields from OCR words."""

        # Build full text for regex searches
        all_text = " ".join(w["text"] for w in words)
        all_lines = []
        for ln in sorted(lines_dict.keys()):
            line_text = " ".join(w["text"] for w in lines_dict[ln])
            all_lines.append(line_text)

        full_text = "\n".join(all_lines)

        # ── GSTIN ───────────────────────────────────────────────────────
        gstins = _RE_GSTIN.findall(all_text)
        vendor_gstin = gstins[0].upper() if gstins else None

        # ── Vendor name ─────────────────────────────────────────────────
        vendor_name = self._extract_vendor_name(words, lines_dict, img_h)

        # ── Vendor address ─────────────────────────────────────────────
        vendor_address = self._extract_address(words, lines_dict, img_h, vendor_gstin)

        # ── Bill number ───────────────────────────────────────────────
        bill_number = None
        m = _RE_INV_NUMBER.search(full_text)
        if m:
            bill_number = m.group(1).strip()
        else:
            # Fallback: first line with "invoice" or "bill" keyword
            for line in all_lines:
                if re.search(r'\b(?:invoice|bill)\b', line, re.I):
                    m2 = _RE_INV_NUMBER.search(line)
                    if m2:
                        bill_number = m2.group(1).strip()
                        break

        # ── Dates ───────────────────────────────────────────────────────
        all_dates = _extract_all_dates(full_text)
        bill_date = all_dates[0] if all_dates else None

        # Due date: look for "due" keyword
        due_date = None
        for line in all_lines:
            m = re.search(r'(?:due\s*date|payment\s*due)[\s:]+([0-9/\-\.A-Za-z]+)', line, re.I)
            if m:
                due_date = _parse_date(m.group(1))
                break
        if not due_date and len(all_dates) >= 2:
            remaining = [d for d in all_dates if d != bill_date]
            if remaining:
                due_date = remaining[-1]

        # ── PO number ───────────────────────────────────────────────────
        po_number = None
        m = re.search(
            r'(?:p\.?o\.?\s*(?:no|number|#)[.:]?\s*|purchase\s*order\s*(?:no|#)[.:]?\s*)'
            r'([A-Z0-9/\-_]+)',
            full_text, re.IGNORECASE,
        )
        if m:
            po_number = m.group(1).strip()

        # ── Line items (primary extraction) ─────────────────────────────
        line_items = self._extract_line_items(words, lines_dict, img_h)

        # ── Totals (from footer area) ──────────────────────────────────
        footer_text = self._get_footer_text(words, lines_dict, img_h)

        total = self._extract_total(footer_text, full_text)
        subtotal = self._extract_subtotal(footer_text, full_text)
        cgst = self._extract_tax(_RE_CGST, footer_text, full_text)
        sgst = self._extract_tax(_RE_SGST, footer_text, full_text)
        igst = self._extract_tax(_RE_IGST, footer_text, full_text)

        # Fallback: largest amount as total
        if total is None:
            amounts = []
            for m in _RE_AMOUNT.finditer(full_text):
                val = _clean_amount(m.group(1))
                if val and val > 0:
                    amounts.append(val)
            if amounts:
                total = max(amounts)

        # Derive subtotal if missing
        if subtotal is None and total is not None:
            tax_sum = (cgst or 0) + (sgst or 0) + (igst or 0)
            if tax_sum > 0 and tax_sum < total:
                subtotal = round(total - tax_sum, 2)

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
        """Extract vendor name from top region of page."""
        candidates = []

        for ln in sorted(lines_dict.keys()):
            line_words = lines_dict[ln]
            y = line_words[0]["cy"] if line_words else 0

            # Only top 30% of page
            if y > img_h * 0.30:
                break

            text = " ".join(w["text"] for w in line_words)
            conf = sum(w["conf"] for w in line_words) / len(line_words)
            stripped = text.strip()

            if len(stripped) < 3:
                continue
            if _RE_VENDOR_SKIP.match(stripped):
                continue
            if re.fullmatch(r'[\d\s/\-.,]+', stripped):
                continue

            score = conf

            if _RE_COMPANY_SUFFIX.search(stripped):
                score += 50

            caps_ratio = sum(1 for c in stripped if c.isupper()) / max(len(stripped), 1)
            if caps_ratio > 0.5:
                score += 20

            word_count = len(stripped.split())
            if 2 <= word_count <= 8:
                score += 15

            candidates.append((score, stripped))

        if candidates:
            candidates.sort(key=lambda x: x[0], reverse=True)
            return candidates[0][1]

        return None

    # ------------------------------------------------------------------
    def _extract_address(self, words: List[Dict], lines_dict: Dict[int, List[Dict]], img_h: int, gstin: Optional[str]) -> Optional[str]:
        """Extract vendor address from lines near the vendor name."""
        addr_parts = []

        # Find GSTIN line
        gstin_y = None
        for w in words:
            if gstin and gstin in w["text"]:
                gstin_y = w["cy"]
                break

        for ln in sorted(lines_dict.keys()):
            line_words = lines_dict[ln]
            y = line_words[0]["cy"] if line_words else 0

            # Stop at GSTIN
            if gstin_y and y >= gstin_y:
                break

            text = " ".join(w["text"] for w in line_words)
            stripped = text.strip()

            if _RE_VENDOR_SKIP.match(stripped):
                continue
            if re.search(r'(?:gstin|pan|phone|mob|tel|email|fax|invoice|bill)\s*[:\-]?\s*\w', stripped, re.I):
                continue

            # Address indicators
            addr_indicators = [
                r'\b\d{6}\b',
                r'\b(road|street|nagar|colony|sector|phase|block|complex|building|tower|floor|shop|plot)\b',
            ]

            is_addr = any(re.search(p, stripped, re.I) for p in addr_indicators)
            if is_addr or (len(stripped) > 10 and len(stripped.split()) >= 3 and not re.fullmatch(r'[\d\s/\-.,]+', stripped)):
                if not _RE_GSTIN.search(stripped):
                    addr_parts.append(stripped)

        return ", ".join(addr_parts[:4]) if addr_parts else None

    # ------------------------------------------------------------------
    def _get_footer_text(self, words: List[Dict], lines_dict: Dict[int, List[Dict]], img_h: int) -> str:
        """Get text from bottom 25% of page (totals/footer area)."""
        footer_words = [w for w in words if w["cy"] > img_h * 0.75]
        return " ".join(w["text"] for w in footer_words)

    # ------------------------------------------------------------------
    def _extract_total(self, footer_text: str, full_text: str) -> Optional[float]:
        """Extract total amount from footer or full text."""
        # Try footer first
        m = _RE_TOTAL_KEYWORDS.search(footer_text)
        if m:
            # Find amount after the keyword
            rest = footer_text[m.end():]
            m2 = _RE_AMOUNT.search(rest)
            if m2:
                return _clean_amount(m2.group(1))

        # Try full text
        m = _RE_TOTAL_KEYWORDS.search(full_text)
        if m:
            rest = full_text[m.end():]
            m2 = _RE_AMOUNT.search(rest)
            if m2:
                return _clean_amount(m2.group(1))

        return None

    # ------------------------------------------------------------------
    def _extract_subtotal(self, footer_text: str, full_text: str) -> Optional[float]:
        """Extract subtotal/taxable amount."""
        m = _RE_SUBTOTAL_KEYWORDS.search(footer_text)
        if m:
            rest = footer_text[m.end():]
            m2 = _RE_AMOUNT.search(rest)
            if m2:
                return _clean_amount(m2.group(1))

        m = _RE_SUBTOTAL_KEYWORDS.search(full_text)
        if m:
            rest = full_text[m.end():]
            m2 = _RE_AMOUNT.search(rest)
            if m2:
                return _clean_amount(m2.group(1))

        return None

    # ------------------------------------------------------------------
    def _extract_tax(self, pattern: re.Pattern, footer_text: str, full_text: str) -> Optional[float]:
        """Extract tax amount (CGST/SGST/IGST)."""
        m = pattern.search(footer_text)
        if m:
            return _clean_amount(m.group(1))
        m = pattern.search(full_text)
        if m:
            return _clean_amount(m.group(1))
        return None

    # ------------------------------------------------------------------
    # ------------------------------------------------------------------
    def _extract_line_items(
        self,
        words: List[Dict],
        lines_dict: Dict[int, List[Dict]],
        img_h: int,
    ) -> list:
        """
        Extract line items from the invoice table.

        Two-pass approach:
          Pass 1 - detect table region using header + GRAND-TOTAL footer keywords only.
          Pass 2 - if region too narrow (<= 2 lines), scan ALL available lines.

        Each OCR entry is tokenised individually because PaddleOCR 3.x returns
        full text lines, not individual word boxes.
        """
        items = []
        if not lines_dict:
            return items

        all_lns = sorted(lines_dict.keys())
        max_ln = max(all_lns)

        # ── Find table header ─────────────────────────────────────────────────
        table_start = None
        for ln in all_lns:
            lt = ' '.join(w['text'] for w in lines_dict[ln])
            if _RE_TABLE_HEADER.search(lt):
                table_start = ln

        # ── Find table footer — ONLY grand-total level lines ─────────────────
        # NOT "CGST @ 9%" column headers which previously caused early cutoff.
        _RE_GRAND_TOTAL = re.compile(
            r'\b(?:grand\s*total|amount\s*payable|net\s*payable|total\s*payable|'
            r'total\s*invoice\s*value|invoice\s*total|bill\s*total)\b',
            re.IGNORECASE,
        )
        table_end = None
        if table_start is not None:
            for ln in all_lns:
                if ln <= table_start:
                    continue
                lt = ' '.join(w['text'] for w in lines_dict[ln])
                if _RE_GRAND_TOTAL.search(lt):
                    table_end = ln
                    break

        # ── Y-position fallback if header not found ───────────────────────────
        if table_start is None:
            for ln in all_lns:
                y = lines_dict[ln][0]['cy'] if lines_dict[ln] else 0
                if y > img_h * 0.15:
                    table_start = ln
                    break
            if table_start is None:
                table_start = 0

        if table_end is None:
            for ln in reversed(all_lns):
                y = lines_dict[ln][0]['cy'] if lines_dict[ln] else 0
                if y < img_h * 0.88:
                    table_end = ln
                    break
            if table_end is None:
                table_end = max_ln

        # ── Expand region if too narrow ───────────────────────────────────────
        region_lns = [ln for ln in all_lns if table_start <= ln <= table_end]
        if len(region_lns) <= 2:
            logger.info(
                f'Table region too narrow ({len(region_lns)} lines) '
                f'— scanning all {len(all_lns)} lines'
            )
            region_lns = all_lns

        logger.info(f'Table region: lines {table_start} -> {table_end} ({len(region_lns)} of {len(all_lns)})')
        for _ld in all_lns:
            _lt = ' '.join(w['text'] for w in lines_dict[_ld])
            logger.info(f'  OCR L{_ld}: {repr(_lt[:90])}')

        # ── Noise-line filter ─────────────────────────────────────────────────
        _RE_SKIP_LINE = re.compile(
            r'\b(?:bank|branch|ifsc|swift|micr|pan|din|cin|upi|'
            r'authoris|signatory|seal|'
            r'terms|condition|warranty|'
            r'rupees|paise|words|declaration|certified|'
            r'reverse\s*charge|original|duplicate)\b',
            re.IGNORECASE,
        )

        for ln in region_lns:
            if ln not in lines_dict:
                continue

            line_words = lines_dict[ln]
            line_text = ' '.join(w['text'] for w in line_words)

            # Skip pure header rows (keywords, no digits)
            if _RE_TABLE_HEADER.search(line_text) and not re.search(r'\d', line_text):
                logger.debug(f'  L{ln} SKIP header: {repr(line_text[:60])}')
                continue
            # Skip grand total lines
            if _RE_GRAND_TOTAL.search(line_text):
                logger.debug(f'  L{ln} SKIP grand total')
                continue
            # Skip obvious noise lines
            if _RE_SKIP_LINE.search(line_text):
                logger.debug(f'  L{ln} SKIP noise: {repr(line_text[:60])}')
                continue

            # ── Tokenise and classify ─────────────────────────────────────────
            desc_words = []
            numbers = []
            hsn = ''

            for w in line_words:
                wtext = w['text'].strip()
                if not wtext:
                    continue
                for token in wtext.split():
                    tok = token.strip('.,;:')
                    if not tok:
                        continue
                    cleaned = (tok.replace(',', '')
                                  .replace('\u20b9', '')
                                  .replace('Rs.', '')
                                  .replace('Rs', '')
                                  .strip())
                    if re.match(r'^\d+(?:\.\d{1,3})?$', cleaned) and cleaned:
                        val = _clean_amount(cleaned)
                        if val is not None:
                            numbers.append(val)
                    elif re.match(r'^\d{4,8}$', tok) and not hsn and len(numbers) == 0:
                        hsn = tok
                    else:
                        desc_words.append(tok)

            desc = ' '.join(desc_words).strip()
            logger.info(f'  Line {ln}: desc={repr(desc[:50])} nums={numbers} hsn={repr(hsn)}')

            # ── Reject weak lines ─────────────────────────────────────────────
            if not desc or len(numbers) < 1:
                logger.info(f'    -> SKIP (no desc or no numbers)')
                continue
            if len(desc) < 2:
                continue

            # Reject if description is ONLY unit/tax/column-header noise
            desc_clean = re.sub(
                r'\b(?:pcs|nos|units?|kg|gm|ltr|mtr|box|set|pair|each|per|'
                r'output|input|rate|value|taxable|amount|disc|incl|of|tax|@|'
                r'cgst|sgst|igst|cess|gst|hsn|sac|qty|quantity|sr|no|sl|'
                r's\.no|s\.n)\b',
                '', desc, flags=re.IGNORECASE,
            ).strip()
            if not desc_clean or _RE_VENDOR_SKIP.match(desc_clean):
                logger.info(f'    -> SKIP (desc only noise: {repr(desc_clean[:30])})')
                continue

            # ── Parse qty / rate / amount ─────────────────────────────────────
            qty = 1.0
            rate = 0.0
            amount = 0.0

            # De-dup values that appear twice in multi-column OCR output
            unique_numbers = list(dict.fromkeys(numbers))

            if len(unique_numbers) == 1:
                amount = unique_numbers[0]
                rate = amount
            elif len(unique_numbers) == 2:
                a, b = unique_numbers
                if a < 1000 and a == int(a):
                    qty, amount = a, b
                    rate = round(b / a, 2) if a > 0 else b
                else:
                    qty, rate, amount = 1.0, a, b
            elif len(unique_numbers) >= 3:
                # Find qty (small integer), amount (largest value)
                int_candidates = [v for v in unique_numbers if v == int(v) and 0 < v < 10000]
                qty = min(int_candidates) if int_candidates and min(int_candidates) < 1000 else 1.0
                amount = max(unique_numbers)
                # Find rate that best satisfies qty * rate ~= amount
                best_rate, best_diff = amount, float('inf')
                for candidate in unique_numbers:
                    if candidate != qty and candidate != amount:
                        diff = abs(qty * candidate - amount)
                        if diff < best_diff:
                            best_diff, best_rate = diff, candidate
                rate = best_rate if best_diff < amount * 0.25 else round(amount / qty, 2)

            if qty <= 0 or amount <= 0:
                continue

            # Extract GST rate from desc
            gst_rate = 0.0
            gst_m = _RE_GST_RATE.search(desc)
            if gst_m:
                gst_rate = float(gst_m.group(1))
                desc = _RE_GST_RATE.sub('', desc).strip()

            desc = re.sub(r'\s+', ' ', desc).strip()

            items.append({
                'product_name': desc,
                'hsn_sac': hsn,
                'quantity': qty,
                'rate': rate if rate > 0 else round(amount / qty, 2),
                'gst_rate': gst_rate,
                'amount': amount,
            })
            logger.info(f'    -> ITEM: {repr(desc[:40])} qty={qty} rate={rate} amt={amount}')

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

    def _scan_with_nvidia_nim(self, file_bytes: bytes, filename: str) -> dict:
        import base64
        import requests
        import json

        # 1. Convert PDF to image bytes if needed
        lower_name = filename.lower()
        if lower_name.endswith(".pdf") or file_bytes[:4] == b"%PDF":
            image_bytes = _pdf_to_image_bytes(file_bytes)
        else:
            image_bytes = file_bytes

        img_b64 = base64.b64encode(image_bytes).decode("utf-8")

        api_key = settings.NVIDIA_NIM_API_KEY
        model = settings.NVIDIA_NIM_MODEL or "meta/llama-3.2-11b-vision-instruct"

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }

        prompt = (
            "You are an expert bookkeeping and invoice scanning assistant.\n"
            "Analyze the uploaded invoice image and extract all relevant details.\n"
            "Respond ONLY with a valid JSON object. Do not include markdown code block formatting (like ```json), explanations, or other text.\n"
            "IMPORTANT:\n"
            "1. Use double quotes for all keys and string values in the JSON. Never use single quotes and do not include trailing commas.\n"
            "2. LAYOUT ANALYSIS — STRICT SEPARATION OF SELLER AND BUYER:\n"
            "   - Seller/Vendor: The company/individual selling/issuing the bill. Their details are at the very top of the invoice. Identify their name, address, and GSTIN. Use these ONLY for vendor_name, vendor_address, and vendor_gstin.\n"
            "   - Buyer/Customer/Consignee: The company/individual purchasing the goods/services (often under 'Bill To', 'Ship To', 'Consignee', or 'Buyer'). Their details are lower down or in a separate block. You MUST extract their details into buyer_name, buyer_address, and buyer_gstin.\n"
            "   - Do NOT mix up the seller's details with the buyer's details. Keep them strictly separate. Do NOT use the buyer's address or buyer's GSTIN for vendor fields.\n"
            "   - Invoice/Bill number and Date are in the invoice details block. Look at the box/cell labeled 'Invoice No.' and extract the alphanumeric value. Look at the box/cell labeled 'Dated' or 'Date' and extract the date value.\n"
            "3. FIELDS TO EXTRACT:\n"
            "   - vendor_name: The company name of the seller/issuer at the top.\n"
            "   - vendor_gstin: The 15-character GSTIN of the seller at the top.\n"
            "   - vendor_address: The physical address of the seller at the top.\n"
            "   - buyer_name: The company name of the buyer/customer (e.g. Apex Integrations).\n"
            "   - buyer_gstin: The 15-character GSTIN of the buyer/customer.\n"
            "   - buyer_address: The physical address of the buyer/customer.\n"
            "   - bill_number: The exact invoice number.\n"
            "   - bill_date: The date of the invoice (format as YYYY-MM-DD).\n"
            "\n"
            "The JSON must have the following schema:\n"
            "{\n"
            '  "vendor_name": "string or null",\n'
            '  "vendor_gstin": "string or null",\n'
            '  "vendor_address": "string or null",\n'
            '  "buyer_name": "string or null",\n'
            '  "buyer_gstin": "string or null",\n'
            '  "buyer_address": "string or null",\n'
            '  "bill_number": "string or null",\n'
            '  "bill_date": "string or null (format YYYY-MM-DD)",\n'
            '  "due_date": "string or null (format YYYY-MM-DD)",\n'
            '  "po_number": "string or null",\n'
            '  "subtotal": 0.0,\n'
            '  "cgst": 0.0,\n'
            '  "sgst": 0.0,\n'
            '  "igst": 0.0,\n'
            '  "total": 0.0,\n'
            '  "line_items": [\n'
            "    {\n"
            '      "product_name": "string",\n'
            '      "hsn_sac": "string or null",\n'
            '      "quantity": 1.0,\n'
            '      "rate": 0.0,\n'
            '      "gst_rate": 0.0,\n'
            '      "amount": 0.0\n'
            "    }\n"
            "  ]\n"
            "}"
        )

        payload = {
            "model": model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": prompt
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{img_b64}"
                            }
                        }
                    ]
                }
            ],
            "response_format": {"type": "json_object"},
            "temperature": 0.1,
            "max_tokens": 2048
        }

        logger.info(f"Sending vision extraction request to Nvidia NIM with model {model}...")
        response = requests.post(
            "https://integrate.api.nvidia.com/v1/chat/completions",
            headers=headers,
            json=payload,
            timeout=60
        )
        response.raise_for_status()
        res_data = response.json()
        content = res_data["choices"][0]["message"]["content"].strip()

        # Clean markdown code block wraps if LLM outputted them
        if content.startswith("```"):
            lines = content.splitlines()
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines[-1].startswith("```"):
                lines = lines[:-1]
            content = "\n".join(lines).strip()

        # Find first '{' and last '}' to strip any surrounding text/garbage
        first_brace = content.find('{')
        last_brace = content.rfind('}')
        if first_brace != -1 and last_brace != -1 and last_brace > first_brace:
            content = content[first_brace:last_brace+1]

        try:
            cleaned_content = _clean_json_string(content)
            parsed = _robust_json_loads(cleaned_content)
        except Exception as e:
            logger.warning(f"Failed to parse JSON from NIM response, attempting fallback text parsing. Error: {e}")
            try:
                parsed = self._parse_nim_markdown_fallback(content)
            except Exception as fallback_err:
                logger.error(f"Failed to parse JSON from NIM response and fallback parser failed. Raw content was: {repr(content)}")
                raise ValueError(f"Failed to parse JSON from NIM response: {e}. Fallback error: {fallback_err}. Raw content: {content[:500]}")

        # Validate types and set defaults
        result = {
            "vendor_name": parsed.get("vendor_name"),
            "vendor_gstin": parsed.get("vendor_gstin"),
            "vendor_address": parsed.get("vendor_address"),
            "bill_number": parsed.get("bill_number"),
            "bill_date": parsed.get("bill_date"),
            "due_date": parsed.get("due_date"),
            "po_number": parsed.get("po_number"),
            "subtotal": _clean_amount(str(parsed.get("subtotal", 0.0))),
            "cgst": _clean_amount(str(parsed.get("cgst", 0.0))),
            "sgst": _clean_amount(str(parsed.get("sgst", 0.0))),
            "igst": _clean_amount(str(parsed.get("igst", 0.0))),
            "total": _clean_amount(str(parsed.get("total", 0.0))),
            "line_items": [],
            "confidence_scores": {"_engine": "nvidia_nim"},
            "overall_confidence": 0.98,
            "warnings": []
        }

        for item in parsed.get("line_items", []):
            qty = float(item.get("quantity") or 1.0)
            rate = float(item.get("rate") or 0.0)
            amt = float(item.get("amount") or (qty * rate))
            result["line_items"].append({
                "product_name": str(item.get("product_name") or "").strip(),
                "hsn_sac": str(item.get("hsn_sac") or "") if item.get("hsn_sac") else None,
                "quantity": qty,
                "rate": rate,
                "gst_rate": float(item.get("gst_rate") or 0.0),
                "amount": amt
            })

        logger.info(f"Nvidia NIM extraction complete. Extracted {len(result['line_items'])} line items.")
        return result

    def _parse_nim_markdown_fallback(self, content: str) -> dict:
        import re
        parsed = {}
        
        # Helper to find standard bullet point or colon values
        def search_field(patterns: list[str]) -> Optional[str]:
            for pattern in patterns:
                match = re.search(pattern, content, re.IGNORECASE)
                if match:
                    val = match.group(1).strip()
                    val = val.strip("*_:-. \t\n")
                    if val:
                        return val
            return None

        parsed["vendor_name"] = search_field([
            r'\*\s*\*\*Vendor Name:\*\*\s*([^\n\*]+)',
            r'(?:Vendor Name|vendor\'s name)(?:\s*is)?\s*[:\*]*\s*([^\n\*,.]+)',
        ])
        parsed["vendor_gstin"] = search_field([
            r'\*\s*\*\*Vendor GSTIN:\*\*\s*([A-Za-z0-9]+)',
            r'(?:Vendor GSTIN|GSTIN)(?:\s*is)?\s*[:\*]*\s*([A-Za-z0-9]+)',
        ])
        parsed["vendor_address"] = search_field([
            r'\*\s*\*\*Vendor Address:\*\*\s*([^\n\*]+)',
            r'(?:Vendor Address|vendor\'s address)(?:\s*is)?\s*[:\*]*\s*([^\n\*]+)',
        ])
        parsed["bill_number"] = search_field([
            r'\*\s*\*\*Invoice Number:\*\*\s*([A-Za-z0-9/\-_\.]+)',
            r'(?:Invoice Number|Invoice No|Invoice no\.|bill number|invoice number)(?:\s*is)?\s*[:\*]*\s*([A-Za-z0-9/\-_\.]+)',
        ])
        
        raw_date = search_field([
            r'\*\s*\*\*Date:\*\*\s*([^\n\*]+)',
            r'(?:Date|date)(?:\s*is)?\s*[:\*]*\s*([^\n\*]+)',
        ])
        parsed["bill_date"] = _parse_date(raw_date) if raw_date else None
            
        due_date = search_field([
            r'\*\s*\*\*Due Date:\*\*\s*([^\n\*]+)',
            r'(?:Due Date|due date|payment due)(?:\s*is)?\s*[:\*]*\s*([^\n\*]+)',
        ])
        parsed["due_date"] = _parse_date(due_date) if due_date else None

        parsed["po_number"] = search_field([
            r'(?:PO Number|P\.O\.\s*No|PO\s*No|purchase order)(?:\s*is)?\s*[:\*]*\s*([^\n\*]+)',
        ])

        def search_amount(patterns: list[str]) -> float:
            val_str = search_field(patterns)
            if val_str:
                amt = _clean_amount(val_str)
                if amt is not None:
                    return amt
            return 0.0

        parsed["total"] = search_amount([
            r'(?:Total Amount|Total|total amount of)\s*[:\*]*\s*([\d,]+(?:\.\d+)?)',
        ])
        parsed["subtotal"] = search_amount([
            r'(?:Subtotal|Sub-Total|Taxable Amount|Taxable Value)\s*[:\*]*\s*([\d,]+(?:\.\d+)?)',
        ])
        parsed["cgst"] = search_amount([
            r'CGST\s*[:\*]*\s*([\d,]+(?:\.\d+)?%?)',
        ])
        parsed["sgst"] = search_amount([
            r'SGST\s*[:\*]*\s*([\d,]+(?:\.\d+)?%?)',
        ])
        parsed["igst"] = search_amount([
            r'IGST\s*[:\*]*\s*([\d,]+(?:\.\d+)?%?)',
        ])

        # Line items parsing
        line_items = []
        line_items_match = re.search(r'\*\*Line Items:\*\*(.*?)(?:\*\*Tax Details:\*\*|\*\*Total Amount:\*\*|\*\*Payment Terms:\*\*|$)', content, re.DOTALL | re.IGNORECASE)
        if line_items_match:
            items_block = line_items_match.group(1)
            item_blocks = []
            matches = list(re.finditer(r'\*\s*\*\*Product Name:\*\*', items_block, re.IGNORECASE))
            for j in range(len(matches)):
                start = matches[j].start()
                end = matches[j+1].start() if j + 1 < len(matches) else len(items_block)
                item_blocks.append(items_block[start:end])

            for block in item_blocks:
                prod_name = re.search(r'Product Name:\*\*?\s*([^\n\*]+)', block, re.IGNORECASE)
                hsn_sac = re.search(r'HSN/SAC:\*\*?\s*([^\n\*]+)', block, re.IGNORECASE)
                qty_match = re.search(r'Quantity:\*\*?\s*([^\n\*]+)', block, re.IGNORECASE)
                rate_match = re.search(r'Rate:\*\*?\s*([^\n\*]+)', block, re.IGNORECASE)
                gst_match = re.search(r'GST Rate:\*\*?\s*([^\n\*]+)', block, re.IGNORECASE)
                amt_match = re.search(r'Amount:\*\*?\s*([^\n\*]+)', block, re.IGNORECASE)

                if prod_name:
                    p_name = prod_name.group(1).strip("*_:-. \t\n")
                    hsn = hsn_sac.group(1).strip("*_:-. \t\n") if hsn_sac else None
                    
                    qty = 1.0
                    if qty_match:
                        qty_str = qty_match.group(1).strip("*_:-. \t\n")
                        qty_clean = re.sub(r'[^\d.]', '', qty_str)
                        if qty_clean:
                            try:
                                qty = float(qty_clean)
                            except ValueError:
                                pass
                                
                    rate = 0.0
                    if rate_match:
                        rate_str = rate_match.group(1).strip("*_:-. \t\n")
                        rate_clean = re.sub(r'[^\d.]', '', rate_str)
                        if rate_clean:
                            try:
                                rate = float(rate_clean)
                            except ValueError:
                                pass
                                
                    gst = 0.0
                    if gst_match:
                        gst_str = gst_match.group(1).strip("*_:-. \t\n")
                        gst_clean = re.sub(r'[^\d.]', '', gst_str)
                        if gst_clean:
                            try:
                                gst = float(gst_clean)
                            except ValueError:
                                pass
                                
                    amt = qty * rate
                    if amt_match:
                        amt_str = amt_match.group(1).strip("*_:-. \t\n")
                        amt_clean = re.sub(r'[^\d.]', '', amt_str)
                        if amt_clean:
                            try:
                                amt = float(amt_clean)
                            except ValueError:
                                pass

                    line_items.append({
                        "product_name": p_name,
                        "hsn_sac": hsn,
                        "quantity": qty,
                        "rate": rate,
                        "gst_rate": gst,
                        "amount": amt
                    })
        
        if not line_items:
            fallback_prod = search_field([r'Product Name:\*\*?\s*([^\n\*]+)'])
            if fallback_prod:
                line_items.append({
                    "product_name": fallback_prod,
                    "hsn_sac": search_field([r'HSN/SAC:\*\*?\s*([^\n\*]+)']),
                    "quantity": 1.0,
                    "rate": parsed.get("total", 0.0),
                    "gst_rate": 0.0,
                    "amount": parsed.get("total", 0.0)
                })

        parsed["line_items"] = line_items
        return parsed


# ---------------------------------------------------------------------------
# Confidence scoring
# ---------------------------------------------------------------------------

def _compute_confidence(data: dict) -> dict:
    scores = {}

    # ── Header fields (weighted) ──────────────────────────────────────
    header_fields = {
        'vendor_name': 0.15,
        'vendor_gstin': 0.10,
        'bill_number': 0.10,
        'bill_date': 0.05,
    }
    for f, weight in header_fields.items():
        val = data.get(f)
        scores[f] = weight if val not in (None, '', [], 0.0, 0) else 0.0

    # ── Financial totals (weighted) ───────────────────────────────────
    total_fields = {
        'subtotal': 0.10,
        'total': 0.15,
    }
    for f, weight in total_fields.items():
        val = data.get(f)
        scores[f] = weight if val not in (None, '', [], 0.0, 0) else 0.0

    # ── Line items (most important — 35% weight) ──────────────────────
    items = data.get('line_items', [])
    if items:
        # Score based on item quality
        item_score = 0.35
        # Bonus if items have HSN codes
        items_with_hsn = sum(1 for i in items if i.get('hsn_sac'))
        if items_with_hsn > 0:
            item_score += 0.05
        # Bonus if items have GST rates
        items_with_gst = sum(1 for i in items if i.get('gst_rate', 0) > 0)
        if items_with_gst > 0:
            item_score += 0.05
        scores['line_items'] = min(item_score, 0.45)
    else:
        scores['line_items'] = 0.0

    return scores


# ---------------------------------------------------------------------------
# Singleton
# ---------------------------------------------------------------------------

_scanner: Optional[InvoiceScanner] = None


def get_scanner() -> InvoiceScanner:
    global _scanner
    if _scanner is None:
        _scanner = InvoiceScanner()
        logger.info("InvoiceScanner initialised (PaddleOCR pipeline)")
    return _scanner
