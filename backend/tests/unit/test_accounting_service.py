import pytest
from unittest.mock import MagicMock, patch, call
import uuid
from uuid import uuid4, UUID
from datetime import date
from decimal import Decimal

from src.domains.accounting.services import (
    LedgerValidationError,
    JournalLineDraft,
    JournalEntryDraft,
    LedgerPostingEngine,
    AccountResolver,
    _STANDARD_ACCOUNTS,
)


# =========================================================================
# JournalLineDraft
# =========================================================================

class TestJournalLineDraft:
    def test_create_valid(self):
        line = JournalLineDraft(uuid4(), Decimal("100.00"), "DEBIT", "test")
        assert line.direction == "DEBIT"
        assert line.amount == Decimal("100.00")
        assert line.narration == "test"

    def test_negative_amount_raises(self):
        with pytest.raises(LedgerValidationError, match="cannot be negative"):
            JournalLineDraft(uuid4(), Decimal("-50.00"), "DEBIT")

    def test_invalid_direction_raises(self):
        with pytest.raises(LedgerValidationError, match="must be either"):
            JournalLineDraft(uuid4(), Decimal("10.00"), "BALANCE")

    def test_amount_is_quantized(self):
        line = JournalLineDraft(uuid4(), Decimal("100.456"), "CREDIT")
        assert line.amount == Decimal("100.46")

    def test_narration_defaults_to_none(self):
        line = JournalLineDraft(uuid4(), Decimal("50.00"), "DEBIT")
        assert line.narration is None

    def test_zero_amount_allowed(self):
        line = JournalLineDraft(uuid4(), Decimal("0.00"), "DEBIT")
        assert line.amount == Decimal("0.00")


# =========================================================================
# JournalEntryDraft
# =========================================================================

class TestJournalEntryDraft:
    def test_create_valid(self):
        tid = uuid4()
        sid = uuid4()
        entry = JournalEntryDraft(
            tenant_id=tid,
            entry_date=date(2026, 5, 1),
            reference_number="JV/2026/001",
            description="Test entry",
            source_type="MANUAL",
            source_id=sid,
            lines=[
                JournalLineDraft(uuid4(), Decimal("100.00"), "DEBIT"),
                JournalLineDraft(uuid4(), Decimal("100.00"), "CREDIT"),
            ],
        )
        assert entry.tenant_id == tid
        assert entry.source_id == sid
        assert entry.reference_number == "JV/2026/001"
        assert entry.source_type == "MANUAL"

    def test_single_line_raises(self):
        with pytest.raises(LedgerValidationError, match="at least two"):
            JournalEntryDraft(
                tenant_id=uuid4(), entry_date=date.today(),
                reference_number="X", description="X",
                source_type="MANUAL", source_id=uuid4(),
                lines=[JournalLineDraft(uuid4(), Decimal("100.00"), "DEBIT")],
            )

    def test_unbalanced_raises(self):
        with pytest.raises(LedgerValidationError, match="out of balance"):
            JournalEntryDraft(
                tenant_id=uuid4(), entry_date=date.today(),
                reference_number="X", description="X",
                source_type="MANUAL", source_id=uuid4(),
                lines=[
                    JournalLineDraft(uuid4(), Decimal("100.00"), "DEBIT"),
                    JournalLineDraft(uuid4(), Decimal("50.00"), "CREDIT"),
                ],
            )

    def test_multi_line_balanced_succeeds(self):
        acc1, acc2, acc3 = uuid4(), uuid4(), uuid4()
        entry = JournalEntryDraft(
            tenant_id=uuid4(), entry_date=date.today(),
            reference_number="MULTI", description="Multi-line",
            source_type="MANUAL", source_id=uuid4(),
            lines=[
                JournalLineDraft(acc1, Decimal("500.00"), "DEBIT"),
                JournalLineDraft(acc2, Decimal("300.00"), "CREDIT"),
                JournalLineDraft(acc3, Decimal("200.00"), "CREDIT"),
            ],
        )
        assert len(entry.lines) == 3

    def test_zero_amount_lines_valid(self):
        entry = JournalEntryDraft(
            tenant_id=uuid4(), entry_date=date.today(),
            reference_number="ZERO", description="Zero",
            source_type="MANUAL", source_id=uuid4(),
            lines=[
                JournalLineDraft(uuid4(), Decimal("0.00"), "DEBIT"),
                JournalLineDraft(uuid4(), Decimal("0.00"), "CREDIT"),
            ],
        )
        assert len(entry.lines) == 2


