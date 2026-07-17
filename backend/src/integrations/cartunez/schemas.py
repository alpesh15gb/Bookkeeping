from __future__ import annotations

from typing import Literal

from src.integrations.core.auth import EventEnvelope


class CartunezEventEnvelope(EventEnvelope):
    source_system: Literal["MEDUSA"]
