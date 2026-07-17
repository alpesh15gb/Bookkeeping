from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.orm import Session

from src.infrastructure.database.models import WebhookEvent


class WebhookQueue:
    def enqueue(
        self,
        db: Session,
        tenant_id: uuid.UUID,
        event_type: str,
        payload: dict[str, Any],
        target_url: str,
        max_retries: int = 3,
    ) -> WebhookEvent:
        event = WebhookEvent(
            tenant_id=tenant_id,
            event_type=event_type,
            payload=payload,
            status="PENDING",
            target_url=target_url,
            retry_count=0,
            max_retries=max_retries,
        )
        db.add(event)
        return event
