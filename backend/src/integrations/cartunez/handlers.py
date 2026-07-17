from __future__ import annotations

from src.integrations.core.auth import AuthenticatedIntegrationRequest
from src.integrations.core.exceptions import IntegrationError


class CartunezHandlerRegistry:
    def resolve(self, request: AuthenticatedIntegrationRequest):
        raise IntegrationError(
            f"No Phase 1 business handler is registered for {request.envelope.event_name}."
        )
