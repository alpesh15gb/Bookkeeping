"""Direct-contract overrides for the end-to-end UAT suite.

The original UAT scenarios are preserved verbatim in
`_uat_business_simulation_base.py`. Only the expense scenario that encoded the
retired explicit `/post` action is overridden here.
"""

import importlib.util
import pathlib
import sys

_BASE_NAME = "_uat_business_simulation_base"
_BASE_PATH = pathlib.Path(__file__).with_name(f"{_BASE_NAME}.py")
_spec = importlib.util.spec_from_file_location(_BASE_NAME, _BASE_PATH)
_base = importlib.util.module_from_spec(_spec)
sys.modules[_BASE_NAME] = _base
_spec.loader.exec_module(_base)

for _name in dir(_base):
    if _name.startswith("Test"):
        globals()[_name] = getattr(_base, _name)

_Phase1Base = _base.TestUAT_Phase1_BusinessSimulation


class TestUAT_Phase1_BusinessSimulation(_Phase1Base):
    def test_024_expense_creation(self):
        """Save posts an expense immediately and creates its ledger entry."""
        cats = self.client.get(
            "/api/v1/masters/expense-categories", headers=self.headers
        ).json()
        cat = cats[0]

        response = _base._create_expense(
            self.client,
            self.headers,
            _base.uuid.UUID(cat["id"]),
            _base.Decimal("15000"),
            "18.00",
        )
        assert response.status_code == 201, response.text
        expense = response.json()
        assert expense["status"] == "POSTED"

        posting = self.db.query(_base.JournalEntry).filter(
            _base.JournalEntry.tenant_id == self.tenant_id,
            _base.JournalEntry.source_type == "EXPENSE",
            _base.JournalEntry.source_id == _base.uuid.UUID(expense["id"]),
        ).one()
        assert posting is not None
