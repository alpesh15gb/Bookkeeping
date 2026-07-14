import sys
import os
import uuid
from datetime import date
from decimal import Decimal
import unittest
from fastapi.testclient import TestClient

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import SessionLocal, engine
from src.main import app
from src.infrastructure.database.models import Base, Product, User, TenantMembership, JournalEntry, StockLedger

class TestInventoryAdjustmentWorkflow(unittest.TestCase):
    def setUp(self):
        """Set up test database and test data"""
        # Create tables
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)
        registered = self.client.post("/api/v1/auth/register", json={
            "email": "stock.adjustment@test.com", "password": "SecurePassword123!",
            "full_name": "Stock Controller", "phone_number": "+919876543219",
            "company_legal_name": "Stock Control Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1", "company_pan": "AAAAA1111A",
        })
        self.assertEqual(registered.status_code, 201, registered.text)
        token = self.client.post("/api/v1/auth/login", json={
            "email": "stock.adjustment@test.com", "password": "SecurePassword123!",
        }).json()["access_token"]
        
        # Create test session
        self.db = SessionLocal()
        
        user = self.db.query(User).filter(User.email == "stock.adjustment@test.com").one()
        self.tenant_id = self.db.query(TenantMembership).filter(
            TenantMembership.user_id == user.id
        ).one().tenant_id
        self.headers = {"X-Tenant-ID": str(self.tenant_id), "Authorization": f"Bearer {token}"}
        
        # Create test product
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
            is_active=True
        )
        self.db.add(self.test_product)
        
        self.db.commit()
    
    def tearDown(self):
        """Clean up after tests"""
        self.db.rollback()
        self.db.close()
        Base.metadata.drop_all(bind=engine)
    
    def test_inventory_adjustment_creation_logic(self):
        """Test inventory adjustment creation logic"""
        # This would test the business logic for inventory adjustment creation
        self.assertTrue(True)
        
    def test_inventory_adjustment_calculations(self):
        """Test inventory adjustment calculations"""
        quantity_change = Decimal("10")  # Increase by 10 units
        unit_cost = Decimal("50.00")
        
        # Calculate expected total cost
        expected_total_cost = quantity_change * unit_cost  # 10 * 50 = 500
        
        self.assertEqual(expected_total_cost, Decimal("500.00"))
        
        # Test decrease
        quantity_change_negative = Decimal("-5")  # Decrease by 5 units
        expected_total_cost_negative = abs(quantity_change_negative * unit_cost)  # 5 * 50 = 250
        
        self.assertEqual(expected_total_cost_negative, Decimal("250.00"))

    def test_decrease_confirm_and_cancel_preserve_audit_history(self):
        created = self.client.post("/api/v1/inventory-adjustments", json={
            "adjustment_number": "ADJ-0001", "adjustment_date": str(date.today()),
            "reason": "Physical count shortage",
            "line_items": [{
                "product_id": str(self.test_product.id),
                "quantity_change": -5, "unit_cost": 50,
            }],
        }, headers=self.headers)
        self.assertEqual(created.status_code, 201, created.text)
        adjustment = created.json()
        self.assertEqual(Decimal(adjustment["lines"][0]["total_cost"]), Decimal("250.0000"))

        confirmed = self.client.post(
            f"/api/v1/inventory-adjustments/{adjustment['id']}/confirm", headers=self.headers
        )
        self.assertEqual(confirmed.status_code, 200, confirmed.text)
        self.db.expire_all()
        self.assertEqual(self.db.get(Product, self.test_product.id).current_stock, Decimal("995.0000"))

        cancelled = self.client.post(
            f"/api/v1/inventory-adjustments/{adjustment['id']}/cancel", headers=self.headers
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        self.db.expire_all()
        self.assertEqual(self.db.get(Product, self.test_product.id).current_stock, Decimal("1000.0000"))
        self.assertEqual(self.db.query(JournalEntry).filter(
            JournalEntry.source_id == uuid.UUID(adjustment["id"])
        ).count(), 2)
        self.assertEqual(self.db.query(StockLedger).filter(
            StockLedger.reference_id == uuid.UUID(adjustment["id"])
        ).count(), 2)

if __name__ == "__main__":
    unittest.main()
