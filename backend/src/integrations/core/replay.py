from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from src.integrations.core.auth import AuthenticatedIntegrationRequest
from src.integrations.core.exceptions import IdempotencyConflict, ReplayDetected
from src.integrations.core.models import IntegrationReplayCache
from src.integrations.core.utils import utc_now


@dataclass(frozen=True)
class ReplayClaim:
    record: IntegrationReplayCache
    replayed: bool


class ReplayService:
    def claim(self, db: Session, request: AuthenticatedIntegrationRequest) -> ReplayClaim:
        record = IntegrationReplayCache(
            tenant_id=request.internal_tenant_id,
            connection_id=request.connection.id,
            integration_name=request.connection.integration_name,
            event_id=request.envelope.event_id,
            idempotency_key=request.envelope.idempotency_key,
            event_name=request.envelope.event_name,
            source_id=request.envelope.source_id,
            method=request.method,
            path=request.path,
            signature_hash=request.signature_hash,
            request_hash=request.request_hash,
            status="PROCESSING",
            expires_at=utc_now() + timedelta(days=request.connection.replay_retention_days),
        )
        try:
            db.add(record)
            db.flush()
            return ReplayClaim(record=record, replayed=False)
        except IntegrityError:
            db.rollback()

        event_record = (
            db.query(IntegrationReplayCache)
            .filter(
                IntegrationReplayCache.tenant_id == request.internal_tenant_id,
                IntegrationReplayCache.integration_name == request.connection.integration_name,
                IntegrationReplayCache.event_id == request.envelope.event_id,
            )
            .one_or_none()
        )
        key_record = (
            db.query(IntegrationReplayCache)
            .filter(
                IntegrationReplayCache.tenant_id == request.internal_tenant_id,
                IntegrationReplayCache.integration_name == request.connection.integration_name,
                IntegrationReplayCache.idempotency_key == request.envelope.idempotency_key,
            )
            .one_or_none()
        )
        if event_record is not None and not self._is_exact(event_record, request):
            raise ReplayDetected("The event ID has already been used for a different request.")
        if key_record is not None and not self._is_exact(key_record, request):
            raise IdempotencyConflict("The idempotency key has already been used for a different request.")
        existing = event_record or key_record
        if existing is not None and existing.status == "PROCESSING":
            existing = self._wait_for_completed_record(db, request)
        if existing is None or existing.status != "COMPLETED":
            raise ReplayDetected("An identical request is already processing.")
        return ReplayClaim(record=existing, replayed=True)

    @staticmethod
    def _wait_for_completed_record(
        db: Session,
        request: AuthenticatedIntegrationRequest,
    ) -> IntegrationReplayCache | None:
        for _ in range(100):
            db.rollback()
            existing = (
                db.query(IntegrationReplayCache)
                .filter(
                    IntegrationReplayCache.tenant_id == request.internal_tenant_id,
                    IntegrationReplayCache.integration_name == request.connection.integration_name,
                    IntegrationReplayCache.event_id == request.envelope.event_id,
                )
                .one_or_none()
            )
            if existing is None or existing.status == "COMPLETED":
                return existing
            time.sleep(0.02)
        return existing

    @staticmethod
    def _is_exact(
        record: IntegrationReplayCache,
        request: AuthenticatedIntegrationRequest,
    ) -> bool:
        return (
            record.event_id == request.envelope.event_id
            and record.idempotency_key == request.envelope.idempotency_key
            and record.tenant_id == request.internal_tenant_id
            and record.event_name == request.envelope.event_name
            and record.source_id == request.envelope.source_id
            and record.method == request.method
            and record.path == request.path
            and record.request_hash == request.request_hash
        )
