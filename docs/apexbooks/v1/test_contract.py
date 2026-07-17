"""Mechanical conformance tests for the canonical Cartunez ↔ ApexBooks v1 contract."""

from __future__ import annotations

import re
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Any, Iterator

import pytest
import yaml
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate as validate_openapi


SPEC_PATH = Path(__file__).with_name("apexbooks-integration-v1.openapi.yaml")
SPEC = yaml.safe_load(SPEC_PATH.read_text(encoding="utf-8"))
FORMAT_CHECKER = FormatChecker()
HTTP_METHODS = {"get", "put", "post", "delete", "patch", "head", "options", "trace"}
REQUIRED_HEADERS = {
    "X-Api-Key",
    "X-Tenant-Id",
    "X-Event-Id",
    "X-Idempotency-Key",
    "X-Timestamp",
    "X-Signature",
}


def resolve(reference_or_value: Any) -> Any:
    value = reference_or_value
    seen: set[str] = set()
    while isinstance(value, dict) and set(value) == {"$ref"}:
        reference = value["$ref"]
        assert reference.startswith("#/"), f"Only internal references are permitted: {reference}"
        assert reference not in seen, f"Reference cycle while resolving {reference}"
        seen.add(reference)
        current: Any = SPEC
        for part in reference[2:].split("/"):
            current = current[part.replace("~1", "/").replace("~0", "~")]
        value = current
    return value


def walk(value: Any) -> Iterator[Any]:
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def dereference(value: Any) -> Any:
    """Inline internal references so draft-2020 unevaluatedProperties sees every branch."""
    if isinstance(value, dict) and set(value) == {"$ref"}:
        return dereference(resolve(value))
    if isinstance(value, dict):
        return {key: dereference(child) for key, child in value.items()}
    if isinstance(value, list):
        return [dereference(child) for child in value]
    return value


def operations() -> Iterator[tuple[str, str, dict[str, Any]]]:
    for path, path_item in SPEC["paths"].items():
        for method, operation in path_item.items():
            if method in HTTP_METHODS:
                yield path, method, operation


def validate(instance: Any, schema: dict[str, Any]) -> None:
    validator = Draft202012Validator(dereference(schema), format_checker=FORMAT_CHECKER)
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.path))
    assert not errors, "\n".join(
        f"{'.'.join(map(str, error.absolute_path)) or '<root>'}: {error.message}"
        for error in errors
    )


def request_example(operation: dict[str, Any]) -> dict[str, Any]:
    media = operation["requestBody"]["content"]["application/json"]
    assert len(media["examples"]) == 1
    example = resolve(next(iter(media["examples"].values())))
    return example["value"]


def round_minor(value: int, rate_bps: int) -> int:
    return int(
        (Decimal(value) * Decimal(rate_bps) / Decimal(10000)).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        )
    )


def assert_gst(gst: dict[str, Any], seller_state: str, supply_state: str) -> None:
    assert gst["tax_amount_minor"] == (
        gst["cgst_amount_minor"]
        + gst["sgst_amount_minor"]
        + gst["igst_amount_minor"]
        + gst["cess_amount_minor"]
    )
    assert gst["cgst_amount_minor"] == round_minor(
        gst["taxable_value_minor"], gst["cgst_rate_bps"]
    )
    assert gst["sgst_amount_minor"] == round_minor(
        gst["taxable_value_minor"], gst["sgst_rate_bps"]
    )
    assert gst["igst_amount_minor"] == round_minor(
        gst["taxable_value_minor"], gst["igst_rate_bps"]
    )
    assert gst["cess_amount_minor"] == round_minor(
        gst["taxable_value_minor"], gst["cess_rate_bps"]
    )
    if seller_state == supply_state:
        assert gst["igst_rate_bps"] == gst["igst_amount_minor"] == 0
        assert gst["cgst_rate_bps"] + gst["sgst_rate_bps"] == gst["gst_rate_bps"]
    else:
        assert gst["cgst_rate_bps"] == gst["cgst_amount_minor"] == 0
        assert gst["sgst_rate_bps"] == gst["sgst_amount_minor"] == 0
        assert gst["igst_rate_bps"] == gst["gst_rate_bps"]


