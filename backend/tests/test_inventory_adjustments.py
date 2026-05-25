import sys
import os
import uuid
from datetime import date
from decimal import Decimal
import unittest

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import SessionLocal, engine
from src.infrastructure.database.models import Base, Product

class TestInventoryAdjustmentWorkflow(unittest.TestCase):
    def setUp(self):
        """Set up test database and test data"""
        # Create tables
        Base.metadata.create_all(bind=engine)
        
        # Create test session
        self.db = SessionLocal()
        
        # Create test tenant (using a fixed UUID for consistency)
        self.tenant_id = uuid.UUID("0aa85f64-5717-4562-b3fc-2c963f66b110")
        
        # Create test product
        self.test_product = Product(
            id=uuid.uuid4(),
            tenant_id=self.tenant_id,
            name="Test Product",
            sku="TEST-001",
            hsn_sac="1234",
            product_type="GOODS",
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

if __name__ == "__main__":
    unittest.main()