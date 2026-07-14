"""Barcode normalization and GS1/GTIN validation helpers."""
import re
from typing import Optional


_GS1_GTIN = re.compile(r"\(01\)(\d{14})")
_GTIN_LENGTHS = {8, 12, 13, 14}


def gtin_has_valid_check_digit(value: str) -> bool:
    """Validate a GTIN-8/12/13/14 using the GS1 modulo-10 algorithm."""
    if not value.isdigit() or len(value) not in _GTIN_LENGTHS:
        return False
    digits = [int(char) for char in value]
    expected = digits.pop()
    total = sum(
        digit * (3 if index % 2 == 0 else 1)
        for index, digit in enumerate(reversed(digits))
    )
    return (10 - (total % 10)) % 10 == expected


def normalize_barcode(value: Optional[str]) -> Optional[str]:
    """Normalize a stored or scanned product identifier.

    Parenthesized GS1 element strings are reduced to their AI (01) GTIN so a
    label containing batch/expiry/serial data can still identify the product.
    Internal barcodes remain supported and are compared case-insensitively.
    """
    if value is None:
        return None
    cleaned = value.strip().replace("\x1d", "")
    if not cleaned:
        return None
    match = _GS1_GTIN.search(cleaned)
    if match:
        cleaned = match.group(1)
    return cleaned.upper()


def barcode_validation_error(value: Optional[str]) -> Optional[str]:
    """Return a user-facing error for malformed standard GTINs, if any."""
    normalized = normalize_barcode(value)
    if not normalized:
        return None
    if normalized.isdigit() and len(normalized) in _GTIN_LENGTHS:
        if not gtin_has_valid_check_digit(normalized):
            return "GTIN/EAN/UPC check digit is invalid. Check the scanned or entered barcode."
    return None