def assert_commercial_line(line: dict[str, Any], seller_state: str, supply_state: str) -> None:
    currencies = {
        line["unit_price"]["currency_code"],
        line["discount"]["currency_code"],
        line.get("line_total", line.get("refund_total"))["currency_code"],
    }
    assert len(currencies) == 1
    gross = line["unit_price"]["amount_minor"] * line["quantity"]
    discounted = gross - line["discount"]["amount_minor"]
    gst = line["gst"]
    assert discounted >= 0
    assert gst["discount_minor"] == line["discount"]["amount_minor"]
    assert_gst(gst, seller_state, supply_state)
    total = gst["taxable_value_minor"] + gst["tax_amount_minor"]
    if line["tax_inclusive"]:
        assert discounted == total
    else:
        assert discounted == gst["taxable_value_minor"]
    assert line.get("line_total", line.get("refund_total"))["amount_minor"] == total


def test_openapi_document_and_schema_dialect() -> None:
    validate_openapi(SPEC)
    assert SPEC["openapi"] == "3.1.0"
    assert SPEC["jsonSchemaDialect"] == "https://json-schema.org/draft/2020-12/schema"
    assert len(SPEC["paths"]) == 11
    assert len(list(operations())) == 11
    for name, schema in SPEC["components"]["schemas"].items():
        Draft202012Validator.check_schema(schema)


def test_all_references_resolve_and_all_components_are_referenced() -> None:
    references = {
        node["$ref"]
        for node in walk(SPEC)
        if isinstance(node, dict) and isinstance(node.get("$ref"), str)
    }
    for reference in references:
        resolve({"$ref": reference})

    schema_references = {
        reference.removeprefix("#/components/schemas/")
        for reference in references
        if reference.startswith("#/components/schemas/")
    }
    assert set(SPEC["components"]["schemas"]) == schema_references

    example_references = {
        reference.removeprefix("#/components/examples/")
        for reference in references
        if reference.startswith("#/components/examples/")
    }
    assert set(SPEC["components"]["examples"]) == example_references


def test_every_operation_is_complete_and_has_no_undefined_path_parameter() -> None:
    operation_ids: set[str] = set()
    for path, method, operation in operations():
        assert operation["operationId"] not in operation_ids
        operation_ids.add(operation["operationId"])
        assert operation["security"] if "security" in operation else SPEC["security"]
        assert operation["requestBody"]["required"] is True
        assert "application/json" in operation["requestBody"]["content"]
        assert operation["responses"]
        assert {"408", "429", "500", "502", "503", "504"}.issubset(operation["responses"])

        parameters = [resolve(parameter) for parameter in operation.get("parameters", [])]
        header_names = {p["name"] for p in parameters if p["in"] == "header"}
        assert header_names == REQUIRED_HEADERS
        declared_path_names = {p["name"] for p in parameters if p["in"] == "path"}
        actual_path_names = set(re.findall(r"\{([^}]+)\}", path))
        assert declared_path_names == actual_path_names
        assert all(p["required"] is True for p in parameters)


def test_retryable_statuses_have_retryable_error_examples() -> None:
    retryable = {str(status) for status in SPEC["x-retry-policy"]["retryable_http_statuses"]}
    for _, _, operation in operations():
        for status in retryable:
            response = resolve(operation["responses"][status])
            media = response["content"]["application/json"]
            example = resolve(next(iter(media["examples"].values())))["value"]
            assert example["success"] is False
            assert example["error"]["retryable"] is True


