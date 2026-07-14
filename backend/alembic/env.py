from logging.config import fileConfig

from sqlalchemy import engine_from_config, inspect
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
# Register every table with Base.metadata for the guarded fresh-database bootstrap.
from src.infrastructure.database import models as _models  # noqa: F401
from src.infrastructure.database.idempotency import IdempotencyRecord as _IdempotencyRecord  # noqa: F401
target_metadata = Base.metadata

# Override sqlalchemy.url with DATABASE_URL env var when running in Docker
database_url = os.getenv("DATABASE_URL")
if database_url:
    config.set_main_option("sqlalchemy.url", database_url)


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
        # The historical chain begins with ALTER statements and predates an
        # Alembic baseline.  A genuinely empty database therefore needs the
        # current declarative schema once; existing databases always follow
        # the normal revision-by-revision migration path below.
        existing_tables = inspect(connection).get_table_names()
        # SQLAlchemy 2 starts an implicit transaction for the inspection query.
        # Alembic will not commit a transaction it considers externally owned,
        # so leaving this open makes a successful upgrade roll back silently
        # when the connection closes. End inspection before Alembic takes over.
        connection.commit()
        if not existing_tables:
            target_metadata.create_all(connection)
            MigrationContext.configure(connection).stamp(
                ScriptDirectory.from_config(config), "head"
            )
            connection.commit()
            return
        context.configure(
            connection=connection, target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
