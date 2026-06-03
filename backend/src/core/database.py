"""
src/core/database.py
SQLAlchemy engine, session factory, and tenant context variable.
All connection config comes from src.core.config (never hardcoded).
"""
import contextvars
import logging
from sqlalchemy import create_engine, text, event
from sqlalchemy.orm import sessionmaker, Session, declarative_base
from sqlalchemy.pool import QueuePool

logger = logging.getLogger(__name__)

from src.core.config import settings

# ContextVar to hold tenant_id across request contexts
tenant_context: contextvars.ContextVar = contextvars.ContextVar("tenant_context", default=None)

# ---------------------------------------------------------------------------
# Engine — PostgreSQL in production, SQLite fallback for tests
# ---------------------------------------------------------------------------
DATABASE_URL = settings.DATABASE_URL

if DATABASE_URL.startswith("postgresql://"):
    try:
        import psycopg2  # noqa: F401 — just checking availability
    except ImportError:
        pass
    engine = create_engine(
        DATABASE_URL,
        poolclass=QueuePool,
        pool_size=5,
        max_overflow=10,
        pool_timeout=30,
        pool_recycle=1800,
        pool_pre_ping=True,
    )
else:
    # SQLite fallback for lightweight unit tests
    DATABASE_URL = DATABASE_URL or "sqlite:///./bookkeeping.db"
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# ---------------------------------------------------------------------------
# Row-Level Security tenant context hook
# ---------------------------------------------------------------------------

@event.listens_for(Session, "after_begin")
def set_rls_tenant_context(session, transaction, connection):
    """
    SQLAlchemy session event listener.
    Sets a transaction-local PostgreSQL config parameter for RLS policies.
    Skips silently on SQLite (used in tests).
    """
    if connection.dialect.name == "sqlite":
        return

    tenant_id = tenant_context.get()
    if tenant_id is not None:
        connection.execute(
            text("SET LOCAL app.current_tenant_id = :tid"),
            {"tid": str(tenant_id)},
        )
    else:
        connection.execute(text("SET LOCAL app.current_tenant_id = ''"))


# ---------------------------------------------------------------------------
# FastAPI dependency
# ---------------------------------------------------------------------------

def get_db_session():
    """FastAPI dependency — yields a database session per request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def ensure_vyapar_import_columns():
    """Add columns needed for Vyapar import if they don't exist yet."""
    from sqlalchemy import inspect, text as sql_text
    inspector = inspect(engine)
    dialect = engine.dialect.name

    migrations = [
        ("expense_categories", "deleted_at", "ALTER TABLE expense_categories ADD COLUMN deleted_at TIMESTAMPTZ"),
        ("contacts", "opening_balance", "ALTER TABLE contacts ADD COLUMN opening_balance NUMERIC(15,4) NOT NULL DEFAULT 0"),
        ("contacts", "custom_fields", "ALTER TABLE contacts ADD COLUMN custom_fields JSONB NOT NULL DEFAULT '{}'"),
        ("products", "party_item_rates", "ALTER TABLE products ADD COLUMN party_item_rates JSONB NOT NULL DEFAULT '{}'"),
        ("invoices", "vyapar_custom_fields", "ALTER TABLE invoices ADD COLUMN vyapar_custom_fields JSONB NOT NULL DEFAULT '{}'"),
        ("bills", "vyapar_custom_fields", "ALTER TABLE bills ADD COLUMN vyapar_custom_fields JSONB NOT NULL DEFAULT '{}'"),
    ]

    for table, column, sql in migrations:
        try:
            cols = [c["name"] for c in inspector.get_columns(table)]
            if column not in cols:
                with engine.begin() as conn:
                    conn.execute(sql_text(sql))
                logger.info(f"Added column {table}.{column}")
        except Exception as e:
            logger.warning(f"Could not add {table}.{column}: {e}")

    # Backfill NULL descriptions on proforma_invoice_lines from product names
    try:
        with engine.begin() as conn:
            conn.execute(sql_text("""
                UPDATE proforma_invoice_lines pil
                SET description = p.name
                FROM products p
                WHERE pil.product_id = p.id
                  AND (pil.description IS NULL OR pil.description = '')
            """))
        logger.info("Backfilled proforma_invoice_lines.description from products.name")
    except Exception as e:
        logger.warning(f"Could not backfill proforma_invoice_lines.description: {e}")

    # Backfill NULL descriptions on invoice_lines from product names
    try:
        with engine.begin() as conn:
            conn.execute(sql_text("""
                UPDATE invoice_lines il
                SET description = p.name
                FROM products p
                WHERE il.product_id = p.id
                  AND (il.description IS NULL OR il.description = '')
            """))
        logger.info("Backfilled invoice_lines.description from products.name")
    except Exception as e:
        logger.warning(f"Could not backfill invoice_lines.description: {e}")

    # Backfill NULL descriptions on bill_lines from product names
    try:
        with engine.begin() as conn:
            conn.execute(sql_text("""
                UPDATE bill_lines bl
                SET description = p.name
                FROM products p
                WHERE bl.product_id = p.id
                  AND (bl.description IS NULL OR bl.description = '')
            """))
        logger.info("Backfilled bill_lines.description from products.name")
    except Exception as e:
        logger.warning(f"Could not backfill bill_lines.description: {e}")
