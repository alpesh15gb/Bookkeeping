import os
import sys
import uuid
import unittest
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient
from sqlalchemy.orm import joinedload

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import Base, SessionLocal, engine
from src.infrastructure.database.models import (
    BankingProfile,
    Contact,
    CreditNote,
    DebitNote,
    Invoice,
    JournalEntry,
    JournalLine,
    Product,
    StockLedger,
    Tenant,
    TenantMembership,
)
from src.domains.inventory.services import resolve_default_warehouse_id


class TestInvoicingFlow(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        reg_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma",
            "phone_number": "+919999988888",
            "company_legal_name": "Varma Ventures Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z6",
            "company_pan": "BBBBB2222B",
        }
        self.client.post("/api/v1/auth/register", json=reg_payload)
        login = self.client.post(
            "/api/v1/auth/login",
            json={"email": "owner@company.com", "password": "SecurePassword123!"},
        )
        self.access_token = login.json()["access_token"]

        db = SessionLocal()
        try:
            membership = db.query(TenantMembership).first()
            self.tenant_id = membership.tenant_id
            tenant = db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
            tenant.tax_mode = "GST_REGULAR"
            db.add(BankingProfile(
                tenant_id=self.tenant_id,
                bank_name="HDFC Bank",
                account_number="50001002003004",
                ifsc_code="HDFC0000001",
                account_holder_name="Varma Ventures Pvt Ltd",
                is_primary=True,
                is_active=True,
            ))
            customer = Contact(
                id=uuid.UUID("3fa85f64-5717-4562-b3fc-2c963f66afa6"),
                tenant_id=self.tenant_id,
                name="Tata Consultancy Services Ltd",
                email="finance@tcs.com",
                phone="+912267789999",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={
                    "street": "TCS House, Raveline Street",
                    "city": "Mumbai", "state": "Maharashtra",
                    "state_code": "27", "pincode": "400001",
                    "country": "India",
                },
                state_code="27",
                is_active=True,
            )
            product = Product(
                id=uuid.UUID("4fa85f64-5717-4562-b3fc-2c963f66afd9"),
                tenant_id=self.tenant_id,
                name="MacBook Pro M3 Max",
                sku="APL-MBP-M3MX",
                hsn_sac="84713010",
                product_type="GOODS",
                current_stock=Decimal("1000.00"),
                opening_stock=Decimal("1000.00"),
                uom="PCS",
                sales_price=Decimal("249900.00"),
                purchase_price=Decimal("200000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True,
            )
            db.add_all([customer, product])
            db.flush()
            db.add(StockLedger(
                tenant_id=self.tenant_id,
                product_id=product.id,
                warehouse_id=resolve_default_warehouse_id(db, self.tenant_id),
                quantity=product.opening_stock,
                balance_quantity=product.opening_stock,
                reference_type="OPENING",
                reference_id=product.id,
                rate=product.purchase_price,
            ))
            db.commit()
            self.customer_id = customer.id
            self.product_id = product.id
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.access_token}",
        }

    def _invoice_payload(self, *, quantity=1, rate=10000.0, pos="27"):
        return {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": pos,
            "line_items": [{
                "product_id": str(self.product_id),
                "quantity": quantity,
                "rate": rate,
                "discount": 0,
                "hsn_sac": "84713010",
                "gst_rate": 18,
            }],
        }

    def test_invoice_autonumbering_roundoff_and_immediate_post(self):
        payload = self._invoice_payload(rate=100.55)
        first = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertEqual(first.status_code, 201, first.text)
        data = first.json()
        self.assertTrue(data["invoice_number"].startswith("INV/"))
        self.assertTrue(data["invoice_number"].endswith("/0001"))
        self.assertEqual(float(data["round_off"]), 0.35)
        self.assertEqual(float(data["total"]), 119.00)
        self.assertEqual(data["status"], "POSTED")

        second = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertEqual(second.status_code, 201, second.text)
        self.assertTrue(second.json()["invoice_number"].endswith("/0002"))

    def test_invoice_delete_creates_reversal_and_hides_document(self):
        created = self.client.post(
            "/api/v1/invoices", json=self._invoice_payload(), headers=self.headers
        )
        self.assertEqual(created.status_code, 201, created.text)
        invoice = created.json()
        invoice_id = uuid.UUID(invoice["id"])
        deleted = self.client.delete(
            f"/api/v1/invoices/{invoice_id}", headers=self.headers
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        self.assertEqual(
            self.client.get(f"/api/v1/invoices/{invoice_id}", headers=self.headers).status_code,
            404,
        )
        db = SessionLocal()
        try:
            original = db.query(Invoice).filter(Invoice.id == invoice_id).one()
            self.assertIsNotNone(original.deleted_at)
            posting = db.query(JournalEntry).filter(
                JournalEntry.source_type == "INVOICE",
                JournalEntry.source_id == invoice_id,
            ).one()
            reversal = db.query(JournalEntry).filter(
                JournalEntry.source_type == "INVOICE_REVERSAL",
                JournalEntry.source_id == invoice_id,
            ).one()
            self.assertEqual(posting.reversal_transaction_id, reversal.id)
            self.assertEqual(reversal.reverses_transaction_id, posting.id)
            debits = sum((l.amount for l in reversal.lines if l.direction == "DEBIT"), Decimal("0"))
            credits = sum((l.amount for l in reversal.lines if l.direction == "CREDIT"), Decimal("0"))
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("11800.00"))
        finally:
            db.close()

    def test_invoice_edit_is_reversal_plus_replacement(self):
        created = self.client.post(
            "/api/v1/invoices", json=self._invoice_payload(rate=10000), headers=self.headers
        )
        original_id = uuid.UUID(created.json()["id"])
        edited = self.client.put(
            f"/api/v1/invoices/{original_id}",
            json={"line_items": self._invoice_payload(rate=20000)["line_items"]},
            headers=self.headers,
        )
        self.assertEqual(edited.status_code, 200, edited.text)
        replacement_id = uuid.UUID(edited.json()["id"])
        self.assertNotEqual(original_id, replacement_id)
        self.assertEqual(edited.json()["status"], "POSTED")
        db = SessionLocal()
        try:
            original = db.query(Invoice).filter(Invoice.id == original_id).one()
            replacement = db.query(Invoice).filter(Invoice.id == replacement_id).one()
            self.assertEqual(original.replaced_by_id, replacement_id)
            self.assertEqual(replacement.replaces_id, original_id)
            self.assertIsNotNone(original.deleted_at)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "INVOICE_REVERSAL",
                JournalEntry.source_id == original_id,
            ).count(), 1)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "INVOICE",
                JournalEntry.source_id == replacement_id,
            ).count(), 1)
        finally:
            db.close()

    def test_credit_note_save_posts_to_ledger(self):
        invoice = self.client.post(
            "/api/v1/invoices", json=self._invoice_payload(), headers=self.headers
        ).json()
        response = self.client.post(
            "/api/v1/invoices/credit-notes",
            json={
                "invoice_id": invoice["id"],
                "issue_date": str(date.today()),
                "reason": "Sales return",
                "line_items": [{
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 10000,
                    "hsn_sac": "84713010",
                    "gst_rate": 18,
                }],
            },
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        note = response.json()
        self.assertEqual(note["status"], "POSTED")
        self.assertEqual(float(note["total"]), 11800.0)
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.source_type == "CREDIT_NOTE",
                JournalEntry.source_id == uuid.UUID(note["id"]),
            ).one()
            debit = sum((l.amount for l in entry.lines if l.direction == "DEBIT"), Decimal("0"))
            credit = sum((l.amount for l in entry.lines if l.direction == "CREDIT"), Decimal("0"))
            self.assertEqual(debit, credit)
        finally:
            db.close()

    def test_debit_note_save_posts_to_ledger(self):
        invoice = self.client.post(
            "/api/v1/invoices", json=self._invoice_payload(rate=5000), headers=self.headers
        ).json()
        response = self.client.post(
            "/api/v1/invoices/debit-notes",
            json={
                "invoice_id": invoice["id"],
                "issue_date": str(date.today()),
                "reason": "Price correction",
                "line_items": [{
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 5000,
                    "hsn_sac": "84713010",
                    "gst_rate": 18,
                }],
            },
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        note = response.json()
        self.assertEqual(note["status"], "POSTED")
        self.assertEqual(float(note["total"]), 5900.0)
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.source_type == "DEBIT_NOTE",
                JournalEntry.source_id == uuid.UUID(note["id"]),
            ).one()
            debit = sum((l.amount for l in entry.lines if l.direction == "DEBIT"), Decimal("0"))
            credit = sum((l.amount for l in entry.lines if l.direction == "CREDIT"), Decimal("0"))
            self.assertEqual(debit, credit)
            self.assertEqual(debit, Decimal("5900.00"))
        finally:
            db.close()

    def test_pdf_payload_structure(self):
        invoice = self.client.post(
            "/api/v1/invoices",
            json=self._invoice_payload(quantity=2, rate=150000),
            headers=self.headers,
        ).json()
        response = self.client.get(
            f"/api/v1/invoices/{invoice['id']}/pdf-payload", headers=self.headers
        )
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        for key in ("company", "bank_details", "customer", "invoice", "lines"):
            self.assertIn(key, data)
        self.assertEqual(data["company"]["legal_name"], "Varma Ventures Pvt Ltd")
        self.assertEqual(data["bank_details"]["bank_name"], "HDFC Bank")
        self.assertEqual(data["customer"]["name"], "Tata Consultancy Services Ltd")
        self.assertEqual(data["invoice"]["invoice_number"], invoice["invoice_number"])
        self.assertEqual(data["lines"][0]["product_name"], "MacBook Pro M3 Max")

    def test_preview_save_post_integration(self):
        payload = self._invoice_payload(quantity=2, rate=10000)
        preview = self.client.post(
            "/api/v1/invoices/preview", json=payload, headers=self.headers
        )
        self.assertEqual(preview.status_code, 200, preview.text)
        p = preview.json()
        self.assertEqual(float(p["subtotal"]), 20000.0)
        self.assertEqual(float(p["cgst_amount"]), 1800.0)
        self.assertEqual(float(p["sgst_amount"]), 1800.0)
        self.assertEqual(float(p["total"]), 23600.0)

        saved = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertEqual(saved.status_code, 201, saved.text)
        s = saved.json()
        self.assertEqual(s["status"], "POSTED")
        self.assertEqual(float(s["total"]), float(p["total"]))
        invoice_id = uuid.UUID(s["id"])

        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).options(
                joinedload(JournalEntry.lines).joinedload(JournalLine.account)
            ).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.source_type == "INVOICE",
                JournalEntry.source_id == invoice_id,
            ).one()
            debits = sum((line.amount for line in entry.lines if line.direction == "DEBIT"), Decimal("0"))
            credits = sum((line.amount for line in entry.lines if line.direction == "CREDIT"), Decimal("0"))
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("23600.00"))
            cgst = sum((line.amount for line in entry.lines if line.direction == "CREDIT" and line.narration == "CGST Output"), Decimal("0"))
            sgst = sum((line.amount for line in entry.lines if line.direction == "CREDIT" and line.narration == "SGST Output"), Decimal("0"))
            self.assertEqual(cgst, Decimal("1800.00"))
            self.assertEqual(sgst, Decimal("1800.00"))
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
