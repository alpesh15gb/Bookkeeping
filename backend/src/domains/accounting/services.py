from decimal import Decimal
from typing import List, Optional, Dict
from datetime import date
import uuid
from sqlalchemy.orm import Session
from sqlalchemy import func

class LedgerValidationError(Exception):
    """Raised when double-entry rules or compliance requirements are violated."""
    pass

class JournalLineDraft:
    def __init__(self, account_id: uuid.UUID, amount: Decimal, direction: str, narration: Optional[str] = None):
        if amount < Decimal("0.00"):
            raise LedgerValidationError("Journal Line amount cannot be negative.")
        if direction not in ("DEBIT", "CREDIT"):
            raise LedgerValidationError("Direction must be either DEBIT or CREDIT.")
        
        self.account_id = account_id
        self.amount = amount.quantize(Decimal("0.01"))
        self.direction = direction
        self.narration = narration

class JournalEntryDraft:
    def __init__(
        self,
        tenant_id: uuid.UUID,
        entry_date: date,
        reference_number: str,
        description: str,
        source_type: str,
        source_id: uuid.UUID,
        lines: List[JournalLineDraft]
    ):
        self.tenant_id = tenant_id
        self.entry_date = entry_date
        self.reference_number = reference_number
        self.description = description
        self.source_type = source_type
        self.source_id = source_id
        self.lines = lines
        self.validate()

    def validate(self) -> None:
        """Enforces that Sum(Debits) == Sum(Credits) and lines contain at least two entries."""
        if len(self.lines) < 2:
            raise LedgerValidationError("A double-entry Journal Entry must contain at least two lines.")

        debit_sum = sum(line.amount for line in self.lines if line.direction == "DEBIT")
        credit_sum = sum(line.amount for line in self.lines if line.direction == "CREDIT")

        if debit_sum != credit_sum:
            raise LedgerValidationError(
                f"Ledger out of balance. Debits ({debit_sum}) must equal Credits ({credit_sum}). "
                f"Diff: {debit_sum - credit_sum}"
            )


