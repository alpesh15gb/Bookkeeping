from __future__ import annotations

import uuid

from sqlalchemy.orm import Session

from src.integrations.core.models import IntegrationEntityMap


class CartunezEntityMapper:
    integration_name = "cartunez"

    def find_internal_id(
        self,
        db: Session,
        tenant_id: uuid.UUID,
        entity_type: str,
        external_id: str,
    ) -> uuid.UUID | None:
        mapping = (
            db.query(IntegrationEntityMap)
            .filter(
                IntegrationEntityMap.tenant_id == tenant_id,
                IntegrationEntityMap.integration_name == self.integration_name,
                IntegrationEntityMap.entity_type == entity_type,
                IntegrationEntityMap.external_id == external_id,
                IntegrationEntityMap.sync_status != "DISABLED",
            )
            .one_or_none()
        )
        return mapping.internal_id if mapping else None
