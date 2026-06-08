"""
Roll-Forward Engine
===================
Carries forward opening balances and inventory from one FY to the next.

Flow during FY close:
    1. Balance Sheet snapshot (ASSET, LIABILITY, EQUITY closing balances)
    2. Set opening_balance = 0 on permanent accounts (journal lines are source of truth)
    3. Inventory carry-forward (product current_stock → opening_stock)

Design decision:
    - Journal lines across ALL time are the sole source of truth
    - opening_balance is set to 0 (not closing balance) to avoid double-counting
    - No opening journal entry is created (snapshots provide audit trail)
    - update_account_balances computes: opening_balance + sum(all_journals)

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
        3. Set Account.opening_balance = 0 (journal lines are source of truth)

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

    # Idempotency guard: check if snapshots already exist for this FY
    existing_count = db.query(func.count(OpeningBalanceSnapshot.id)).filter(
        OpeningBalanceSnapshot.tenant_id == tenant_id,
        OpeningBalanceSnapshot.financial_year_id == closing_fy.id,
    ).scalar()
    if existing_count > 0:
        return {"accounts_carried": existing_count, "total_debits": "0", "total_credits": "0", "already_carried": True}

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
    snapshots: List[OpeningBalanceSnapshot] = []

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

        # CRITICAL: Set opening_balance = 0 (not closing_balance!)
        # Journal lines across ALL time are the source of truth.
        # update_account_balances computes: opening_balance + sum(all_journals)
        # By setting opening_balance = 0, we avoid double-counting historical movements.
        account.opening_balance = Decimal("0.0000")
        account.current_balance = Decimal("0.0000")

    # 4. Create snapshots
    db.add_all(snapshots)

    # 5. Recalculate current_balance for all affected accounts
    # This sums ALL journal lines (which is correct now that opening_balance = 0)
    account_ids_set = {a.id for a in permanent_accounts}
    from src.domains.accounting.services import update_account_balances
    update_account_balances(db, tenant_id, account_ids_set)

    return {
        "accounts_carried": len(snapshots),
        "total_debits": "0",
        "total_credits": "0",
        "journal_entry_id": None,
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
