import os
import sys
import time
import uuid
import unittest
from datetime import date


sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.common.audit_log import set_audit_context
from src.core.database import Base, SessionLocal, engine
from src.infrastructure.database.models import AuditLog, Invoice


class TestAuditLogging(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.tenant_id = uuid.uuid4()
        self.actor_id = uuid.uuid4()
        set_audit_context(
            tenant_id=self.tenant_id,
            actor_id=self.actor_id,
            actor_email="auditor@example.com",
            ip_address="127.0.0.1",
            user_agent="pytest",
        )

    def _wait_for_action(self, action: str) -> AuditLog:
        deadline = time.time() + 2
        while time.time() < deadline:
            db = SessionLocal()
            try:
                row = db.query(AuditLog).filter(AuditLog.action == action).first()
                if row:
                    return row
            finally:
                db.close()
            time.sleep(0.05)
        self.fail(f"Audit action {action} was not written")

    def test_create_is_audited_with_actor_and_after_state(self):
        db = SessionLocal()
        try:
            invoice = Invoice(
                tenant_id=self.tenant_id,
                invoice_number="INV-AUDIT-001",
                issue_date=date.today(),
                due_date=date.today(),
                status="DRAFT",
                pos_state_code="27",
            )
            db.add(invoice)
            db.commit()
        finally:
            db.close()

        audit = self._wait_for_action("invoice.created")
        self.assertEqual(audit.tenant_id, self.tenant_id)
        self.assertEqual(audit.actor_id, self.actor_id)
        self.assertEqual(audit.actor_email, "auditor@example.com")
        self.assertEqual(audit.ip_address, "127.0.0.1")
        self.assertIsNone(audit.before_state)
        self.assertEqual(audit.after_state["invoice_number"], "INV-AUDIT-001")

    def test_invoice_status_transition_is_named_finalize(self):
        db = SessionLocal()
        try:
            invoice = Invoice(
                tenant_id=self.tenant_id,
                invoice_number="INV-AUDIT-002",
                issue_date=date.today(),
                due_date=date.today(),
                status="DRAFT",
                pos_state_code="27",
            )
            db.add(invoice)
            db.commit()
            invoice_id = invoice.id
        finally:
            db.close()

        db = SessionLocal()
        try:
            invoice = db.query(Invoice).filter(Invoice.id == invoice_id).first()
            invoice.status = "SENT"
            db.commit()
        finally:
            db.close()

        audit = self._wait_for_action("invoice.finalized")
        self.assertEqual(audit.before_state["status"], "DRAFT")
        self.assertEqual(audit.after_state["status"], "SENT")


if __name__ == "__main__":
    unittest.main()
