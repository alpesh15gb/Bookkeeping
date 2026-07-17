from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator
from urllib.parse import urlparse


APEX_ID = r"^ab_[a-z]+_[A-Z0-9]{26}$"
EVENT_ID = r"^evt_[A-Z0-9]{26}$"
TENANT_ID = r"^[a-z][a-z0-9_]{2,63}$"
IDEMPOTENCY_KEY = r"^[a-z][a-z0-9_]{2,63}:[a-z]+\.[a-z]+:[A-Za-z0-9_-]+:v1$"
UTC_TIMESTAMP = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class MasterEnvelope(StrictModel):
    event_id: str = Field(pattern=EVENT_ID)
    event_name: str
    event_version: Literal["v1"]
    tenant_id: str = Field(pattern=TENANT_ID)
    occurred_at: str = Field(pattern=UTC_TIMESTAMP)
    source_system: Literal["APEXBOOKS"]
    source_id: str = Field(pattern=APEX_ID)
    idempotency_key: str = Field(min_length=15, max_length=255, pattern=IDEMPOTENCY_KEY)

    @field_validator("occurred_at")
    @classmethod
    def valid_occurred_at(cls, value):
        return _require_utc_timestamp(value)


class ProductVariant(StrictModel):
    apexbooks_variant_id: str = Field(pattern=APEX_ID)
    sku: str = Field(min_length=1, max_length=64)
    title: str = Field(min_length=1, max_length=150)
    product_type: Literal["GOODS", "SERVICE"]
    active: bool


class ProductPayload(StrictModel):
    apexbooks_product_id: str = Field(pattern=APEX_ID)
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(max_length=10000)
    hsn_sac: str = Field(pattern=r"^[0-9]{4,8}$")
    gst_rate_bps: int = Field(ge=0, le=10000)
    active: bool
    categories: list[str]
    images: list[str]
    variants: list[ProductVariant] = Field(min_length=1, max_length=1000)
    updated_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("updated_at")
    @classmethod
    def valid_updated_at(cls, value):
        return _require_utc_timestamp(value)

    @model_validator(mode="after")
    def contract_collections(self):
        if len(self.categories) != len(set(self.categories)):
            raise ValueError("categories must contain unique values")
        if any(not 1 <= len(value) <= 100 for value in self.categories):
            raise ValueError("category values must contain 1 to 100 characters")
        if len(self.images) != len(set(self.images)) or any(not _valid_https_uri(value) for value in self.images):
            raise ValueError("images must be unique HTTPS URIs")
        variant_ids = [variant.apexbooks_variant_id for variant in self.variants]
        if len(variant_ids) != len(set(variant_ids)):
            raise ValueError("variant IDs must be unique")
        return self


class ProductChangedRequest(MasterEnvelope):
    event_name: Literal["product.changed"]
    product: ProductPayload


class PriceEntry(StrictModel):
    apexbooks_variant_id: str = Field(pattern=APEX_ID)
    currency_code: str = Field(pattern=r"^[A-Z]{3}$")
    amount_minor: int = Field(ge=0)
    tax_inclusive: bool
    price_list_id: str | None = Field(max_length=100)
    valid_from: str | None
    valid_to: str | None

    @model_validator(mode="after")
    def timestamps(self):
        for field in ("valid_from", "valid_to"):
            value = getattr(self, field)
            if value is not None and not _is_utc_timestamp(value):
                raise ValueError(f"{field} must be an RFC 3339 UTC timestamp")
        return self


class PriceUpdate(StrictModel):
    apexbooks_product_id: str = Field(pattern=APEX_ID)
    replace_all: Literal[True]
    prices: list[PriceEntry] = Field(min_length=1, max_length=5000)
    updated_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("updated_at")
    @classmethod
    def valid_updated_at(cls, value):
        return _require_utc_timestamp(value)


class PriceUpdatedRequest(MasterEnvelope):
    event_name: Literal["price.updated"]
    price_update: PriceUpdate


class InventoryLevel(StrictModel):
    apexbooks_variant_id: str = Field(pattern=APEX_ID)
    warehouse_id: str = Field(pattern=APEX_ID)
    available_quantity: int = Field(ge=0)
    reserved_quantity: int = Field(ge=0)
    updated_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("updated_at")
    @classmethod
    def valid_updated_at(cls, value):
        return _require_utc_timestamp(value)


class InventoryUpdate(StrictModel):
    apexbooks_product_id: str = Field(pattern=APEX_ID)
    replace_all: Literal[True]
    levels: list[InventoryLevel] = Field(min_length=1, max_length=5000)
    updated_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("updated_at")
    @classmethod
    def valid_updated_at(cls, value):
        return _require_utc_timestamp(value)

    @model_validator(mode="after")
    def unique_scope(self):
        keys = [(level.apexbooks_variant_id, level.warehouse_id) for level in self.levels]
        if len(keys) != len(set(keys)):
            raise ValueError("inventory variant and warehouse pairs must be unique")
        return self


class InventoryUpdatedRequest(MasterEnvelope):
    event_name: Literal["inventory.updated"]
    inventory_update: InventoryUpdate


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
    def conditional_gstin(self):
        registered = self.gst_type in {"REGULAR", "COMPOSITION", "SEZ"}
        if registered and (self.gstin is None or not _valid_gstin(self.gstin)):
            raise ValueError("a valid GSTIN is required for registered GST types")
        if not registered and self.gstin is not None:
            raise ValueError("GSTIN must be null for this GST type")
        return self


class CanonicalCustomer(StrictModel):
    apexbooks_customer_id: str = Field(pattern=APEX_ID)
    medusa_customer_id: str = Field(pattern=r"^cus_[A-Z0-9]{26}$")
    accounting_email: EmailStr = Field(max_length=255)
    first_name: str = Field(min_length=1, max_length=75)
    last_name: str = Field(min_length=1, max_length=75)
    phone: str = Field(pattern=r"^\+[1-9][0-9]{7,14}$")
    gst: GstIdentity
    billing_address: Address
    shipping_address: Address
    credit_terms_days: int = Field(ge=0, le=365)
    active: bool
    updated_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("updated_at")
    @classmethod
    def valid_updated_at(cls, value):
        return _require_utc_timestamp(value)

    @model_validator(mode="after")
    def customer_consistency(self):
        if self.gst.state_code != self.billing_address.state_code:
            raise ValueError("GST state_code must match billing address state_code")
        return self


class CustomerUpdatedRequest(MasterEnvelope):
    event_name: Literal["customer.updated"]
    customer: CanonicalCustomer


def parse_utc(value: str | None) -> datetime | None:
    return None if value is None else datetime.fromisoformat(value[:-1] + "+00:00")


def _is_utc_timestamp(value: str) -> bool:
    try:
        return bool(__import__("re").fullmatch(UTC_TIMESTAMP, value)) and parse_utc(value) is not None
    except ValueError:
        return False


def _valid_gstin(value: str) -> bool:
    return bool(__import__("re").fullmatch(r"[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]", value))


def _require_utc_timestamp(value: str) -> str:
    if not _is_utc_timestamp(value):
        raise ValueError("must be a valid RFC 3339 UTC timestamp")
    return value


def _valid_https_uri(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)
