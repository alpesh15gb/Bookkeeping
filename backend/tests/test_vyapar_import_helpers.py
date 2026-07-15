import pytest

from src.common.import_normalization import normalize_hsn_sac


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
