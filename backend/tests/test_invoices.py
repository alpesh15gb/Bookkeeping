import sys
import os
import uuid
from datetime import date
from decimal import Decimal
import unittest

# Adjust path to import from src
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.domains.taxation.services import GSTEngine
from src.domains.taxation.einvoice_service import get_financial_year
from src.domains.accounting.services import LedgerPostingEngine, LedgerValidationError

class TestInvoiceWorkflow(unittest.TestCase):
    def test_get_financial_year_indian_fy_boundaries(self):
        self.assertEqual(get_financial_year(date(2026, 4, 1)), "202627")
        self.assertEqual(get_financial_year(date(2027, 3, 31)), "202627")
        self.assertEqual(get_financial_year(date(2026, 10, 15)), "202627")

    def test_gst_engine_intra_state(self):
        # Maharashtra (27) to Maharashtra (27) -> CGST + SGST (9% + 9% for 18% slab)
        res = GSTEngine.calculate_tax(
            origin_state_code="27",
            place_of_supply_state_code="27",
            base_amount=Decimal("10000.00"),
            gst_rate=Decimal("18.00")
        )
        self.assertEqual(res.cgst_rate, Decimal("9.00"))
        self.assertEqual(res.cgst_amount, Decimal("900.00"))
        self.assertEqual(res.sgst_rate, Decimal("9.00"))
        self.assertEqual(res.sgst_amount, Decimal("900.00"))
        self.assertEqual(res.igst_rate, Decimal("0.00"))
        self.assertEqual(res.igst_amount, Decimal("0.00"))
        self.assertEqual(res.total_amount, Decimal("11800.00"))

    def test_gst_engine_inter_state(self):
        # Maharashtra (27) to Karnataka (29) -> IGST (18% for 18% slab)
        res = GSTEngine.calculate_tax(
            origin_state_code="27",
            place_of_supply_state_code="29",
            base_amount=Decimal("10000.00"),
            gst_rate=Decimal("18.00")
        )
        self.assertEqual(res.cgst_rate, Decimal("0.00"))
        self.assertEqual(res.cgst_amount, Decimal("0.00"))
        self.assertEqual(res.sgst_rate, Decimal("0.00"))
        self.assertEqual(res.sgst_amount, Decimal("0.00"))
        self.assertEqual(res.igst_rate, Decimal("18.00"))
        self.assertEqual(res.igst_amount, Decimal("1800.00"))
        self.assertEqual(res.total_amount, Decimal("11800.00"))

    def test_gst_engine_odd_paise_cgst_sgst_split(self):
        cases = [
            (Decimal("5.05"), Decimal("2.53"), Decimal("2.52")),
            (Decimal("0.01"), Decimal("0.01"), Decimal("0.00")),
            (Decimal("101.01"), Decimal("50.51"), Decimal("50.50")),
        ]

        for gst_amount, expected_cgst, expected_sgst in cases:
            with self.subTest(gst_amount=gst_amount):
                res = GSTEngine.calculate_tax(
                    origin_state_code="27",
                    place_of_supply_state_code="27",
                    base_amount=gst_amount,
                    gst_rate=Decimal("100.00"),
                )
                self.assertEqual(res.cgst_amount, expected_cgst)
                self.assertEqual(res.sgst_amount, expected_sgst)
                self.assertEqual(res.cgst_amount + res.sgst_amount, gst_amount)

    def test_gst_engine_odd_paise_cgst_utgst_split(self):
        res = GSTEngine.calculate_tax(
            origin_state_code="04",
            place_of_supply_state_code="04",
            base_amount=Decimal("5.05"),
            gst_rate=Decimal("100.00"),
        )

        self.assertEqual(res.cgst_amount, Decimal("2.53"))
        self.assertEqual(res.utgst_amount, Decimal("2.52"))
        self.assertEqual(res.sgst_amount, Decimal("0.00"))
        self.assertEqual(res.cgst_amount + res.utgst_amount, Decimal("5.05"))

    def test_ledger_posting_balancing_error(self):
        tenant_id = uuid.uuid4()
        invoice_id = uuid.uuid4()
        customer_account = uuid.uuid4()
        sales_account = uuid.uuid4()

        # Try to post invoice where sums do not balance (LedgerPostingEngine handles correct balancing internally,
        # but let's test if we manually compile unbalanced ledger inputs)
        from src.domains.accounting.services import JournalEntryDraft, JournalLineDraft
        
        with self.assertRaises(LedgerValidationError):
            lines = [
                JournalLineDraft(customer_account, Decimal("118.00"), "DEBIT"),
                JournalLineDraft(sales_account, Decimal("100.00"), "CREDIT") # Out of balance: missing CGST/SGST lines
            ]
            JournalEntryDraft(
                tenant_id=tenant_id,
                entry_date=date.today(),
                reference_number="INV-001",
                description="Test",
                source_type="INVOICE",
                source_id=invoice_id,
                lines=lines
            )

if __name__ == "__main__":
    unittest.main()
