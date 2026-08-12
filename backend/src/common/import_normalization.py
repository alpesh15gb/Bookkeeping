"""Normalization helpers shared by external accounting-data importers."""

import re
from decimal import Decimal
from typing import Optional


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


def next_payment_number(
    base: str,
    lookup,
    contact_id_val,
    amount: Decimal,
    used: set,
) -> Optional[str]:
    """Return a tenant-unique payment number derived from ``base``.

    A single Vyapar transaction can carry several payment rows in
    txn_payment_mapping, so the same base number (VYP-PAY-<txn_id> /
    VYP-BPAY-<txn_id>) can repeat within one backup, and txn_ids are reused
    across backups. If the exact payment already exists in the database (same
    number, contact and amount) it is a re-import of the same record — return
    None so the caller skips it, matching the invoice importer. Otherwise suffix
    the number until it is unique within this tenant and this run.

    ``lookup`` takes a candidate number and returns the matching row (or None),
    so the DB access stays with the caller and this stays unit-testable.
    """
    existing = lookup(base)
    if existing is not None and existing.contact_id == contact_id_val and existing.amount == amount:
        return None
    candidate = base
    suffix = 2
    while candidate in used or lookup(candidate) is not None:
        candidate = f"{base}-{suffix}"
        suffix += 1
    used.add(candidate)
    return candidate
