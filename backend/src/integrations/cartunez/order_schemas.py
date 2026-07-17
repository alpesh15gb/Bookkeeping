from __future__ import annotations

import re
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator


EVENT_ID = r"^evt_[A-Z0-9]{26}$"
TENANT_ID = r"^[a-z][a-z0-9_]{2,63}$"
IDEMPOTENCY_KEY = r"^[a-z][a-z0-9_]{2,63}:[a-z]+\.[a-z]+:[A-Za-z0-9_-]+:v1$"
UTC_TIMESTAMP = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"
APEX_ID = r"^ab_[a-z]+_[A-Z0-9]{26}$"


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class OrderEnvelope(StrictModel):
    event_id: str = Field(pattern=EVENT_ID)
    event_name: str
    event_version: Literal["v1"]
    tenant_id: str = Field(pattern=TENANT_ID)
    occurred_at: str = Field(pattern=UTC_TIMESTAMP)
    source_system: Literal["MEDUSA"]
    source_id: str = Field(pattern=r"^[A-Za-z][A-Za-z0-9_-]{2,100}$")
    idempotency_key: str = Field(min_length=15, max_length=255, pattern=IDEMPOTENCY_KEY)

    @field_validator("occurred_at")
    @classmethod
    def occurred_at_is_valid(cls, value):
        return require_utc(value)


class Money(StrictModel):
    currency_code: str = Field(pattern=r"^[A-Z]{3}$")
    amount_minor: int = Field(ge=0)


class Address(StrictModel):
    name: str = Field(min_length=1, max_length=150)
    company: str | None = Field(default=None, max_length=150)
    phone: str | None = Field(default=None, pattern=r"^\+[1-9][0-9]{7,14}$")
    address_1: str = Field(min_length=1, max_length=200)
    address_2: str | None = Field(default=None, max_length=200)
    city: str = Field(min_length=1, max_length=100)
    state: str = Field(min_length=1, max_length=100)
    state_code: str = Field(pattern=r"^[0-9]{2}$")
    postal_code: str = Field(pattern=r"^[0-9]{6}$")
    country_code: Literal["IN"]


class GstIdentity(StrictModel):
    gstin: str | None = None
    gst_type: Literal["CONSUMER", "UNREGISTERED", "REGULAR", "COMPOSITION", "SEZ", "OVERSEAS"]
    state_code: str = Field(pattern=r"^[0-9]{2}$")

    @model_validator(mode="after")
    def valid_identity(self):
        registered = self.gst_type in {"REGULAR", "COMPOSITION", "SEZ"}
        valid = self.gstin is not None and re.fullmatch(
            r"[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]", self.gstin
        )
        if registered and not valid:
            raise ValueError("a valid GSTIN is required for registered GST types")
        if not registered and self.gstin is not None:
            raise ValueError("GSTIN must be null for this GST type")
        return self


class CustomerInput(StrictModel):
    medusa_customer_id: str = Field(pattern=r"^cus_[A-Z0-9]{26}$")
    apexbooks_customer_id: str | None = Field(default=None, pattern=APEX_ID)
    accounting_email: EmailStr = Field(max_length=255)
    first_name: str = Field(min_length=1, max_length=75)
    last_name: str = Field(min_length=1, max_length=75)
    phone: str = Field(pattern=r"^\+[1-9][0-9]{7,14}$")
    gst: GstIdentity
    billing_address: Address
    shipping_address: Address
    credit_terms_days: int = Field(ge=0, le=365)


class GstBreakdown(StrictModel):
    hsn_sac: str = Field(pattern=r"^[0-9]{4,8}$")
    gst_rate_bps: int = Field(ge=0, le=10000)
    taxable_value_minor: int = Field(ge=0)
    discount_minor: int = Field(ge=0)
    cgst_rate_bps: int = Field(ge=0, le=10000)
    cgst_amount_minor: int = Field(ge=0)
    sgst_rate_bps: int = Field(ge=0, le=10000)
    sgst_amount_minor: int = Field(ge=0)
    igst_rate_bps: int = Field(ge=0, le=10000)
    igst_amount_minor: int = Field(ge=0)
    cess_rate_bps: int = Field(ge=0, le=10000)
    cess_amount_minor: int = Field(ge=0)
    tax_amount_minor: int = Field(ge=0)


