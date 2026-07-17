from __future__ import annotations

import uuid

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship

from src.core.database import Base
from src.integrations.core.utils import utc_now


class SyncedProduct(Base):
    """Medusa-side projection of an ApexBooks-owned product."""

    __tablename__ = "integration_synced_products"
    __table_args__ = (
        UniqueConstraint("tenant_id", "apexbooks_product_id", name="uq_synced_product_external"),
        UniqueConstraint("tenant_id", "medusa_product_id", name="uq_synced_product_medusa"),
        Index("ix_synced_products_tenant", "tenant_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    apexbooks_product_id = Column(String(150), nullable=False)
    medusa_product_id = Column(String(40), nullable=False)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=False)
    categories = Column(JSON, nullable=False, default=list)
    images = Column(JSON, nullable=False, default=list)
    active = Column(Boolean, nullable=False)
    hsn_sac = Column(String(8), nullable=False)
    gst_rate_bps = Column(Integer, nullable=False)
    source_updated_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)

    variants = relationship("SyncedProductVariant", back_populates="product", cascade="all, delete-orphan")


class SyncedProductVariant(Base):
    __tablename__ = "integration_synced_product_variants"
    __table_args__ = (
        UniqueConstraint("tenant_id", "apexbooks_variant_id", name="uq_synced_variant_external"),
        UniqueConstraint("tenant_id", "medusa_variant_id", name="uq_synced_variant_medusa"),
        Index("ix_synced_variants_product", "product_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_products.id"), nullable=False)
    apexbooks_variant_id = Column(String(150), nullable=False)
    medusa_variant_id = Column(String(40), nullable=False)
    sku = Column(String(64), nullable=False)
    title = Column(String(150), nullable=False)
    product_type = Column(String(10), nullable=False)
    active = Column(Boolean, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)

    product = relationship("SyncedProduct", back_populates="variants")


class SyncedPrice(Base):
    __tablename__ = "integration_synced_prices"
    __table_args__ = (
        Index("ix_synced_prices_product", "tenant_id", "product_id"),
        CheckConstraint("amount_minor >= 0", name="ck_synced_price_amount"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_products.id"), nullable=False)
    variant_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_product_variants.id"), nullable=False)
    amount_minor = Column(Integer, nullable=False)
    currency_code = Column(String(3), nullable=False)
    tax_inclusive = Column(Boolean, nullable=False)
    price_list_id = Column(String(100))
    valid_from = Column(DateTime(timezone=True))
    valid_to = Column(DateTime(timezone=True))
    source_updated_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class SyncedInventoryLevel(Base):
    __tablename__ = "integration_synced_inventory_levels"
    __table_args__ = (
        UniqueConstraint("tenant_id", "variant_id", "warehouse_id", name="uq_synced_inventory_scope"),
        Index("ix_synced_inventory_product", "tenant_id", "product_id"),
        CheckConstraint("available_quantity >= 0", name="ck_synced_inventory_available"),
        CheckConstraint("reserved_quantity >= 0", name="ck_synced_inventory_reserved"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_products.id"), nullable=False)
    variant_id = Column(UUID(as_uuid=True), ForeignKey("integration_synced_product_variants.id"), nullable=False)
    warehouse_id = Column(String(150), nullable=False)
    available_quantity = Column(Integer, nullable=False)
    reserved_quantity = Column(Integer, nullable=False)
    source_updated_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)


class SyncedCustomer(Base):
    """ERP-owned customer fields only; authentication data is deliberately absent."""

    __tablename__ = "integration_synced_customers"
    __table_args__ = (
        UniqueConstraint("tenant_id", "apexbooks_customer_id", name="uq_synced_customer_external"),
        UniqueConstraint("tenant_id", "medusa_customer_id", name="uq_synced_customer_medusa"),
        Index("ix_synced_customers_tenant", "tenant_id"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    apexbooks_customer_id = Column(String(150), nullable=False)
    medusa_customer_id = Column(String(40), nullable=False)
    first_name = Column(String(75), nullable=False)
    last_name = Column(String(75), nullable=False)
    phone = Column(String(16), nullable=False)
    accounting_email = Column(String(255), nullable=False)
    gstin = Column(String(15))
    gst_type = Column(String(20), nullable=False)
    billing_address = Column(JSON, nullable=False)
    shipping_address = Column(JSON, nullable=False)
    state_code = Column(String(2), nullable=False)
    credit_terms_days = Column(Integer, nullable=False)
    active = Column(Boolean, nullable=False)
    source_updated_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now)


class MasterSyncAudit(Base):
    __tablename__ = "integration_master_sync_audit"
    __table_args__ = (
        Index("ix_master_sync_audit_event", "tenant_id", "event_id"),
        Index("ix_master_sync_audit_entity", "tenant_id", "entity_type", "external_id"),
        CheckConstraint("result IN ('CREATED', 'UPDATED')", name="ck_master_sync_audit_result"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    tenant_id = Column(UUID(as_uuid=True), nullable=False)
    integration_name = Column(String(50), nullable=False)
    event_name = Column(String(100), nullable=False)
    event_id = Column(String(100), nullable=False)
    idempotency_key = Column(String(255), nullable=False)
    entity_type = Column(String(50), nullable=False)
    external_id = Column(String(150), nullable=False)
    old_values = Column(JSON)
    new_values = Column(JSON, nullable=False)
    processing_time_ms = Column(Integer, nullable=False)
    result = Column(String(20), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=utc_now)
