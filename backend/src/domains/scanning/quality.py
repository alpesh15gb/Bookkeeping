"""
src/domains/scanning/quality.py

Pure quality signals for OCR bill extraction.

Everything here is side-effect free — no database, no OCR engine, no network —
so it can be unit-tested with a bare interpreter. Both the PaddleOCR pipeline
and the NVIDIA NIM path use these to (a) detect garbage extractions,
(b) reconcile line items against the bill totals, and (c) score confidence
honestly instead of rewarding field *presence*.

The confidence model is deliberately simple: each expected field carries a
weight; a field scores its weight only when a *plausible* value was extracted.
Structural checks (merged/noise rows, totals that don't add up) then pull the
score down. The sum of weights is ≤ 1.0 so callers can treat it as a 0–100%
readiness signal.
"""
from __future__ import annotations

import re
from datetime import datetime
from typing import Any, Dict, List


# Words that should never appear inside a product description or vendor name
# unless the OCR merged a table row / column header into one text blob.
_HEADER_WORDS = {
    "HSN", "SAC", "QTY", "RATE", "GST", "AMOUNT", "AMT", "DESCRIPTION",
    "PARTICULARS", "BUYER", "SELLER", "CGST", "SGST", "IGST", "TOTAL",
    "SUBTOTAL", "VALUE", "TAX", "DISC", "DISCOUNT", "UNIT", "PRICE",
}


def looks_like_ocr_noise(text: Any) -> bool:
    """True when an extracted name is really a merged table row / header blob.

    A clean vendor or product name rarely contains several numeric tokens or
    column-header words. ``"4820 8473 8471 HSN BUYER"`` (a real extraction from
    a synthetic bill) trips every signal here; ``"DESKTOP COMPUTER CORE i5 8GB"``
    trips none.
    """
    s = str(text or "").strip()
    if not s:
        return False

    words = s.split()
    digit_tokens = sum(1 for w in words if any(ch.isdigit() for ch in w))
    upper = {w.upper().rstrip(".:;%") for w in words}
    header_hits = sum(1 for w in upper if w in _HEADER_WORDS)
    digit_chars = sum(1 for ch in s if ch.isdigit())

    # Three or more number tokens = a row of numbers, not a name.
    if digit_tokens >= 3:
        return True

    # A header word jammed together with numbers = merged column header.
    if header_hits >= 1 and digit_chars >= 3:
        return True

    # Two or more header words alone (e.g. "SGST CGST Subtotal").
    if header_hits >= 2:
        return True

    # A long run of digits inside a multi-word blob (HSN + amounts).
    if digit_chars >= 8 and len(words) >= 4:
        return True

    return False


