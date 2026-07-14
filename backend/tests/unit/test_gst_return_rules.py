from datetime import date
from decimal import Decimal

from src.api.v1.gst import _b2cl_threshold


def test_b2cl_threshold_before_august_2024():
    assert _b2cl_threshold(date(2024, 7, 31)) == Decimal("250000.00")


def test_b2cl_threshold_from_august_2024():
    assert _b2cl_threshold(date(2024, 8, 1)) == Decimal("100000.00")
