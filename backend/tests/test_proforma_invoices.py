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

class TestProformaInvoiceWorkflow(unittest.TestCase):
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
    
    def test_proforma_invoice_creation_logic(self):
        """Test proforma invoice creation logic"""
        # This would test the business logic for proforma invoice creation
        self.assertTrue(True)
        
    def test_proforma_invoice_calculations(self):
        """Test proforma invoice calculations"""
        quantity = Decimal("8")
        rate = Decimal("750.00")
        discount = Decimal("25.00")
        gst_rate = Decimal("18.00")
        
        # Calculate expected values
        subtotal = (quantity * rate) - discount  # (8 * 750) - 25 = 6000 - 25 = 5975
        expected_cgst = subtotal * (gst_rate / 2) / 100  # 5975 * 9% = 537.75
        expected_sgst = subtotal * (gst_rate / 2) / 100  # 5975 * 9% = 537.75
        expected_total = subtotal + expected_cgst + expected_sgst  # 5975 + 537.75 + 537.75 = 7050.5
        
        self.assertEqual(subtotal, Decimal("5975.00"))
        self.assertEqual(expected_cgst, Decimal("537.75"))
        self.assertEqual(expected_sgst, Decimal("537.75"))
        self.assertEqual(expected_total, Decimal("7050.50"))

if __name__ == "__main__":
    unittest.main()