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
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product, Invoice, Bill,
    JournalEntry, JournalLine, BankingProfile, Payment, BillPayment
)

class TestPaymentsAndReceiptsFlow(unittest.TestCase):
    def setUp(self):
        # Reset test database tables to ensure clean state
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)

        self.client = TestClient(app)

        # 1. Tenant A Setup
        tenant_a_payload = {
            "email": "owner_a@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma A",
            "phone_number": "+919999988881",
            "company_legal_name": "Tenant A Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A"
        }
        res_a = self.client.post("/api/v1/auth/register", json=tenant_a_payload)
        self.assertEqual(res_a.status_code, 201)
        login_a = self.client.post("/api/v1/auth/login", json={
            "email": "owner_a@company.com",
            "password": "SecurePassword123!"
        }).json()
        self.token_a = login_a["access_token"]

        # 2. Tenant B Setup
        tenant_b_payload = {
            "email": "owner_b@company.com",
            "password": "SecurePassword123!",
            "full_name": "Vijay Varma B",
            "phone_number": "+919999988882",
            "company_legal_name": "Tenant B Pvt Ltd",
            "company_gstin": "27BBBBB2222B2Z2",
            "company_pan": "BBBBB2222B"
        }
        res_b = self.client.post("/api/v1/auth/register", json=tenant_b_payload)
        self.assertEqual(res_b.status_code, 201)
        login_b = self.client.post("/api/v1/auth/login", json={
            "email": "owner_b@company.com",
            "password": "SecurePassword123!"
        }).json()
        self.token_b = login_b["access_token"]

        # Retrieve tenant IDs and seed Master Data
        db = SessionLocal()
        try:
            m_a = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_a@company.com").first().id).first()
            self.tenant_a_id = m_a.tenant_id

            m_b = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_b@company.com").first().id).first()
            self.tenant_b_id = m_b.tenant_id

            # Seed bank details for Tenant A
            bank_a = BankingProfile(
                tenant_id=self.tenant_a_id,
                bank_name="HDFC Bank",
                account_number="50001002003004",
                ifsc_code="HDFC0000001",
                account_holder_name="Tenant A Pvt Ltd",
                is_primary=True,
                is_active=True
            )

            # Seed Customer for Tenant A
            customer_a = Contact(
                id=uuid.UUID("11111111-1111-1111-1111-11111111111a"),
                tenant_id=self.tenant_a_id,
                name="Customer Tenant A",
                email="cust_a@test.com",
                phone="+912267789999",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={"street": "101, Test St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True
            )

            # Seed Vendor for Tenant A
            vendor_a = Contact(
                id=uuid.UUID("22222222-2222-2222-2222-22222222222b"),
                tenant_id=self.tenant_a_id,
                name="Vendor Tenant A",
                email="vendor_a@test.com",
                phone="+918028520261",
                contact_type="VENDOR",
                gstin="29AAACI5678B2Z2",
                pan="AAACI5678B",
                registration_type="REGULAR",
                billing_address={"street": "202, Test St", "city": "Bengaluru", "state": "Karnataka", "state_code": "29", "pincode": "560100", "country": "India"},
                state_code="29",
                is_active=True
            )

            # Seed Product for Tenant A
            product_a = Product(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333c"),
                tenant_id=self.tenant_a_id,
                name="Test Laptop",
                sku="LPT-TST-001",
                hsn_sac="84713010",
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("10000.00"),
                purchase_price=Decimal("8000.00"),
                gst_rate=Decimal("18.00"),
                is_active=True
            )

            db.add_all([bank_a, customer_a, vendor_a, product_a])
            db.commit()

            self.customer_a_id = customer_a.id
            self.vendor_a_id = vendor_a.id
            self.product_a_id = product_a.id
        finally:
            db.close()

        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a_id),
            "Authorization": f"Bearer {self.token_a}"
        }
        self.headers_b = {
            "X-Tenant-ID": str(self.tenant_b_id),
            "Authorization": f"Bearer {self.token_b}"
        }

    def test_payment_receipt_workflow(self):
        # 1. Create two invoices under Tenant A
        inv_payload = {
            "contact_id": str(self.customer_a_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_a_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        inv1 = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        inv2 = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()

        # Finalize both invoices (status becomes SENT, total becomes 11800.00)
        self.client.post(f"/api/v1/invoices/{inv1['id']}/finalize", headers=self.headers_a)
        self.client.post(f"/api/v1/invoices/{inv2['id']}/finalize", headers=self.headers_a)

        # 2. Record Customer Payment Receipt (Payment In) allocating to both invoices
        receipt_payload = {
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 15000.00,
            "reference_number": "TXN-999001",
            "description": "Partial payment for inv1 and inv2",
            "allocations": [
                {"invoice_id": inv1["id"], "amount": 11800.00}, # fully pays inv1
                {"invoice_id": inv2["id"], "amount": 3200.00}    # partially pays inv2
            ]
        }
        res = self.client.post("/api/v1/payments/receipts", json=receipt_payload, headers=self.headers_a)
        self.assertEqual(res.status_code, 201)
        receipt = res.json()

        # Verify receipt parameters
        self.assertTrue(receipt["payment_number"].startswith("REC/2026/"))
        self.assertEqual(receipt["status"], "ACTIVE")
        self.assertEqual(len(receipt["allocations"]), 2)

        # Verify invoice states updated
        res_inv1 = self.client.get(f"/api/v1/invoices/{inv1['id']}", headers=self.headers_a).json()
        res_inv2 = self.client.get(f"/api/v1/invoices/{inv2['id']}", headers=self.headers_a).json()

        self.assertEqual(res_inv1["status"], "PAID")
        self.assertEqual(float(res_inv1["amount_paid"]), 11800.00)
        self.assertEqual(res_inv2["status"], "PARTIALLY_PAID")
        self.assertEqual(float(res_inv2["amount_paid"]), 3200.00)

        # Verify ledger posting
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.source_type == "PAYMENT",
                JournalEntry.source_id == uuid.UUID(receipt["id"])
            ).first()
            self.assertIsNotNone(entry)
            self.assertEqual(entry.reference_number, receipt["payment_number"])
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("15000.00"))

            # Bank Account must be DEBITED, Customer Account CREDITED
            bank_line = next(line for line in entry.lines if line.direction == "DEBIT")
            customer_line = next(line for line in entry.lines if line.direction == "CREDIT")
            
            # Asset account mapping: uuid5(NAMESPACE_DNS, "account.assets.bank")
            asset_acc = uuid.uuid5(uuid.NAMESPACE_DNS, "account.assets.bank")
            cust_acc = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.customer.{self.customer_a_id}-{self.tenant_a_id}")
            self.assertEqual(bank_line.account_id, asset_acc)
            self.assertEqual(customer_line.account_id, cust_acc)
        finally:
            db.close()

        # 3. Test list and details API
        res_list = self.client.get("/api/v1/payments/receipts", headers=self.headers_a)
        self.assertEqual(res_list.status_code, 200)
        self.assertEqual(len(res_list.json()), 1)
        self.assertEqual(res_list.json()[0]["contact_name"], "Customer Tenant A")

        res_det = self.client.get(f"/api/v1/payments/receipts/{receipt['id']}", headers=self.headers_a)
        self.assertEqual(res_det.status_code, 200)
        self.assertEqual(res_det.json()["payment_number"], receipt["payment_number"])

        # 4. Cancel payment receipt and verify reversal
        res_can = self.client.post(f"/api/v1/payments/receipts/{receipt['id']}/cancel", headers=self.headers_a)
        self.assertEqual(res_can.status_code, 200)
        self.assertEqual(res_can.json()["status"], "CANCELLED")

        # Verify invoice amounts/states rolled back
        res_inv1_post = self.client.get(f"/api/v1/invoices/{inv1['id']}", headers=self.headers_a).json()
        res_inv2_post = self.client.get(f"/api/v1/invoices/{inv2['id']}", headers=self.headers_a).json()

        self.assertEqual(res_inv1_post["status"], "POSTED")
        self.assertEqual(float(res_inv1_post["amount_paid"]), 0.0)
        self.assertEqual(res_inv2_post["status"], "POSTED")
        self.assertEqual(float(res_inv2_post["amount_paid"]), 0.0)

        # Verify reversal journal entry created
        db = SessionLocal()
        try:
            rev_entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.reference_number == f"REV-{receipt['payment_number']}"
            ).first()
            self.assertIsNotNone(rev_entry)
            rev_debits = sum(line.amount for line in rev_entry.lines if line.direction == "DEBIT")
            rev_credits = sum(line.amount for line in rev_entry.lines if line.direction == "CREDIT")
            self.assertEqual(rev_debits, rev_credits)
            self.assertEqual(rev_debits, Decimal("15000.00"))

            # Customer Account must be DEBITED, Bank Account CREDITED
            cust_line = next(line for line in rev_entry.lines if line.direction == "DEBIT")
            bank_line = next(line for line in rev_entry.lines if line.direction == "CREDIT")
            
            self.assertEqual(cust_line.account_id, cust_acc)
            self.assertEqual(bank_line.account_id, asset_acc)
        finally:
            db.close()

    def test_vendor_disbursement_workflow(self):
        # 1. Create vendor bill
        bill_payload = {
            "contact_id": str(self.vendor_a_id),
            "bill_number": "BILL-TEST-888",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29", # Karnataka
            "line_items": [
                {
                    "product_id": str(self.product_a_id),
                    "quantity": 1,
                    "rate": 10000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        bill = self.client.post("/api/v1/bills", json=bill_payload, headers=self.headers_a).json()

        # Finalize bill (status becomes UNPAID, total is 11800.00)
        self.client.post(f"/api/v1/bills/{bill['id']}/finalize", headers=self.headers_a)

        # 2. Record vendor payment (Disbursement / Payment Out)
        pay_payload = {
            "contact_id": str(self.vendor_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 11800.00,
            "reference_number": "CHQ-002",
            "description": "Full bill settlement",
            "allocations": [
                {"bill_id": bill["id"], "amount": 11800.00}
            ]
        }
        res = self.client.post("/api/v1/payments/disbursements", json=pay_payload, headers=self.headers_a)
        self.assertEqual(res.status_code, 201)
        disb = res.json()

        self.assertTrue(disb["payment_number"].startswith("PAY/2026/"))
        self.assertEqual(disb["status"], "ACTIVE")

        # Verify bill state updated to PAID
        res_bill = self.client.get(f"/api/v1/bills/{bill['id']}", headers=self.headers_a).json()
        self.assertEqual(res_bill["status"], "PAID")
        self.assertEqual(float(res_bill["amount_paid"]), 11800.00)

        # Verify ledger posting: Vendor DEBIT, Bank CREDIT
        db = SessionLocal()
        try:
            entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.source_type == "PAYMENT",
                JournalEntry.source_id == uuid.UUID(disb["id"])
            ).first()
            self.assertIsNotNone(entry)
            debits = sum(line.amount for line in entry.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
            self.assertEqual(debits, Decimal("11800.00"))

            vendor_acc = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.vendor.{self.vendor_a_id}-{self.tenant_a_id}")
            asset_acc = uuid.uuid5(uuid.NAMESPACE_DNS, "account.assets.bank")

            v_line = next(line for line in entry.lines if line.direction == "DEBIT")
            b_line = next(line for line in entry.lines if line.direction == "CREDIT")
            self.assertEqual(v_line.account_id, vendor_acc)
            self.assertEqual(b_line.account_id, asset_acc)
        finally:
            db.close()

        # 3. Cancel vendor payment and verify reversal
        res_can = self.client.post(f"/api/v1/payments/disbursements/{disb['id']}/cancel", headers=self.headers_a)
        self.assertEqual(res_can.status_code, 200)
        self.assertEqual(res_can.json()["status"], "CANCELLED")

        # Verify bill rolled back
        res_bill_post = self.client.get(f"/api/v1/bills/{bill['id']}", headers=self.headers_a).json()
        self.assertEqual(res_bill_post["status"], "POSTED")
        self.assertEqual(float(res_bill_post["amount_paid"]), 0.0)

        # Verify reversal journal entry created: Bank DEBIT, Vendor CREDIT
        db = SessionLocal()
        try:
            rev_entry = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.reference_number == f"REV-{disb['payment_number']}"
            ).first()
            self.assertIsNotNone(rev_entry)
            
            b_rev_line = next(line for line in rev_entry.lines if line.direction == "DEBIT")
            v_rev_line = next(line for line in rev_entry.lines if line.direction == "CREDIT")
            self.assertEqual(b_rev_line.account_id, asset_acc)
            self.assertEqual(v_rev_line.account_id, vendor_acc)
        finally:
            db.close()

    def test_payment_validation_constraints(self):
        # 1. Create a valid invoice first
        inv_payload = {
            "contact_id": str(self.customer_a_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_a_id),
                    "quantity": 1,
                    "rate": 1000.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 18.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/invoices/{inv['id']}/finalize", headers=self.headers_a)

        # Test creating receipt with allocations exceeding payment amount
        receipt_payload = {
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "CASH",
            "amount": 500.00,
            "allocations": [
                {"invoice_id": inv["id"], "amount": 1000.00}
            ]
        }
        res = self.client.post("/api/v1/payments/receipts", json=receipt_payload, headers=self.headers_a)
        self.assertEqual(res.status_code, 400)


    def test_tenant_boundary_isolation(self):
        # Create an invoice in Tenant A context first
        inv_payload = {
            "contact_id": str(self.customer_a_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [
                {
                    "product_id": str(self.product_a_id),
                    "quantity": 1,
                    "rate": 100.00,
                    "discount": 0.00,
                    "hsn_sac": "84713010",
                    "gst_rate": 0.0
                }
            ]
        }
        inv = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        self.client.post(f"/api/v1/invoices/{inv['id']}/finalize", headers=self.headers_a)

        # 1. Try to record payment under Tenant B using Tenant A's customer
        payload_b = {
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 100.00,
            "allocations": [{"invoice_id": inv["id"], "amount": 100.00}]
        }
        res = self.client.post("/api/v1/payments/receipts", json=payload_b, headers=self.headers_b)
        self.assertEqual(res.status_code, 404) # contact not found in tenant B context

        # 2. Record payment in Tenant A
        payload_a = {
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "CASH",
            "amount": 100.00,
            "allocations": [{"invoice_id": inv["id"], "amount": 100.00}]
        }
        receipt = self.client.post("/api/v1/payments/receipts", json=payload_a, headers=self.headers_a).json()

        # 3. Try to view Tenant A's receipt from Tenant B context
        res_get = self.client.get(f"/api/v1/payments/receipts/{receipt['id']}", headers=self.headers_b)
        self.assertEqual(res_get.status_code, 404)

        # 4. Try to cancel Tenant A's receipt from Tenant B context
        res_can = self.client.post(f"/api/v1/payments/receipts/{receipt['id']}/cancel", headers=self.headers_b)
        self.assertEqual(res_can.status_code, 404)

if __name__ == "__main__":
    unittest.main()
