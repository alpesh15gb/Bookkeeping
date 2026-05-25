import os
import sys
import uuid
import unittest
from datetime import date

from sqlalchemy.exc import IntegrityError


sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import Base, SessionLocal, engine
from src.infrastructure.database.models import Invoice, Payment, Tenant


class TestDatabaseConstraints(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.db = SessionLocal()

    def tearDown(self):
        self.db.close()

    def test_tenant_gstin_is_unique(self):
        self.db.add_all([
            Tenant(legal_name="Alpha Pvt Ltd", gstin="27AAAAA1111A1Z1", pan="AAAAA1111A"),
            Tenant(legal_name="Beta Pvt Ltd", gstin="27AAAAA1111A1Z1", pan="BBBBB2222B"),
        ])

        with self.assertRaises(IntegrityError):
            self.db.commit()

    def test_invoice_status_check_constraint(self):
        invoice = Invoice(
            tenant_id=uuid.uuid4(),
            invoice_number="INV-INVALID",
            issue_date=date.today(),
            due_date=date.today(),
            status="INVALID",
            pos_state_code="27",
        )
        self.db.add(invoice)

        with self.assertRaises(IntegrityError):
            self.db.commit()

    def test_invoice_irn_is_unique(self):
        tenant_id = uuid.uuid4()
        self.db.add_all([
            Invoice(
                tenant_id=tenant_id,
                invoice_number="INV-001",
                issue_date=date.today(),
                due_date=date.today(),
                status="SENT",
                pos_state_code="27",
                irn="a" * 64,
            ),
            Invoice(
                tenant_id=tenant_id,
                invoice_number="INV-002",
                issue_date=date.today(),
                due_date=date.today(),
                status="SENT",
                pos_state_code="27",
                irn="a" * 64,
            ),
        ])

        with self.assertRaises(IntegrityError):
            self.db.commit()

    def test_payment_mode_check_constraint(self):
        payment = Payment(
            tenant_id=uuid.uuid4(),
            payment_number="REC-INVALID",
            payment_date=date.today(),
            payment_mode="CHEQUE",
            amount=100,
        )
        self.db.add(payment)

        with self.assertRaises(IntegrityError):
            self.db.commit()


if __name__ == "__main__":
    unittest.main()
