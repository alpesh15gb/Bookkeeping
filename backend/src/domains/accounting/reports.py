from decimal import Decimal
from typing import List, Dict, Any, Optional
from datetime import date
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import text


def _uuid_param(db: Session, uid: uuid.UUID) -> str:
    """Return UUID in dialect-appropriate format for raw SQL queries.
    SQLite stores UUIDs as hex; PostgreSQL accepts standard hyphenated format."""
    if db.bind.dialect.name == "sqlite":
        return uid.hex
    return str(uid)


class ReportItem:
    def __init__(self, account_name: str, account_code: str, classification: str, balance: Decimal):
        self.account_name = account_name
        self.account_code = account_code
        self.classification = classification
        self.balance = balance.quantize(Decimal("0.01"))

    def to_dict(self) -> Dict[str, Any]:
        return {
            "account_name": self.account_name,
            "account_code": self.account_code,
            "classification": self.classification,
            "balance": float(self.balance)
        }

class FinancialReportingService:
    """
    Accounting reporting compiler.
    Uses database-level aggregations to compile standard Indian compliance reports.
    
    CRITICAL: All queries filter by tenant_id to prevent cross-tenant data leaks.
    """

    @staticmethod
    def get_trial_balance(db: Session, as_of_date: date, tenant_id: uuid.UUID = None) -> Dict[str, Any]:
        """
        Compiles the Trial Balance as of a specific date.
        Sums debits and credits for each ledger account.
        
        CRITICAL: Requires tenant_id parameter to prevent cross-tenant data leaks.
        """
        if tenant_id is None:
            raise ValueError("tenant_id is required for get_trial_balance")
            
        query = text("""
            SELECT
                a.name AS account_name,
                a.code AS account_code,
                a.account_type AS classification,
                a.opening_balance,
                COALESCE(SUM(CASE WHEN jl.direction = 'DEBIT' THEN jl.amount ELSE 0 END), 0) AS tx_debit,
                COALESCE(SUM(CASE WHEN jl.direction = 'CREDIT' THEN jl.amount ELSE 0 END), 0) AS tx_credit
            FROM accounts a
            LEFT JOIN journal_lines jl ON a.id = jl.account_id
            LEFT JOIN journal_entries je ON jl.entry_id = je.id AND je.tenant_id = :tenant_id
            WHERE (je.entry_date <= :as_of_date OR je.entry_date IS NULL)
              AND a.tenant_id = :tenant_id
              AND a.deleted_at IS NULL
            GROUP BY a.id, a.name, a.code, a.account_type, a.opening_balance
            ORDER BY a.code
        """)

        result = db.execute(query, {"as_of_date": as_of_date, "tenant_id": _uuid_param(db, tenant_id)}).fetchall()

        trial_balance_lines = []
        total_debits = Decimal("0.00")
        total_credits = Decimal("0.00")

        for row in result:
            tx_debit = Decimal(str(row.tx_debit))
            tx_credit = Decimal(str(row.tx_credit))
            op_bal = Decimal(str(row.opening_balance or 0))

            # Include opening balance: ASSET/EXPENSE have debit opening; others have credit opening
            if row.classification in ("ASSET", "EXPENSE"):
                total_debit = tx_debit + op_bal
                total_credit = tx_credit
            else:
                total_debit = tx_debit
                total_credit = tx_credit + op_bal

            # Net balance calculation based on account type
            if row.classification in ("ASSET", "EXPENSE"):
                net_balance = total_debit - total_credit
            else:
                net_balance = total_credit - total_debit

            trial_balance_lines.append({
                "account_name": row.account_name,
                "account_code": row.account_code,
                "classification": row.classification,
                "debit": float(total_debit.quantize(Decimal("0.01"))),
                "credit": float(total_credit.quantize(Decimal("0.01"))),
                "net_balance": float(net_balance.quantize(Decimal("0.01")))
            })

            total_debits += total_debit
            total_credits += total_credit

        return {
            "as_of_date": as_of_date.isoformat(),
            "lines": trial_balance_lines,
            "total_debits": float(total_debits.quantize(Decimal("0.01"))),
            "total_credits": float(total_credits.quantize(Decimal("0.01"))),
            "is_balanced": total_debits.quantize(Decimal("0.01")) == total_credits.quantize(Decimal("0.01"))
        }

    @staticmethod
    def get_profit_and_loss(db: Session, start_date: date, end_date: date, tenant_id: uuid.UUID = None) -> Dict[str, Any]:
        """
        Compiles the Profit and Loss (Income Statement) for a date range.
        Revenue - Expenses.
        
        CRITICAL: Requires tenant_id parameter to prevent cross-tenant data leaks.
        """
        if tenant_id is None:
            raise ValueError("tenant_id is required for get_profit_and_loss")
            
        query = text("""
            SELECT 
                a.name AS account_name,
                a.code AS account_code,
                a.account_type AS classification,
                COALESCE(SUM(CASE WHEN jl.direction = 'DEBIT' THEN jl.amount ELSE 0 END), 0) AS total_debit,
                COALESCE(SUM(CASE WHEN jl.direction = 'CREDIT' THEN jl.amount ELSE 0 END), 0) AS total_credit
            FROM accounts a
            JOIN journal_lines jl ON a.id = jl.account_id
            JOIN journal_entries je ON jl.entry_id = je.id
            WHERE je.entry_date BETWEEN :start_date AND :end_date
              AND COALESCE(je.source_type, '') <> 'YEAR_END'
              AND a.account_type IN ('REVENUE', 'EXPENSE')
              AND a.tenant_id = :tenant_id
              AND a.deleted_at IS NULL
            GROUP BY a.id, a.name, a.code, a.account_type
            ORDER BY a.account_type DESC, a.code ASC
        """)

        result = db.execute(query, {"start_date": start_date, "end_date": end_date, "tenant_id": _uuid_param(db, tenant_id)}).fetchall()

        revenue_items = []
        expense_items = []
        total_revenue = Decimal("0.00")
        total_expense = Decimal("0.00")

        for row in result:
            debit = Decimal(str(row.total_debit))
            credit = Decimal(str(row.total_credit))

            if row.classification == "REVENUE":
                net = credit - debit
                total_revenue += net
                revenue_items.append(ReportItem(row.account_name, row.account_code, row.classification, net).to_dict())
            else:
                net = debit - credit
                total_expense += net
                expense_items.append(ReportItem(row.account_name, row.account_code, row.classification, net).to_dict())

        net_profit = total_revenue - total_expense

        return {
            "period": {
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat()
            },
            "revenue": {
                "items": revenue_items,
                "total": float(total_revenue.quantize(Decimal("0.01")))
            },
            "expenses": {
                "items": expense_items,
                "total": float(total_expense.quantize(Decimal("0.01")))
            },
            "net_profit": float(net_profit.quantize(Decimal("0.01")))
        }

    @staticmethod
    def get_balance_sheet(db: Session, as_of_date: date, tenant_id: uuid.UUID = None) -> Dict[str, Any]:
        """
        Compiles the Balance Sheet as of a specific date.
        Assets = Liabilities + Equity (including current year Net Profit / Retained Earnings).
        
        CRITICAL: Requires tenant_id parameter to prevent cross-tenant data leaks.
        """
        if tenant_id is None:
            raise ValueError("tenant_id is required for get_balance_sheet")
            
        # Fetch Asset, Liability, and Equity account summaries up to target date
        query = text("""
            SELECT 
                a.name AS account_name,
                a.code AS account_code,
                a.account_type AS classification,
                COALESCE(SUM(CASE WHEN jl.direction = 'DEBIT' THEN jl.amount ELSE 0 END), 0) AS total_debit,
                COALESCE(SUM(CASE WHEN jl.direction = 'CREDIT' THEN jl.amount ELSE 0 END), 0) AS total_credit
            FROM accounts a
            JOIN journal_lines jl ON a.id = jl.account_id
            JOIN journal_entries je ON jl.entry_id = je.id
            WHERE je.entry_date <= :as_of_date
              AND a.account_type IN ('ASSET', 'LIABILITY', 'EQUITY')
              AND a.tenant_id = :tenant_id
              AND a.deleted_at IS NULL
            GROUP BY a.id, a.name, a.code, a.account_type
            ORDER BY a.account_type ASC, a.code ASC
        """)

        result = db.execute(query, {"as_of_date": as_of_date, "tenant_id": _uuid_param(db, tenant_id)}).fetchall()

        assets = []
        liabilities = []
        equity = []
        total_assets = Decimal("0.00")
        total_liabilities = Decimal("0.00")
        total_equity = Decimal("0.00")

        for row in result:
            debit = Decimal(str(row.total_debit))
            credit = Decimal(str(row.total_credit))

            if row.classification == "ASSET":
                net = debit - credit
                total_assets += net
                assets.append(ReportItem(row.account_name, row.account_code, row.classification, net).to_dict())
            elif row.classification == "LIABILITY":
                net = credit - debit
                total_liabilities += net
                liabilities.append(ReportItem(row.account_name, row.account_code, row.classification, net).to_dict())
            elif row.classification == "EQUITY":
                net = credit - debit
                total_equity += net
                equity.append(ReportItem(row.account_name, row.account_code, row.classification, net).to_dict())

        # Dynamic Retained Earnings from P&L up to this date
        # Note: In a complete ledger, current year earnings must be accounted for to balance
        # Find start of the current financial year (April 1st)
        fy_year = as_of_date.year if as_of_date.month >= 4 else as_of_date.year - 1
        fy_start = date(fy_year, 4, 1)
        
        # Guard: ensure P&L period is valid (start <= end)
        if fy_start <= as_of_date:
            # A year-end journal has already transferred that FY's result to
            # retained earnings. Adding P&L again would double-count equity.
            closing_entry_exists = db.execute(text("""
                SELECT 1 FROM journal_entries
                WHERE tenant_id = :tenant_id
                  AND source_type = 'YEAR_END'
                  AND entry_date BETWEEN :fy_start AND :as_of_date
                LIMIT 1
            """), {
                "tenant_id": _uuid_param(db, tenant_id),
                "fy_start": fy_start,
                "as_of_date": as_of_date,
            }).first() is not None
            if closing_entry_exists:
                current_year_earnings = Decimal("0.00")
            else:
                pl_data = FinancialReportingService.get_profit_and_loss(db, fy_start, as_of_date, tenant_id)
                current_year_earnings = Decimal(str(pl_data["net_profit"]))
        else:
            current_year_earnings = Decimal("0.00")
        total_equity += current_year_earnings
        
        equity.append({
            "account_name": "Current Year Earnings (P&L)",
            "account_code": "39999",
            "classification": "EQUITY",
            "balance": float(current_year_earnings.quantize(Decimal("0.01")))
        })

        return {
            "as_of_date": as_of_date.isoformat(),
            "assets": {
                "items": assets,
                "total": float(total_assets.quantize(Decimal("0.01")))
            },
            "liabilities": {
                "items": liabilities,
                "total": float(total_liabilities.quantize(Decimal("0.01")))
            },
            "equity": {
                "items": equity,
                "total": float(total_equity.quantize(Decimal("0.01")))
            },
            "total_liabilities_and_equity": float((total_liabilities + total_equity).quantize(Decimal("0.01"))),
            "is_balanced": total_assets.quantize(Decimal("0.01")) == (total_liabilities + total_equity).quantize(Decimal("0.01"))
        }
