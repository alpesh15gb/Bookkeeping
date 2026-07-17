from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy.orm import Session
from starlette.requests import Request

from src.integrations.core.exceptions import (
    AuthenticationFailed,
    ErrorDetail,
    IntegrationError,
    TimestampExpired,
)
from src.integrations.core.models import IntegrationConnection
from src.integrations.core.signatures import verify_signature
from src.integrations.core.tenant import TenantResolver
from src.integrations.core.utils import sha256_hex


EVENT_ID_PATTERN = r"^evt_[A-Z0-9]{26}$"
SOURCE_ID_PATTERN = r"^[A-Za-z][A-Za-z0-9_-]{2,100}$"
TENANT_ID_PATTERN = r"^[A-Za-z][A-Za-z0-9_-]{2,100}$"


class EventEnvelope(BaseModel):
    model_config = ConfigDict(extra="allow")

    event_id: str = Field(pattern=EVENT_ID_PATTERN)
    event_name: str = Field(min_length=1, max_length=100)
    event_version: str
    tenant_id: str = Field(pattern=TENANT_ID_PATTERN)
    occurred_at: datetime
    source_system: str
    source_id: str = Field(pattern=SOURCE_ID_PATTERN)
    idempotency_key: str = Field(min_length=1, max_length=255)


@dataclass(frozen=True)
class AuthenticatedIntegrationRequest:
    connection: IntegrationConnection
    internal_tenant_id: Any
    external_tenant_id: str
    envelope: EventEnvelope
    raw_body: bytes
    request_hash: str
    signature_hash: str
    method: str
    path: str


class IntegrationAuthenticator:
    def __init__(self, integration_name: str):
        self.integration_name = integration_name
        self.tenant_resolver = TenantResolver(integration_name)

    async def authenticate(self, request: Request, db: Session) -> AuthenticatedIntegrationRequest:
        raw_body = await request.body()
        api_key = request.headers.get("X-Api-Key")
        if api_key is None or not 32 <= len(api_key) <= 256:
            raise AuthenticationFailed(
                "The API key is missing or unknown.",
                [ErrorDetail("header", "X-Api-Key", "A valid API key is required.")],
            )

        connection, tenant = self.tenant_resolver.resolve(
            db,
            request.headers.get("X-Tenant-Id"),
            api_key,
        )
        if connection is None or tenant is None or not connection.matches_api_key(api_key):
            raise AuthenticationFailed(
                "The API key is missing or unknown.",
                [ErrorDetail("header", "X-Api-Key", "A valid API key is required.")],
            )

        timestamp = self._validate_timestamp(
            request.headers.get("X-Timestamp"),
            connection.clock_skew_seconds,
        )
        signature = request.headers.get("X-Signature")
        verify_signature(
            signature,
            connection.get_hmac_secret(),
            timestamp,
            request.method,
            request.url.path,
            raw_body,
        )
        envelope = self._parse_envelope(raw_body)
        self._validate_consistency(request, envelope)

        return AuthenticatedIntegrationRequest(
            connection=connection,
            internal_tenant_id=tenant.id,
            external_tenant_id=envelope.tenant_id,
            envelope=envelope,
            raw_body=raw_body,
            request_hash=sha256_hex(raw_body),
            signature_hash=sha256_hex(signature or ""),
            method=request.method.upper(),
            path=request.url.path,
        )

    @staticmethod
    def _validate_timestamp(value: str | None, maximum_skew_seconds: int) -> str:
        if value is None or not value.endswith("Z"):
            raise TimestampExpired(
                "The request timestamp is missing, malformed, or expired.",
                [ErrorDetail("header", "X-Timestamp", "An RFC 3339 UTC timestamp with Z suffix is required.")],
            )
        try:
            parsed = datetime.fromisoformat(value[:-1] + "+00:00")
        except ValueError as exc:
            raise TimestampExpired(
                "The request timestamp is missing, malformed, or expired.",
                [ErrorDetail("header", "X-Timestamp", "Timestamp parsing failed.")],
            ) from exc
        skew = abs((datetime.now(timezone.utc) - parsed).total_seconds())
        if skew > maximum_skew_seconds:
            raise TimestampExpired(
                "The request timestamp is outside the allowed replay window.",
                [ErrorDetail("header", "X-Timestamp", f"Maximum clock skew is {maximum_skew_seconds} seconds.")],
            )
        return value

    @staticmethod
    def _parse_envelope(raw_body: bytes) -> EventEnvelope:
        try:
            payload = json.loads(raw_body)
            return EventEnvelope.model_validate(payload)
        except (json.JSONDecodeError, ValidationError, TypeError) as exc:
            raise IntegrationError(
                "The request body is not a valid v1 event envelope.",
                [ErrorDetail("body", "event_envelope", str(exc)[:500])],
            ) from exc

    @staticmethod
    def _validate_consistency(request: Request, envelope: EventEnvelope) -> None:
        checks = (
            ("X-Tenant-Id", envelope.tenant_id),
            ("X-Event-Id", envelope.event_id),
            ("X-Idempotency-Key", envelope.idempotency_key),
        )
        details = [
            ErrorDetail("header", header, "Header does not match the request body.")
            for header, body_value in checks
            if request.headers.get(header) != body_value
        ]
        canonical_key = (
            f"{envelope.tenant_id}:{envelope.event_name}:"
            f"{envelope.source_id}:{envelope.event_version}"
        )
        if envelope.idempotency_key != canonical_key:
            details.append(
                ErrorDetail("body", "idempotency_key", "Value does not match the canonical key formula.")
            )
        if envelope.event_version != "v1":
            details.append(ErrorDetail("body", "event_version", "Only v1 is supported."))
        if details:
            raise IntegrationError("Request headers and event envelope are inconsistent.", details)
