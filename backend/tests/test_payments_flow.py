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
from src.domains.inventory.services import resolve_default_warehouse_id
from src.infrastructure.database.models import (
    User, Tenant, TenantMembership, Contact, Product, Invoice, Bill,
    JournalEntry, JournalLine, BankingProfile, Payment, BillPayment, GSTReturn,
    StockLedger, AuditLog,
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
            tenant_a = db.query(Tenant).filter(Tenant.id == self.tenant_a_id).first()
            tenant_a.tax_mode = "GST_REGULAR"

            m_b = db.query(TenantMembership).filter(TenantMembership.user_id == db.query(User).filter(User.email == "owner_b@company.com").first().id).first()
            self.tenant_b_id = m_b.tenant_id
            tenant_b = db.query(Tenant).filter(Tenant.id == self.tenant_b_id).first()
            tenant_b.tax_mode = "GST_REGULAR"

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
                is_active=True,
                current_stock=Decimal("100.00")
            )

            db.add_all([bank_a, customer_a, vendor_a, product_a])
            db.flush()
            default_warehouse_id = resolve_default_warehouse_id(db, self.tenant_a_id)
            db.add(StockLedger(
                tenant_id=self.tenant_a_id,
                product_id=product_a.id,
                warehouse_id=default_warehouse_id,
                quantity=Decimal("100.00"),
                balance_quantity=Decimal("100.00"),
                reference_type="OPENING",
                reference_id=product_a.id,
                rate=product_a.purchase_price,
            ))
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
        self.assertTrue(receipt["payment_number"].startswith("REC/"))
        self.assertTrue(receipt["payment_number"].endswith("/0001"))
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
            
            # Asset account mapping: uuid5(NAMESPACE_DNS, "account.assets.bank-{tenant_id}")
            asset_acc = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.assets.bank-{self.tenant_a_id}")
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

        self.assertTrue(disb["payment_number"].startswith("PAY/"))
        self.assertTrue(disb["payment_number"].endswith("/0001"))
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
            asset_acc = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.assets.bank-{self.tenant_a_id}")

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

    def test_customer_advance_and_cancellation_restore_credit(self):
        payload = {
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "NEFT_RTGS",
            "amount": 2500.00,
            "reference_number": "UTR-ADV-001",
            "advance_supply_type": "GOODS",
            "allocations": [],
        }
        created = self.client.post(
            "/api/v1/payments/receipts", json=payload, headers=self.headers_a
        )
        self.assertEqual(created.status_code, 201, created.text)

        db = SessionLocal()
        try:
            customer = db.query(Contact).filter(Contact.id == self.customer_a_id).first()
            self.assertEqual(customer.credit_balance, Decimal("2500.0000"))
        finally:
            db.close()

        cancelled = self.client.post(
            f"/api/v1/payments/receipts/{created.json()['id']}/cancel",
            json={"reason": "Customer requested refund"},
            headers=self.headers_a,
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        self.assertEqual(cancelled.json()["cancellation_reason"], "Customer requested refund")

        db = SessionLocal()
        try:
            customer = db.query(Contact).filter(Contact.id == self.customer_a_id).first()
            self.assertEqual(customer.credit_balance, Decimal("0.0000"))
        finally:
            db.close()

    def test_quotation_to_receipt_traceable_workflow(self):
        quotation_payload = {
            "contact_id": str(self.customer_a_id),
            "proforma_number": "QT-E2E-001",
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": str(self.product_a_id), "description": "Workflow item",
                "quantity": 1, "rate": 1000, "discount": 100,
                "hsn_sac": "84713010", "gst_rate": 18,
            }],
        }
        quotation = self.client.post(
            "/api/v1/proforma-invoices", json=quotation_payload, headers=self.headers_a
        )
        self.assertEqual(quotation.status_code, 201, quotation.text)
        qid = quotation.json()["id"]
        self.assertEqual(self.client.post(
            f"/api/v1/proforma-invoices/{qid}/issue", headers=self.headers_a
        ).status_code, 200)

        order = self.client.post(
            f"/api/v1/proforma-invoices/{qid}/convert-to-sales-order",
            headers=self.headers_a,
        )
        self.assertEqual(order.status_code, 200, order.text)
        self.assertEqual(order.json()["source_proforma_id"], qid)
        order_id = order.json()["id"]
        self.assertEqual(self.client.post(
            f"/api/v1/sales-orders/{order_id}/confirm", headers=self.headers_a
        ).status_code, 200)

        challan = self.client.post(
            f"/api/v1/sales-orders/{order_id}/create-delivery-challan",
            headers=self.headers_a,
        )
        self.assertEqual(challan.status_code, 200, challan.text)
        challan_id = challan.json()["id"]
        self.assertEqual(self.client.post(
            f"/api/v1/delivery-challans/{challan_id}/issue", headers=self.headers_a
        ).status_code, 200)
        db = SessionLocal()
        try:
            self.assertEqual(
                db.query(Product).filter(Product.id == self.product_a_id).one().current_stock,
                Decimal("99.00"),
            )
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "DELIVERY_CHALLAN",
                StockLedger.reference_id == uuid.UUID(challan_id),
            ).count(), 1)
        finally:
            db.close()

        invoice = self.client.post(
            f"/api/v1/delivery-challans/{challan_id}/convert-to-invoice",
            headers=self.headers_a,
        )
        self.assertEqual(invoice.status_code, 200, invoice.text)
        invoice_id = invoice.json()["id"]
        # Conversion is idempotent and must never duplicate a financial document.
        duplicate = self.client.post(
            f"/api/v1/delivery-challans/{challan_id}/convert-to-invoice",
            headers=self.headers_a,
        )
        self.assertEqual(duplicate.json()["id"], invoice_id)

        self.assertEqual(self.client.post(
            f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a
        ).status_code, 200)
        db = SessionLocal()
        try:
            self.assertEqual(
                db.query(Product).filter(Product.id == self.product_a_id).one().current_stock,
                Decimal("99.00"),
                "A delivery-based invoice must not deduct stock a second time",
            )
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "INVOICE",
                StockLedger.reference_id == uuid.UUID(invoice_id),
            ).count(), 0)
        finally:
            db.close()
        receipt = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "UPI", "amount": 1062,
            "allocations": [{"invoice_id": invoice_id, "amount": 1062}],
        }, headers=self.headers_a)
        self.assertEqual(receipt.status_code, 201, receipt.text)
        self.assertEqual(self.client.get(
            f"/api/v1/invoices/{invoice_id}", headers=self.headers_a
        ).json()["status"], "PAID")

        # Database + ledger: every financial document must have a balanced,
        # traceable journal entry after the complete commercial workflow.
        db = SessionLocal()
        try:
            entries = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.source_id.in_([
                    uuid.UUID(invoice_id),
                    uuid.UUID(receipt.json()["id"]),
                ]),
            ).all()
            self.assertEqual(len(entries), 2)
            for entry in entries:
                lines = db.query(JournalLine).filter(
                    JournalLine.entry_id == entry.id
                ).all()
                debits = sum(
                    (line.amount for line in lines if line.direction == "DEBIT"),
                    Decimal("0"),
                )
                credits = sum(
                    (line.amount for line in lines if line.direction == "CREDIT"),
                    Decimal("0"),
                )
                self.assertEqual(debits, credits)

            audit_actions = {
                row.action
                for row in db.query(AuditLog).filter(
                    AuditLog.tenant_id == self.tenant_a_id,
                    AuditLog.entity_id.in_([
                        uuid.UUID(invoice_id),
                        uuid.UUID(receipt.json()["id"]),
                    ]),
                ).all()
            }
            self.assertIn("invoice.created", audit_actions)
            self.assertIn("invoice.finalized", audit_actions)
            self.assertIn("payment.created", audit_actions)
        finally:
            db.close()

        # Reports: the customer is settled, financial statements balance, and
        # GST still reflects the invoice (receiving payment never changes GST).
        outstanding = self.client.get(
            "/api/v1/reports/outstanding/receivables",
            params={"as_of_date": str(date.today())},
            headers=self.headers_a,
        )
        self.assertEqual(outstanding.status_code, 200, outstanding.text)
        self.assertEqual(Decimal(str(outstanding.json()["total_outstanding"])), Decimal("0"))

        aging = self.client.get(
            "/api/v1/reports/aging/receivables",
            params={"as_of_date": str(date.today())},
            headers=self.headers_a,
        )
        self.assertEqual(aging.status_code, 200, aging.text)
        self.assertEqual(Decimal(str(aging.json()["total_outstanding"])), Decimal("0"))

        statement = self.client.get(
            "/api/v1/reports/party-statement",
            params={
                "contact_id": str(self.customer_a_id),
                "start_date": str(date.today()),
                "end_date": str(date.today()),
            },
            headers=self.headers_a,
        )
        self.assertEqual(statement.status_code, 200, statement.text)
        self.assertEqual(
            Decimal(str(statement.json()["summary"]["closing_outstanding"])),
            Decimal("0"),
        )

        trial_balance = self.client.get(
            "/api/v1/reports/trial-balance",
            params={"as_of_date": str(date.today())},
            headers=self.headers_a,
        )
        self.assertEqual(trial_balance.status_code, 200, trial_balance.text)
        self.assertTrue(trial_balance.json()["is_balanced"])
        self.assertEqual(
            Decimal(str(trial_balance.json()["total_debits"])),
            Decimal(str(trial_balance.json()["total_credits"])),
        )

        balance_sheet = self.client.get(
            "/api/v1/reports/balance-sheet",
            params={"as_of_date": str(date.today())},
            headers=self.headers_a,
        )
        self.assertEqual(balance_sheet.status_code, 200, balance_sheet.text)
        self.assertTrue(balance_sheet.json()["is_balanced"])

        gstr1 = self.client.get(
            "/api/v1/reports/gst/gstr1",
            params={"start_date": str(date.today()), "end_date": str(date.today())},
            headers=self.headers_a,
        )
        self.assertEqual(gstr1.status_code, 200, gstr1.text)
        self.assertEqual(Decimal(str(gstr1.json()["total_taxable_value"])), Decimal("900"))
        self.assertEqual(Decimal(str(gstr1.json()["total_cgst"])), Decimal("81"))
        self.assertEqual(Decimal(str(gstr1.json()["total_sgst"])), Decimal("81"))
        self.assertEqual(Decimal(str(gstr1.json()["total_invoice_value"])), Decimal("1062"))

        # Document output must be generated from the same persisted invoice.
        pdf_payload = self.client.get(
            f"/api/v1/invoices/{invoice_id}/pdf-payload", headers=self.headers_a
        )
        self.assertEqual(pdf_payload.status_code, 200, pdf_payload.text)
        self.assertEqual(pdf_payload.json()["invoice"]["id"], invoice_id)

        pdf = self.client.get(
            f"/api/v1/invoices/{invoice_id}/print", headers=self.headers_a
        )
        self.assertEqual(pdf.status_code, 200, pdf.text)
        self.assertEqual(pdf.headers["content-type"], "application/pdf")
        self.assertTrue(pdf.content.startswith(b"%PDF"))

    def test_direct_invoice_stock_moves_once_and_cancellation_restores_once(self):
        payload = {
            "contact_id": str(self.customer_a_id),
            "issue_date": str(date.today()), "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": str(self.product_a_id), "quantity": 3,
                "rate": 100, "discount": 0, "hsn_sac": "84713010", "gst_rate": 0,
            }],
        }
        created = self.client.post("/api/v1/invoices", json=payload, headers=self.headers_a)
        self.assertEqual(created.status_code, 201, created.text)
        invoice_id = created.json()["id"]
        self.assertEqual(self.client.post(
            f"/api/v1/invoices/{invoice_id}/finalize", headers=self.headers_a
        ).status_code, 200)
        db = SessionLocal()
        try:
            self.assertEqual(db.query(Product).filter(Product.id == self.product_a_id).one().current_stock, Decimal("97.00"))
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "INVOICE",
                StockLedger.reference_id == uuid.UUID(invoice_id),
            ).count(), 1)
        finally:
            db.close()
        cancelled = self.client.post(f"/api/v1/invoices/{invoice_id}/cancel", headers=self.headers_a)
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.query(Product).filter(Product.id == self.product_a_id).one().current_stock, Decimal("100.00"))
        finally:
            db.close()

    def test_partial_receipt_does_not_change_gstr1_and_filed_period_blocks_cancel(self):
        invoice = self.client.post("/api/v1/invoices", json={
            "contact_id": str(self.customer_a_id), "issue_date": str(date.today()),
            "due_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{"product_id": str(self.product_a_id), "quantity": 1,
                "rate": 1000, "discount": 0, "hsn_sac": "84713010", "gst_rate": 18}],
        }, headers=self.headers_a)
        self.assertEqual(invoice.status_code, 201, invoice.text)
        invoice_id = invoice.json()["id"]
        before = self.client.get("/api/v1/gst/gstr1", headers=self.headers_a).json()
        receipt = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "BANK", "amount": 500,
            "allocations": [{"invoice_id": invoice_id, "amount": 500}],
        }, headers=self.headers_a)
        self.assertEqual(receipt.status_code, 201, receipt.text)
        after = self.client.get("/api/v1/gst/gstr1", headers=self.headers_a).json()
        for section in ("b2b", "b2cl", "b2cs", "cdnr", "cdnur", "hsn_summary"):
            self.assertEqual(after.get(section), before.get(section), section)

        db = SessionLocal()
        try:
            db.add(GSTReturn(
                tenant_id=self.tenant_a_id, return_type="GSTR1",
                period_start=date.today().replace(day=1), period_end=date.today(),
                status="FILED",
            ))
            db.commit()
        finally:
            db.close()
        blocked = self.client.post(f"/api/v1/invoices/{invoice_id}/cancel", headers=self.headers_a)
        self.assertEqual(blocked.status_code, 409, blocked.text)

    def test_service_advance_cannot_be_silently_posted_without_gst(self):
        response = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "UPI", "amount": 1000,
            "advance_supply_type": "SERVICES", "allocations": [],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 422, response.text)
        self.assertIn("GST", response.json()["detail"])

    def test_receipt_rejects_duplicate_or_other_customer_invoice(self):
        db = SessionLocal()
        try:
            other = Contact(
                tenant_id=self.tenant_a_id,
                name="Other Customer",
                contact_type="CUSTOMER",
                registration_type="UNREGISTERED",
                state_code="27",
                billing_address={},
                shipping_address={},
                is_active=True,
            )
            db.add(other)
            db.commit()
            other_id = other.id
        finally:
            db.close()

        inv_payload = {
            "contact_id": str(other_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": str(self.product_a_id), "quantity": 1,
                "rate": 100, "discount": 0, "hsn_sac": "84713010", "gst_rate": 0,
            }],
        }
        invoice = self.client.post("/api/v1/invoices", json=inv_payload, headers=self.headers_a).json()
        base = {
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 100,
        }
        wrong_customer = {**base, "allocations": [{"invoice_id": invoice["id"], "amount": 100}]}
        response = self.client.post("/api/v1/payments/receipts", json=wrong_customer, headers=self.headers_a)
        self.assertEqual(response.status_code, 400)
        self.assertIn("different customer", response.json()["detail"])

        duplicate = {**base, "allocations": [
            {"invoice_id": invoice["id"], "amount": 50},
            {"invoice_id": invoice["id"], "amount": 50},
        ]}
        response = self.client.post("/api/v1/payments/receipts", json=duplicate, headers=self.headers_a)
        self.assertEqual(response.status_code, 400)
        self.assertIn("only be allocated once", response.json()["detail"])

    def test_sales_return_is_source_bound_and_cancel_reverses_stock_and_ledger(self):
        invoice = self.client.post("/api/v1/invoices", json={
            "contact_id": str(self.customer_a_id), "issue_date": str(date.today()),
            "due_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{"product_id": str(self.product_a_id), "quantity": 2,
                "rate": 1000, "discount": 0, "hsn_sac": "84713010", "gst_rate": 18}],
        }, headers=self.headers_a).json()
        payload = {
            "invoice_id": invoice["id"], "contact_id": str(self.customer_a_id),
            "issue_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{"invoice_line_id": invoice["lines"][0]["id"],
                "product_id": str(self.product_a_id), "quantity": 1,
                "rate": 1, "hsn_sac": "84713010", "gst_rate": 0}],
        }
        created = self.client.post("/api/v1/returns/sales", json=payload, headers=self.headers_a)
        self.assertEqual(created.status_code, 201, created.text)
        sales_return = created.json()
        self.assertEqual(Decimal(sales_return["subtotal"]), Decimal("1000.0000"))
        self.assertEqual(Decimal(sales_return["cgst_amount"]), Decimal("90.0000"))

        over_return = {**payload, "line_items": [{**payload["line_items"][0], "quantity": 2}]}
        blocked = self.client.post("/api/v1/returns/sales", json=over_return, headers=self.headers_a)
        self.assertEqual(blocked.status_code, 400)
        self.assertIn("exceeds invoice quantity remaining", blocked.json()["detail"])

        cancelled = self.client.post(
            f"/api/v1/returns/sales/{sales_return['id']}/cancel", headers=self.headers_a)
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("98.0000"))
            reversal = db.query(JournalEntry).filter(
                JournalEntry.source_type == "SALES_RETURN_REVERSAL",
                JournalEntry.source_id == uuid.UUID(sales_return["id"])).one()
            debits = sum(line.amount for line in reversal.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in reversal.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
        finally:
            db.close()

    def test_purchase_gst_return_and_tds_cancellation_are_balanced(self):
        bill = self.client.post("/api/v1/bills", json={
            "contact_id": str(self.vendor_a_id), "bill_number": "KA-INTERSTATE-1",
            "issue_date": str(date.today()), "due_date": str(date.today()),
            "pos_state_code": "27", "tds_rate": 10,
            "line_items": [{"product_id": str(self.product_a_id), "quantity": 2,
                "rate": 1000, "discount": 0, "hsn_sac": "84713010", "gst_rate": 18}],
        }, headers=self.headers_a)
        self.assertEqual(bill.status_code, 201, bill.text)
        bill_data = bill.json()
        # Vendor in Karnataka (29), Company in Maharashtra (27), POS = Maharashtra (27)
        # Origin = vendor state (29), POS = 27 => inter-state => IGST
        self.assertEqual(Decimal(bill_data["igst_amount"]), Decimal("360.0000"))
        self.assertEqual(Decimal(bill_data["cgst_amount"]), Decimal("0.0000"))
        self.assertEqual(Decimal(bill_data["sgst_amount"]), Decimal("0.0000"))

        ret = self.client.post("/api/v1/returns/purchase", json={
            "bill_id": bill_data["id"], "contact_id": str(self.vendor_a_id),
            "issue_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{"bill_line_id": bill_data["lines"][0]["id"],
                "product_id": str(self.product_a_id), "quantity": 1,
                "rate": 1, "hsn_sac": "84713010", "gst_rate": 0}],
        }, headers=self.headers_a)
        self.assertEqual(ret.status_code, 201, ret.text)
        purchase_return = ret.json()
        self.assertEqual(Decimal(purchase_return["subtotal"]), Decimal("1000.0000"))
        self.assertEqual(Decimal(purchase_return["igst_amount"]), Decimal("180.0000"))
        self.assertEqual(self.client.post(
            f"/api/v1/returns/purchase/{purchase_return['id']}/cancel",
            headers=self.headers_a).status_code, 200)
        cancelled_bill = self.client.post(
            f"/api/v1/bills/{bill_data['id']}/cancel", headers=self.headers_a)
        self.assertEqual(cancelled_bill.status_code, 200, cancelled_bill.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("100.0000"))
            reversal = db.query(JournalEntry).filter(
                JournalEntry.source_type == "BILL_REVERSAL",
                JournalEntry.source_id == uuid.UUID(bill_data["id"])).one()
            debits = sum(line.amount for line in reversal.lines if line.direction == "DEBIT")
            credits = sum(line.amount for line in reversal.lines if line.direction == "CREDIT")
            self.assertEqual(debits, credits)
        finally:
            db.close()

if __name__ == "__main__":
    unittest.main()
