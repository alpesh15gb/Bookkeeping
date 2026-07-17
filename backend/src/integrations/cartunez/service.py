from __future__ import annotations

from sqlalchemy.orm import Session
from starlette.requests import Request

from src.integrations.core.idempotency import (
    Handler,
    IntegrationRequestProcessor,
    IntegrationResult,
)


class CartunezIntegrationService:
    integration_name = "cartunez"

    def __init__(self):
        self.processor = IntegrationRequestProcessor(self.integration_name)

    async def process_foundation_request(
        self,
        request: Request,
        db: Session,
        handler: Handler,
    ) -> IntegrationResult:
        return await self.processor.process(request, db, handler)
