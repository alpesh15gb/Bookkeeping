from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass
from datetime import timedelta, timezone
from typing import Any
from urllib.parse import urlsplit

import requests
from sqlalchemy.orm import Session

from src.core.config import settings
from src.infrastructure.database.models import WebhookEvent
from src.integrations.core.models import (
    IntegrationConnection,
    IntegrationDeadLetter,
    IntegrationEventLog,
)
from src.integrations.core.signatures import create_signature
from src.integrations.core.utils import (
    canonical_json_bytes,
    encrypt_text,
    generate_request_id,
    sha256_hex,
    utc_now,
)


logger = logging.getLogger("bookkeeping.integrations.outbound")


CONTRACT_PATHS = {
    "product.changed": "/api/integrations/apexbooks/v1/products/{source_id}",
    "price.updated": "/api/integrations/apexbooks/v1/prices/{source_id}",
    "inventory.updated": "/api/integrations/apexbooks/v1/inventory/{source_id}",
    "customer.updated": "/api/integrations/apexbooks/v1/customers/{source_id}",
}
RETRY_SCHEDULE_SECONDS = (60, 300, 900, 3600, 21600, 86400)
MAXIMUM_RETRY_WINDOW_SECONDS = 259200


@dataclass(frozen=True)
class DeliveryResult:
    delivered: bool
    retryable: bool
    status_code: int | None
    error_code: str | None = None


