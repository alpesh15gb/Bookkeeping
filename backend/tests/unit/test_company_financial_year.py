from datetime import date

from src.domains.company.services import indian_financial_year


def test_indian_financial_year_boundary_before_april():
    assert indian_financial_year(date(2026, 3, 31)) == (
        date(2025, 4, 1),
        date(2026, 3, 31),
        "2025-26",
    )


def test_indian_financial_year_boundary_from_april():
    assert indian_financial_year(date(2026, 4, 1)) == (
        date(2026, 4, 1),
        date(2027, 3, 31),
        "2026-27",
    )
