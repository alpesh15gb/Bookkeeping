"""Direct-contract overrides for the comprehensive backend integration suite.

The original P1-P7 suite is preserved verbatim in
`_backend_integration_sprint_base.py`.  Only tests that encoded the retired
Draft/Post/Cancel/nested-payment API are overridden here; every unaffected test
class is re-exported unchanged.
"""

import importlib.util
import pathlib
import sys

_BASE_NAME = "_backend_integration_sprint_base"
_BASE_PATH = pathlib.Path(__file__).with_name(f"{_BASE_NAME}.py")
_spec = importlib.util.spec_from_file_location(_BASE_NAME, _BASE_PATH)
_base = importlib.util.module_from_spec(_spec)
sys.modules[_BASE_NAME] = _base
_spec.loader.exec_module(_base)

# Re-export every original test class. The three classes below are then
# replaced with subclasses that override only obsolete workflow methods.
for _name in dir(_base):
    if _name.startswith("Test"):
        globals()[_name] = getattr(_base, _name)

_P2Base = _base.TestP2_APIContractValidation
_P3Base = _base.TestP3_AccountingEngine
_P5Base = _base.TestP5_OfflineSyncValidation


class TestP2_APIContractValidation(_P2Base):
    def test_expense_crud_lifecycle(self, db_session, client):
        tenant = _base._seed_tenant(db_session)
        user = _base._seed_user(db_session, tenant)
        cat = _base._seed_expense_category(db_session, tenant)
        _base._seed_numbering_series(db_session, tenant)
        headers = _base._auth(user, tenant)

        created = client.post(
            "/api/v1/expenses",
            json={
                "expense_category_id": str(cat.id),
                "expense_date": str(_base.date.today()),
                "vendor_name": "Test Vendor",
                "description": "Sprint test expense",
                "amount": "1000.00",
                "gst_rate": "18.00",
            },
            headers=headers,
        )
        assert created.status_code == 201, created.text
        data = created.json()
        assert data["status"] == "POSTED"
        eid = _base.uuid.UUID(data["id"])

        posting = db_session.query(_base.JournalEntry).filter(
            _base.JournalEntry.tenant_id == tenant.id,
            _base.JournalEntry.source_type == "EXPENSE",
            _base.JournalEntry.source_id == eid,
        ).one()
        assert posting is not None

        assert client.get(f"/api/v1/expenses/{eid}", headers=headers).status_code == 200
        assert client.get("/api/v1/expenses", headers=headers).status_code == 200

        deleted = client.delete(f"/api/v1/expenses/{eid}", headers=headers)
        assert deleted.status_code == 204, deleted.text
        assert db_session.query(_base.JournalEntry).filter(
            _base.JournalEntry.tenant_id == tenant.id,
            _base.JournalEntry.source_type == "EXPENSE_REVERSAL",
            _base.JournalEntry.source_id == eid,
        ).count() == 1


class TestP3_AccountingEngine(_P3Base):
    def test_expense_posting_creates_journal(self, db_session, client):
        tenant = _base._seed_tenant(db_session)
        user = _base._seed_user(db_session, tenant)
        cat = _base._seed_expense_category(db_session, tenant)
        _base._seed_numbering_series(db_session, tenant)
        headers = _base._auth(user, tenant)

        created = client.post(
            "/api/v1/expenses",
            json={
                "expense_category_id": str(cat.id),
                "expense_date": str(_base.date.today()),
                "vendor_name": "Expense Vendor",
                "description": "Test expense",
                "amount": "500.00",
                "gst_rate": "0.00",
            },
            headers=headers,
        )
        assert created.status_code == 201, created.text
        data = created.json()
        assert data["status"] == "POSTED"
        assert db_session.query(_base.JournalEntry).filter(
            _base.JournalEntry.tenant_id == tenant.id,
            _base.JournalEntry.source_type == "EXPENSE",
            _base.JournalEntry.source_id == _base.uuid.UUID(data["id"]),
        ).count() == 1

    def test_payment_creates_posting(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _base._auth(user, tenant)
        invoice_response = client.post(
            "/api/v1/invoices",
            json=_base._make_invoice_payload(contact.id, product.id, pos_state="27"),
            headers=headers,
        )
        assert invoice_response.status_code == 201, invoice_response.text
        invoice = invoice_response.json()

        payment_response = client.post(
            "/api/v1/payments/receipts",
            json={
                "contact_id": str(contact.id),
                "payment_date": str(_base.date.today()),
                "payment_mode": "CASH",
                "amount": invoice["total"],
                "allocations": [
                    {"invoice_id": invoice["id"], "amount": invoice["total"]}
                ],
            },
            headers=headers,
        )
        assert payment_response.status_code == 201, payment_response.text
        payment = payment_response.json()
        assert db_session.query(_base.JournalEntry).filter(
            _base.JournalEntry.tenant_id == tenant.id,
            _base.JournalEntry.source_type == "PAYMENT",
            _base.JournalEntry.source_id == _base.uuid.UUID(payment["id"]),
        ).count() == 1

    def test_invoice_cancel_creates_reversal(self, db_session, client):
        tenant, user, contact, product = self._setup(db_session)
        headers = _base._auth(user, tenant)
        created = client.post(
            "/api/v1/invoices",
            json=_base._make_invoice_payload(contact.id, product.id, pos_state="27"),
            headers=headers,
        )
        assert created.status_code == 201, created.text
        invoice_id = _base.uuid.UUID(created.json()["id"])

        deleted = client.delete(f"/api/v1/invoices/{invoice_id}", headers=headers)
        assert deleted.status_code == 204, deleted.text
        assert db_session.query(_base.JournalEntry).filter(
            _base.JournalEntry.tenant_id == tenant.id,
            _base.JournalEntry.source_type == "INVOICE_REVERSAL",
            _base.JournalEntry.source_id == invoice_id,
        ).count() == 1


class TestP5_OfflineSyncValidation(_P5Base):
    def test_cancelled_invoice_cannot_be_edited(self, db_session, client):
        """Delete is the public reversal action; a deleted source cannot be edited."""
        tenant = _base._seed_tenant(db_session)
        user = _base._seed_user(db_session, tenant)
        contact = _base._seed_contact(
            db_session,
            tenant,
            gstin="27AAACB1234F1Z5",
            state_code="27",
        )
        product = _base._seed_product(db_session, tenant)
        _base._seed_numbering_series(db_session, tenant)
        headers = _base._auth(user, tenant)

        created = client.post(
            "/api/v1/invoices",
            json=_base._make_invoice_payload(contact.id, product.id, pos_state="27"),
            headers=headers,
        )
        assert created.status_code == 201, created.text
        invoice_id = created.json()["id"]

        deleted = client.delete(f"/api/v1/invoices/{invoice_id}", headers=headers)
        assert deleted.status_code == 204, deleted.text

        edit = client.put(
            f"/api/v1/invoices/{invoice_id}",
            json={"notes": "must not resurrect deleted source"},
            headers=headers,
        )
        assert edit.status_code == 404
