"""Squashed baseline: reproducible schema for fresh PostgreSQL deployments.

Revision ID: 20260811_0000_squashed_baseline
Revises: None
Create Date: 2026-08-11

Why this exists
---------------
The historical revision chain (20260524_0001 .. 20260810_0001) began life as
ALTERs on a schema that predated Alembic: 54 of the 87 production tables are
never created by any migration in that chain.  A genuinely empty database
therefore cannot be built by replaying the chain — a fresh deploy previously
fell back to an env.py shortcut that called ``Base.metadata.create_all()`` and
stamped the head without recording a revision.

This revision replaces that shortcut with a committed, versioned baseline:

* ``upgrade()`` builds the complete current schema from the ORM metadata and
  applies the full PostgreSQL hardening (RLS, tenant-consistency triggers,
  ledger balance checks, ledger/stock immutability triggers, audit
  immutability, the controlled tenant enumerator).  ``alembic upgrade head``
  on an empty database is now the only thing a fresh deployment needs.
* Existing deployments are NOT affected: ``alembic/env.py`` recognises the
  legacy chain head (20260810_0001), verifies the schema already matches this
  baseline (the legacy head is the direct ancestor of the baseline schema),
  stamps this revision, and continues with normal upgrades.

The schema produced here is the same schema the ORM metadata describes, and
CI runs ``alembic check`` (autogenerate diff) plus the PostgreSQL integration
suite against it, so drift between models and migrations fails the build.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "20260811_0000_squashed_baseline"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Build the complete current schema + hardening on an empty database."""
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        # The baseline only runs on PostgreSQL; SQLite test databases are
        # still built by the test fixtures (Base.metadata.create_all).
        return

    # Register every table with Base.metadata (mirrors alembic/env.py).
    import sys
    import os

    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    from src.core.database import Base
    from src.core.postgres_hardening import apply_postgres_hardening
    from src.infrastructure.database import models as _models  # noqa: F401
    from src.infrastructure.database.idempotency import IdempotencyRecord  # noqa: F401
    from src.integrations.core import models as _integration_models  # noqa: F401
    from src.integrations.cartunez import master_models as _integration_master_models  # noqa: F401
    from src.integrations.cartunez import order_models as _integration_order_models  # noqa: F401
    from src.integrations.cartunez import payment_models as _integration_payment_models  # noqa: F401

    # The squashed chain uses revision ids longer than the 32-character
    # default of the alembic_version.version_num column, so widen it before
    # Alembic records the first new-chain revision.  (Legacy deployments get
    # the same widening from alembic/env.py before their baseline stamp.)
    bind.execute(
        sa.text("ALTER TABLE alembic_version ALTER COLUMN version_num TYPE VARCHAR(255)")
    )

    # create_all is checkfirst (never touches existing tables), so this is
    # safe even if a partially-populated database is ever stamped here.
    Base.metadata.create_all(bind=bind)
    apply_postgres_hardening(bind)


def downgrade() -> None:
    """Not supported: a squashed baseline has no reversible downgrade path.

    Existing deployments never run this revision (they are stamped over it),
    so a downgrade target would be meaningless.  Fresh databases that need to
    roll back should restore a backup instead.
    """
    raise NotImplementedError(
        "20260811_0000_squashed_baseline cannot be downgraded; restore from backup."
    )
