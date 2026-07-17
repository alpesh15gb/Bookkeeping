from __future__ import annotations

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


UTC_TIMESTAMP = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$"


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Money(StrictModel):
    currency_code: str = Field(pattern=r"^[A-Z]{3}$")
    amount_minor: int = Field(ge=0)


class PaymentCapture(StrictModel):
    medusa_payment_id: str = Field(pattern=r"^pay_[A-Z0-9]{26}$")
    medusa_order_id: str = Field(pattern=r"^order_[A-Z0-9]{26}$")
    capture_sequence: int = Field(ge=1)
    amount: Money
    provider_id: str = Field(min_length=1, max_length=100)
    transaction_id: str = Field(min_length=1, max_length=150)
    captured_at: str = Field(pattern=UTC_TIMESTAMP)

    @field_validator("captured_at")
    @classmethod
    def valid_captured_at(cls, value):
        return require_utc(value)


class PaymentCapturedRequest(StrictModel):
    event_id: str = Field(pattern=r"^evt_[A-Z0-9]{26}$")
    event_name: Literal["payment.captured"]
    event_version: Literal["v1"]
    tenant_id: str = Field(pattern=r"^[a-z][a-z0-9_]{2,63}$")
    occurred_at: str = Field(pattern=UTC_TIMESTAMP)
    source_system: Literal["MEDUSA"]
    source_id: str = Field(pattern=r"^[A-Za-z][A-Za-z0-9_-]{2,100}$")
    idempotency_key: str = Field(
        min_length=15,
        max_length=255,
        pattern=r"^[a-z][a-z0-9_]{2,63}:[a-z]+\.[a-z]+:[A-Za-z0-9_-]+:v1$",
    )
    payment: PaymentCapture

    @field_validator("occurred_at")
    @classmethod
    def valid_occurred_at(cls, value):
        return require_utc(value)


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
