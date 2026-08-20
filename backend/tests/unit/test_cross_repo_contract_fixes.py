import asyncio
import json

import pytest
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError


def test_application_imports_with_admin_router():
    from src.main import app

    assert app is not None


def test_request_validation_errors_are_readable():
    from src.main import request_validation_handler

    request = Request({"type": "http", "method": "POST", "path": "/", "headers": []})
    error = RequestValidationError([{
        "type": "string_pattern_mismatch",
        "loc": ("body", "hsn_sac"),
        "msg": "String should match pattern",
        "input": "12345",
    }])
    response = asyncio.run(request_validation_handler(request, error))
    body = json.loads(response.body)

    assert response.status_code == 422
    assert body["detail"] == "hsn_sac: String should match pattern"
    assert body["code"] == "VALIDATION_ERROR"


def test_admin_access_token_uses_supported_scope_argument(monkeypatch):
    from src.core import security

    monkeypatch.setattr(security, "SECRET_KEY", "test-secret")
    token = security.create_access_token("00000000-0000-0000-0000-000000000001", scopes=["admin"])
    payload = security.decode_token(token, expected_type="access")

    assert payload["scopes"] == ["admin"]


def test_product_hsn_requires_six_to_eight_digits():
    from src.schemas.master_schemas import ProductCreate

    valid = ProductCreate(name="Test item", hsn_sac="123456", product_type="GOODS", uom="PCS")
    assert valid.hsn_sac == "123456"

    with pytest.raises(ValidationError):
        ProductCreate(name="Test item", hsn_sac="12345", product_type="GOODS", uom="PCS")
