from src.domains.inventory.barcodes import (
    barcode_validation_error,
    gtin_has_valid_check_digit,
    normalize_barcode,
)


def test_validates_standard_gtin_check_digits():
    assert gtin_has_valid_check_digit("4006381333931")
    assert not gtin_has_valid_check_digit("4006381333932")
    assert barcode_validation_error("4006381333931") is None
    assert barcode_validation_error("4006381333932") is not None


def test_normalizes_internal_and_gs1_scanner_values():
    assert normalize_barcode("  sku-ab/12 ") == "SKU-AB/12"
    assert (
        normalize_barcode("(01)09506000134352(17)280229(10)LOT42(21)SER7")
        == "09506000134352"
    )


def test_internal_numeric_codes_remain_supported():
    assert normalize_barcode("12345") == "12345"
    assert barcode_validation_error("12345") is None
