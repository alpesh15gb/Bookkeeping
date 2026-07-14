"""Idempotent defaults that make a newly-created company ready for bookkeeping."""

from datetime import date, timedelta
import uuid

from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from src.core.database import Base
from src.domains.accounting.services import AccountResolver, _STANDARD_ACCOUNTS
from src.domains.company.services import (
    NumberingSeriesService,
    derive_origin_state_code,
    indian_financial_year,
    is_valid_gstin,
)
from src.infrastructure.database.models import (
    Branch,
    ExpenseCategory,
    FinancialYear,
    FinancialYearAudit,
    Tenant,
    TenantSetting,
)


DEFAULT_EXPENSE_CATEGORIES = (
    ("Tea & Refreshments", "expense.tea"),
    ("Transport & Travel", "expense.transport"),
    ("Rent", "expense.rent"),
    ("Salary & Wages", "expense.salary"),
    ("Office Supplies & Stationery", "expense.office"),
    ("Telephone & Internet", "expense.telephone"),
    ("Electricity & Utilities", "expense.electricity"),
    ("Advertising & Marketing", "expense.advertising"),
    ("Insurance", "expense.insurance"),
    ("Professional Fees", "expense.professional"),
    ("Repairs & Maintenance", "expense.repairs"),
    ("Bank Charges", "expense.bank_charges"),
    ("Depreciation", "expense.depreciation"),
    ("Miscellaneous Expense", "expense.misc"),
)


def _financial_year_from_start(start: date) -> tuple[date, date, str]:
    end = date(start.year + 1, start.month, start.day) - timedelta(days=1)
    return start, end, f"{start.year}-{end.year % 100:02d}"


def provision_company_defaults(
    db: Session,
    tenant: Tenant,
    owner_id: uuid.UUID,
    *,
    financial_year_start: date | None = None,
    as_of: date | None = None,
) -> None:
    """Seed safe, zero-balance company defaults in the caller's transaction.

    This deliberately does not create opening balances, bank accounts, GST filing
    registrations, or e-invoice credentials. Those facts must be supplied by the
    accountant and cannot be inferred safely during signup.
    """
    if financial_year_start is None:
        fy_start, fy_end, fy_name = indian_financial_year(as_of or date.today())
    else:
        fy_start, fy_end, fy_name = _financial_year_from_start(financial_year_start)
    tenant.financial_year_start = fy_start

    financial_year = db.query(FinancialYear).filter(
        FinancialYear.tenant_id == tenant.id,
        FinancialYear.start_date == fy_start,
        FinancialYear.end_date == fy_end,
    ).first()
    if financial_year is None:
        financial_year = FinancialYear(
            tenant_id=tenant.id,
            name=fy_name,
            start_date=fy_start,
            end_date=fy_end,
            status="CURRENT",
            is_current=True,
            created_by=owner_id,
        )
        db.add(financial_year)
        db.flush()
        db.add(FinancialYearAudit(
            tenant_id=tenant.id,
            financial_year_id=financial_year.id,
            action="CREATED",
            detail="Initial financial year created during company setup.",
            performed_by=owner_id,
        ))

    # Materialize the complete standard COA at setup. AccountResolver is
    # deterministic and idempotent, so all posting paths resolve the same ledgers.
    resolver = AccountResolver(db, tenant.id)
    for account_key in _STANDARD_ACCOUNTS:
        resolver.resolve(account_key)

    for category_name, account_key in DEFAULT_EXPENSE_CATEGORIES:
        category = db.query(ExpenseCategory).filter(
            ExpenseCategory.tenant_id == tenant.id,
            ExpenseCategory.name == category_name,
            ExpenseCategory.deleted_at == None,
        ).first()
        if category is None:
            db.add(ExpenseCategory(
                tenant_id=tenant.id,
                name=category_name,
                linked_account_id=resolver.resolve(account_key),
                is_active=True,
            ))

    warehouse = db.query(Branch).filter(
        Branch.tenant_id == tenant.id,
        Branch.deleted_at == None,
    ).order_by(Branch.created_at.asc()).first()
    if warehouse is None:
        warehouse = Branch(
            tenant_id=tenant.id,
            name="Main Warehouse",
            gstin=tenant.gstin if is_valid_gstin(tenant.gstin) else None,
            address={"country": "India"},
            is_active=True,
        )
        db.add(warehouse)
        db.flush()

    setting = db.query(TenantSetting).filter(TenantSetting.tenant_id == tenant.id).first()
    if setting is None:
        setting = TenantSetting(tenant_id=tenant.id)
        db.add(setting)

    setting.currency = "INR"
    setting.gst_enabled = is_valid_gstin(tenant.gstin)
    setting.e_invoicing_enabled = False
    setting.origin_state_code = derive_origin_state_code(tenant.gstin)
    setting.display_settings = {
        **(setting.display_settings or {}),
        "date_format": "dd MMM yyyy",
        "number_format": "en_IN",
        "theme_mode": "system",
        "timezone": "Asia/Kolkata",
    }
    setting.extra_settings = {
        **(setting.extra_settings or {}),
        "country_code": "IN",
        "accounting_basis": "ACCRUAL",
        "books_beginning_from": fy_start.isoformat(),
        "financial_year_name": fy_name,
        "financial_year_end": fy_end.isoformat(),
        "default_warehouse_id": str(warehouse.id),
        "pdf_template": "professional",
        "allow_negative_stock": False,
        "onboarding_completed": False,
    }

    NumberingSeriesService.seed_all_defaults(db, tenant.id)


_PURGE_PRESERVED_TABLES = {
    "tenants",
    "tenant_memberships",
    "audit_logs",
    "financial_year_audits",
    "period_lock_audits",
}


def reset_company_to_signup_defaults(
    db: Session,
    tenant: Tenant,
    owner_id: uuid.UUID,
    *,
    as_of: date | None = None,
) -> None:
    """Remove company data and recreate the same defaults used at signup.

    Membership and append-only compliance audit tables are deliberately
    retained. All other tenant-owned rows, including newer modules, are
    discovered from SQLAlchemy metadata so purge cannot silently miss a table.
    The caller owns the transaction and audit-log entry.
    """
    tables = list(reversed(Base.metadata.sorted_tables))

    # Line/detail tables generally inherit tenant scope through their parent
    # document rather than carrying tenant_id themselves. Delete those first.
    for table in tables:
        if "tenant_id" in table.c:
            continue
        tenant_parent_predicates = []
        for foreign_key in table.foreign_keys:
            parent = foreign_key.column.table
            if "tenant_id" not in parent.c:
                continue
            tenant_parent_predicates.append(
                foreign_key.parent.in_(
                    select(foreign_key.column).where(parent.c.tenant_id == tenant.id)
                )
            )
        if tenant_parent_predicates:
            db.execute(delete(table).where(or_(*tenant_parent_predicates)))

    # Reverse dependency order removes documents before masters. Preserve the
    # company, its users, and immutable audit evidence.
    for table in tables:
        if (
            "tenant_id" not in table.c
            or table.name in _PURGE_PRESERVED_TABLES
        ):
            continue
        db.execute(delete(table).where(table.c.tenant_id == tenant.id))

    db.flush()
    provision_company_defaults(db, tenant, owner_id, as_of=as_of)
