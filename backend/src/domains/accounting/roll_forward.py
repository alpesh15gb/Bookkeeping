"""
Roll-Forward Engine
===================
Carries forward opening balances and inventory from one FY to the next.

Flow during FY close:
    1. Balance Sheet snapshot (ASSET, LIABILITY, EQUITY closing balances)
    2. Set opening_balance on each permanent account
    3. Create opening journal entry for the new FY (audit trail)
    4. Inventory carry-forward (product current_stock → opening_stock)

This ensures the user never has to manually enter opening balances.
"""

import uuid
from decimal import Decimal
from datetime import date, datetime, timezone
from typing import List, Tuple

from sqlalchemy import func, case
from sqlalchemy.orm import Session

from src.infrastructure.database.models import (
    Account,
    JournalEntry,
    JournalLine,
    OpeningBalanceSnapshot,
    InventoryCarryForward,
    Product,
    FinancialYear,
)


def carry_forward_balances(
    db: Session,
    tenant_id: uuid.UUID,
    closing_fy: FinancialYear,
    new_fy: FinancialYear,
) -> dict:
    """
    Carry forward all permanent account balances from closing_fy to new_fy.

    Steps:
        1. Compute closing balance for every ASSET, LIABILITY, EQUITY account
           using: opening_balance + (debits - credits) or (credits - debits)
        2. Create OpeningBalanceSnapshot rows (audit trail)
        3. Update Account.opening_balance = closing_balance
        4. Update Account.current_balance = closing_balance (clean slate for new FY)
        5. Create an opening journal entry in the new FY

    Returns dict with summary data for audit logging.
    """
    # 1. Query all permanent accounts (not REVENUE/EXPENSE, which are zeroed)
    permanent_accounts = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.account_type.in_(["ASSET", "LIABILITY", "EQUITY"]),
        Account.deleted_at == None,
    ).all()

    if not permanent_accounts:
        return {"accounts_carried": 0, "total_debits": "0", "total_credits": "0"}

    # 2. Compute journal movements within the closing FY
    account_ids = [a.id for a in permanent_accounts]
    movements = db.query(
        JournalLine.account_id,
        func.coalesce(
            func.sum(case((JournalLine.direction == "DEBIT", JournalLine.amount), else_=0)),
            Decimal("0.0000"),
        ).label("debits"),
        func.coalesce(
            func.sum(case((JournalLine.direction == "CREDIT", JournalLine.amount), else_=0)),
            Decimal("0.0000"),
        ).label("credits"),
    ).join(JournalEntry, JournalLine.entry_id == JournalEntry.id).filter(
        JournalEntry.tenant_id == tenant_id,
        JournalEntry.entry_date >= closing_fy.start_date,
        JournalEntry.entry_date <= closing_fy.end_date,
        JournalLine.account_id.in_(account_ids),
    ).group_by(JournalLine.account_id).all()

    movement_map = {row.account_id: (row.debits, row.credits) for row in movements}

    # 3. Process each account
    opening_lines: List[JournalLine] = []
    snapshots: List[OpeningBalanceSnapshot] = []
    total_debits = Decimal("0.0000")
    total_credits = Decimal("0.0000")

    for account in permanent_accounts:
        opening_bal = account.opening_balance or Decimal("0.0000")
        debits, credits = movement_map.get(account.id, (Decimal("0.0000"), Decimal("0.0000")))

        # Compute closing balance using standard accounting formula
        if account.account_type in ("ASSET", "EXPENSE"):
            closing_balance = (opening_bal + debits - credits).quantize(Decimal("0.0001"))
        else:
            closing_balance = (opening_bal + credits - debits).quantize(Decimal("0.0001"))

        # Determine direction for display
        if closing_balance >= 0:
            direction = "DEBIT" if account.account_type in ("ASSET", "EXPENSE") else "CREDIT"
        else:
            direction = "CREDIT" if account.account_type in ("ASSET", "EXPENSE") else "DEBIT"

        abs_balance = abs(closing_balance)

        # Create snapshot (audit trail)
        snapshots.append(OpeningBalanceSnapshot(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            financial_year_id=closing_fy.id,
            account_id=account.id,
            account_type=account.account_type,
            account_name=account.name,
            account_code=account.code,
            closing_balance=closing_balance,
            direction=direction,
            created_at=datetime.now(timezone.utc),
        ))

        # Update account for new FY
        account.opening_balance = closing_balance
        account.current_balance = closing_balance  # Clean slate — no journal lines yet in new FY

        # Build opening journal line for the new FY (only if balance is non-zero)
        if abs_balance > 0:
            opening_lines.append(JournalLine(
                account_id=account.id,
                amount=abs_balance,
                direction=direction,
                narration=f"Opening balance carried forward from {closing_fy.name}",
            ))
            if direction == "DEBIT":
                total_debits += abs_balance
            else:
                total_credits += abs_balance

    # 4. Create snapshots
    db.add_all(snapshots)

    # 5. Create opening journal entry for the new FY
    journal_entry = None
    if len(opening_lines) >= 2:
        entry_id = uuid.uuid4()
        ref_num = f"OB-{new_fy.start_date.year}-{new_fy.end_date.year % 100:02d}"
        journal_entry = JournalEntry(
            id=entry_id,
            tenant_id=tenant_id,
            entry_date=new_fy.start_date,
            reference_number=ref_num,
            description=f"Opening balances carried forward from {closing_fy.name}",
            source_type="OPENING_BALANCE",
            source_id=entry_id,
            is_locked=True,
            lines=opening_lines,
        )
        db.add(journal_entry)
        db.flush()

    return {
        "accounts_carried": len(snapshots),
        "total_debits": str(total_debits),
        "total_credits": str(total_credits),
        "journal_entry_id": str(journal_entry.id) if journal_entry else None,
    }


def carry_forward_inventory(
    db: Session,
    tenant_id: uuid.UUID,
    closing_fy: FinancialYear,
    new_fy: FinancialYear,
) -> dict:
    """
    Carry forward all product stock from closing_fy to new_fy.

    Steps:
        1. Get every active product with current_stock > 0
        2. Create InventoryCarryForward rows (audit trail)
        3. Set Product.opening_stock = current_stock

    Returns dict with summary data for audit logging.
    """
    products = db.query(Product).filter(
        Product.tenant_id == tenant_id,
        Product.is_active == True,
        Product.current_stock > 0,
    ).all()

    if not products:
        return {"products_carried": 0, "total_value": "0"}

    carry_forwards: List[InventoryCarryForward] = []
    total_value = Decimal("0.0000")

    for product in products:
        qty = product.current_stock or Decimal("0.00")
        rate = product.purchase_price or Decimal("0.0000")
        value = (qty * rate).quantize(Decimal("0.0000"))

        carry_forwards.append(InventoryCarryForward(
            id=uuid.uuid4(),
            tenant_id=tenant_id,
            financial_year_id=closing_fy.id,
            product_id=product.id,
            product_name=product.name,
            product_sku=product.sku,
            closing_quantity=qty,
            closing_value=value,
            unit_rate=rate,
            created_at=datetime.now(timezone.utc),
        ))

        # Set opening stock for new FY
        product.opening_stock = qty
        total_value += value

    db.add_all(carry_forwards)

    return {
        "products_carried": len(carry_forwards),
        "total_value": str(total_value),
    }
