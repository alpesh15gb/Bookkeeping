import os
import sys
import uuid
import unittest
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import SessionLocal, engine
from src.main import app
from src.infrastructure.database.models import (
    Base,
    InventoryAdjustment,
    JournalEntry,
    Product,
    StockLedger,
    TenantMembership,
    User,
)
from src.domains.inventory.services import resolve_default_warehouse_id


class TestInventoryAdjustmentWorkflow(unittest.TestCase):
    def setUp(self):
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)
        registered = self.client.post("/api/v1/auth/register", json={
            "email": "stock.adjustment@test.com",
            "password": "SecurePassword123!",
            "full_name": "Stock Controller",
            "phone_number": "+919876543219",
            "company_legal_name": "Stock Control Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A",
        })
        self.assertEqual(registered.status_code, 201, registered.text)
        token = self.client.post("/api/v1/auth/login", json={
            "email": "stock.adjustment@test.com",
            "password": "SecurePassword123!",
        }).json()["access_token"]

        self.db = SessionLocal()
        user = self.db.query(User).filter(User.email == "stock.adjustment@test.com").one()
        self.tenant_id = self.db.query(TenantMembership).filter(
            TenantMembership.user_id == user.id
        ).one().tenant_id
        self.headers = {
            "X-Tenant-ID": str(self.tenant_id),
            "Authorization": f"Bearer {token}",
        }

        self.test_product = Product(
            id=uuid.uuid4(),
            tenant_id=self.tenant_id,
            name="Test Product",
            sku="TEST-001",
            hsn_sac="1234",
            product_type="GOODS",
            current_stock=Decimal("1000.00"),
            opening_stock=Decimal("1000.00"),
            uom="PCS",
            sales_price=Decimal("1000.00"),
            purchase_price=Decimal("800.00"),
            gst_rate=Decimal("18.00"),
            is_active=True,
        )
        self.db.add(self.test_product)
        self.db.flush()
        self.db.add(StockLedger(
            tenant_id=self.tenant_id,
            product_id=self.test_product.id,
            warehouse_id=resolve_default_warehouse_id(self.db, self.tenant_id),
            quantity=self.test_product.opening_stock,
            balance_quantity=self.test_product.opening_stock,
            reference_type="OPENING",
            reference_id=self.test_product.id,
            rate=self.test_product.purchase_price,
        ))
        self.db.commit()

    def tearDown(self):
        self.db.rollback()
        self.db.close()
        Base.metadata.drop_all(bind=engine)

    def test_inventory_adjustment_calculations(self):
        quantity_change = Decimal("10")
        unit_cost = Decimal("50.00")
        self.assertEqual(quantity_change * unit_cost, Decimal("500.00"))
        self.assertEqual(abs(Decimal("-5") * unit_cost), Decimal("250.00"))

    def _create_decrease(self, qty=-5):
        created = self.client.post("/api/v1/inventory-adjustments", json={
            # adjustment_number deliberately omitted; backend owns numbering
            "adjustment_date": str(date.today()),
            "reason": "Physical count shortage",
            "line_items": [{
                "product_id": str(self.test_product.id),
                "quantity_change": qty,
                "unit_cost": 50,
            }],
        }, headers=self.headers)
        self.assertEqual(created.status_code, 201, created.text)
        self.assertEqual(created.json()["status"], "CONFIRMED")
        return created

    def test_save_posts_and_delete_reverses_preserving_history(self):
        created = self._create_decrease(-5)
        adjustment_id = uuid.UUID(created.json()["id"])
        self.assertEqual(
            Decimal(created.json()["lines"][0]["total_cost"]), Decimal("250.0000")
        )
        self.db.expire_all()
        self.assertEqual(
            self.db.get(Product, self.test_product.id).current_stock,
            Decimal("995.0000"),
        )
        self.assertEqual(self.db.query(JournalEntry).filter(
            JournalEntry.source_type == "INVENTORY_ADJUSTMENT",
            JournalEntry.source_id == adjustment_id,
        ).count(), 1)

        deleted = self.client.delete(
            f"/api/v1/inventory-adjustments/{adjustment_id}", headers=self.headers
        )
        self.assertEqual(deleted.status_code, 204, deleted.text)
        self.db.expire_all()
        self.assertEqual(
            self.db.get(Product, self.test_product.id).current_stock,
            Decimal("1000.0000"),
        )
        original = self.db.query(InventoryAdjustment).filter(
            InventoryAdjustment.id == adjustment_id
        ).one()
        self.assertIsNotNone(original.deleted_at)
        self.assertEqual(self.db.query(JournalEntry).filter(
            JournalEntry.source_id == adjustment_id
        ).count(), 2)
        self.assertEqual(self.db.query(StockLedger).filter(
            StockLedger.reference_id == adjustment_id
        ).count(), 2)

    def test_edit_reverses_old_adjustment_and_posts_replacement(self):
        created = self._create_decrease(-5)
        original_id = uuid.UUID(created.json()["id"])
        edited = self.client.put(
            f"/api/v1/inventory-adjustments/{original_id}",
            json={
                "reason": "Corrected physical count",
                "line_items": [{
                    "product_id": str(self.test_product.id),
                    "quantity_change": -2,
                    "unit_cost": 50,
                }],
            },
            headers=self.headers,
        )
        self.assertEqual(edited.status_code, 200, edited.text)
        replacement_id = uuid.UUID(edited.json()["id"])
        self.assertNotEqual(original_id, replacement_id)
        self.assertEqual(edited.json()["status"], "CONFIRMED")
        self.db.expire_all()
        self.assertEqual(
            self.db.get(Product, self.test_product.id).current_stock,
            Decimal("998.0000"),
        )
        old = self.db.query(InventoryAdjustment).filter(
            InventoryAdjustment.id == original_id
        ).one()
        self.assertIsNotNone(old.deleted_at)
        self.assertEqual(self.db.query(JournalEntry).filter(
            JournalEntry.source_type == "INVENTORY_ADJUSTMENT_REVERSAL",
            JournalEntry.source_id == original_id,
        ).count(), 1)
        self.assertEqual(self.db.query(JournalEntry).filter(
            JournalEntry.source_type == "INVENTORY_ADJUSTMENT",
            JournalEntry.source_id == replacement_id,
        ).count(), 1)


if __name__ == "__main__":
    unittest.main()
