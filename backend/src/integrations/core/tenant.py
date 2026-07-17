from __future__ import annotations

from sqlalchemy.orm import Session

from src.infrastructure.database.models import Tenant
from src.integrations.core.exceptions import ErrorDetail, TenantDisabled, TenantNotResolved
from src.integrations.core.models import IntegrationConnection
from src.integrations.core.utils import sha256_hex


class TenantResolver:
    def __init__(self, integration_name: str):
        self.integration_name = integration_name

    def resolve(
        self,
        db: Session,
        external_tenant_id: str | None,
        api_key: str,
    ) -> tuple[IntegrationConnection | None, Tenant | None]:
        if not external_tenant_id:
            raise TenantNotResolved(
                "The tenant could not be resolved.",
                [ErrorDetail("header", "X-Tenant-Id", "The header is required.")],
            )

        api_key_hash = sha256_hex(api_key)
        connection = (
            db.query(IntegrationConnection)
            .filter(
                IntegrationConnection.integration_name == self.integration_name,
                IntegrationConnection.external_tenant_id == external_tenant_id,
                IntegrationConnection.api_key_hash == api_key_hash,
            )
            .one_or_none()
        )
        if connection is None:
            authorized_client = (
                db.query(IntegrationConnection.id)
                .filter(
                    IntegrationConnection.integration_name == self.integration_name,
                    IntegrationConnection.api_key_hash == api_key_hash,
                )
                .first()
            )
            if authorized_client:
                raise TenantNotResolved(
                    "The integration client is not authorized for this tenant.",
                    [ErrorDetail("header", "X-Tenant-Id", "Tenant is outside the API key allow-list.")],
                )
            return None, None

        if connection.status != "ENABLED":
            raise TenantDisabled(
                "The integration tenant is disabled.",
                [ErrorDetail("header", "X-Tenant-Id", "The connection is disabled.")],
            )

        tenant = (
            db.query(Tenant)
            .filter(Tenant.id == connection.tenant_id, Tenant.deleted_at.is_(None))
            .one_or_none()
        )
        if tenant is None:
            raise TenantDisabled(
                "The ApexBooks tenant is disabled or unavailable.",
                [ErrorDetail("header", "X-Tenant-Id", "No enabled ApexBooks tenant is mapped.")],
            )
        return connection, tenant