# =========================================================================
# LedgerPostingEngine
# =========================================================================

class TestLedgerPostingEngine:
    def test_invoice_posting_no_tax(self):
        tenant_id, inv_id = uuid4(), uuid4()
        cust_acc, rev_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_invoice_posting(
            tenant_id, inv_id, "INV-001", date(2026, 5, 1),
            cust_acc, rev_acc, Decimal("1000.00"),
        )
        assert draft.source_type == "INVOICE"
        assert draft.source_id == inv_id
        assert draft.reference_number == "INV-001"
        assert len(draft.lines) == 2
        # Debit customer (receivable), Credit revenue
        assert draft.lines[0].account_id == cust_acc
        assert draft.lines[0].amount == Decimal("1000.00")
        assert draft.lines[0].direction == "DEBIT"
        assert draft.lines[1].account_id == rev_acc
        assert draft.lines[1].amount == Decimal("1000.00")
        assert draft.lines[1].direction == "CREDIT"

    def test_invoice_posting_with_tax(self):
        tenant_id, inv_id = uuid4(), uuid4()
        cust_acc, rev_acc = uuid4(), uuid4()
        cgst_acc, sgst_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_invoice_posting(
            tenant_id, inv_id, "INV-002", date(2026, 5, 1),
            cust_acc, rev_acc, Decimal("1000.00"),
            cgst_account_id=cgst_acc, cgst_amount=Decimal("90.00"),
            sgst_account_id=sgst_acc, sgst_amount=Decimal("90.00"),
        )
        assert len(draft.lines) == 4
        # Debit customer = 1000 + 90 + 90 = 1180
        assert draft.lines[0].account_id == cust_acc
        assert draft.lines[0].amount == Decimal("1180.00")
        assert draft.lines[0].direction == "DEBIT"
        # Credit revenue = 1000
        assert draft.lines[1].account_id == rev_acc
        assert draft.lines[1].amount == Decimal("1000.00")
        assert draft.lines[1].direction == "CREDIT"
        # Credit CGST = 90
        assert draft.lines[2].account_id == cgst_acc
        assert draft.lines[2].direction == "CREDIT"
        assert draft.lines[2].amount == Decimal("90.00")
        # Credit SGST = 90
        assert draft.lines[3].account_id == sgst_acc
        assert draft.lines[3].direction == "CREDIT"
        assert draft.lines[3].amount == Decimal("90.00")

    def test_invoice_posting_all_taxes(self):
        tenant_id, inv_id = uuid4(), uuid4()
        cust_acc, rev_acc = uuid4(), uuid4()
        cgst_acc, sgst_acc = uuid4(), uuid4()
        igst_acc, utgst_acc, cess_acc = uuid4(), uuid4(), uuid4()
        draft = LedgerPostingEngine.create_invoice_posting(
            tenant_id, inv_id, "INV-003", date(2026, 5, 1),
            cust_acc, rev_acc, Decimal("1000.00"),
            cgst_account_id=cgst_acc, cgst_amount=Decimal("50.00"),
            sgst_account_id=sgst_acc, sgst_amount=Decimal("50.00"),
            igst_account_id=igst_acc, igst_amount=Decimal("100.00"),
            utgst_account_id=utgst_acc, utgst_amount=Decimal("20.00"),
            cess_account_id=cess_acc, cess_amount=Decimal("10.00"),
        )
        tax_total = Decimal("50.00") * 2 + Decimal("100.00") + Decimal("20.00") + Decimal("10.00")
        invoice_total = Decimal("1000.00") + tax_total
        assert len(draft.lines) == 7
        assert draft.lines[0].amount == invoice_total
        totals = {"DEBIT": Decimal("0"), "CREDIT": Decimal("0")}
        for line in draft.lines:
            totals[line.direction] += line.amount
        assert totals["DEBIT"] == totals["CREDIT"]

    def test_bill_posting(self):
        tenant_id, bill_id = uuid4(), uuid4()
        vend_acc, purch_acc = uuid4(), uuid4()
        cgst_acc, sgst_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_bill_posting(
            tenant_id, bill_id, "BILL-001", date(2026, 5, 1),
            vend_acc, purch_acc, Decimal("8000.00"),
            cgst_account_id=cgst_acc, cgst_amount=Decimal("720.00"),
            sgst_account_id=sgst_acc, sgst_amount=Decimal("720.00"),
        )
        assert draft.source_type == "BILL"
        assert draft.source_id == bill_id
        assert len(draft.lines) == 4
        # Debit purchase expense
        assert draft.lines[0].account_id == purch_acc
        assert draft.lines[0].amount == Decimal("8000.00")
        assert draft.lines[0].direction == "DEBIT"
        # Debit CGST input
        assert draft.lines[1].account_id == cgst_acc
        assert draft.lines[1].amount == Decimal("720.00")
        assert draft.lines[1].direction == "DEBIT"
        # Debit SGST input
        assert draft.lines[2].account_id == sgst_acc
        assert draft.lines[2].amount == Decimal("720.00")
        assert draft.lines[2].direction == "DEBIT"
        # Credit vendor (payable) = 8000 + 720 + 720 = 9440
        assert draft.lines[3].account_id == vend_acc
        assert draft.lines[3].amount == Decimal("9440.00")
        assert draft.lines[3].direction == "CREDIT"

    def test_payment_receipt_posting_no_discount(self):
        tenant_id, pay_id = uuid4(), uuid4()
        bank_acc, cust_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_payment_receipt_posting(
            tenant_id, pay_id, "PAY-001", date(2026, 5, 1),
            bank_acc, cust_acc, Decimal("5000.00"),
        )
        assert draft.source_type == "PAYMENT"
        assert len(draft.lines) == 2
        # Debit bank
        assert draft.lines[0].account_id == bank_acc
        assert draft.lines[0].amount == Decimal("5000.00")
        assert draft.lines[0].direction == "DEBIT"
        # Credit customer
        assert draft.lines[1].account_id == cust_acc
        assert draft.lines[1].amount == Decimal("5000.00")
        assert draft.lines[1].direction == "CREDIT"

    def test_payment_receipt_posting_with_discount(self):
        tenant_id, pay_id = uuid4(), uuid4()
        bank_acc, cust_acc, disc_acc = uuid4(), uuid4(), uuid4()
        draft = LedgerPostingEngine.create_payment_receipt_posting(
            tenant_id, pay_id, "PAY-002", date(2026, 5, 1),
            bank_acc, cust_acc, Decimal("4800.00"),
            discount_account_id=disc_acc, discount_amount=Decimal("200.00"),
        )
        assert len(draft.lines) == 3
        # Debit bank: 4800
        assert draft.lines[0].account_id == bank_acc
        assert draft.lines[0].amount == Decimal("4800.00")
        assert draft.lines[0].direction == "DEBIT"
        # Debit discount: 200
        assert draft.lines[1].account_id == disc_acc
        assert draft.lines[1].amount == Decimal("200.00")
        assert draft.lines[1].direction == "DEBIT"
        # Credit customer: 5000
        assert draft.lines[2].account_id == cust_acc
        assert draft.lines[2].amount == Decimal("5000.00")
        assert draft.lines[2].direction == "CREDIT"

    def test_payment_out_posting(self):
        tenant_id, pay_id = uuid4(), uuid4()
        bank_acc, vend_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_payment_out_posting(
            tenant_id, pay_id, "POUT-001", date(2026, 5, 1),
            bank_acc, vend_acc, Decimal("3000.00"),
        )
        assert draft.source_type == "PAYMENT"
        assert len(draft.lines) == 2
        # Debit vendor (settle payable)
        assert draft.lines[0].account_id == vend_acc
        assert draft.lines[0].amount == Decimal("3000.00")
        assert draft.lines[0].direction == "DEBIT"
        # Credit bank
        assert draft.lines[1].account_id == bank_acc
        assert draft.lines[1].amount == Decimal("3000.00")
        assert draft.lines[1].direction == "CREDIT"

    def test_invoice_reversal_posting(self):
        tenant_id, inv_id = uuid4(), uuid4()
        cust_acc, rev_acc = uuid4(), uuid4()
        cgst_acc = uuid4()
        draft = LedgerPostingEngine.create_invoice_reversal_posting(
            tenant_id, inv_id, "INV-001", date(2026, 6, 1),
            cust_acc, rev_acc, Decimal("1000.00"),
            cgst_account_id=cgst_acc, cgst_amount=Decimal("90.00"),
        )
        assert draft.reference_number == "REV-INV-001"
        assert len(draft.lines) == 3
        # Credit customer (reverses debit)
        assert draft.lines[0].direction == "CREDIT"
        assert draft.lines[0].amount == Decimal("1090.00")
        # Debit revenue (reverses credit)
        assert draft.lines[1].direction == "DEBIT"
        assert draft.lines[1].amount == Decimal("1000.00")
        # Debit CGST (reverses credit)
        assert draft.lines[2].direction == "DEBIT"
        assert draft.lines[2].amount == Decimal("90.00")
        totals = {"DEBIT": Decimal("0"), "CREDIT": Decimal("0")}
        for line in draft.lines:
            totals[line.direction] += line.amount
        assert totals["DEBIT"] == totals["CREDIT"]

    def test_credit_note_posting(self):
        tenant_id, cn_id = uuid4(), uuid4()
        cust_acc, rev_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_credit_note_posting(
            tenant_id, cn_id, "CN-001", date(2026, 5, 1),
            cust_acc, rev_acc, Decimal("500.00"),
        )
        assert len(draft.lines) == 2
        # Credit customer (reduces receivable)
        assert draft.lines[0].direction == "CREDIT"
        assert draft.lines[0].amount == Decimal("500.00")
        # Debit revenue (reduces income)
        assert draft.lines[1].direction == "DEBIT"
        assert draft.lines[1].amount == Decimal("500.00")

    def test_debit_note_posting(self):
        tenant_id, dn_id = uuid4(), uuid4()
        cust_acc, rev_acc = uuid4(), uuid4()
        draft = LedgerPostingEngine.create_debit_note_posting(
            tenant_id, dn_id, "DN-001", date(2026, 5, 1),
            cust_acc, rev_acc, Decimal("750.00"),
        )
        assert len(draft.lines) == 2
        # Debit customer (increases receivable)
        assert draft.lines[0].direction == "DEBIT"
        assert draft.lines[0].amount == Decimal("750.00")
        # Credit revenue (increases income)
        assert draft.lines[1].direction == "CREDIT"
        assert draft.lines[1].amount == Decimal("750.00")


