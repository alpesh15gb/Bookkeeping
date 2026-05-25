from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import date, datetime
from decimal import Decimal
import uuid

class SchemaBase(BaseModel):
    class Config:
        from_attributes = True

# Journal Entry Creation & Response
class JournalLineCreate(SchemaBase):
    account_id: uuid.UUID
    amount: Decimal = Field(..., gt=0)
    direction: str = Field(..., pattern="^(DEBIT|CREDIT)$")
    narration: Optional[str] = Field(None, max_length=255)

class JournalEntryCreate(SchemaBase):
    entry_date: date
    reference_number: Optional[str] = Field(None, max_length=50)
    description: str = Field(..., max_length=255)
    lines: List[JournalLineCreate]

class JournalLineResponse(SchemaBase):
    id: uuid.UUID
    account_id: uuid.UUID
    account_name: str
    account_code: str
    amount: Decimal
    direction: str
    narration: Optional[str] = None

class JournalEntryResponse(SchemaBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    entry_date: date
    reference_number: str
    description: str
    source_type: str
    source_id: Optional[uuid.UUID] = None
    created_at: datetime
    updated_at: datetime
    lines: List[JournalLineResponse]

# General Ledger Card Report
class LedgerLine(SchemaBase):
    entry_date: date
    reference_number: str
    description: str
    debit_amount: Decimal
    credit_amount: Decimal
    narration: Optional[str] = None
    running_balance: Decimal

class LedgerReportResponse(SchemaBase):
    account_id: uuid.UUID
    account_name: str
    account_code: str
    opening_balance: Decimal
    closing_balance: Decimal
    lines: List[LedgerLine]

# Trial Balance Report
class TrialBalanceLine(SchemaBase):
    account_id: uuid.UUID
    account_name: str
    account_code: str
    account_type: str
    opening_balance: Decimal
    total_debits: Decimal
    total_credits: Decimal
    closing_balance: Decimal

class TrialBalanceResponse(SchemaBase):
    lines: List[TrialBalanceLine]
    total_opening_debits: Decimal
    total_opening_credits: Decimal
    total_debits: Decimal
    total_credits: Decimal
    total_closing_debits: Decimal
    total_closing_credits: Decimal

# Profit & Loss Report
class ProfitLossItem(SchemaBase):
    account_name: str
    account_code: str
    amount: Decimal

class ProfitLossResponse(SchemaBase):
    revenue_lines: List[ProfitLossItem]
    total_revenue: Decimal
    expense_lines: List[ProfitLossItem]
    total_expenses: Decimal
    net_profit: Decimal
