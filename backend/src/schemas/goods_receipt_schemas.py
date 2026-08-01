from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid

from src.schemas import SchemaBase


# ── Line Items ───────────────────────────────────────────────────────────────

class GoodsReceiptLineBase(SchemaBase):
    purchase_order_line_id: Optional[uuid.UUID] = None
    product_id: uuid.UUID
    quantity_ordered: Decimal = Field(..., gt=0)
    quantity_received: Decimal = Field(..., ge=0)
    warehouse_id: Optional[uuid.UUID] = None
    lot_number: Optional[str] = None
    batch_number: Optional[str] = None


class GoodsReceiptLineCreate(GoodsReceiptLineBase):
    pass


class GoodsReceiptLineResponse(GoodsReceiptLineBase):
    id: uuid.UUID
    product_name: Optional[str] = None
    warehouse_name: Optional[str] = None


# ── Header ───────────────────────────────────────────────────────────────────

class GoodsReceiptBase(SchemaBase):
    purchase_order_id: Optional[uuid.UUID] = None
    receipt_date: date
    notes: Optional[str] = None


class GoodsReceiptCreate(GoodsReceiptBase):
    lines: List[GoodsReceiptLineCreate]


class GoodsReceiptResponse(GoodsReceiptBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    contact_id: Optional[uuid.UUID] = None
    receipt_number: str
    status: str
    po_number: Optional[str] = None
    contact_name: Optional[str] = None
    lines: List[GoodsReceiptLineResponse]
    created_at: Optional[datetime] = None
    confirmed_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None


# ── List ─────────────────────────────────────────────────────────────────────

class GoodsReceiptListResponse(SchemaBase):
    id: uuid.UUID
    receipt_number: str
    receipt_date: date
    status: str
    po_number: Optional[str] = None
    contact_name: Optional[str] = None
    created_at: Optional[datetime] = None


class PaginatedGoodsReceiptResponse(SchemaBase):
    items: List[GoodsReceiptListResponse]
    total: int
    page: int
    limit: int
