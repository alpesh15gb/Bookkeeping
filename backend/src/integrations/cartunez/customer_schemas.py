from __future__ import annotations

from typing import Literal

from pydantic import EmailStr, Field, model_validator

from src.integrations.cartunez.order_schemas import (
    APEX_ID,
    Address,
    GstIdentity,
    OrderEnvelope,
    StrictModel,
)


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


class CustomerCreatedRequest(OrderEnvelope):
    event_name: Literal["customer.created"]
    source_id: str = Field(pattern=r"^cus_[A-Z0-9]{26}$")
    customer: CustomerInput

    @model_validator(mode="after")
    def source_matches_customer(self):
        if self.source_id != self.customer.medusa_customer_id:
            raise ValueError("source_id must equal customer.medusa_customer_id")
        return self
