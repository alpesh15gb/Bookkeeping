"""Normalization helpers shared by external accounting-data importers."""

import re


def normalize_hsn_sac(value: object, default: str = "998313") -> str:
    """Return an HSN/SAC value that fits ApexBooks' VARCHAR(8) columns.

    External systems commonly export display-formatted values such as
    ``8443 32 90``, ``8443-32-90``, or ``SAC 998313``. HSN/SAC identifiers
    are stored without those separators and labels.
    """
    compact = re.sub(r"[^0-9A-Za-z]", "", str(value or "")).upper()
    if not compact or compact in {"NA", "NIL", "NONE"}:
        return default
    digits = re.sub(r"\D", "", compact)
    return (digits if len(digits) >= 4 else compact)[:8]
