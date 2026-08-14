"""
tests/test_scan_quality.py

Pure unit tests for the OCR extraction quality signals. These deliberately
import only the pure module so the suite can run without the full app stack:

    python -m pytest tests/test_scan_quality.py --noconftest -q
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from src.domains.scanning.quality import (  # noqa: E402
    compute_confidence,
    looks_like_ocr_noise,
    reconcile_totals,
    validate_extraction,
)


# ── looks_like_ocr_noise ─────────────────────────────────────────────────────

def test_clean_names_are_not_noise():
    for name in [
        "MAHAVEER COMPUTERS",
        "M/s Keystone Infra Pvt Ltd",
        "9 House Kitchen",
        "DESKTOP COMPUTER CORE i5 8GB",
        "OPTICAL MOUSE USB",
        "NOTE BOOK A4 200 PAGES",
        "I-HEAP ELECTRONICS PVT LTD",
    ]:
        assert looks_like_ocr_noise(name) is False, name


def test_merged_table_row_is_noise():
    # Real extraction from a synthetic vendor bill.
    assert looks_like_ocr_noise("4820 8473 8471 HSN BUYER") is True


def test_merged_footer_row_is_noise():
    assert looks_like_ocr_noise("GRAND TOTAL13,688.0 2.000.00 GST% AMOUNT") is True


def test_header_words_alone_are_noise():
    assert looks_like_ocr_noise("SGST CGST Subtotal") is True


def test_empty_and_none_are_not_noise():
    assert looks_like_ocr_noise(None) is False
    assert looks_like_ocr_noise("") is False


# ── reconcile_totals ─────────────────────────────────────────────────────────

def _bill(subtotal, total, lines, cgst=0.0, sgst=0.0, igst=0.0):
    return {
        "subtotal": subtotal,
        "total": total,
        "cgst": cgst,
        "sgst": sgst,
        "igst": igst,
        "line_items": lines,
    }


def test_totals_that_reconcile_produce_no_warnings():
    data = _bill(
        11600.0,
        13688.0,
        [
            {"quantity": 1, "rate": 9000.0, "amount": 9000.0},
            {"quantity": 4, "rate": 500.0, "amount": 2000.0},
            {"quantity": 5, "rate": 120.0, "amount": 600.0},
        ],
        cgst=1044.0,
        sgst=1044.0,
    )
    assert reconcile_totals(data) == []


def test_line_subtotal_mismatch_is_flagged():
    data = _bill(
        18.0,
        13688.0,
        [
            {"quantity": 1, "rate": 200.0, "amount": 200.0},
            {"quantity": 1, "rate": 18.0, "amount": 18.0},
            {"quantity": 600, "rate": 15.0, "amount": 9000.0},
        ],
        cgst=9.0,
        sgst=9.0,
    )
    warnings = reconcile_totals(data)
    assert any("subtotal" in w for w in warnings)
    assert any("tax" in w for w in warnings)


def test_reconcile_uses_amount_when_present():
    # amount is authoritative; qty*rate may differ (discounts).
    data = _bill(9500.0, 11210.0, [{"quantity": 10, "rate": 1000.0, "amount": 9500.0}], cgst=855.0, sgst=855.0)
    assert reconcile_totals(data) == []


def test_reconcile_empty_lines_are_silent():
    assert reconcile_totals({"line_items": []}) == []


# ── compute_confidence ───────────────────────────────────────────────────────

def test_garbage_extraction_scores_low():
    """The exact garbage result seen on a synthetic bill must NOT score ~0.9."""
    data = {
        "vendor_name": "4820 8473 8471 HSN BUYER",
        "vendor_gstin": "27ABCDE1234F1Z5",
        "bill_number": None,
        "bill_date": None,
        "subtotal": 18.0,
        "total": 13688.0,
        "cgst": 9.0,
        "sgst": 9.0,
        "line_items": [
            {"product_name": "NOTE BOOK A4 PAGES DESKTOP COMPUTER CORE i5 8GB", "quantity": 1, "rate": 200.0, "amount": 200.0},
            {"product_name": "SGST CGST Subtotal", "quantity": 1, "rate": 18.0, "amount": 18.0},
            {"product_name": "GRAND TOTAL13,688.0 2.000.00 GST% AMOUNT", "quantity": 600, "rate": 15.0, "amount": 9000.0},
        ],
    }
    scores = compute_confidence(data)
    assert scores["vendor_name"] == 0.0          # noise name earns nothing
    assert scores["bill_number"] == 0.0          # missing essential field
    assert scores["subtotal"] == 0.0             # unreconciled
    total = round(sum(scores.values()), 2)
    assert total <= 0.5, f"garbage extraction scored {total}"  # was ~0.9


def test_clean_extraction_scores_high():
    data = {
        "vendor_name": "MAHAVEER COMPUTERS",
        "vendor_gstin": "27AAHCM1234F1Z5",
        "bill_number": "MC2025-26/7164",
        "bill_date": "2026-08-12",
        "subtotal": 11600.0,
        "total": 13688.0,
        "cgst": 1044.0,
        "sgst": 1044.0,
        "line_items": [
            {"product_name": "DESKTOP COMPUTER CORE i5 8GB", "hsn_sac": "8471", "quantity": 1, "rate": 9000.0, "amount": 9000.0, "gst_rate": 18},
            {"product_name": "OPTICAL MOUSE USB", "hsn_sac": "8473", "quantity": 4, "rate": 500.0, "amount": 2000.0, "gst_rate": 18},
            {"product_name": "NOTE BOOK A4 200 PAGES", "hsn_sac": "4820", "quantity": 5, "rate": 120.0, "amount": 600.0, "gst_rate": 18},
        ],
    }
    scores = compute_confidence(data)
    assert sum(scores.values()) >= 0.9


def test_confidence_never_exceeds_one():
    data = {
        "vendor_name": "MAHAVEER COMPUTERS",
        "vendor_gstin": "27AAHCM1234F1Z5",
        "bill_number": "MC2025-26/7164",
        "bill_date": "2026-08-12",
        "subtotal": 11600.0,
        "total": 13688.0,
        "cgst": 1044.0,
        "sgst": 1044.0,
        "line_items": [
            {"product_name": "DESKTOP", "hsn_sac": "8471", "quantity": 1, "rate": 9000.0, "amount": 9000.0, "gst_rate": 18},
        ],
    }
    scores = compute_confidence(data)
    assert round(sum(scores.values()), 2) <= 1.0


# ── validate_extraction ──────────────────────────────────────────────────────

def test_validate_extraction_clean_data_no_warnings():
    data = {
        "vendor_gstin": "27AAHCM1234F1Z5",
        "bill_number": "INV-2026-00117",
        "bill_date": "2026-08-10",
    }
    assert validate_extraction(data) == []


def test_validate_extraction_flags_bad_gstin():
    data = {"vendor_gstin": "not-a-gstin"}
    warnings = validate_extraction(data)
    assert any("GSTIN" in w for w in warnings)


def test_validate_extraction_flags_gstin_as_bill_number():
    # The classic vision-model mistake: bill_number slot filled with the GSTIN
    data = {"bill_number": "27ABCDE1234F1Z5"}
    warnings = validate_extraction(data)
    assert any("GSTIN" in w and "bill number" in w.lower() for w in warnings)


def test_validate_extraction_flags_phone_like_bill_number():
    data = {"bill_number": "9876543210"}
    warnings = validate_extraction(data)
    assert any("phone number" in w for w in warnings)


def test_validate_extraction_flags_bad_date():
    data = {"bill_date": "08/10/2026"}
    warnings = validate_extraction(data)
    assert any("date" in w.lower() for w in warnings)
