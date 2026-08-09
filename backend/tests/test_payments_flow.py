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
from src.domains.inventory.services import resolve_default_warehouse_id
from src.infrastructure.database.models import (
    AuditLog,
    BankingProfile,
    BillPayment,
    Contact,
    GSTReturn,
    JournalEntry,
    JournalLine,
    Payment,
    Product,
    StockLedger,
    Tenant,
    TenantMembership,
    User,
)


class TestPaymentsAndReceiptsFlow(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        for suffix, gstin, pan, phone in (
            ("a", "27AAAAA1111A1Z1", "AAAAA1111A", "+919999988881"),
            ("b", "27BBBBB2222B2Z2", "BBBBB2222B", "+919999988882"),
        ):
            registered = self.client.post("/api/v1/auth/register", json={
                "email": f"owner_{suffix}@company.com",
                "password": "SecurePassword123!",
                "full_name": f"Owner {suffix.upper()}",
                "phone_number": phone,
                "company_legal_name": f"Tenant {suffix.upper()} Pvt Ltd",
                "company_gstin": gstin,
                "company_pan": pan,
            })
            self.assertEqual(registered.status_code, 201, registered.text)
        self.token_a = self.client.post("/api/v1/auth/login", json={
            "email": "owner_a@company.com", "password": "SecurePassword123!"
        }).json()["access_token"]
        self.token_b = self.client.post("/api/v1/auth/login", json={
            "email": "owner_b@company.com", "password": "SecurePassword123!"
        }).json()["access_token"]

        db = SessionLocal()
        try:
            user_a = db.query(User).filter(User.email == "owner_a@company.com").one()
            user_b = db.query(User).filter(User.email == "owner_b@company.com").one()
            self.tenant_a_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user_a.id
            ).one().tenant_id
            self.tenant_b_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user_b.id
            ).one().tenant_id
            db.get(Tenant, self.tenant_a_id).tax_mode = "GST_REGULAR"
            db.get(Tenant, self.tenant_b_id).tax_mode = "GST_REGULAR"
            db.add(BankingProfile(
                tenant_id=self.tenant_a_id,
                bank_name="HDFC Bank",
                account_number="50001002003004",
                ifsc_code="HDFC0000001",
                account_holder_name="Tenant A Pvt Ltd",
                is_primary=True,
                is_active=True,
            ))
            customer = Contact(
                id=uuid.UUID("11111111-1111-1111-1111-11111111111a"),
                tenant_id=self.tenant_a_id,
                name="Customer Tenant A",
                email="cust_a@test.com",
                phone="+912267789999",
                contact_type="CUSTOMER",
                gstin="27AAACT1234A1Z1",
                pan="AAACT1234A",
                registration_type="REGULAR",
                billing_address={"street": "101 Test St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
                state_code="27",
                is_active=True,
            )
            vendor = Contact(
                id=uuid.UUID("22222222-2222-2222-2222-22222222222b"),
                tenant_id=self.tenant_a_id,
                name="Vendor Tenant A",
                email="vendor_a@test.com",
                phone="+918028520261",
                contact_type="VENDOR",
                gstin="29AAACI5678B2Z2",
                pan="AAACI5678B",
                registration_type="REGULAR",
                billing_address={"street": "202 Test St", "city": "Bengaluru", "state": "Karnataka", "state_code": "29", "pincode": "560100", "country": "India"},
                state_code="29",
                is_active=True,
            )
            product = Product(
                id=uuid.UUID("33333333-3333-3333-3333-33333333333c"),
                tenant_id=self.tenant_a_id,
                name="Test Laptop",
                sku="LPT-TST-001",
                hsn_sac="84713010",
                product_type="GOODS",
                uom="PCS",
                sales_price=Decimal("10000"),
                purchase_price=Decimal("8000"),
                gst_rate=Decimal("18"),
                opening_stock=Decimal("100"),
                current_stock=Decimal("100"),
                is_active=True,
            )
            db.add_all([customer, vendor, product])
            db.flush()
            db.add(StockLedger(
                tenant_id=self.tenant_a_id,
                product_id=product.id,
                warehouse_id=resolve_default_warehouse_id(db, self.tenant_a_id),
                quantity=Decimal("100"),
                balance_quantity=Decimal("100"),
                reference_type="OPENING",
                reference_id=product.id,
                rate=product.purchase_price,
            ))
            db.commit()
            self.customer_a_id = customer.id
            self.vendor_a_id = vendor.id
            self.product_a_id = product.id
        finally:
            db.close()

        self.headers_a = {
            "X-Tenant-ID": str(self.tenant_a_id),
            "Authorization": f"Bearer {self.token_a}",
        }
        self.headers_b = {
            "X-Tenant-ID": str(self.tenant_b_id),
            "Authorization": f"Bearer {self.token_b}",
        }

    def _invoice(self, *, rate=1000, qty=1, gst=18, contact_id=None):
        response = self.client.post("/api/v1/invoices", json={
            "contact_id": str(contact_id or self.customer_a_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "27",
            "line_items": [{
                "product_id": str(self.product_a_id), "quantity": qty,
                "rate": rate, "discount": 0, "hsn_sac": "84713010", "gst_rate": gst,
            }],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()

    def _bill(self, *, rate=1000, qty=1, gst=18, tds=0):
        response = self.client.post("/api/v1/bills", json={
            "contact_id": str(self.vendor_a_id),
            "issue_date": str(date.today()),
            "due_date": str(date.today()),
            "pos_state_code": "29",
            "tds_rate": tds,
            "line_items": [{
                "product_id": str(self.product_a_id), "quantity": qty,
                "rate": rate, "discount": 0, "hsn_sac": "84713010", "gst_rate": gst,
            }],
        }, headers=self.headers_a)
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["status"], "POSTED")
        return response.json()

    def _assert_balanced(self, entry):
        debits = sum((line.amount for line in entry.lines if line.direction == "DEBIT"), Decimal("0"))
        credits = sum((line.amount for line in entry.lines if line.direction == "CREDIT"), Decimal("0"))
        self.assertEqual(debits, credits)

    def test_receipt_create_allocate_and_delete_reverses(self):
        inv1, inv2 = self._invoice(rate=10000), self._invoice(rate=10000)
        receipt = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id),
            "payment_date": str(date.today()),
            "payment_mode": "BANK",
            "amount": 15000,
            "reference_number": "TXN-999001",
            "allocations": [
                {"invoice_id": inv1["id"], "amount": 11800},
                {"invoice_id": inv2["id"], "amount": 3200},
            ],
        }, headers=self.headers_a)
        self.assertEqual(receipt.status_code, 201, receipt.text)
        data = receipt.json()
        self.assertEqual(data["status"], "ACTIVE")
        self.assertEqual(len(data["allocations"]), 2)
        self.assertEqual(self.client.get(f"/api/v1/invoices/{inv1['id']}", headers=self.headers_a).json()["status"], "PAID")
        self.assertEqual(self.client.get(f"/api/v1/invoices/{inv2['id']}", headers=self.headers_a).json()["status"], "PARTIALLY_PAID")

        db = SessionLocal()
        try:
            posting = db.query(JournalEntry).filter(
                JournalEntry.source_type == "PAYMENT",
                JournalEntry.source_id == uuid.UUID(data["id"]),
            ).one()
            self._assert_balanced(posting)
            self.assertEqual(sum((l.amount for l in posting.lines if l.direction == "DEBIT"), Decimal("0")), Decimal("15000"))
        finally:
            db.close()

        deleted = self.client.delete(
            f"/api/v1/payments/receipts/{data['id']}", headers=self.headers_a
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        self.assertEqual(self.client.get(f"/api/v1/payments/receipts/{data['id']}", headers=self.headers_a).status_code, 404)
        for invoice_id in (inv1["id"], inv2["id"]):
            invoice = self.client.get(f"/api/v1/invoices/{invoice_id}", headers=self.headers_a).json()
            self.assertEqual(invoice["status"], "POSTED")
            self.assertEqual(float(invoice["amount_paid"]), 0)
        db = SessionLocal()
        try:
            payment = db.query(Payment).filter(Payment.id == uuid.UUID(data["id"])).one()
            self.assertIsNotNone(payment.deleted_at)
            reversal = db.query(JournalEntry).filter(
                JournalEntry.reference_number == f"REV-{data['payment_number']}"
            ).one()
            self._assert_balanced(reversal)
        finally:
            db.close()

    def test_receipt_edit_reverses_original_and_posts_replacement(self):
        invoice = self._invoice(rate=1000)
        created = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "CASH", "amount": 500,
            "allocations": [{"invoice_id": invoice["id"], "amount": 500}],
        }, headers=self.headers_a)
        self.assertEqual(created.status_code, 201, created.text)
        original = created.json()
        edited = self.client.put(
            f"/api/v1/payments/receipts/{original['id']}",
            json={
                "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
                "payment_mode": "BANK", "amount": 700,
                "allocations": [{"invoice_id": invoice["id"], "amount": 700}],
            }, headers=self.headers_a,
        )
        self.assertEqual(edited.status_code, 200, edited.text)
        replacement = edited.json()
        self.assertNotEqual(replacement["id"], original["id"])
        invoice_after = self.client.get(f"/api/v1/invoices/{invoice['id']}", headers=self.headers_a).json()
        self.assertEqual(float(invoice_after["amount_paid"]), 700)
        db = SessionLocal()
        try:
            old = db.query(Payment).filter(Payment.id == uuid.UUID(original["id"])).one()
            self.assertIsNotNone(old.deleted_at)
            self.assertIn(replacement["id"], old.cancellation_reason)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.reference_number == f"REV-{original['payment_number']}"
            ).count(), 1)
            self.assertEqual(db.query(JournalEntry).filter(
                JournalEntry.source_type == "PAYMENT",
                JournalEntry.source_id == uuid.UUID(replacement["id"]),
            ).count(), 1)
        finally:
            db.close()

    def test_vendor_disbursement_create_and_delete_reverses(self):
        bill = self._bill(rate=10000)
        created = self.client.post("/api/v1/payments/disbursements", json={
            "contact_id": str(self.vendor_a_id), "payment_date": str(date.today()),
            "payment_mode": "BANK", "amount": 11800,
            "allocations": [{"bill_id": bill["id"], "amount": 11800}],
        }, headers=self.headers_a)
        self.assertEqual(created.status_code, 201, created.text)
        disb = created.json()
        self.assertEqual(self.client.get(f"/api/v1/bills/{bill['id']}", headers=self.headers_a).json()["status"], "PAID")
        deleted = self.client.delete(
            f"/api/v1/payments/disbursements/{disb['id']}", headers=self.headers_a
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        bill_after = self.client.get(f"/api/v1/bills/{bill['id']}", headers=self.headers_a).json()
        self.assertEqual(bill_after["status"], "POSTED")
        self.assertEqual(float(bill_after["amount_paid"]), 0)
        db = SessionLocal()
        try:
            old = db.query(BillPayment).filter(BillPayment.id == uuid.UUID(disb["id"])).one()
            self.assertIsNotNone(old.deleted_at)
            reversal = db.query(JournalEntry).filter(
                JournalEntry.reference_number == f"REV-{disb['payment_number']}"
            ).one()
            self._assert_balanced(reversal)
        finally:
            db.close()

    def test_payment_validation_and_tenant_boundary(self):
        invoice = self._invoice(rate=1000)
        invalid = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "CASH", "amount": 500,
            "allocations": [{"invoice_id": invoice["id"], "amount": 1000}],
        }, headers=self.headers_a)
        self.assertEqual(invalid.status_code, 400)

        cross = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "BANK", "amount": 100,
            "allocations": [{"invoice_id": invoice["id"], "amount": 100}],
        }, headers=self.headers_b)
        self.assertEqual(cross.status_code, 404)

        receipt = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "CASH", "amount": 100,
            "allocations": [{"invoice_id": invoice["id"], "amount": 100}],
        }, headers=self.headers_a).json()
        self.assertEqual(self.client.get(f"/api/v1/payments/receipts/{receipt['id']}", headers=self.headers_b).status_code, 404)
        self.assertEqual(self.client.delete(f"/api/v1/payments/receipts/{receipt['id']}", headers=self.headers_b).status_code, 404)

    def test_customer_advance_delete_restores_credit(self):
        created = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "NEFT_RTGS", "amount": 2500,
            "advance_supply_type": "GOODS", "allocations": [],
        }, headers=self.headers_a)
        self.assertEqual(created.status_code, 201, created.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Contact, self.customer_a_id).credit_balance, Decimal("2500.0000"))
        finally:
            db.close()
        deleted = self.client.delete(
            f"/api/v1/payments/receipts/{created.json()['id']}", headers=self.headers_a
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Contact, self.customer_a_id).credit_balance, Decimal("0.0000"))
        finally:
            db.close()

    def test_service_advance_requires_gst_workflow(self):
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
                billing_address={}, shipping_address={}, is_active=True,
            )
            db.add(other)
            db.commit()
            other_id = other.id
        finally:
            db.close()
        invoice = self._invoice(rate=100, gst=0, contact_id=other_id)
        base = {
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "BANK", "amount": 100,
        }
        wrong = self.client.post("/api/v1/payments/receipts", json={
            **base, "allocations": [{"invoice_id": invoice["id"], "amount": 100}]
        }, headers=self.headers_a)
        self.assertEqual(wrong.status_code, 400)
        duplicate = self.client.post("/api/v1/payments/receipts", json={
            **base, "allocations": [
                {"invoice_id": invoice["id"], "amount": 50},
                {"invoice_id": invoice["id"], "amount": 50},
            ]
        }, headers=self.headers_a)
        self.assertEqual(duplicate.status_code, 400)

    def test_invoice_stock_moves_once_and_delete_restores_once(self):
        invoice = self._invoice(rate=100, qty=3, gst=0)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("97.00"))
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "INVOICE",
                StockLedger.reference_id == uuid.UUID(invoice["id"]),
            ).count(), 1)
        finally:
            db.close()
        deleted = self.client.delete(f"/api/v1/invoices/{invoice['id']}", headers=self.headers_a)
        self.assertEqual(deleted.status_code, 204, deleted.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("100.00"))
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "INVOICE_REVERSAL",
                StockLedger.reference_id == uuid.UUID(invoice["id"]),
            ).count(), 1)
        finally:
            db.close()

    def test_partial_receipt_does_not_change_gst_and_filed_period_blocks_delete(self):
        invoice = self._invoice(rate=1000, gst=18)
        before = self.client.get("/api/v1/gst/gstr1", headers=self.headers_a).json()
        receipt = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "BANK", "amount": 500,
            "allocations": [{"invoice_id": invoice["id"], "amount": 500}],
        }, headers=self.headers_a)
        self.assertEqual(receipt.status_code, 201, receipt.text)
        after = self.client.get("/api/v1/gst/gstr1", headers=self.headers_a).json()
        for section in ("b2b", "b2cl", "b2cs", "cdnr", "cdnur", "hsn_summary"):
            self.assertEqual(after.get(section), before.get(section), section)
        db = SessionLocal()
        try:
            db.add(GSTReturn(
                tenant_id=self.tenant_a_id, return_type="GSTR1",
                period_start=date.today().replace(day=1), period_end=date.today(), status="FILED",
            ))
            db.commit()
        finally:
            db.close()
        # Payment allocation blocks the correction first; either way deletion must not occur.
        blocked = self.client.delete(f"/api/v1/invoices/{invoice['id']}", headers=self.headers_a)
        self.assertEqual(blocked.status_code, 409, blocked.text)
        self.assertEqual(self.client.get(f"/api/v1/invoices/{invoice['id']}", headers=self.headers_a).status_code, 200)

    def test_sales_return_save_and_delete_reverses_stock_and_ledger(self):
        invoice = self._invoice(rate=1000, qty=2, gst=18)
        payload = {
            "invoice_id": invoice["id"], "contact_id": str(self.customer_a_id),
            "issue_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{
                "invoice_line_id": invoice["lines"][0]["id"],
                "product_id": str(self.product_a_id), "quantity": 1,
                "rate": 1, "hsn_sac": "84713010", "gst_rate": 0,
            }],
        }
        created = self.client.post("/api/v1/returns/sales", json=payload, headers=self.headers_a)
        self.assertEqual(created.status_code, 201, created.text)
        sales_return = created.json()
        self.assertEqual(Decimal(sales_return["subtotal"]), Decimal("1000.0000"))
        over_return = {**payload, "line_items": [{**payload["line_items"][0], "quantity": 2}]}
        self.assertEqual(self.client.post("/api/v1/returns/sales", json=over_return, headers=self.headers_a).status_code, 400)
        deleted = self.client.delete(
            f"/api/v1/returns/sales/{sales_return['id']}", headers=self.headers_a
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("98.0000"))
            reversal = db.query(JournalEntry).filter(
                JournalEntry.source_type == "SALES_RETURN_REVERSAL",
                JournalEntry.source_id == uuid.UUID(sales_return["id"]),
            ).one()
            self._assert_balanced(reversal)
        finally:
            db.close()

    def test_purchase_return_and_bill_delete_are_balanced(self):
        bill = self.client.post("/api/v1/bills", json={
            "contact_id": str(self.vendor_a_id), "bill_number": "KA-INTERSTATE-1",
            "issue_date": str(date.today()), "due_date": str(date.today()),
            "pos_state_code": "27", "tds_rate": 10,
            "line_items": [{
                "product_id": str(self.product_a_id), "quantity": 2,
                "rate": 1000, "discount": 0, "hsn_sac": "84713010", "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(bill.status_code, 201, bill.text)
        bill_data = bill.json()
        self.assertEqual(Decimal(bill_data["igst_amount"]), Decimal("360.0000"))
        returned = self.client.post("/api/v1/returns/purchase", json={
            "bill_id": bill_data["id"], "contact_id": str(self.vendor_a_id),
            "issue_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{
                "bill_line_id": bill_data["lines"][0]["id"],
                "product_id": str(self.product_a_id), "quantity": 1,
                "rate": 1, "hsn_sac": "84713010", "gst_rate": 0,
            }],
        }, headers=self.headers_a)
        self.assertEqual(returned.status_code, 201, returned.text)
        purchase_return = returned.json()
        self.assertEqual(Decimal(purchase_return["subtotal"]), Decimal("1000.0000"))
        self.assertEqual(self.client.delete(
            f"/api/v1/returns/purchase/{purchase_return['id']}", headers=self.headers_a
        ).status_code, 204)
        deleted_bill = self.client.delete(
            f"/api/v1/bills/{bill_data['id']}", headers=self.headers_a
        )
        self.assertEqual(deleted_bill.status_code, 204, deleted_bill.text)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("100.0000"))
            reversal = db.query(JournalEntry).filter(
                JournalEntry.source_type == "BILL_REVERSAL",
                JournalEntry.source_id == uuid.UUID(bill_data["id"]),
            ).one()
            self._assert_balanced(reversal)
        finally:
            db.close()

    def test_quotation_delivery_invoice_receipt_reports_traceability(self):
        quotation = self.client.post("/api/v1/proforma-invoices", json={
            "contact_id": str(self.customer_a_id), "proforma_number": "QT-E2E-001",
            "issue_date": str(date.today()), "due_date": str(date.today()), "pos_state_code": "27",
            "line_items": [{
                "product_id": str(self.product_a_id), "description": "Workflow item",
                "quantity": 1, "rate": 1000, "discount": 100,
                "hsn_sac": "84713010", "gst_rate": 18,
            }],
        }, headers=self.headers_a)
        self.assertEqual(quotation.status_code, 201, quotation.text)
        qid = quotation.json()["id"]
        self.assertEqual(self.client.post(f"/api/v1/proforma-invoices/{qid}/issue", headers=self.headers_a).status_code, 200)
        order = self.client.post(f"/api/v1/proforma-invoices/{qid}/convert-to-sales-order", headers=self.headers_a)
        self.assertEqual(order.status_code, 200, order.text)
        oid = order.json()["id"]
        self.assertEqual(self.client.post(f"/api/v1/sales-orders/{oid}/confirm", headers=self.headers_a).status_code, 200)
        challan = self.client.post(f"/api/v1/sales-orders/{oid}/create-delivery-challan", headers=self.headers_a)
        self.assertEqual(challan.status_code, 200, challan.text)
        cid = challan.json()["id"]
        self.assertEqual(self.client.post(f"/api/v1/delivery-challans/{cid}/issue", headers=self.headers_a).status_code, 200)
        invoice = self.client.post(f"/api/v1/delivery-challans/{cid}/convert-to-invoice", headers=self.headers_a)
        self.assertEqual(invoice.status_code, 200, invoice.text)
        iid = invoice.json()["id"]
        self.assertEqual(invoice.json()["status"], "POSTED")
        duplicate = self.client.post(f"/api/v1/delivery-challans/{cid}/convert-to-invoice", headers=self.headers_a)
        self.assertEqual(duplicate.json()["id"], iid)
        db = SessionLocal()
        try:
            self.assertEqual(db.get(Product, self.product_a_id).current_stock, Decimal("99.00"))
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.reference_type == "INVOICE",
                StockLedger.reference_id == uuid.UUID(iid),
            ).count(), 0)
        finally:
            db.close()
        receipt = self.client.post("/api/v1/payments/receipts", json={
            "contact_id": str(self.customer_a_id), "payment_date": str(date.today()),
            "payment_mode": "UPI", "amount": 1062,
            "allocations": [{"invoice_id": iid, "amount": 1062}],
        }, headers=self.headers_a)
        self.assertEqual(receipt.status_code, 201, receipt.text)
        self.assertEqual(self.client.get(f"/api/v1/invoices/{iid}", headers=self.headers_a).json()["status"], "PAID")
        db = SessionLocal()
        try:
            entries = db.query(JournalEntry).filter(
                JournalEntry.tenant_id == self.tenant_a_id,
                JournalEntry.source_id.in_([uuid.UUID(iid), uuid.UUID(receipt.json()["id"])]),
            ).all()
            self.assertEqual(len(entries), 2)
            for entry in entries:
                self._assert_balanced(entry)
            actions = {row.action for row in db.query(AuditLog).filter(
                AuditLog.tenant_id == self.tenant_a_id,
                AuditLog.entity_id.in_([uuid.UUID(iid), uuid.UUID(receipt.json()["id"])]),
            ).all()}
            self.assertIn("invoice.created", actions)
            self.assertIn("payment.created", actions)
        finally:
            db.close()
        outstanding = self.client.get(
            "/api/v1/reports/outstanding/receivables",
            params={"as_of_date": str(date.today())}, headers=self.headers_a,
        )
        self.assertEqual(outstanding.status_code, 200, outstanding.text)
        self.assertEqual(Decimal(str(outstanding.json()["total_outstanding"])), Decimal("0"))
        trial = self.client.get(
            "/api/v1/reports/trial-balance",
            params={"as_of_date": str(date.today())}, headers=self.headers_a,
        )
        self.assertEqual(trial.status_code, 200, trial.text)
        self.assertTrue(trial.json()["is_balanced"])
        gstr1 = self.client.get(
            "/api/v1/reports/gst/gstr1",
            params={"start_date": str(date.today()), "end_date": str(date.today())},
            headers=self.headers_a,
        )
        self.assertEqual(gstr1.status_code, 200, gstr1.text)
        self.assertEqual(Decimal(str(gstr1.json()["total_invoice_value"])), Decimal("1062"))
        pdf = self.client.get(f"/api/v1/invoices/{iid}/print", headers=self.headers_a)
        self.assertEqual(pdf.status_code, 200, pdf.text)
        self.assertTrue(pdf.content.startswith(b"%PDF"))


if __name__ == "__main__":
    unittest.main()
