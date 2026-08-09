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


def set_db_tenant_context(db: Session, tenant_id) -> None:
    """Bind a tenant to both the current context and an active DB transaction.

    The session event handles transactions that begin after the context is set.
    This explicit statement also covers signup/bootstrap flows where the tenant
    row is created after the session has already started a transaction.
    """
    tenant_context.set(tenant_id)
    bind = db.get_bind()
    if bind.dialect.name != "sqlite":
        db.connection().execute(
            text("SET LOCAL app.current_tenant_id = :tid"),
            {"tid": str(tenant_id)},
        )

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
        tenant_context.set(None)
