"""
src/infrastructure/database/mixins.py
Soft-delete query mixin that auto-applies deleted_at IS NULL to all queries.
"""
from sqlalchemy.orm import Query


class ActiveQuery(Query):
    """SQLAlchemy Query subclass that auto-filters soft-deleted rows."""

    def __init__(self, entities, session=None):
        super().__init__(entities, session)

    def __iter__(self):
        return self._apply_active_filter().__iter__()

    def all(self):
        return self._apply_active_filter().all()

    def first(self):
        return self._apply_active_filter().first()

    def one(self):
        return self._apply_active_filter().one()

    def one_or_none(self):
        return self._apply_active_filter().one_or_none()

    def count(self):
        return self._apply_active_filter().count()

    def _apply_active_filter(self):
        """Applies deleted_at IS NULL filter if the model has the column."""
        if self.column_descriptions:
            model = self.column_descriptions[0]["entity"]
            if hasattr(model, "deleted_at"):
                return self.filter(model.deleted_at.is_(None))
        return self
