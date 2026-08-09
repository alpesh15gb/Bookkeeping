import os
import sys
import uuid
import unittest
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import Base, SessionLocal, engine
from src.core.security import ROLE_PERMISSIONS, create_access_token, get_password_hash
from src.infrastructure.database.models import (
    Contact,
    CreditNote,
    DebitNote,
    JournalEntry,
    Product,
    StockLedger,
    Tenant,
    TenantMembership,
    User,
)


class TestCreditDebitNotes(unittest.TestCase):
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
                email="notes_owner@company.com",
                password_hash=get_password_hash("SecurePassword123!"),
                full_name="Notes Test Owner",
                phone_number="+919876543210",
                is_active=True,
                email_verified=True,
            ))
            db.add(Tenant(
                id=self.tenant_id,
                legal_name="Notes Corp Pvt Ltd",
                trade_name="Notes Corp",
                gstin="27AAPFU0939F1ZV",
                tax_mode="GST_REGULAR",
                pan="AAPFU0939F",
                financial_year_start=date(2026, 4, 1),
            ))
            db.add(TenantMembership(
                user_id=self.user_id,
                tenant_id=self.tenant_id,
                role="OWNER",
                is_active=True,
            ))
            contact = Contact(
                id=uuid.uuid4(),
                tenant_id=self.tenant_id,
                name="Test Customer Ltd",
                email="customer@test.com",
                phone="+919876543210",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={
                    "street": "123 Test St", "city": "Mumbai",
                    "state": "Maharashtra", "state_code": "27",
                    "pincode": "400001", "country": "India",
                },
                state_code="27",
                is_active=True,
            )
            product = Product(
                id=uuid.uuid4(),
                tenant_id=self.tenant_id,
                name="Widget Pro",
                sku="WGT-001",
                hsn_sac="84713010",
                product_type="GOODS",
                current_stock=Decimal("1000.00"),
                opening_stock=Decimal("1000.00"),
                uom="PCS",
                sales_price=Decimal("10000.00"),
                purchase_price=Decimal("8000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True,
            )
            db.add_all([contact, product])
            db.commit()
            self.contact_id = contact.id
            self.product_id = product.id
        finally:
            db.close()

        token = create_access_token(
            user_id=str(self.user_id), scopes=ROLE_PERMISSIONS.get("owner", [])
        )
        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {token}",
        }

    def _create_invoice(self, quantity=2, rate=10000.0):
        response = self.client.post(
            "/api/v1/invoices",
            json={
                "contact_id": str(self.contact_id),
                "invoice_number": f"INV-NOTE-{uuid.uuid4().hex[:6].upper()}",
                "issue_date": str(date.today()),
                "due_date": str(date.today()),
                "pos_state_code": "27",
                "line_items": [{
                    "product_id": str(self.product_id),
                    "quantity": quantity,
                    "rate": rate,
                    "discount": 0,
                    "hsn_sac": "84713010",
                    "gst_rate": 18,
                }],
            },
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()

    def _credit_payload(self, invoice_id, *, rate=10000.0, restock=False, reason="Goods returned"):
        return {
            "invoice_id": invoice_id,
            "issue_date": str(date.today()),
            "reason": reason,
            "restock_items": restock,
            "line_items": [{
                "product_id": str(self.product_id),
                "quantity": 1,
                "rate": rate,
                "discount": 0,
                "hsn_sac": "84713010",
                "gst_rate": 18,
            }],
        }

    def _debit_payload(self, invoice_id, *, rate=5000.0, reason="Price correction"):
        return {
            "invoice_id": invoice_id,
            "issue_date": str(date.today()),
            "reason": reason,
            "line_items": [{
                "product_id": str(self.product_id),
                "quantity": 1,
                "rate": rate,
                "discount": 0,
                "hsn_sac": "84713010",
                "gst_rate": 18,
            }],
        }

    def _assert_balanced(self, entry):
        debit = sum((line.amount for line in entry.lines if line.direction == "DEBIT"), Decimal("0"))
        credit = sum((line.amount for line in entry.lines if line.direction == "CREDIT"), Decimal("0"))
        self.assertEqual(debit, credit)

    def test_credit_note_save_posts_immediately_and_auto_numbers(self):
        invoice = self._create_invoice()
        response = self.client.post(
            "/api/v1/invoices/credit-notes",
            json=self._credit_payload(invoice["id"]),
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        data = response.json()
        self.assertEqual(data["status"], "POSTED")
        self.assertIn("CN/", data["credit_note_number"])
        self.assertEqual(Decimal(str(data["cgst_amount"])), Decimal("900.00"))
        self.assertEqual(Decimal(str(data["sgst_amount"])), Decimal("900.00"))
        self.assertEqual(Decimal(str(data["total"])), Decimal("11800.00"))
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.source_type == "CREDIT_NOTE",
                JournalEntry.source_id == uuid.UUID(data["id"]),
            ).one()
            self._assert_balanced(entry)
        finally:
            db.close()

    def test_credit_note_edit_reverses_and_replaces(self):
        invoice = self._create_invoice()
        created = self.client.post(
            "/api/v1/invoices/credit-notes",
            json=self._credit_payload(invoice["id"], rate=10000),
            headers=self.headers,
        )
        self.assertEqual(created.status_code, 201, created.text)
        original_id = uuid.UUID(created.json()["id"])
        edited = self.client.put(
            f"/api/v1/invoices/credit-notes/{original_id}",
            json=self._credit_payload(invoice["id"], rate=5000, reason="Corrected return"),
            headers=self.headers,
        )
        self.assertEqual(edited.status_code, 200, edited.text)
        replacement_id = uuid.UUID(edited.json()["id"])
        self.assertNotEqual(original_id, replacement_id)
        self.assertEqual(edited.json()["status"], "POSTED")
        db = SessionLocal()
        try:
            original = db.query(CreditNote).filter(CreditNote.id == original_id).one()
            replacement = db.query(CreditNote).filter(CreditNote.id == replacement_id).one()
            self.assertIsNotNone(original.deleted_at)
            self.assertEqual(original.replaced_by_id, replacement_id)
            self.assertEqual(replacement.replaces_id, original_id)
            original_je = db.query(JournalEntry).filter(
                JournalEntry.source_type == "CREDIT_NOTE",
                JournalEntry.source_id == original_id,
            ).one()
            reversal = db.query(JournalEntry).filter(
                JournalEntry.source_type == "CREDIT_NOTE_REVERSAL",
                JournalEntry.source_id == original_id,
            ).one()
            replacement_je = db.query(JournalEntry).filter(
                JournalEntry.source_type == "CREDIT_NOTE",
                JournalEntry.source_id == replacement_id,
            ).one()
            self.assertEqual(original_je.reversal_transaction_id, reversal.id)
            self.assertEqual(reversal.reverses_transaction_id, original_je.id)
            self._assert_balanced(reversal)
            self._assert_balanced(replacement_je)
        finally:
            db.close()
        self.assertEqual(
            self.client.get(f"/api/v1/invoices/credit-notes/{original_id}", headers=self.headers).status_code,
            404,
        )

    def test_credit_note_delete_reverses_stock_and_keeps_history(self):
        invoice = self._create_invoice(quantity=2)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_id).current_stock, Decimal("998.00"))
        finally:
            db.close()
        created = self.client.post(
            "/api/v1/invoices/credit-notes",
            json=self._credit_payload(invoice["id"], restock=True),
            headers=self.headers,
        )
        self.assertEqual(created.status_code, 201, created.text)
        note_id = uuid.UUID(created.json()["id"])
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_id).current_stock, Decimal("999.00"))
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "CREDIT_NOTE",
                StockLedger.reference_id == note_id,
            ).count(), 1)
        finally:
            db.close()
        deleted = self.client.delete(
            f"/api/v1/invoices/credit-notes/{note_id}", headers=self.headers
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        db = SessionLocal()
        try:
            note = db.query(CreditNote).filter(CreditNote.id == note_id).one()
            self.assertIsNotNone(note.deleted_at)
            self.assertEqual(db.get(Product, self.product_id).current_stock, Decimal("998.00"))
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "CREDIT_NOTE_REVERSAL",
                JournalEntry.source_id == note_id,
            ).count(), 1)
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "CREDIT_NOTE_REVERSAL",
                StockLedger.reference_id == note_id,
            ).count(), 1)
        finally:
            db.close()

    def test_credit_note_list_and_get(self):
        invoice = self._create_invoice()
        created = self.client.post(
            "/api/v1/invoices/credit-notes",
            json=self._credit_payload(invoice["id"]),
            headers=self.headers,
        )
        note_id = created.json()["id"]
        listing = self.client.get("/api/v1/invoices/credit-notes", headers=self.headers)
        self.assertEqual(listing.status_code, 200)
        self.assertGreaterEqual(len(listing.json()), 1)
        detail = self.client.get(
            f"/api/v1/invoices/credit-notes/{note_id}", headers=self.headers
        )
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["reason"], "Goods returned")

    def test_debit_note_save_posts_immediately(self):
        invoice = self._create_invoice()
        response = self.client.post(
            "/api/v1/invoices/debit-notes",
            json=self._debit_payload(invoice["id"]),
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        data = response.json()
        self.assertEqual(data["status"], "POSTED")
        self.assertEqual(Decimal(str(data["total"])), Decimal("5900.00"))
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.source_type == "DEBIT_NOTE",
                JournalEntry.source_id == uuid.UUID(data["id"]),
            ).one()
            self._assert_balanced(entry)
            customer_line = next(line for line in entry.lines if line.direction == "DEBIT")
            self.assertEqual(customer_line.amount, Decimal("5900.00"))
        finally:
            db.close()

    def test_debit_note_edit_and_delete_preserve_reversal_chain(self):
        invoice = self._create_invoice()
        created = self.client.post(
            "/api/v1/invoices/debit-notes",
            json=self._debit_payload(invoice["id"], rate=5000),
            headers=self.headers,
        )
        original_id = uuid.UUID(created.json()["id"])
        edited = self.client.put(
            f"/api/v1/invoices/debit-notes/{original_id}",
            json=self._debit_payload(invoice["id"], rate=2500, reason="Corrected debit"),
            headers=self.headers,
        )
        self.assertEqual(edited.status_code, 200, edited.text)
        replacement_id = uuid.UUID(edited.json()["id"])
        self.assertNotEqual(original_id, replacement_id)
        deleted = self.client.delete(
            f"/api/v1/invoices/debit-notes/{replacement_id}", headers=self.headers
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        db = SessionLocal()
        try:
            original = db.query(DebitNote).filter(DebitNote.id == original_id).one()
            replacement = db.query(DebitNote).filter(DebitNote.id == replacement_id).one()
            self.assertEqual(original.replaced_by_id, replacement_id)
            self.assertEqual(replacement.replaces_id, original_id)
            self.assertIsNotNone(original.deleted_at)
            self.assertIsNotNone(replacement.deleted_at)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "DEBIT_NOTE_REVERSAL",
                JournalEntry.source_id == original_id,
            ).count(), 1)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "DEBIT_NOTE_REVERSAL",
                JournalEntry.source_id == replacement_id,
            ).count(), 1)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
