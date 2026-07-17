from __future__ import annotations

import uuid

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Index, Integer, JSON, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID

from src.core.database import Base
from src.integrations.core.utils import utc_now


class IntegrationPaymentState(Base):
    __tablename__ = "integration_payment_state"
    __table_args__ = (
        UniqueConstraint("tenant_id", "medusa_payment_id", name="uq_integration_payment_medusa"),
        UniqueConstraint("tenant_id", "order_state_id", "capture_sequence", name="uq_integration_payment_sequence"),
        UniqueConstraint("tenant_id", "provider_id", "transaction_id", name="uq_integration_payment_transaction"),
        UniqueConstraint("payment_id", name="uq_integration_payment_receipt"),
        Index("ix_integration_payment_order", "tenant_id", "order_state_id"),
        CheckConstraint("status = 'CAPTURED'", name="ck_integration_payment_status"),
        CheckConstraint("amount_minor > 0", name="ck_integration_payment_amount"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    order_state_id = Column(UUID(as_uuid=True), ForeignKey("integration_order_state.id"), nullable=False)
    payment_id = Column(UUID(as_uuid=True), ForeignKey("payments.id"), nullable=False)
    medusa_payment_id = Column(String(40), nullable=False)
    apexbooks_payment_id = Column(String(150), nullable=False)
    receipt_id = Column(String(150), nullable=False)
    capture_sequence = Column(Integer, nullable=False)
    currency_code = Column(String(3), nullable=False)
    amount_minor = Column(Integer, nullable=False)
    provider_id = Column(String(100), nullable=False)
    transaction_id = Column(String(150), nullable=False)
    status = Column(String(20), nullable=False, default="CAPTURED")
    captured_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class IntegrationPaymentInventoryMovement(Base):
    __tablename__ = "integration_payment_inventory_movement"
    __table_args__ = (
        Index("ix_payment_inventory_order", "tenant_id", "order_state_id"),
        Index("ix_payment_inventory_level", "tenant_id", "variant_id", "warehouse_id"),
        CheckConstraint("movement_type = 'SALE_OUT'", name="ck_payment_inventory_type"),
        CheckConstraint("quantity > 0", name="ck_payment_inventory_quantity"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    order_state_id = Column(UUID(as_uuid=True), ForeignKey("integration_order_state.id"), nullable=False)
    payment_state_id = Column(UUID(as_uuid=True), ForeignKey("integration_payment_state.id"), nullable=False)
    variant_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_product_variants.id"), nullable=False)
    warehouse_id = Column(String(150), nullable=False)
    movement_type = Column(String(20), nullable=False, default="SALE_OUT")
    quantity = Column(Integer, nullable=False)
    available_before = Column(Integer, nullable=False)
    available_after = Column(Integer, nullable=False)
    reserved_before = Column(Integer, nullable=False)
    reserved_after = Column(Integer, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class IntegrationInvoiceLineMap(Base):
    __tablename__ = "integration_invoice_line_map"
    __table_args__ = (
        UniqueConstraint("tenant_id", "apexbooks_invoice_line_id", name="uq_integration_invoice_line_apexbooks"),
        UniqueConstraint("tenant_id", "invoice_id", "medusa_line_id", name="uq_integration_invoice_line_medusa"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    invoice_id = Column(UUID(as_uuid=True), ForeignKey("invoices.id"), nullable=False)
    invoice_line_id = Column(UUID(as_uuid=True), ForeignKey("invoice_lines.id"), nullable=False)
    medusa_line_id = Column(String(40), nullable=False)
    apexbooks_invoice_line_id = Column(String(150), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class IntegrationPaymentAudit(Base):
    __tablename__ = "integration_payment_audit"
    __table_args__ = (
        Index("ix_integration_payment_audit_event", "tenant_id", "event_id"),
        Index("ix_integration_payment_audit_order", "tenant_id", "medusa_order_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    event_id = Column(String(100), nullable=False)
    idempotency_key = Column(String(255), nullable=False)
    medusa_payment_id = Column(String(40), nullable=False)
    medusa_order_id = Column(String(40), nullable=False)
    apexbooks_payment_id = Column(String(150), nullable=False)
    apexbooks_invoice_id = Column(String(150), nullable=False)
    capture_sequence = Column(Integer, nullable=False)
    amount_minor = Column(Integer, nullable=False)
    old_values = Column(JSON, nullable=False)
    new_values = Column(JSON, nullable=False)
    execution_time_ms = Column(Integer, nullable=False)
    result = Column(String(20), nullable=False, default="CAPTURED")
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