class CartunezOutboundDispatcher:
    integration_name = "cartunez"

    @staticmethod
    def enqueue(db: Session, tenant_id, payload: dict[str, Any], max_retries: int = 7) -> WebhookEvent:
        event_name = payload.get("event_name")
        source_id = payload.get("source_id")
        if event_name not in CONTRACT_PATHS or not isinstance(source_id, str):
            raise ValueError("Only existing Contract v1 master-data events can be queued.")
        target_path = CONTRACT_PATHS[event_name].format(source_id=source_id)
        event = WebhookEvent(
            tenant_id=tenant_id,
            event_type=f"cartunez.{event_name}",
            payload=payload,
            status="PENDING",
            target_url=target_path,
            retry_count=0,
            max_retries=max_retries,
        )
        db.add(event)
        return event

    def dispatch_pending(self, db: Session, limit: int | None = None) -> dict[str, int | bool]:
        if not settings.CARTUNEZ_OUTBOUND_ENABLED:
            return {"enabled": False, "selected": 0, "delivered": 0, "failed": 0}
        batch_size = limit or settings.CARTUNEZ_DELIVERY_BATCH_SIZE
        candidates = db.query(WebhookEvent).filter(
            WebhookEvent.status == "PENDING",
            WebhookEvent.event_type.in_([f"cartunez.{name}" for name in CONTRACT_PATHS]),
        ).order_by(WebhookEvent.created_at.asc()).limit(batch_size * 4).all()
        rows = [row for row in candidates if self._is_due(row)][:batch_size]
        delivered = 0
        failed = 0
        for row in rows:
            result = self.deliver(db, row.id)
            delivered += int(result.delivered)
            failed += int(not result.delivered)
        return {
            "enabled": True,
            "selected": len(rows),
            "delivered": delivered,
            "failed": failed,
        }

    def deliver(self, db: Session, event_id) -> DeliveryResult:
        event = db.query(WebhookEvent).filter(WebhookEvent.id == event_id).with_for_update().one_or_none()
        if event is None:
            return DeliveryResult(False, False, None, "QUEUE_EVENT_NOT_FOUND")
        if event.status == "DELIVERED":
            return DeliveryResult(True, False, None)
        if event.status != "PENDING":
            return DeliveryResult(False, False, None, "QUEUE_EVENT_NOT_PENDING")

        started_at = utc_now()
        started_clock = time.perf_counter()
        payload = dict(event.payload)
        raw_body = canonical_json_bytes(payload)
        path = event.target_url or ""
        connection = db.query(IntegrationConnection).filter(
            IntegrationConnection.tenant_id == event.tenant_id,
            IntegrationConnection.integration_name == self.integration_name,
            IntegrationConnection.status == "ENABLED",
        ).one_or_none()

        try:
            self._validate_configuration(connection, path, payload)
            timestamp = utc_now().isoformat().replace("+00:00", "Z")
            signature = create_signature(
                connection.get_hmac_secret(), timestamp, "PUT", path, raw_body
            )
            headers = {
                "Content-Type": "application/json",
                "X-Api-Key": settings.CARTUNEZ_MEDUSA_API_KEY,
                "X-Tenant-Id": connection.external_tenant_id,
                "X-Event-Id": payload["event_id"],
                "X-Idempotency-Key": payload["idempotency_key"],
                "X-Timestamp": timestamp,
                "X-Signature": signature,
            }
            target_url = f"{settings.CARTUNEZ_MEDUSA_BASE_URL}{path}"
            response = requests.put(
                target_url,
                data=raw_body,
                headers=headers,
                timeout=settings.CARTUNEZ_DELIVERY_TIMEOUT_SECONDS,
            )
            response_hash = sha256_hex(response.content)
            response_payload = self._response_json(response)
            if 200 <= response.status_code < 300 and response_payload.get("success") is True:
                event.status = "DELIVERED"
                event.last_error = None
                self._write_log(
                    db, connection, payload, path, raw_body, signature, started_at,
                    started_clock, "COMPLETED", response.status_code, response_hash, None,
                )
                db.commit()
                return DeliveryResult(True, False, response.status_code)

            retryable = response.status_code in {408, 429, 500, 502, 503, 504}
            error_code = self._contract_error_code(response_payload) or "DELIVERY_REJECTED"
            message = self._contract_error_message(response_payload) or (
                f"Medusa returned HTTP {response.status_code}."
            )
            result = self._record_failure(
                db, event, connection, payload, path, raw_body, signature, started_at,
                started_clock, response.status_code, response_hash, error_code, message,
                retryable,
            )
            db.commit()
            return result
        except requests.RequestException as exc:
            result = self._record_failure(
                db, event, connection, payload, path, raw_body, "", started_at,
                started_clock, None, None, "DELIVERY_UNAVAILABLE", str(exc), True,
            )
            db.commit()
            return result
        except Exception as exc:
            logger.exception("Cartunez outbound delivery failed", extra={"event_id": str(event.id)})
            result = self._record_failure(
                db, event, connection, payload, path, raw_body, "", started_at,
                started_clock, None, None, "DELIVERY_CONFIGURATION_ERROR", str(exc), False,
            )
            db.commit()
            return result

    @staticmethod
    def _validate_configuration(connection, path: str, payload: dict[str, Any]) -> None:
        if connection is None:
            raise ValueError("No enabled Cartunez integration connection exists for the tenant.")
        if not settings.CARTUNEZ_MEDUSA_BASE_URL:
            raise ValueError("CARTUNEZ_MEDUSA_BASE_URL is not configured.")
        parsed = urlsplit(settings.CARTUNEZ_MEDUSA_BASE_URL)
        if parsed.scheme != "https" or not parsed.netloc or parsed.path not in {"", "/"}:
            raise ValueError("CARTUNEZ_MEDUSA_BASE_URL must be an HTTPS origin without a path.")
        if not 32 <= len(settings.CARTUNEZ_MEDUSA_API_KEY) <= 256:
            raise ValueError("CARTUNEZ_MEDUSA_API_KEY must contain 32 to 256 characters.")
        if path != CONTRACT_PATHS.get(payload.get("event_name"), "").format(
            source_id=payload.get("source_id", "")
        ):
            raise ValueError("The queued target path does not match Contract v1.")
        if payload.get("tenant_id") != connection.external_tenant_id:
            raise ValueError("The event tenant does not match the integration connection.")

    def _record_failure(
        self, db, event, connection, payload, path, raw_body, signature, started_at,
        started_clock, response_status, response_hash, error_code, message, retryable,
    ) -> DeliveryResult:
        event.retry_count += 1
        next_delay = self._retry_delay(event.retry_count)
        created_at = self._aware(event.created_at)
        retry_window_exhausted = utc_now() + timedelta(seconds=next_delay) > (
            created_at + timedelta(seconds=MAXIMUM_RETRY_WINDOW_SECONDS)
        )
        exhausted = (
            not retryable
            or event.retry_count >= event.max_retries
            or retry_window_exhausted
        )
        event.status = "FAILED" if exhausted else "PENDING"
        event.last_error = message[:4000]
        self._write_log(
            db, connection, payload, path, raw_body, signature, started_at, started_clock,
            "FAILED" if retryable else "REJECTED", response_status, response_hash, error_code,
        )
        if exhausted and connection is not None:
            self._dead_letter(db, event, connection, payload, raw_body, error_code, message)
        return DeliveryResult(False, retryable and not exhausted, response_status, error_code)

    def _write_log(
        self, db, connection, payload, path, raw_body, signature, started_at,
        started_clock, status, response_status, response_hash, error_code,
    ) -> None:
        db.add(IntegrationEventLog(
            request_id=generate_request_id(),
            tenant_id=connection.tenant_id if connection is not None else None,
            connection_id=connection.id if connection is not None else None,
            integration_name=self.integration_name,
            external_tenant_id=payload.get("tenant_id"),
            direction="OUTBOUND",
            method="PUT",
            path=path,
            event_id=payload.get("event_id"),
            idempotency_key=payload.get("idempotency_key"),
            event_name=payload.get("event_name"),
            source_id=payload.get("source_id"),
            signature_hash=sha256_hex(signature),
            payload_hash=sha256_hex(raw_body),
            response_hash=response_hash,
            response_status=response_status,
            status=status,
            processing_time_ms=max(0, round((time.perf_counter() - started_clock) * 1000)),
            error_code=error_code,
            started_at=started_at,
            processed_at=utc_now(),
        ))

    def _dead_letter(self, db, event, connection, payload, raw_body, error_code, message) -> None:
        existing = db.query(IntegrationDeadLetter).filter(
            IntegrationDeadLetter.tenant_id == event.tenant_id,
            IntegrationDeadLetter.integration_name == self.integration_name,
            IntegrationDeadLetter.direction == "OUTBOUND",
            IntegrationDeadLetter.event_id == payload.get("event_id"),
            IntegrationDeadLetter.status.in_(["OPEN", "RETRYING"]),
        ).one_or_none()
        if existing is not None:
            existing.failure_code = error_code
            existing.failure_message = message[:4000]
            existing.retry_count = event.retry_count
            return
        db.add(IntegrationDeadLetter(
            tenant_id=event.tenant_id,
            connection_id=connection.id,
            integration_name=self.integration_name,
            direction="OUTBOUND",
            event_id=payload.get("event_id"),
            event_name=payload.get("event_name", "unknown"),
            payload_encrypted=encrypt_text(raw_body.decode("utf-8")),
            payload_hash=sha256_hex(raw_body),
            failure_code=error_code,
            failure_message=message[:4000],
            retry_count=event.retry_count,
            status="OPEN",
        ))

    @classmethod
    def _is_due(cls, event: WebhookEvent) -> bool:
        if event.retry_count == 0:
            return True
        last_attempt = cls._aware(event.updated_at)
        return utc_now() >= last_attempt + timedelta(
            seconds=cls._retry_delay(event.retry_count)
        )

    @staticmethod
    def _retry_delay(retry_count: int) -> int:
        index = max(0, retry_count - 1)
        return RETRY_SCHEDULE_SECONDS[min(index, len(RETRY_SCHEDULE_SECONDS) - 1)]

    @staticmethod
    def _aware(value):
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value

    @staticmethod
    def _response_json(response) -> dict[str, Any]:
        try:
            value = response.json()
        except (ValueError, json.JSONDecodeError):
            return {}
        return value if isinstance(value, dict) else {}

    @staticmethod
    def _contract_error_code(payload: dict[str, Any]) -> str | None:
        error = payload.get("error")
        return error.get("code") if isinstance(error, dict) else None

    @staticmethod
    def _contract_error_message(payload: dict[str, Any]) -> str | None:
        error = payload.get("error")
        return error.get("message") if isinstance(error, dict) else None
