from __future__ import annotations

import hashlib
import hmac
import re

from src.integrations.core.exceptions import ErrorDetail, SignatureInvalid


SIGNATURE_PATTERN = re.compile(r"^sha256=([a-f0-9]{64})$")


def canonical_signature_input(
    timestamp: str,
    method: str,
    raw_path: str,
    raw_body: bytes,
) -> bytes:
    prefix = f"{timestamp}.{method.upper()}.{raw_path}.".encode("utf-8")
    return prefix + raw_body


def create_signature(
    secret: str,
    timestamp: str,
    method: str,
    raw_path: str,
    raw_body: bytes,
) -> str:
    digest = hmac.new(
        secret.encode("utf-8"),
        canonical_signature_input(timestamp, method, raw_path, raw_body),
        hashlib.sha256,
    ).hexdigest()
    return f"sha256={digest}"


def verify_signature(
    supplied_signature: str | None,
    secret: str,
    timestamp: str,
    method: str,
    raw_path: str,
    raw_body: bytes,
) -> None:
    if supplied_signature is None or SIGNATURE_PATTERN.fullmatch(supplied_signature) is None:
        raise SignatureInvalid(
            "The request signature is missing or malformed.",
            [ErrorDetail("header", "X-Signature", "Expected sha256 followed by 64 lowercase hexadecimal characters.")],
        )
    expected = create_signature(secret, timestamp, method, raw_path, raw_body)
    if not hmac.compare_digest(supplied_signature, expected):
        raise SignatureInvalid(
            "The request signature is invalid.",
            [ErrorDetail("header", "X-Signature", "Signature verification failed.")],
        )
