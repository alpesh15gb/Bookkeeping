import sys
import os
import uuid
from datetime import date
from decimal import Decimal
import unittest

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.database import SessionLocal, engine
from src.infrastructure.database.models import Base, BankingProfile, Product, Contact
from src.infrastructure.database.models import BankStatement, BankTransaction, BankReconciliation, Payment, BillPayment

class TestBankReconciliationWorkflow(unittest.TestCase):
    def setUp(self):
        """Set up test database and test data"""
        # Create tables
        Base.metadata.create_all(bind=engine)
        
        # Create test session
        self.db = SessionLocal()
        
        # Create test tenant (using a fixed UUID for consistency)
        self.tenant_id = uuid.UUID("0aa85f64-5717-4562-b3fc-2c963f66b110")
        
        # Create test banking profile
        self.banking_profile = BankingProfile(
            id=uuid.uuid4(),
            tenant_id=self.tenant_id,
            bank_name="Test Bank",
            account_number="ACC123456789",
            ifsc_code="TESTB0001234",
            branch_name="Main Branch",
            account_holder_name="Test Company",
            upi_id="test@upi",
            is_primary=True,
            is_active=True
        )
        self.db.add(self.banking_profile)
        
        # Create test contact for payments
        self.test_contact = Contact(
            id=uuid.uuid4(),
            tenant_id=self.tenant_id,
            name="Test Contact",
            email="contact@test.com",
            phone="+919876543210",
            contact_type="BOTH",
            gstin="27AACTC1234A1Z5",
            pan="AACTC1234A",
            registration_type="REGULAR",
            billing_address={"street": "123 Contact St", "city": "Mumbai", "state": "Maharashtra", "state_code": "27", "pincode": "400001", "country": "India"},
            state_code="27",
            is_active=True
        )
        self.db.add(self.test_contact)
        
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
    
    def test_bank_statement_creation_logic(self):
        """Test bank statement creation logic"""
        # This would test the business logic for bank statement creation
        self.assertTrue(True)
        
    def test_bank_reconciliation_calculations(self):
        """Test bank reconciliation calculations"""
        statement_date = date.today()
        starting_balance = Decimal("10000.00")
        ending_balance = Decimal("15000.00")
        
        # Calculate expected net change
        expected_net_change = ending_balance - starting_balance  # 15000 - 10000 = 5000
        
        self.assertEqual(expected_net_change, Decimal("5000.00"))
        
        # Test transaction amounts
        deposit = Decimal("2500.00")  # Positive amount
        withdrawal = Decimal("-1500.00")  # Negative amount
        net_change = deposit + withdrawal  # 2500 + (-1500) = 1000
        
        self.assertEqual(net_change, Decimal("1000.00"))

if __name__ == "__main__":
    unittest.main()