def _clean_amount(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def reconcile_totals(data: Dict[str, Any]) -> List[str]:
    """Compare extracted line items against subtotal and total.

    Returns human-readable warnings for every mismatch found. Amounts are
    considered equal within a small absolute / relative tolerance so that
    rounding and legitimate discounts don't produce false alarms.
    """
    warnings: List[str] = []
    items = data.get("line_items") or []
    if not items:
        return warnings

    line_sum = 0.0
    for item in items:
        amt = _clean_amount(item.get("amount"))
        if amt:
            line_sum += amt
        else:
            line_sum += _clean_amount(item.get("quantity")) * _clean_amount(item.get("rate"))

    def near(a: float, b: float) -> bool:
        return abs(a - b) <= max(1.0, 0.01 * max(abs(a), abs(b)))

    subtotal = data.get("subtotal")
    total = data.get("total")
    cgst = _clean_amount(data.get("cgst"))
    sgst = _clean_amount(data.get("sgst"))
    igst = _clean_amount(data.get("igst"))

    if subtotal is not None and not near(_clean_amount(subtotal), line_sum):
        warnings.append(
            f"Line items add up to {line_sum:,.2f} but the bill's subtotal reads "
            f"{_clean_amount(subtotal):,.2f} — check quantities, rates and discounts."
        )

    if total is not None and subtotal is not None:
        expected = _clean_amount(subtotal) + cgst + sgst + igst
        if not near(_clean_amount(total), expected):
            warnings.append(
                f"Subtotal plus tax ({expected:,.2f}) does not match the bill's "
                f"total of {_clean_amount(total):,.2f}."
            )

    return warnings


def compute_confidence(data: Dict[str, Any]) -> Dict[str, float]:
    """Honest per-field confidence for an OCR extraction.

    Returns ``{field: score}`` where each score is that field's contribution to
    overall readiness. A field scores zero when it is missing *or* when its value
    fails a plausibility check. Structural problems (noise rows, unreconciled
    totals) pull the financial scores down. Sum of scores is ≤ 1.0.
    """
    scores: Dict[str, float] = {}

    # ── Header fields (weighted) ──────────────────────────────────────
    header_fields = {
        "vendor_name": 0.15,
        "vendor_gstin": 0.10,
        "bill_number": 0.10,
        "bill_date": 0.05,
    }
    for field, weight in header_fields.items():
        val = data.get(field)
        scores[field] = weight if val not in (None, "", [], 0.0, 0) else 0.0

    # A vendor name that is OCR noise is worth zero — it is an unverifiable guess.
    if scores.get("vendor_name") and looks_like_ocr_noise(data.get("vendor_name")):
        scores["vendor_name"] = 0.0

    # ── Financial totals (weighted) ───────────────────────────────────
    total_fields = {
        "subtotal": 0.10,
        "total": 0.15,
    }
    for field, weight in total_fields.items():
        val = data.get(field)
        scores[field] = weight if val not in (None, "", [], 0.0, 0) else 0.0

    # ── Line items (most important — 35%+ weight) ─────────────────────
    items = data.get("line_items") or []
    if items:
        item_score = 0.35
        clean_count = sum(1 for i in items if not looks_like_ocr_noise(i.get("product_name")))
        if clean_count == len(items):
            item_score += 0.05  # every row is a plausible product
        if any(i.get("hsn_sac") for i in items):
            item_score += 0.05
        if any(_clean_amount(i.get("gst_rate")) > 0 for i in items):
            item_score += 0.05
        # Noise rows cut the line-item score proportionally.
        item_score -= 0.15 * (1.0 - clean_count / len(items))
        scores["line_items"] = max(min(item_score, 0.45), 0.0)
    else:
        scores["line_items"] = 0.0

    # ── Totals that don't reconcile undercut every financial field ────
    if reconcile_totals(data):
        scores["subtotal"] = 0.0
        scores["total"] = max(scores.get("total", 0.0) * 0.5, 0.0)
        scores["line_items"] = max(scores.get("line_items", 0.0) * 0.6, 0.0)

    return scores


# GSTIN: 2-digit state + 10-char PAN (5 letters, 4 digits, 1 letter) +
# entity code + 'Z' + check digit = 15 chars total.
_GSTIN_RE = re.compile(r"^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]{3}$")


def validate_extraction(data: Dict[str, Any]) -> List[str]:
    """Format-level sanity checks on extracted fields.

    Catches the classic vision-model mistakes — a GSTIN in the bill-number
    slot, a phone number in the bill-number slot, a malformed GSTIN, or an
    unparsable date — without ever blocking the scan. The warnings ride the
    normal warnings channel so the review UI surfaces them.
    """
    warnings: List[str] = []

    gstin = str(data.get("vendor_gstin") or "").strip().upper()
    if gstin and not _GSTIN_RE.match(gstin):
        warnings.append(
            f"Vendor GSTIN '{gstin}' doesn't match the 15-character GSTIN format "
            "(2-digit state + PAN + entity + check) — verify it before saving."
        )

    bill_no = str(data.get("bill_number") or "").strip()
    if bill_no:
        if re.fullmatch(r"[0-9]{10}", bill_no):
            warnings.append(
                "Bill number looks like a 10-digit phone number — verify it is the "
                "invoice number and not a contact number."
            )
        if _GSTIN_RE.match(bill_no.upper()):
            warnings.append(
                "Bill number looks like a GSTIN — verify it is the invoice number "
                "and not a tax registration."
            )

    bill_date = data.get("bill_date")
    if bill_date:
        try:
            datetime.strptime(str(bill_date).strip(), "%Y-%m-%d")
        except (ValueError, TypeError):
            warnings.append(
                f"Bill date '{bill_date}' is not a valid YYYY-MM-DD date — verify it."
            )

    return warnings
