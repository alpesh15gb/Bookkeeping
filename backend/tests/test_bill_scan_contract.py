"""Safety contract tests for OCR bill capture.

The scanner is allowed to create missing masters, but OCR-derived financial data
must enter the normal vendor-bill workflow as DRAFT so a user explicitly
finalizes it after review.
"""
from __future__ import annotations

import ast
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[1] / "src" / "api" / "v1" / "bill_scan.py"


def _scan_save_function() -> ast.FunctionDef:
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "scan_save":
            return node
    raise AssertionError("scan_save function not found")


def test_scan_save_forces_draft_bill_creation() -> None:
    function = _scan_save_function()
    payload_dict = None

    for node in ast.walk(function):
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(target, ast.Name) and target.id == "bill_create_payload" for target in node.targets):
            continue
        if isinstance(node.value, ast.Dict):
            payload_dict = node.value
            break

    assert payload_dict is not None, "scan_save must build bill_create_payload explicitly"

    values = {
        key.value: value
        for key, value in zip(payload_dict.keys, payload_dict.values)
        if isinstance(key, ast.Constant) and isinstance(key.value, str)
    }
    assert "post_on_create" in values, "OCR scan-save must explicitly control posting"
    assert isinstance(values["post_on_create"], ast.Constant)
    assert values["post_on_create"].value is False, "OCR scan-save must create a DRAFT bill"
