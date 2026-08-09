import os
import sys
import uuid
import unittest
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.core.security import create_access_token, get_password_hash, ROLE_PERMISSIONS
from src.infrastructure.database.models import (
    Expense,
    JournalEntry,
    Tenant,
    TenantMembership,
    User,
)


class TestExpenses(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        db = SessionLocal()
        try:
            self.user_id = uuid.uuid4()
            self.tenant_id = uuid.uuid4()
            db.add(User(
                id=self.user_id,
                email="expense_owner@company.com",
                password_hash=get_password_hash("SecurePassword123!"),
                full_name="Expense Owner",
                phone_number="+919876543210",
                is_active=True,
                email_verified=True,
            ))
            db.add(Tenant(
                id=self.tenant_id,
                legal_name="Expense Corp Pvt Ltd",
                trade_name="Expense Corp",
                gstin="27AAPFU0939F1ZV",
                pan="AAPFU0939F",
                financial_year_start=date(2026, 4, 1),
                tax_mode="GST_REGULAR",
            ))
            db.add(TenantMembership(
                user_id=self.user_id,
                tenant_id=self.tenant_id,
                role="OWNER",
                is_active=True,
            ))
            db.commit()
        finally:
            db.close()

        token = create_access_token(
            user_id=str(self.user_id), scopes=ROLE_PERMISSIONS.get("owner", [])
        )
        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {token}",
        }
        category = self.client.post(
            "/api/v1/masters/expense-categories",
            json={"name": "Office Supplies", "description": "General office expenses"},
            headers=self.headers,
        )
        self.assertEqual(category.status_code, 201, category.text)
        self.category_id = category.json()["id"]

    def _payload(self, amount=1000.0, gst_rate=18.0, pos="27", vendor="Vendor"):
        payload = {
            "expense_category_id": self.category_id,
            "expense_date": str(date.today()),
            "vendor_name": vendor,
            "description": "Expense test",
            "amount": amount,
            "gst_rate": gst_rate,
        }
        if pos is not None:
            payload["place_of_supply_state_code"] = pos
        return payload

    def _create(self, **kwargs):
        response = self.client.post(
            "/api/v1/expenses", json=self._payload(**kwargs), headers=self.headers
        )
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response

    def test_create_posts_expense_and_balanced_journal(self):
        response = self._create(amount=5000.0, gst_rate=18.0, vendor="Staples India")
        data = response.json()
        self.assertEqual(Decimal(str(data["cgst_amount"])), Decimal("450.00"))
        self.assertEqual(Decimal(str(data["sgst_amount"])), Decimal("450.00"))
        self.assertEqual(Decimal(str(data["total"])), Decimal("5900.00"))
        self.assertIn("EXP-", data["expense_number"])

        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.source_type == "EXPENSE",
                JournalEntry.source_id == uuid.UUID(data["id"]),
            ).one()
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
        finally:
            db.close()

    def test_list_and_get_posted_expenses(self):
        first = self._create(amount=1000.0, vendor="Vendor A")
        self._create(amount=2000.0, vendor="Vendor B")
        listing = self.client.get(
            "/api/v1/expenses?status_filter=POSTED&page=1&limit=10",
            headers=self.headers,
        )
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(len(listing.json()), 2)
        detail = self.client.get(
            f"/api/v1/expenses/{first.json()['id']}", headers=self.headers
        )
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["vendor_name"], "Vendor A")

    def test_edit_creates_replacement_and_reversal(self):
        created = self._create(amount=1000.0, vendor="Original Vendor")
        original_id = uuid.UUID(created.json()["id"])
        updated = self.client.put(
            f"/api/v1/expenses/{original_id}",
            json={"vendor_name": "Updated Vendor", "amount": 2000.0},
            headers=self.headers,
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["status"], "POSTED")
        self.assertEqual(updated.json()["vendor_name"], "Updated Vendor")
        replacement_id = uuid.UUID(updated.json()["id"])
        self.assertNotEqual(original_id, replacement_id)

        db = SessionLocal()
        try:
            original = db.query(Expense).filter(Expense.id == original_id).one()
            replacement = db.query(Expense).filter(Expense.id == replacement_id).one()
            self.assertIsNotNone(original.deleted_at)
            self.assertEqual(original.replaced_by_id, replacement_id)
            self.assertEqual(replacement.replaces_id, original_id)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "EXPENSE_REVERSAL",
                JournalEntry.source_id == original_id,
            ).count(), 1)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "EXPENSE",
                JournalEntry.source_id == replacement_id,
            ).count(), 1)
        finally:
            db.close()

        old_detail = self.client.get(
            f"/api/v1/expenses/{original_id}", headers=self.headers
        )
        self.assertEqual(old_detail.status_code, 404)

    def test_delete_reverses_and_hides_expense(self):
        created = self._create(amount=500.0, gst_rate=0.0)
        expense_id = uuid.UUID(created.json()["id"])
        deleted = self.client.delete(
            f"/api/v1/expenses/{expense_id}", headers=self.headers
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        self.assertEqual(
            self.client.get(f"/api/v1/expenses/{expense_id}", headers=self.headers).status_code,
            404,
        )
        db = SessionLocal()
        try:
            original = db.query(Expense).filter(Expense.id == expense_id).one()
            self.assertIsNotNone(original.deleted_at)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "EXPENSE",
                JournalEntry.source_id == expense_id,
            ).count(), 1)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "EXPENSE_REVERSAL",
                JournalEntry.source_id == expense_id,
            ).count(), 1)
        finally:
            db.close()

    def test_expense_not_found(self):
        response = self.client.get(
            f"/api/v1/expenses/{uuid.uuid4()}", headers=self.headers
        )
        self.assertEqual(response.status_code, 404)

    def test_intra_state_gst(self):
        data = self._create(amount=10000.0, gst_rate=18.0, pos="27").json()
        self.assertEqual(Decimal(str(data["cgst_amount"])), Decimal("900.00"))
        self.assertEqual(Decimal(str(data["sgst_amount"])), Decimal("900.00"))
        self.assertEqual(Decimal(str(data["igst_amount"])), Decimal("0.00"))
        self.assertEqual(Decimal(str(data["total"])), Decimal("11800.00"))

    def test_inter_state_gst_and_edit_recomputes(self):
        data = self._create(amount=10000.0, gst_rate=18.0, pos="29").json()
        self.assertEqual(Decimal(str(data["igst_amount"])), Decimal("1800.00"))
        updated = self.client.put(
            f"/api/v1/expenses/{data['id']}",
            json={"amount": 20000.0, "notes": "Updated after verification"},
            headers=self.headers,
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["place_of_supply_state_code"], "29")
        self.assertEqual(Decimal(str(updated.json()["igst_amount"])), Decimal("3600.00"))
        self.assertEqual(Decimal(str(updated.json()["cgst_amount"])), Decimal("0.00"))
        self.assertEqual(updated.json()["notes"], "Updated after verification")

    def test_zero_gst(self):
        data = self._create(amount=5000.0, gst_rate=0.0, pos=None).json()
        self.assertEqual(Decimal(str(data["cgst_amount"])), Decimal("0.00"))
        self.assertEqual(Decimal(str(data["sgst_amount"])), Decimal("0.00"))
        self.assertEqual(Decimal(str(data["igst_amount"])), Decimal("0.00"))
        self.assertEqual(Decimal(str(data["total"])), Decimal("5000.00"))

    def test_preview_does_not_post(self):
        before = SessionLocal()
        try:
            count_before = before.query(JournalEntry).count()
        finally:
            before.close()
        preview = self.client.post(
            "/api/v1/expenses/preview",
            json={
                "amount": 10000.0,
                "gst_rate": 18.0,
                "place_of_supply_state_code": "27",
            },
            headers=self.headers,
        )
        self.assertEqual(preview.status_code, 200, preview.text)
        self.assertEqual(Decimal(str(preview.json()["total"])), Decimal("11800.00"))
        after = SessionLocal()
        try:
            self.assertEqual(after.query(JournalEntry).count(), count_before)
        finally:
            after.close()


if __name__ == "__main__":
    unittest.main()
