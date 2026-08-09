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
# Register every table with Base.metadata so the squashed baseline revision
# (20260811_0000_squashed_baseline) can build the complete schema on a fresh
# database, and so autogenerate diffs see the whole model.
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
# Squashed-baseline chain bookkeeping.
#
# The current chain is rooted at the squashed baseline revision
# ``20260811_0000_squashed_baseline`` (down_revision = None).  The pre-squash
# chain (20260524_0001 .. 20260810_0001) is preserved under
# ``alembic/versions_legacy/`` for auditability but is NOT loaded by Alembic:
# those revisions predate an Alembic baseline and cannot be replayed from an
# empty database (54 of the tables they ALTER were created outside the chain).
#
# Deployments that already ran the legacy chain carry the legacy head revision
# in their alembic_version table.  Their schema is exactly the schema the
# squashed baseline describes (the legacy head is the direct ancestor), so we
# STAMP the baseline and continue with normal upgrades.  Everything else
# (fresh databases, databases already on the new chain) upgrades normally.
# ---------------------------------------------------------------------------
LEGACY_CHAIN_HEADS = {"20260810_0001"}
SQUASHED_BASELINE_REVISION = "20260811_0000_squashed_baseline"


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
        # SQLAlchemy 2 starts an implicit transaction for the inspection query.
        # Alembic will not commit a transaction it considers externally owned,
        # so leaving this open makes a successful upgrade roll back silently
        # when the connection closes. End inspection before Alembic takes over.
        connection.commit()

        current_rev = _current_revision(connection) if existing_tables else None

        if existing_tables and current_rev is None:
            raise RuntimeError(
                "Database contains tables but no alembic_version entry. "
                "Refusing to guess: verify the schema, then stamp the "
                "squashed baseline explicitly (alembic stamp "
                "20260811_0000_squashed_baseline) before upgrading."
            )

        if current_rev in LEGACY_CHAIN_HEADS:
            # Legacy deployment: schema already matches the squashed baseline.
            # Stamp it and let the normal upgrade continue to head.
            print(
                f"env.py: stamping squashed baseline {SQUASHED_BASELINE_REVISION} "
                f"(was on legacy chain head {current_rev})",
                file=sys.stderr,
            )
            # The new-chain revision ids exceed VARCHAR(32).  Widen the
            # version column first; requires table ownership (the ownership
            # transfer script must run before the first new-chain upgrade on
            # an existing deployment).
            try:
                connection.execute(
                    text(
                        "ALTER TABLE alembic_version "
                        "ALTER COLUMN version_num TYPE VARCHAR(255)"
                    )
                )
                connection.commit()
            except Exception as exc:  # pragma: no cover - environment dependent
                raise RuntimeError(
                    "Cannot widen alembic_version for the squashed baseline. "
                    "Run scripts/transfer_ownership.py first so the migration "
                    "role owns the schema. (%s)" % exc
                ) from exc
            # Alembic's stamp() resolves the *current* heads from the loaded
            # script directory, and the legacy head is no longer loaded.  Purge
            # the stale version row so stamp() treats the baseline as a fresh
            # head (the schema is already at the baseline shape).
            connection.execute(text("DELETE FROM alembic_version"))
            connection.commit()
            MigrationContext.configure(connection).stamp(
                ScriptDirectory.from_config(config), SQUASHED_BASELINE_REVISION
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
