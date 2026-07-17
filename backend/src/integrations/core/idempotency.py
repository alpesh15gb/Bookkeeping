from __future__ import annotations

import inspect
import json
import logging
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Awaitable, Callable

from sqlalchemy.orm import Session
from starlette.requests import Request

from src.integrations.core.auth import (
    AuthenticatedIntegrationRequest,
    IntegrationAuthenticator,
)
from src.integrations.core.exceptions import IntegrationError, InternalIntegrationError
from src.integrations.core.models import IntegrationEventLog
from src.integrations.core.replay import ReplayService
from src.integrations.core.utils import (
    canonical_json_bytes,
    generate_request_id,
    sha256_hex,
    utc_now,
)


logger = logging.getLogger("bookkeeping.integrations")


@dataclass(frozen=True)
class HandlerResult:
    status_code: int
    body: dict[str, Any]


@dataclass(frozen=True)
class IntegrationResult:
    status_code: int
    body: dict[str, Any]
    headers: dict[str, str]


Handler = Callable[
    [Session, AuthenticatedIntegrationRequest],
    HandlerResult | Awaitable[HandlerResult],
]


class IntegrationRequestProcessor:
    def __init__(self, integration_name: str):
        self.integration_name = integration_name
        self.authenticator = IntegrationAuthenticator(integration_name)
        self.replay_service = ReplayService()

    async def process(
        self,
        request: Request,
        db: Session,
        handler: Handler,
    ) -> IntegrationResult:
        request_id = generate_request_id()
        started_at = utc_now()
        started_clock = time.perf_counter()
        raw_body = await request.body()
        payload_hash = sha256_hex(raw_body)
        authenticated: AuthenticatedIntegrationRequest | None = None
        try:
            authenticated = await self.authenticator.authenticate(request, db)
            claim = self.replay_service.claim(db, authenticated)
            if claim.replayed:
                body = json.loads(claim.record.get_response_body() or "{}")
                self._write_log(
                    db,
                    request_id,
                    started_at,
                    started_clock,
                    request,
                    payload_hash,
                    "REPLAYED",
                    200,
                    authenticated,
                    response_hash=claim.record.response_hash,
                )
                db.commit()
                return IntegrationResult(
                    status_code=200,
                    body=body,
                    headers={"Idempotency-Replayed": "true"},
                )

            event_log = self._write_log(
                db,
                request_id,
                started_at,
                started_clock,
                request,
                payload_hash,
                "PROCESSING",
                None,
                authenticated,
            )
            result = handler(db, authenticated)
            if inspect.isawaitable(result):
                result = await result
            response_bytes = canonical_json_bytes(result.body)
            response_hash = sha256_hex(response_bytes)
            claim.record.status = "COMPLETED"
            claim.record.response_status = result.status_code
            claim.record.response_hash = response_hash
            claim.record.set_response_body(response_bytes.decode("utf-8"))
            claim.record.processed_at = utc_now()
            event_log.status = "COMPLETED"
            event_log.response_status = result.status_code
            event_log.response_hash = response_hash
            event_log.processing_time_ms = self._elapsed_ms(started_clock)
            event_log.processed_at = utc_now()
            db.commit()
            return IntegrationResult(result.status_code, result.body, {})
        except IntegrationError as exc:
            db.rollback()
            body = exc.response_body(
                request_id,
                authenticated.envelope.event_id if authenticated else request.headers.get("X-Event-Id"),
                authenticated.external_tenant_id if authenticated else request.headers.get("X-Tenant-Id"),
            )
            self._write_log(
                db,
                request_id,
                started_at,
                started_clock,
                request,
                payload_hash,
                "REJECTED",
                exc.status_code,
                authenticated,
                response_hash=sha256_hex(canonical_json_bytes(body)),
                error_code=exc.code,
            )
            db.commit()
            return IntegrationResult(exc.status_code, body, {})
        except Exception:
            db.rollback()
            logger.exception("Unhandled integration request failure", extra={"request_id": request_id})
            exc = InternalIntegrationError("The integration request could not be processed.")
            body = exc.response_body(
                request_id,
                authenticated.envelope.event_id if authenticated else request.headers.get("X-Event-Id"),
                authenticated.external_tenant_id if authenticated else request.headers.get("X-Tenant-Id"),
            )
            self._write_log(
                db,
                request_id,
                started_at,
                started_clock,
                request,
                payload_hash,
                "FAILED",
                exc.status_code,
                authenticated,
                response_hash=sha256_hex(canonical_json_bytes(body)),
                error_code=exc.code,
            )
            db.commit()
            return IntegrationResult(exc.status_code, body, {})

    def _write_log(
        self,
        db: Session,
        request_id: str,
        started_at: datetime,
        started_clock: float,
        request: Request,
        payload_hash: str,
        status: str,
        response_status: int | None,
        authenticated: AuthenticatedIntegrationRequest | None,
        response_hash: str | None = None,
        error_code: str | None = None,
    ) -> IntegrationEventLog:
        log = IntegrationEventLog(
            request_id=request_id,
            tenant_id=authenticated.internal_tenant_id if authenticated else None,
            connection_id=authenticated.connection.id if authenticated else None,
            integration_name=self.integration_name,
            external_tenant_id=(
                authenticated.external_tenant_id
                if authenticated
                else request.headers.get("X-Tenant-Id")
            ),
            direction="INBOUND",
            method=request.method.upper(),
            path=request.url.path,
            event_id=(
                authenticated.envelope.event_id
                if authenticated
                else request.headers.get("X-Event-Id")
            ),
            idempotency_key=(
                authenticated.envelope.idempotency_key
                if authenticated
                else request.headers.get("X-Idempotency-Key")
            ),
            event_name=authenticated.envelope.event_name if authenticated else None,
            source_id=authenticated.envelope.source_id if authenticated else None,
            signature_hash=sha256_hex(request.headers.get("X-Signature", "")),
            payload_hash=payload_hash,
            response_hash=response_hash,
            response_status=response_status,
            status=status,
            processing_time_ms=self._elapsed_ms(started_clock),
            error_code=error_code,
            started_at=started_at,
            processed_at=utc_now() if status != "PROCESSING" else None,
        )
        db.add(log)
        return log

    @staticmethod
    def _elapsed_ms(started_clock: float) -> int:
        return max(0, round((time.perf_counter() - started_clock) * 1000))
