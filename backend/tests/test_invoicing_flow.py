import sys
import os
import uuid
import unittest
from datetime import date
from decimal import Decimal
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import User, Tenant, TenantMembership, Contact, Product, JournalEntry, JournalLine, BankingProfile

class TestInvoicingFlow(unittest.TestCase):
    def setUp(self):
        # 1. Reset test database tables
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # 2. Register/Login Owner
        reg_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma",
            "phone_number": "+919999988888",
            "company_legal_name": "Varma Ventures Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z6",
            "company_pan": "BBBBB2222B"
        }
        self.client.post("/api/v1/auth/register", json=reg_payload)
        login_payload = {
            "email": "owner@company.com",
            "password": "SecurePassword123!"
        }
        res_login = self.client.post("/api/v1/auth/login", json=login_payload)
        token_data = res_login.json()
        self.access_token = token_data["access_token"]

        # Fetch the generated tenant ID
        db = SessionLocal()
        try:
            membership = db.query(TenantMembership).first()
            self.tenant_id = membership.tenant_id

            # Seed bank details
            bank = BankingProfile(
                tenant_id=self.tenant_id,
                bank_name="HDFC Bank",
                account_number="50001002003004",
                ifsc_code="HDFC0000001",
                account_holder_name="Varma Ventures Pvt Ltd",
                is_primary=True,
                is_active=True
            )
            db.add(bank)

            # Seed customer
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
                billing_address={"street": "TCS House, Raveline Street", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True
            )
            
            # Seed product
            product = Product(
                id=uuid.UUID("4fa85f64-5717-4562-b3fc-2c963f66afd9"),
                tenant_id=self.tenant_id,
                name="MacBook Pro M3 Max",
                sku="APL-MBP-M3MX",
                hsn_sac="84713010",
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("249900.00"),
                purchase_price=Decimal("200000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )
            db.add_all([customer, product])
            db.commit()

            self.customer_id = customer.id
            self.product_id = product.id
        finally:
            db.close()

        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {self.access_token}"
        }

    def test_invoice_autonumbering_and_roundoff(self):
        # Create an invoice, omitting invoice_number to trigger active numbering series
        payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27", # Maharashtra (CGST+SGST)
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 100.55, # subtotal = 100.55, CGST = 9.0495 (9.05), SGST = 9.0495 (9.05) -> raw total = 118.65
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        res = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 201)
        data = res.json()
        
        # Verify sequence number matches first number in default series
        self.assertEqual(data["invoice_number"], "INV/2026/0001")
        
        # Verify round-off calculation:
        # raw total: 100.55 + 9.05 (CGST) + 9.05 (SGST) = 118.65
        # rounded total = 119.00
        # round_off = 119.00 - 118.65 = +0.35
        self.assertEqual(float(data["round_off"]), 0.35)
        self.assertEqual(float(data["total"]), 119.00)

        # Create a second invoice and verify numbering series increments
        res2 = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertEqual(res2.json()["invoice_number"], "INV/2026/0002")

    def test_invoice_cancellation_reversal(self):
        # Create and finalize invoice
        payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=payload, headers=self.headers).json()
        inv_id = inv["id"]

        # Finalize (status becomes SENT)
        res_fin = self.client.post(f"/api/v1/invoices/{inv_id}/finalize", headers=self.headers)
        self.assertEqual(res_fin.status_code, 200)

        # Cancel (status becomes CANCELLED)
        res_can = self.client.post(f"/api/v1/invoices/{inv_id}/cancel", headers=self.headers)
        self.assertEqual(res_can.status_code, 200)
        self.assertEqual(res_can.json()["status"], "CANCELLED")

        # Verify balancing reversal journal entry in ledger
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.reference_number == f"REV-INV/2026/0001"
            ).first()
            self.assertIsNotNone(entry)
            self.assertEqual(entry.source_type, "INVOICE")
            self.assertEqual(entry.source_id, uuid.UUID(inv_id))

            # Reversal entries sum of debits must equal sum of credits
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("11800.00")) # 10000 + 18% GST

            # Accounts Receivable (Customer Account) must be CREDITED to clear the receivable
            customer_line = next(line for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(customer_line.amount, Decimal("11800.00"))
        finally:
            db.close()

    def test_credit_note_workflow(self):
        # Create and finalize an invoice first
        inv_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers).json()
        self.client.post(f"/api/v1/invoices/{inv['id']}/finalize", headers=self.headers)

        # Create draft Credit Note linked to the invoice
        cn_payload = {
            "invoice_id": inv["id"],
            "issue_date": str(date.today()),
            "reason": "Sales returns - defective product",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        res_post = self.client.post("/api/v1/invoices/credit-notes", json=cn_payload, headers=self.headers)
        self.assertEqual(res_post.status_code, 201)
        cn = res_post.json()
        self.assertEqual(cn["status"], "DRAFT")
        self.assertEqual(float(cn["total"]), 11800.00) # 10000 + 18% GST
        cn_id = cn["id"]

        # Finalize Credit Note
        res_fin = self.client.post(f"/api/v1/invoices/credit-notes/{cn_id}/finalize", headers=self.headers)
        self.assertEqual(res_fin.status_code, 200)
        self.assertEqual(res_fin.json()["status"], "POSTED")

        # Verify ledger journal entry posted
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.source_id == uuid.UUID(cn_id)
            ).first()
            self.assertIsNotNone(entry)
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("11800.00"))

            # Customer Account must be CREDITED
            customer_line = next(line for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(customer_line.amount, Decimal("11800.00"))
        finally:
            db.close()

    def test_debit_note_workflow(self):
        # Create and finalize an invoice first
        inv_payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 5000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers).json()
        self.client.post(f"/api/v1/invoices/{inv['id']}/finalize", headers=self.headers)

        # Create draft Debit Note linked to the invoice
        dn_payload = {
            "invoice_id": inv["id"],
            "issue_date": str(date.today()),
            "reason": "Price correction - undercharged",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 1,
                    "rate": 5000.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        res_post = self.client.post("/api/v1/invoices/debit-notes", json=dn_payload, headers=self.headers)
        self.assertEqual(res_post.status_code, 201)
        dn = res_post.json()
        dn_id = dn["id"]

        # Finalize Debit Note
        res_fin = self.client.post(f"/api/v1/invoices/debit-notes/{dn_id}/finalize", headers=self.headers)
        self.assertEqual(res_fin.status_code, 200)
        self.assertEqual(res_fin.json()["status"], "POSTED")

        # Verify ledger journal entry posted
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.source_id == uuid.UUID(dn_id)
            ).first()
            self.assertIsNotNone(entry)
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("5900.00")) # 5000 + 18% GST

            # Customer Account must be DEBITED (increase receivable)
            customer_line = next(line for line in entry.lines if line.direction == "DEBIT")
            self.assertEqual(customer_line.amount, Decimal("5900.00"))
        finally:
            db.close()

    def test_pdf_payload_structure(self):
        # Create an invoice
        payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 2,
                    "rate": 150000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=payload, headers=self.headers).json()
        inv_id = inv["id"]

        # Get PDF payload
        res = self.client.get(f"/api/v1/invoices/{inv_id}/pdf-payload", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()

        # Validate structure keys
        self.assertIn("company", data)
        self.assertIn("bank_details", data)
        self.assertIn("customer", data)
        self.assertIn("invoice", data)
        self.assertIn("lines", data)

        # Assert data fields populated
        self.assertEqual(data["company"]["legal_name"], "Varma Ventures Pvt Ltd")
        self.assertEqual(data["bank_details"]["bank_name"], "HDFC Bank")
        self.assertEqual(data["customer"]["name"], "Tata Consultancy Services Ltd")
        self.assertEqual(data["invoice"]["invoice_number"], "INV/2026/0001")
        self.assertEqual(len(data["lines"]), 1)
        self.assertEqual(data["lines"][0]["product_name"], "MacBook Pro M3 Max")

if __name__ == "__main__":
    unittest.main()
