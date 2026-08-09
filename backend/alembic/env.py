from logging.config import fileConfig

from sqlalchemy import engine_from_config, inspect, text
from sqlalchemy import pool
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory

from alembic import context

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from src.core.database import Base
# Register every table with Base.metadata so autogenerate diffs see the whole
# model.  (The squashed baseline revision does NOT use this metadata — it is
# a committed static snapshot — but keeping the registration here means
# `alembic check` / autogenerate compares against the complete model.)
from src.infrastructure.database import models as _models  # noqa: F401
from src.infrastructure.database.idempotency import IdempotencyRecord as _IdempotencyRecord  # noqa: F401
from src.integrations.core import models as _integration_models  # noqa: F401
from src.integrations.cartunez import master_models as _integration_master_models  # noqa: F401
from src.integrations.cartunez import order_models as _integration_order_models  # noqa: F401
from src.integrations.cartunez import payment_models as _integration_payment_models  # noqa: F401
target_metadata = Base.metadata

# Override sqlalchemy.url with env vars when running in Docker.
# MIGRATION_DATABASE_URL (the privileged migration role) wins over DATABASE_URL
# (the restricted application role), so `alembic upgrade head` never runs as a
# role that lacks DDL privileges.
database_url = os.getenv("MIGRATION_DATABASE_URL") or os.getenv("DATABASE_URL")
if database_url:
    config.set_main_option("sqlalchemy.url", database_url)

# ---------------------------------------------------------------------------
# Chain layout.
#
# The migration chain is a single linear sequence in alembic/versions/:
#
#   20260524_0001 .. 20260810_0001   (historical ALTERs; kept so that existing
#                                    deployments sitting on ANY legacy
#                                    revision can upgrade forward)
#   -> 20260811_0000_squashed_baseline   (immutable full-schema snapshot;
#                                         no-op when a schema already exists)
#   -> 20260811_0001 .. 20260811_0004    (deltas: allocation tenancy, ledger
#                                         immutability, idempotency resource
#                                         recovery, least-privilege grants)
#
# Because the whole chain is loaded:
#   * a fresh database is stamped to the legacy head by env.py and then built
#     by the baseline snapshot (the legacy ALTERs cannot replay from empty —
#     54 of the tables they modify predate the chain, which is exactly why the
#     baseline exists);
#   * an existing deployment on ANY legacy revision upgrades by running the
#     remaining legacy ALTERs, then the baseline (a no-op), then the deltas.
# ---------------------------------------------------------------------------
LEGACY_CHAIN_HEAD = "20260810_0001"


def _current_revision(connection):
    try:
        return connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one_or_none()
    except Exception:
        return None


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode.

    In this scenario we need to create an Engine
    and associate a connection with the context.

    """
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        existing_tables = inspect(connection).get_table_names()
        current_rev = _current_revision(connection) if existing_tables else None
        # SQLAlchemy 2 starts an implicit transaction for every inspection /
        # revision-read query.  Alembic will not commit a transaction it
        # considers externally owned, so leaving any such transaction open
        # makes a successful upgrade (or stamp) roll back silently when the
        # connection closes.  End ALL implicit transactions before Alembic
        # takes over.
        connection.commit()

        if existing_tables and current_rev is None:
            raise RuntimeError(
                "Database contains tables but no alembic_version entry. "
                "Refusing to guess: verify the schema, then stamp an explicit "
                "revision before upgrading (e.g. alembic stamp "
                f"{LEGACY_CHAIN_HEAD} for a legacy schema, or "
                "20260811_0000_squashed_baseline for a schema already at the "
                "squashed shape)."
            )

        if not existing_tables:
            # Fresh database: the historical ALTER chain cannot replay from an
            # empty schema (54 of the tables it modifies predate Alembic), and
            # the squashed baseline IS that whole chain's final shape.  Record
            # the legacy head as the effective starting point; the baseline
            # then builds the complete schema from its committed snapshot.
            print(
                f"env.py: empty database — stamping legacy head "
                f"{LEGACY_CHAIN_HEAD}; the squashed baseline will build the "
                f"schema.",
                file=sys.stderr,
            )
            MigrationContext.configure(connection).stamp(
                ScriptDirectory.from_config(config), LEGACY_CHAIN_HEAD
            )
            connection.commit()

        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
