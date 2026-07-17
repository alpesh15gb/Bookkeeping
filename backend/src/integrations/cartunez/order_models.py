from __future__ import annotations

import uuid

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from src.core.database import Base
from src.integrations.core.utils import utc_now


class IntegrationOrderState(Base):
    __tablename__ = "integration_order_state"
    __table_args__ = (
        UniqueConstraint("tenant_id", "medusa_order_id", name="uq_integration_order_medusa"),
        UniqueConstraint("tenant_id", "apexbooks_order_id", name="uq_integration_order_apexbooks"),
        UniqueConstraint("sales_order_id", name="uq_integration_order_sales_order"),
        Index("ix_integration_order_tenant_status", "tenant_id", "status"),
        CheckConstraint(
            "status IN ('DRAFT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED')",
            name="ck_integration_order_status",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    sales_order_id = Column(UUID(as_uuid=True), ForeignKey("sales_orders.id"), nullable=False)
    medusa_order_id = Column(String(40), nullable=False)
    apexbooks_order_id = Column(String(150), nullable=False)
    medusa_customer_id = Column(String(40), nullable=False)
    apexbooks_customer_id = Column(String(150), nullable=False)
    accounting_reference = Column(String(50), nullable=False)
    revision = Column(Integer, nullable=False)
    status = Column(String(20), nullable=False, default="DRAFT")
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"))
    apexbooks_invoice_id = Column(String(150))
    captured_amount_minor = Column(Integer, nullable=False, default=0)
    refunded_amount_minor = Column(Integer, nullable=False, default=0)
    commercial_snapshot = Column(JSON, nullable=False)
    cancellation_reason_code = Column(String(30))
    cancellation_reason = Column(Text)
    cancelled_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)


class IntegrationInventoryMovement(Base):
    __tablename__ = "integration_inventory_movement"
    __table_args__ = (
        Index("ix_integration_inventory_movement_order", "tenant_id", "order_state_id"),
        Index("ix_integration_inventory_movement_level", "tenant_id", "variant_id", "warehouse_id"),
        CheckConstraint(
            "movement_type IN ('RESERVATION', 'RESERVATION_RELEASE')",
            name="ck_integration_inventory_movement_type",
        ),
        CheckConstraint("quantity_delta != 0", name="ck_integration_inventory_movement_quantity"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    order_state_id = Column(UUID(as_uuid=True), ForeignKey("integration_order_state.id"), nullable=False)
    sales_order_line_id = Column(UUID(as_uuid=True), nullable=False)
    variant_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_product_variants.id"), nullable=False)
    warehouse_id = Column(String(150), nullable=False)
    movement_type = Column(String(30), nullable=False)
    quantity_delta = Column(Integer, nullable=False)
    event_id = Column(String(100), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class IntegrationOrderAudit(Base):
    __tablename__ = "integration_order_audit"
    __table_args__ = (
        Index("ix_integration_order_audit_event", "tenant_id", "event_id"),
        Index("ix_integration_order_audit_order", "tenant_id", "medusa_order_id"),
        CheckConstraint(
            "result IN ('CREATED', 'UPDATED', 'CANCELLED')",
            name="ck_integration_order_audit_result",
        ),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    event_name = Column(String(100), nullable=False)
    event_id = Column(String(100), nullable=False)
    idempotency_key = Column(String(255), nullable=False)
    medusa_order_id = Column(String(40), nullable=False)
    apexbooks_order_id = Column(String(150), nullable=False)
    medusa_customer_id = Column(String(40), nullable=False)
    apexbooks_customer_id = Column(String(150), nullable=False)
    product_ids = Column(JSON, nullable=False)
    old_values = Column(JSON)
    new_values = Column(JSON, nullable=False)
    execution_time_ms = Column(Integer, nullable=False)
    result = Column(String(20), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