# =========================================================================
# AccountResolver
# =========================================================================

class TestAccountResolver:
    """Unit tests for AccountResolver with mocked DB session."""

    @pytest.fixture
    def resolver(self):
        db = MagicMock()
        return AccountResolver(db, uuid4())

    # --- Standard accounts ---

    def test_resolve_standard_auto_creates(self, resolver):
        """resolve('sales_revenue') with no existing account creates one."""
        resolver.db.query.return_value.filter.return_value.first.return_value = None

        result = resolver.resolve("sales_revenue")

        assert result is not None
        assert isinstance(result, UUID)
        # The deterministic ID should be uuid5 of "account.sales_revenue"
        expected = uuid.uuid5(uuid.NAMESPACE_DNS, "account.sales_revenue")
        assert result == expected
        # Should have called db.add and db.flush
        resolver.db.add.assert_called_once()
        resolver.db.flush.assert_called_once()

    def test_resolve_standard_returns_existing(self, resolver):
        """resolve('sales_revenue') with existing account returns without creating."""
        existing_id = uuid4()
        fake_account = MagicMock()
        fake_account.id = existing_id
        resolver.db.query.return_value.filter.return_value.first.return_value = fake_account

        result = resolver.resolve("sales_revenue")

        assert result == existing_id
        resolver.db.add.assert_not_called()
        resolver.db.flush.assert_not_called()

    def test_resolve_unknown_key_raises(self, resolver):
        """resolve('bogus') raises LedgerValidationError."""
        resolver.db.query.return_value.filter.return_value.first.return_value = None

        with pytest.raises(LedgerValidationError, match="Unknown standard account"):
            resolver.resolve("bogus")

    def test_resolve_standard_cached(self, resolver):
        """Second call to resolve('sales_revenue') uses cache, no DB query."""
        resolver.db.query.return_value.filter.return_value.first.return_value = None

        resolver.resolve("sales_revenue")  # first call — creates
        resolver.db.reset_mock()
        resolver.resolve("sales_revenue")  # second call — cached

        resolver.db.query.assert_not_called()
        resolver.db.add.assert_not_called()
        resolver.db.flush.assert_not_called()

    def test_auto_created_account_has_correct_fields(self, resolver):
        resolver.db.query.return_value.filter.return_value.first.return_value = None

        resolver.resolve("assets.cash")

        # Verify the Account was constructed with correct defaults
        added_account = resolver.db.add.call_args[0][0]
        assert added_account.account_type == "ASSET"
        assert added_account.name == "Cash"
        assert added_account.code == "1200"
        assert added_account.is_active is True
        assert added_account.tenant_id == resolver.tenant_id

    # --- Contact accounts ---

    def test_resolve_customer_auto_creates(self, resolver):
        """resolve('customer.<uuid>') with existing contact creates AR account."""
        contact_id = uuid4()
        # First query (contact lookup) returns a contact
        fake_contact = MagicMock()
        fake_contact.name = "Acme Corp"
        # Second query (existing account check) returns None
        resolver.db.query.return_value.filter.return_value.first.side_effect = [fake_contact, None]

        result = resolver.resolve(f"customer.{contact_id}")

        assert result is not None
        assert isinstance(result, UUID)
        resolver.db.add.assert_called_once()
        resolver.db.flush.assert_called_once()

    def test_resolve_customer_account_correct_fields(self, resolver):
        contact_id = uuid4()
        fake_contact = MagicMock()
        fake_contact.name = "Acme Corp"
        resolver.db.query.return_value.filter.return_value.first.side_effect = [fake_contact, None]

        resolver.resolve(f"customer.{contact_id}")

        added = resolver.db.add.call_args[0][0]
        assert added.account_type == "ASSET"
        assert "Acme Corp" in added.name
        assert added.code.startswith("AR-")
        assert added.is_active is True

    def test_resolve_vendor_auto_creates(self, resolver):
        """resolve('vendor.<uuid>') with existing contact creates AP account."""
        contact_id = uuid4()
        fake_contact = MagicMock()
        fake_contact.name = "Supplier Inc"
        resolver.db.query.return_value.filter.return_value.first.side_effect = [fake_contact, None]

        result = resolver.resolve(f"vendor.{contact_id}")

        assert result is not None
        added = resolver.db.add.call_args[0][0]
        assert added.account_type == "LIABILITY"
        assert "Supplier Inc" in added.name
        assert added.code.startswith("AP-")

    def test_resolve_customer_contact_not_found_raises(self, resolver):
        """resolve('customer.<uuid>') with non-existent contact raises error."""
        contact_id = uuid4()
        resolver.db.query.return_value.filter.return_value.first.return_value = None

        with pytest.raises(LedgerValidationError, match="not found"):
            resolver.resolve(f"customer.{contact_id}")

    def test_resolve_contact_invalid_uuid_raises(self, resolver):
        """resolve with invalid UUID in key raises error."""
        with pytest.raises(LedgerValidationError, match="Invalid contact UUID"):
            resolver.resolve("customer.not-a-uuid")

    def test_resolve_contact_account_cached(self, resolver):
        """Second call for same customer uses cache."""
        contact_id = uuid4()
        fake_contact = MagicMock()
        fake_contact.name = "Acme Corp"
        resolver.db.query.return_value.filter.return_value.first.side_effect = [fake_contact, None]

        resolver.resolve(f"customer.{contact_id}")
        resolver.db.reset_mock()

        resolver.resolve(f"customer.{contact_id}")  # cached
        resolver.db.query.assert_not_called()
        resolver.db.add.assert_not_called()

    # --- Cross-key cache independence ---

    def test_different_keys_independent_cache(self, resolver):
        """Resolving different keys queries DB for each."""
        resolver.db.query.return_value.filter.return_value.first.return_value = None
        resolver.resolve("sales_revenue")
        resolver.db.reset_mock()

        resolver.db.query.return_value.filter.return_value.first.return_value = None
        resolver.resolve("purchases")
        resolver.db.query.assert_called_once()


