import sys
import os
import uuid
import unittest
from datetime import date
from decimal import Decimal
from fastapi.testclient import TestClient
from sqlalchemy.orm import joinedload

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import engine, Base, SessionLocal
from src.infrastructure.database.models import User, Tenant, TenantMembership, Contact, Product, JournalEntry, JournalLine, BankingProfile, StockLedger
from src.domains.inventory.services import resolve_default_warehouse_id

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
            tenant = db.query(Tenant).filter(Tenant.id == self.tenant_id).first()
            tenant.tax_mode = "GST_REGULAR"

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
                current_stock=Decimal("1000.00"),
                opening_stock=Decimal("1000.00"),
                uom="PCS",
                sales_price=Decimal("249900.00"),
                purchase_price=Decimal("200000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
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
        self.assertTrue(data["invoice_number"].startswith("INV/"))
        self.assertTrue(data["invoice_number"].endswith("/0001"))
        
        # Verify round-off calculation:
        # raw total: 100.55 + 9.05 (CGST) + 9.05 (SGST) = 118.65
        # rounded total = 119.00
        # round_off = 119.00 - 118.65 = +0.35
        self.assertEqual(float(data["round_off"]), 0.35)
        self.assertEqual(float(data["total"]), 119.00)

        # Create a second invoice and verify numbering series increments
        res2 = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertTrue(res2.json()["invoice_number"].startswith("INV/"))
        self.assertTrue(res2.json()["invoice_number"].endswith("/0002"))

    def test_invoice_cancellation_reversal(self):
        # Create invoice (auto-posted to POSTED by auto_post_invoice)
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

        # Invoice is already POSTED via auto_post, verify
        self.assertEqual(inv["status"], "POSTED")

        # Cancel (status becomes CANCELLED)
        res_can = self.client.post(f"/api/v1/invoices/{inv_id}/cancel", headers=self.headers)
        self.assertEqual(res_can.status_code, 200)
        self.assertEqual(res_can.json()["status"], "CANCELLED")

        # Verify balancing reversal journal entry in ledger
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.reference_number == f"REV-{inv['invoice_number']}"
            ).first()
            self.assertIsNotNone(entry)
            self.assertEqual(entry.source_type, "INVOICE_REVERSAL")
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
        # Create invoice (auto-posted)
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

        # Finalize the credit note to post to ledger
        fin_res = self.client.post(f"/api/v1/invoices/credit-notes/{cn_id}/finalize", headers=self.headers)
        self.assertIn(fin_res.status_code, (200, 409))

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
        # Create invoice (auto-posted)
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

        # Create Debit Note linked to the invoice (stays as DRAFT)
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
        self.assertEqual(dn["status"], "DRAFT")
        dn_id = dn["id"]

        # Finalize the debit note to post to ledger
        fin_res = self.client.post(f"/api/v1/invoices/debit-notes/{dn_id}/finalize", headers=self.headers)
        self.assertIn(fin_res.status_code, (200, 409))

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
        self.assertEqual(data["invoice"]["invoice_number"], inv["invoice_number"])
        self.assertEqual(len(data["lines"]), 1)
        self.assertEqual(data["lines"][0]["product_name"], "MacBook Pro M3 Max")

    def test_invoice_preview_save_finalize_integration(self):
        """
        Integration test: form input → backend preview → save → post → ledger/tax records
        Assert exact values at every stage.
        """
        # 1. Create invoice payload
        payload = {
            "contact_id": str(self.customer_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",  # Same state as company (Maharashtra) -> CGST+SGST
            "line_items": [
                {
                    "product_id": str(self.product_id),
                    "quantity": 2,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }

        # 2. Call preview endpoint
        preview_res = self.client.post("/api/v1/invoices/preview", json=payload, headers=self.headers)
        self.assertEqual(preview_res.status_code, 200)
        preview = preview_res.json()

        # Verify preview totals (authoritative)
        # 2 * 10000 = 20000 subtotal
        # 18% GST = 3600 -> CGST 1800 + SGST 1800
        # Total = 23600
        self.assertEqual(float(preview["subtotal"]), 20000.0)
        self.assertEqual(float(preview["cgst_amount"]), 1800.0)
        self.assertEqual(float(preview["sgst_amount"]), 1800.0)
        self.assertEqual(float(preview["igst_amount"]), 0.0)
        self.assertEqual(float(preview["total"]), 23600.0)

        # 3. Save invoice as draft (POST to /invoices)
        save_res = self.client.post("/api/v1/invoices", json=payload, headers=self.headers)
        self.assertEqual(save_res.status_code, 201)
        saved = save_res.json()
        invoice_id = saved["id"]

        # Verify saved totals match preview exactly
        self.assertEqual(float(saved["subtotal"]), float(preview["subtotal"]))
        self.assertEqual(float(saved["cgst_amount"]), float(preview["cgst_amount"]))
        self.assertEqual(float(saved["sgst_amount"]), float(preview["sgst_amount"]))
        self.assertEqual(float(preview["igst_amount"]), float(saved["igst_amount"]))
        self.assertEqual(float(saved["total"]), float(preview["total"]))

        # 4. Finalize/post the invoice
        finalize_res = self.client.post(f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers)
        self.assertEqual(finalize_res.status_code, 200)
        posted = finalize_res.json()
        self.assertEqual(posted["status"], "POSTED")

        # 5. Verify ledger journal entry matches preview exactly
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).options(
                joinedload(JournalEntry.lines).joinedload(JournalLine.account)
            ).filter(
                JournalEntry.tenant_id == self.tenant_id,
                JournalEntry.source_id == uuid.UUID(invoice_id)
            ).first()
            self.assertIsNotNone(entry)

            # Verify journal entry balances
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("23600.00"))  # Match preview total

            # Verify tax components in ledger
            cgst_credit = sum(line.amount for line in entry.lines
                             if line.direction == "CREDIT" and line.narration == "CGST Output")
            sgst_credit = sum(line.amount for line in entry.lines
                             if line.direction == "CREDIT" and line.narration == "SGST Output")

            self.assertEqual(cgst_credit, Decimal("1800.00"))
            self.assertEqual(sgst_credit, Decimal("1800.00"))

            # 6. Verify tax records match preview
            # Check that tax liability was recorded correctly
            # TaxLiability model doesn't exist; verified via ledger entries instead
            # from src.infrastructure.database.models import TaxLiability
            # tax_liability = db.query(TaxLiability).filter(
            #     TaxLiability.tenant_id == self.tenant_id,
            #     TaxLiability.reference_id == uuid.UUID(invoice_id)
            # ).first()
            # self.assertIsNotNone(tax_liability)
            # self.assertEqual(tax_liability.cgst_amount, Decimal("1800.00"))
            # self.assertEqual(tax_liability.sgst_amount, Decimal("1800.00"))
            # self.assertEqual(tax_liability.igst_amount, Decimal("0.00"))

        finally:
            db.close()

if __name__ == "__main__":
    unittest.main()