class OrderLine(StrictModel):
    medusa_line_id: str = Field(pattern=r"^item_[A-Z0-9]{26}$")
    medusa_product_id: str = Field(pattern=r"^prod_[A-Z0-9]{26}$")
    medusa_variant_id: str = Field(pattern=r"^variant_[A-Z0-9]{26}$")
    apexbooks_product_id: str = Field(pattern=APEX_ID)
    apexbooks_variant_id: str = Field(pattern=APEX_ID)
    sku: str = Field(min_length=1, max_length=64)
    title: str = Field(min_length=1, max_length=200)
    product_type: Literal["GOODS", "SERVICE"]
    quantity: int = Field(ge=1, le=1000000)
    unit_price: Money
    tax_inclusive: bool
    discount: Money
    gst: GstBreakdown
    line_total: Money


class ShippingCharge(StrictModel):
    title: Literal["Shipping"]
    unit_price: Money
    tax_inclusive: bool
    discount: Money
    gst: GstBreakdown
    line_total: Money


class OrderTotals(StrictModel):
    items_gross: Money
    discount_total: Money
    taxable_total: Money
    tax_total: Money
    shipping_total: Money
    grand_total: Money


class OrderSnapshot(StrictModel):
    medusa_order_id: str = Field(pattern=r"^order_[A-Z0-9]{26}$")
    display_id: int = Field(ge=1)
    order_revision: int = Field(ge=1)
    currency_code: str = Field(pattern=r"^[A-Z]{3}$")
    seller_state_code: str = Field(pattern=r"^[0-9]{2}$")
    place_of_supply_state_code: str = Field(pattern=r"^[0-9]{2}$")
    customer: CustomerInput
    billing_address: Address
    shipping_address: Address
    lines: list[OrderLine] = Field(min_length=1, max_length=1000)
    shipping: ShippingCharge
    totals: OrderTotals
    customer_reference: str | None = Field(default=None, max_length=100)
    notes: str | None = Field(default=None, max_length=2000)
    placed_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("placed_at")
    @classmethod
    def placed_at_is_valid(cls, value):
        return require_utc(value)

    @model_validator(mode="after")
    def unique_lines(self):
        ids = [line.medusa_line_id for line in self.lines]
        if len(ids) != len(set(ids)):
            raise ValueError("medusa_line_id values must be unique")
        return self


class OrderCreatedRequest(OrderEnvelope):
    event_name: Literal["order.created"]
    order: OrderSnapshot


class OrderUpdatedRequest(OrderEnvelope):
    event_name: Literal["order.updated"]
    expected_order_revision: int = Field(ge=1)
    order: OrderSnapshot


class OrderCancellation(StrictModel):
    medusa_order_id: str = Field(pattern=r"^order_[A-Z0-9]{26}$")
    expected_order_revision: int = Field(ge=1)
    reason_code: Literal["CUSTOMER_REQUEST", "PAYMENT_FAILED", "FRAUD", "INVENTORY_UNAVAILABLE", "DUPLICATE_ORDER", "OTHER"]
    reason: str = Field(min_length=3, max_length=500)
    cancelled_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("cancelled_at")
    @classmethod
    def cancelled_at_is_valid(cls, value):
        return require_utc(value)


class OrderCancelledRequest(OrderEnvelope):
    event_name: Literal["order.cancelled"]
    cancellation: OrderCancellation


def parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value[:-1] + "+00:00")


def require_utc(value: str) -> str:
    try:
        if not re.fullmatch(UTC_TIMESTAMP, value):
            raise ValueError
        parse_utc(value)
    except ValueError as exc:
        raise ValueError("must be a valid RFC 3339 UTC timestamp") from exc
    return value
