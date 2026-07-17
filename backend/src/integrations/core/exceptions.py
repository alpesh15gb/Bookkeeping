from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class ErrorDetail:
    location: str
    field: str
    issue: str

    def as_dict(self) -> dict[str, str]:
        return {
            "location": self.location,
            "field": self.field,
            "issue": self.issue,
        }


class IntegrationError(Exception):
    status_code = 400
    code = "VALIDATION_ERROR"
    retryable = False

    def __init__(self, message: str, details: list[ErrorDetail] | None = None):
        super().__init__(message)
        self.message = message
        self.details = details or []

    def response_body(
        self,
        request_id: str,
        event_id: str | None,
        tenant_id: str | None,
    ) -> dict[str, Any]:
        return {
            "success": False,
            "error": {
                "code": self.code,
                "message": self.message,
                "details": [detail.as_dict() for detail in self.details],
                "retryable": self.retryable,
            },
            "meta": {
                "request_id": request_id,
                "event_id": event_id,
                "tenant_id": tenant_id,
                "version": "v1",
            },
        }


class AuthenticationFailed(IntegrationError):
    status_code = 401
    code = "AUTH_FAILED"


class SignatureInvalid(IntegrationError):
    status_code = 403
    code = "SIGNATURE_INVALID"


class TimestampExpired(IntegrationError):
    status_code = 403
    code = "TIMESTAMP_EXPIRED"


class TenantNotResolved(IntegrationError):
    status_code = 403
    code = "TENANT_NOT_RESOLVED"


class TenantDisabled(IntegrationError):
    status_code = 403
    code = "TENANT_DISABLED"


class ReplayDetected(IntegrationError):
    status_code = 409
    code = "REPLAY_DETECTED"


class IdempotencyConflict(IntegrationError):
    status_code = 409
    code = "IDEMPOTENCY_CONFLICT"


class InternalIntegrationError(IntegrationError):
    status_code = 500
    code = "INTERNAL_ERROR"
    retryable = True
