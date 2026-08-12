import pytest
from decimal import Decimal

from src.common.import_normalization import normalize_hsn_sac, next_payment_number


class _Row:
    def __init__(self, contact_id, amount):
        self.contact_id = contact_id
        self.amount = amount


def _lookup(rows):
    def lookup(number):
        return rows.get(number)
    return lookup


@pytest.mark.parametrize(
    ("base", "db_rows", "used", "contact_id", "amount", "expected"),
    [
        # Fresh number → returned as-is
        ("VYP-BPAY-19", {}, set(), "c1", Decimal("100"), "VYP-BPAY-19"),
        # Same base used twice in one run (multiple payments per txn) → suffixed
        ("VYP-BPAY-19", {}, {"VYP-BPAY-19"}, "c1", Decimal("100"), "VYP-BPAY-19-2"),
        ("VYP-BPAY-19", {}, {"VYP-BPAY-19", "VYP-BPAY-19-2"}, "c1", Decimal("100"), "VYP-BPAY-19-3"),
        # Exact payment already imported (same number, contact, amount) → skip (None)
        ("VYP-BPAY-19", {"VYP-BPAY-19": _Row("c1", Decimal("100"))}, set(), "c1", Decimal("100"), None),
        # Base taken in DB by a DIFFERENT payment → suffix instead of skipping
        ("VYP-BPAY-19", {"VYP-BPAY-19": _Row("c2", Decimal("50"))}, set(), "c1", Decimal("100"), "VYP-BPAY-19-2"),
        # Suffixed candidate also taken in DB → next suffix
        (
            "VYP-BPAY-19",
            {"VYP-BPAY-19": _Row("c2", Decimal("50")), "VYP-BPAY-19-2": _Row("c3", Decimal("20"))},
            set(),
            "c1",
            Decimal("100"),
            "VYP-BPAY-19-3",
        ),
        # Customer-receipt numbers go through the same helper
        ("VYP-PAY-7", {}, set(), "c1", Decimal("250"), "VYP-PAY-7"),
    ],
)
def test_next_payment_number(base, db_rows, used, contact_id, amount, expected):
    assert next_payment_number(base, _lookup(db_rows), contact_id, amount, used) == expected


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        ("8443 32 90", "84433290"),
        ("8443-32-90", "84433290"),
        (" 998313 ", "998313"),
        ("sac 998313", "998313"),
        ("N/A", "998313"),
        (None, "998313"),
        ("1234567890", "12345678"),
    ],
)
def test_normalize_hsn_sac(source, expected):
    assert normalize_hsn_sac(source) == expected
