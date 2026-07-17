from pathlib import Path


CONTRACT = Path(__file__).resolve().parents[5] / "docs" / "apexbooks" / "v1" / "apexbooks-integration-v1.openapi.yaml"


def test_frozen_contract_has_no_fulfillment_lifecycle_operations():
    contract = CONTRACT.read_text(encoding="utf-8")
    assert "fulfillment.created" not in contract
    assert "shipment.completed" not in contract
    assert "/fulfillments" not in contract
    assert "/shipments" not in contract


def test_frozen_contract_has_no_payment_failed_operation():
    contract = CONTRACT.read_text(encoding="utf-8")
    assert "payment.failed" not in contract
    assert "/payments/failed" not in contract