def test_every_request_example_validates_and_matches_its_envelope() -> None:
    for path, method, operation in operations():
        media = operation["requestBody"]["content"]["application/json"]
        example = request_example(operation)
        validate(example, media["schema"])
        assert example["event_version"] == "v1"
        assert example["idempotency_key"] == (
            f"{example['tenant_id']}:{example['event_name']}:"
            f"{example['source_id']}:{example['event_version']}"
        )

        if "external_order_id" in path:
            nested_id = (
                example.get("order", {}).get("medusa_order_id")
                or example.get("cancellation", {}).get("medusa_order_id")
            )
            assert nested_id == example["source_id"]
        elif example["event_name"] == "order.created":
            assert example["order"]["medusa_order_id"] == example["source_id"]
        elif example["event_name"] == "payment.captured":
            assert example["payment"]["medusa_payment_id"] == example["source_id"]
        elif example["event_name"] == "payment.refunded":
            assert example["refund"]["medusa_refund_id"] == example["source_id"]
        elif example["event_name"] == "return.created":
            assert example["return"]["medusa_return_id"] == example["source_id"]
        elif example["event_name"] == "customer.created":
            assert example["customer"]["medusa_customer_id"] == example["source_id"]
        elif example["event_name"] == "product.changed":
            assert example["product"]["apexbooks_product_id"] == example["source_id"]
        elif example["event_name"] == "price.updated":
            assert example["price_update"]["apexbooks_product_id"] == example["source_id"]
        elif example["event_name"] == "inventory.updated":
            assert example["inventory_update"]["apexbooks_product_id"] == example["source_id"]
        elif example["event_name"] == "customer.updated":
            assert example["customer"]["apexbooks_customer_id"] == example["source_id"]
        else:
            pytest.fail(f"Unhandled event example: {example['event_name']}")


def test_every_response_example_validates() -> None:
    validated = 0
    for response_name, response_component in SPEC["components"]["responses"].items():
        response = resolve(response_component)
        media = response.get("content", {}).get("application/json")
        if not media:
            continue
        for example_reference in media.get("examples", {}).values():
            example = resolve(example_reference)["value"]
            validate(example, media["schema"])
            validated += 1
    assert validated == len(SPEC["components"]["responses"])


def test_order_and_refund_examples_reconcile_exactly() -> None:
    for example_name in ("OrderCreatedRequestExample", "OrderUpdatedRequestExample"):
        order = SPEC["components"]["examples"][example_name]["value"]["order"]
        for line in order["lines"]:
            assert_commercial_line(
                line, order["seller_state_code"], order["place_of_supply_state_code"]
            )
        shipping = order["shipping"]
        shipping_line = {**shipping, "quantity": 1}
        assert_commercial_line(
            shipping_line, order["seller_state_code"], order["place_of_supply_state_code"]
        )
        totals = order["totals"]
        assert totals["items_gross"]["amount_minor"] == sum(
            line["unit_price"]["amount_minor"] * line["quantity"] for line in order["lines"]
        )
        assert totals["discount_total"]["amount_minor"] == sum(
            line["discount"]["amount_minor"] for line in order["lines"]
        ) + shipping["discount"]["amount_minor"]
        assert totals["taxable_total"]["amount_minor"] == sum(
            line["gst"]["taxable_value_minor"] for line in order["lines"]
        ) + shipping["gst"]["taxable_value_minor"]
        assert totals["tax_total"]["amount_minor"] == sum(
            line["gst"]["tax_amount_minor"] for line in order["lines"]
        ) + shipping["gst"]["tax_amount_minor"]
        assert totals["shipping_total"]["amount_minor"] == shipping["line_total"]["amount_minor"]
        assert totals["grand_total"]["amount_minor"] == sum(
            line["line_total"]["amount_minor"] for line in order["lines"]
        ) + shipping["line_total"]["amount_minor"]

    refund = SPEC["components"]["examples"]["PaymentRefundedRequestExample"]["value"]["refund"]
    for line in refund["lines"]:
        assert_commercial_line(line, "27", "27")
        if line["related_medusa_return_id"] is not None:
            assert line["restock"] is False
    assert refund["amount"]["amount_minor"] == sum(
        line["refund_total"]["amount_minor"] for line in refund["lines"]
    )


def test_no_unfinished_contract_language() -> None:
    text = SPEC_PATH.read_text(encoding="utf-8").lower()
    forbidden = (
        "to" + "do",
        "tb" + "d",
        "place" + "holder",
        "example" + ".com",
        "implement " + "later",
        "not " + "defined",
    )
    assert not [term for term in forbidden if term in text]