class LedgerPostingEngine:
    """
    Double-Entry Accounting Posting Engine.
    Translates operations from Billing, Purchasing, and Payments into Journal Entries.
    """

    @staticmethod
    def create_invoice_posting(
        tenant_id: uuid.UUID,
        invoice_id: uuid.UUID,
        invoice_number: str,
        invoice_date: date,
        customer_account_id: uuid.UUID,
        sales_revenue_account_id: uuid.UUID,
        subtotal: Decimal,
        cgst_account_id: Optional[uuid.UUID] = None,
        cgst_amount: Decimal = Decimal("0.00"),
        sgst_account_id: Optional[uuid.UUID] = None,
        sgst_amount: Decimal = Decimal("0.00"),
        igst_account_id: Optional[uuid.UUID] = None,
        igst_amount: Decimal = Decimal("0.00"),
        utgst_account_id: Optional[uuid.UUID] = None,
        utgst_amount: Decimal = Decimal("0.00"),
        cess_account_id: Optional[uuid.UUID] = None,
        cess_amount: Decimal = Decimal("0.00"),
        round_off_account_id: Optional[uuid.UUID] = None,
        round_off_amount: Decimal = Decimal("0.00"),
        is_rcm: bool = False
    ) -> JournalEntryDraft:
        """
        Generates Double Entry Posting for Sales Invoices (Receivables).

        Under Reverse Charge Mechanism (is_rcm=True), the buyer self-assesses
        the GST, so no output tax accounts are credited by the seller.
        """
        lines: List[JournalLineDraft] = []

        if is_rcm:
            # RCM: seller invoices subtotal only — buyer accounts for tax
            invoice_total = subtotal
            lines.append(JournalLineDraft(customer_account_id, invoice_total, "DEBIT", f"Receivable (RCM): {invoice_number}"))
            lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "CREDIT", f"Sales Revenue (RCM): {invoice_number}"))
        else:
            tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
            invoice_total = subtotal + tax_total

            lines.append(JournalLineDraft(customer_account_id, invoice_total, "DEBIT", f"Receivable: {invoice_number}"))
            lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "CREDIT", f"Sales Revenue: {invoice_number}"))

            if cgst_amount > 0 and cgst_account_id:
                lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "CREDIT", "CGST Output"))
            if sgst_amount > 0 and sgst_account_id:
                lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "CREDIT", "SGST Output"))
            if igst_amount > 0 and igst_account_id:
                lines.append(JournalLineDraft(igst_account_id, igst_amount, "CREDIT", "IGST Output"))
            if utgst_amount > 0 and utgst_account_id:
                lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "CREDIT", "UTGST Output"))
            if cess_amount > 0 and cess_account_id:
                lines.append(JournalLineDraft(cess_account_id, cess_amount, "CREDIT", "Cess Output"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {invoice_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {invoice_number}"))
            else:
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {invoice_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {invoice_number}"))

        return JournalEntryDraft(tenant_id, invoice_date, invoice_number, f"Ledger posting for Sales invoice {invoice_number}", "INVOICE", invoice_id, lines)

    @staticmethod
    def create_bill_posting(
        tenant_id: uuid.UUID,
        bill_id: uuid.UUID,
        bill_number: str,
        bill_date: date,
        vendor_account_id: uuid.UUID,
        purchase_expense_account_id: uuid.UUID,
        subtotal: Decimal,
        cgst_account_id: Optional[uuid.UUID] = None,
        cgst_amount: Decimal = Decimal("0.00"),
        sgst_account_id: Optional[uuid.UUID] = None,
        sgst_amount: Decimal = Decimal("0.00"),
        igst_account_id: Optional[uuid.UUID] = None,
        igst_amount: Decimal = Decimal("0.00"),
        utgst_account_id: Optional[uuid.UUID] = None,
        utgst_amount: Decimal = Decimal("0.00"),
        cess_account_id: Optional[uuid.UUID] = None,
        cess_amount: Decimal = Decimal("0.00")
    ) -> JournalEntryDraft:
        """
        Generates Double Entry Posting for Purchase Bills (Payables).
        
        Debits:
          - Purchase Expense A/c (Inventory/COGS) -> Subtotal
          - Input Tax Accounts (CGST, SGST, IGST, etc.) -> tax splits
        Credits:
          - Vendor A/c (Accounts Payable) -> Bill Total
        """
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        bill_total = subtotal + tax_total

        # 1. Debit Purchase Expense
        lines.append(JournalLineDraft(purchase_expense_account_id, subtotal, "DEBIT", f"Expense: Bill {bill_number}"))

        # 2. Debit Input Tax Accounts (ITC Eligible)
        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "DEBIT", "CGST Input Tax"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "DEBIT", "SGST Input Tax"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "DEBIT", "IGST Input Tax"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "DEBIT", "UTGST Input Tax"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "DEBIT", "Cess Input Tax"))

        # 3. Credit Accounts Payable
        lines.append(JournalLineDraft(vendor_account_id, bill_total, "CREDIT", f"Payable: Bill {bill_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=bill_date,
            reference_number=bill_number,
            description=f"Ledger posting for vendor bill {bill_number}",
            source_type="BILL",
            source_id=bill_id,
            lines=lines
        )

    @staticmethod
    def create_expense_posting(
        tenant_id: uuid.UUID,
        expense_id: uuid.UUID,
        expense_number: str,
        expense_date: date,
        expense_account_id: uuid.UUID,
        cash_account_id: uuid.UUID,
        amount: Decimal,
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        lines.append(JournalLineDraft(expense_account_id, amount, "DEBIT", f"Expense recorded: {expense_number}"))
        lines.append(JournalLineDraft(cash_account_id, amount, "CREDIT", f"Cash/Bank used for: {expense_number}"))
        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=expense_date,
            reference_number=expense_number,
            description=f"Ledger posting for expense {expense_number}",
            source_type="EXPENSE",
            source_id=expense_id,
            lines=lines
        )

    @staticmethod
    def create_payment_receipt_posting(
        tenant_id: uuid.UUID,
        payment_id: uuid.UUID,
        payment_number: str,
        payment_date: date,
        bank_or_cash_account_id: uuid.UUID,
        customer_account_id: uuid.UUID,
        amount: Decimal,
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        lines.append(JournalLineDraft(bank_or_cash_account_id, amount, "DEBIT", f"Payment received: {payment_number}"))
        lines.append(JournalLineDraft(customer_account_id, amount, "CREDIT", f"Payment received: {payment_number}"))
        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=payment_date,
            reference_number=payment_number,
            description=f"Payment receipt {payment_number}",
            source_type="PAYMENT",
            source_id=payment_id,
            lines=lines
        )

    @staticmethod
    def create_payment_out_posting(
        tenant_id: uuid.UUID,
        payment_id: uuid.UUID,
        payment_number: str,
        payment_date: date,
        bank_or_cash_account_id: uuid.UUID,
        vendor_account_id: uuid.UUID,
        amount: Decimal,
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        lines.append(JournalLineDraft(vendor_account_id, amount, "DEBIT", f"Payment made: {payment_number}"))
        lines.append(JournalLineDraft(bank_or_cash_account_id, amount, "CREDIT", f"Payment made: {payment_number}"))
        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=payment_date,
            reference_number=payment_number,
            description=f"Vendor payment {payment_number}",
            source_type="PAYMENT",
            source_id=payment_id,
            lines=lines
        )

    @staticmethod
    def create_credit_note_posting(
        tenant_id: uuid.UUID,
        credit_note_id: uuid.UUID,
        credit_note_number: str,
        issue_date: date,
        customer_account_id: uuid.UUID,
        sales_revenue_account_id: uuid.UUID,
        subtotal: Decimal,
        cgst_account_id: Optional[uuid.UUID] = None,
        cgst_amount: Decimal = Decimal("0.00"),
        sgst_account_id: Optional[uuid.UUID] = None,
        sgst_amount: Decimal = Decimal("0.00"),
        igst_account_id: Optional[uuid.UUID] = None,
        igst_amount: Decimal = Decimal("0.00"),
        utgst_account_id: Optional[uuid.UUID] = None,
        utgst_amount: Decimal = Decimal("0.00"),
        cess_account_id: Optional[uuid.UUID] = None,
        cess_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        cn_total = subtotal + tax_total

        lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "DEBIT", f"Credit Note: {credit_note_number}"))
        lines.append(JournalLineDraft(customer_account_id, cn_total, "CREDIT", f"Credit Note: {credit_note_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "DEBIT", "CGST Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "DEBIT", "SGST Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "DEBIT", "IGST Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "DEBIT", "UTGST Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "DEBIT", "Cess Reversal"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=issue_date,
            reference_number=credit_note_number,
            description=f"Credit Note {credit_note_number}",
            source_type="CREDIT_NOTE",
            source_id=credit_note_id,
            lines=lines
        )

    @staticmethod
    def create_debit_note_posting(
        tenant_id: uuid.UUID,
        debit_note_id: uuid.UUID,
        debit_note_number: str,
        issue_date: date,
        customer_account_id: uuid.UUID,
        sales_revenue_account_id: uuid.UUID,
        subtotal: Decimal,
        cgst_account_id: Optional[uuid.UUID] = None,
        cgst_amount: Decimal = Decimal("0.00"),
        sgst_account_id: Optional[uuid.UUID] = None,
        sgst_amount: Decimal = Decimal("0.00"),
        igst_account_id: Optional[uuid.UUID] = None,
        igst_amount: Decimal = Decimal("0.00"),
        utgst_account_id: Optional[uuid.UUID] = None,
        utgst_amount: Decimal = Decimal("0.00"),
        cess_account_id: Optional[uuid.UUID] = None,
        cess_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        dn_total = subtotal + tax_total

        lines.append(JournalLineDraft(customer_account_id, dn_total, "DEBIT", f"Debit Note: {debit_note_number}"))
        lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "CREDIT", f"Debit Note: {debit_note_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "CREDIT", "CGST Adjustment"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "CREDIT", "SGST Adjustment"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "CREDIT", "IGST Adjustment"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "CREDIT", "UTGST Adjustment"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "CREDIT", "Cess Adjustment"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=issue_date,
            reference_number=debit_note_number,
            description=f"Debit Note {debit_note_number}",
            source_type="DEBIT_NOTE",
            source_id=debit_note_id,
            lines=lines
        )

    @staticmethod
    def create_invoice_reversal_posting(
        tenant_id: uuid.UUID,
        invoice_id: uuid.UUID,
        invoice_number: str,
        cancel_date: date,
        customer_account_id: uuid.UUID,
        sales_revenue_account_id: uuid.UUID,
        subtotal: Decimal,
        cgst_account_id: Optional[uuid.UUID] = None,
        cgst_amount: Decimal = Decimal("0.00"),
        sgst_account_id: Optional[uuid.UUID] = None,
        sgst_amount: Decimal = Decimal("0.00"),
        igst_account_id: Optional[uuid.UUID] = None,
        igst_amount: Decimal = Decimal("0.00"),
        utgst_account_id: Optional[uuid.UUID] = None,
        utgst_amount: Decimal = Decimal("0.00"),
        cess_account_id: Optional[uuid.UUID] = None,
        cess_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        total = subtotal + tax_total

        lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "DEBIT", f"Cancellation: {invoice_number}"))
        lines.append(JournalLineDraft(customer_account_id, total, "CREDIT", f"Cancellation: {invoice_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "DEBIT", "CGST Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "DEBIT", "SGST Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "DEBIT", "IGST Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "DEBIT", "UTGST Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "DEBIT", "Cess Reversal"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{invoice_number}",
            description=f"Reversal of invoice {invoice_number}",
            source_type="INVOICE",
            source_id=invoice_id,
            lines=lines
        )


# ---------------------------------------------------------------------------
# Standard Chart of Accounts
# ---------------------------------------------------------------------------
_STANDARD_ACCOUNTS: Dict[str, Dict[str, str]] = {
    "sales_revenue": {"name": "Sales Revenue", "code": "SRV", "type": "REVENUE"},
    "purchases": {"name": "Purchases", "code": "PUR", "type": "EXPENSE"},
    "cgst_output": {"name": "CGST Output Tax", "code": "CGST-OUT", "type": "LIABILITY"},
    "sgst_output": {"name": "SGST Output Tax", "code": "SGST-OUT", "type": "LIABILITY"},
    "igst_output": {"name": "IGST Output Tax", "code": "IGST-OUT", "type": "LIABILITY"},
    "utgst_output": {"name": "UTGST Output Tax", "code": "UTGST-OUT", "type": "LIABILITY"},
    "cess_output": {"name": "Cess Output Tax", "code": "CESS-OUT", "type": "LIABILITY"},
    "cgst_input": {"name": "CGST Input Tax", "code": "CGST-IN", "type": "ASSET"},
    "sgst_input": {"name": "SGST Input Tax", "code": "SGST-IN", "type": "ASSET"},
    "igst_input": {"name": "IGST Input Tax", "code": "IGST-IN", "type": "ASSET"},
    "utgst_input": {"name": "UTGST Input Tax", "code": "UTGST-IN", "type": "ASSET"},
    "cess_input": {"name": "Cess Input Tax", "code": "CESS-IN", "type": "ASSET"},
    "assets.cash": {"name": "Cash on Hand", "code": "CASH", "type": "ASSET"},
    "assets.bank": {"name": "Bank Account", "code": "BANK", "type": "ASSET"},
    "assets.upi": {"name": "UPI Collections", "code": "UPI", "type": "ASSET"},
    "assets.pos": {"name": "POS Collections", "code": "POS", "type": "ASSET"},
    "round_off": {"name": "Round Off Account", "code": "ROF", "type": "EXPENSE"},
}


class AccountResolver:
    """
    Resolves well-known account keys to tenant-scoped Account IDs,
    auto-creating Account records on first use.

    Standard keys: ``sales_revenue``, ``purchases``, ``cgst_output``,
    ``sgst_output``, ``igst_output``, ``utgst_output``, ``cess_output``,
    ``cgst_input``, ``sgst_input``, ``igst_input``, ``utgst_input``,
    ``cess_input``, ``assets.cash``, ``assets.bank``, ``assets.upi``,
    ``assets.pos``.

    Per-contact keys (prefixed with ``customer.`` or ``vendor.``):
    ``customer.<contact_id>``, ``vendor.<contact_id>``.
    """

    def __init__(self, db: Session, tenant_id: uuid.UUID):
        self.db = db
        self.tenant_id = tenant_id
        self._cache: Dict[str, uuid.UUID] = {}

    def resolve(self, key: str) -> uuid.UUID:
        cached = self._cache.get(key)
        if cached is not None:
            return cached

        if key.startswith("customer.") or key.startswith("vendor."):
            account_id = self._resolve_contact_account(key)
        else:
            account_id = self._resolve_standard(key)

        self._cache[key] = account_id
        return account_id

    # ------------------------------------------------------------------
    # Standard accounts
    # ------------------------------------------------------------------
    def _resolve_standard(self, key: str) -> uuid.UUID:
        from src.infrastructure.database.models import Account

        definition = _STANDARD_ACCOUNTS.get(key)
        if definition is None:
            raise LedgerValidationError(f"Unknown standard account key: {key}")

        account_id = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.{key}")
        existing = self.db.query(Account).filter(
            Account.id == account_id,
            Account.tenant_id == self.tenant_id,
            Account.deleted_at == None,
        ).first()
        if existing is not None:
            return existing.id

        account = Account(
            id=account_id,
            tenant_id=self.tenant_id,
            name=definition["name"],
            code=definition["code"],
            account_type=definition["type"],
            is_active=True,
        )
        self.db.add(account)
        self.db.flush()
        return account.id

    # ------------------------------------------------------------------
    # Per-contact accounts (Accounts Receivable / Accounts Payable)
    # ------------------------------------------------------------------
    def _resolve_contact_account(self, key: str) -> uuid.UUID:
        from src.infrastructure.database.models import Account, Contact

        parts = key.split(".", 1)
        if len(parts) != 2:
            raise LedgerValidationError(f"Invalid contact account key: {key}")
        prefix, contact_id_str = parts

        try:
            contact_uuid = uuid.UUID(contact_id_str)
        except ValueError:
            raise LedgerValidationError(f"Invalid contact UUID in account key: {key}")

        contact = self.db.query(Contact).filter(
            Contact.id == contact_uuid,
            Contact.tenant_id == self.tenant_id,
            Contact.deleted_at == None,
        ).first()
        if not contact:
            raise LedgerValidationError(f"Contact not found for account key: {key}")

        if prefix == "customer":
            account_name = f"Accounts Receivable - {contact.name}"
            account_code = f"AR-{contact_uuid}"
            account_type = "ASSET"
        elif prefix == "vendor":
            account_name = f"Accounts Payable - {contact.name}"
            account_code = f"AP-{contact_uuid}"
            account_type = "LIABILITY"
        else:
            raise LedgerValidationError(f"Unknown contact prefix in account key: {key}")

        account_id = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.{key}-{self.tenant_id}")
        existing = self.db.query(Account).filter(
            Account.id == account_id,
            Account.tenant_id == self.tenant_id,
            Account.deleted_at == None,
        ).first()
        if existing is not None:
            return existing.id

        account = Account(
            id=account_id,
            tenant_id=self.tenant_id,
            name=account_name,
            code=account_code,
            account_type=account_type,
            is_active=True,
        )
        self.db.add(account)
        self.db.flush()
        return account.id


def update_account_balances(db: Session, tenant_id: uuid.UUID, account_ids: Optional[set[uuid.UUID]] = None) -> None:
    """
    Recalculates and sets current_balance for the given account IDs directly
    from the journal_lines table, using a pessimistic lock for safety.
    If account_ids is None, recalculates ALL accounts for the tenant.
    """
    from src.infrastructure.database.models import Account, JournalLine

    if account_ids is not None and not account_ids:
        return

    query = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.deleted_at == None
    ).with_for_update()

    if account_ids:
        query = query.filter(Account.id.in_(account_ids))

    accounts = query.all()

    for account in accounts:
        # Compute net balance: sum(DEBIT) - sum(CREDIT) for ASSET/EXPENSE,
        # sum(CREDIT) - sum(DEBIT) for everything else.
        debit_sum = db.query(func.sum(JournalLine.amount)).filter(
            JournalLine.account_id == account.id,
            JournalLine.direction == "DEBIT"
        ).scalar() or Decimal("0.0000")

        credit_sum = db.query(func.sum(JournalLine.amount)).filter(
            JournalLine.account_id == account.id,
            JournalLine.direction == "CREDIT"
        ).scalar() or Decimal("0.0000")

        if account.account_type in ("ASSET", "EXPENSE"):
            account.current_balance = (debit_sum - credit_sum).quantize(Decimal("0.0001"))
        else:
            account.current_balance = (credit_sum - debit_sum).quantize(Decimal("0.0001"))

    db.flush()


def recalculate_all_account_balances(db: Session, tenant_id: uuid.UUID) -> None:
    """
    Recalculates and updates current_balance for ALL accounts belonging to a tenant.
    Use this during reconciliation or after bulk imports.
    """
    from src.infrastructure.database.models import Account, JournalLine, JournalEntry

    # Compute balances from journal lines
    subq = db.query(
        JournalLine.account_id,
        func.sum(
            func.case(
                (JournalLine.direction == "DEBIT", JournalLine.amount),
                else_=-JournalLine.amount
            )
        ).label("balance")
    ).join(
        JournalEntry, JournalLine.entry_id == JournalEntry.id
    ).filter(
        JournalEntry.tenant_id == tenant_id
    ).group_by(
        JournalLine.account_id
    ).subquery()

    accounts = db.query(Account).filter(
        Account.tenant_id == tenant_id,
        Account.deleted_at == None
    ).with_for_update().all()

    balance_map = {row.account_id: (row.balance or Decimal("0.0000")) for row in db.query(subq).all()}

    for account in accounts:
        account.current_balance = balance_map.get(account.id, Decimal("0.0000")).quantize(Decimal("0.0001"))

    db.commit()
