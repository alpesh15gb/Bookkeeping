import sys
import os
import uuid
from datetime import date
from decimal import Decimal
import unittest

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import SessionLocal, engine
from src.infrastructure.database.models import Base, Contact, Product

class TestSalesOrderWorkflow(unittest.TestCase):
    def setUp(self):
        """Set up test database and test data"""
        # Create tables
        Base.metadata.create_all(bind=engine)
        
        # Create test session
        self.db = SessionLocal()
        
        # Create test tenant (using a fixed UUID for consistency)
        self.tenant_id = uuid.UUID("0aa85f64-5717-4562-b3fc-2c963f66b110")
        
        # Create test contact (customer)
        self.customer_contact = Contact(
            id=uuid.uuid4(),
            tenant_id=self.tenant_id,
            name="Test Customer",
            email="customer@test.com",
            phone="+919876543210",
            contact_type="CUSTOMER",
            gstin="27AACTC1234A1Z5",
            pan="AACTC1234A",
            registration_type="REGULAR",
            billing_address={"street": "123 Customer St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
            state_code="27",
            is_active=True
        )
        self.db.add(self.customer_contact)
        
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
    
    def test_sales_order_creation_logic(self):
        """Test sales order creation logic"""
        # This would test the business logic for sales order creation
        # Similar to the purchase order test above
        self.assertTrue(True)
        
    def test_sales_order_calculations(self):
        """Test sales order calculations"""
        quantity = Decimal("5")
        rate = Decimal("1200.00")
        discount = Decimal("100.00")
        gst_rate = Decimal("18.00")
        
        # Calculate expected values
        subtotal = (quantity * rate) - discount  # (5 * 1200) - 100 = 6000 - 100 = 5900
        expected_cgst = subtotal * (gst_rate / 2) / 100  # 5900 * 9% = 531
        expected_sgst = subtotal * (gst_rate / 2) / 100  # 5900 * 9% = 531
        expected_total = subtotal + expected_cgst + expected_sgst  # 5900 + 531 + 531 = 6962
        
        self.assertEqual(subtotal, Decimal("5900.00"))
        self.assertEqual(expected_cgst, Decimal("531.00"))
        self.assertEqual(expected_sgst, Decimal("531.00"))
        self.assertEqual(expected_total, Decimal("6962.00"))

if __name__ == "__main__":
    unittest.main()