# =========================================================================
# _STANDARD_ACCOUNTS data integrity
# =========================================================================

class TestStandardAccountsData:
    def test_all_accounts_have_required_fields(self):
        for key, defn in _STANDARD_ACCOUNTS.items():
            assert "code" in defn, f"{key} missing code"
            assert "name" in defn, f"{key} missing name"
            assert "type" in defn, f"{key} missing type"
            assert defn["type"] in ("ASSET", "LIABILITY", "REVENUE", "EXPENSE", "EQUITY")

    def test_codes_are_unique(self):
        codes = [defn["code"] for defn in _STANDARD_ACCOUNTS.values()]
        assert len(codes) == len(set(codes)), "Duplicate account codes found"

    def test_revenue_and_expense_accounts_present(self):
        types = {defn["type"] for defn in _STANDARD_ACCOUNTS.values()}
        assert "REVENUE" in types
        assert "EXPENSE" in types

    def test_tax_accounts_have_both_input_and_output(self):
        tax_types = {"cgst", "sgst", "igst", "utgst", "cess"}
        found = {k.split("_")[0] for k in _STANDARD_ACCOUNTS}
        assert tax_types.issubset(found), f"Missing tax types: {tax_types - found}"

    def test_asset_accounts_present(self):
        asset_keys = {"assets.cash", "assets.bank", "assets.upi", "assets.pos"}
        assert asset_keys.issubset(_STANDARD_ACCOUNTS.keys())
