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
        if amount <= Decimal("0.00"):
            raise LedgerValidationError("Journal Line amount must be greater than zero.")
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

        diff = abs(debit_sum - credit_sum)
        if diff > Decimal("0.00"):
            raise LedgerValidationError(
                f"Ledger out of balance. Debits ({debit_sum}) must equal Credits ({credit_sum}). "
                f"Diff: {diff}"
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
        discount_total: Decimal = Decimal("0.00"),
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
        net_subtotal = subtotal - discount_total

        if is_rcm:
            # RCM: seller invoices subtotal only — buyer accounts for tax
            invoice_total = net_subtotal
            lines.append(JournalLineDraft(customer_account_id, invoice_total, "DEBIT", f"Receivable (RCM): {invoice_number}"))
            lines.append(JournalLineDraft(sales_revenue_account_id, net_subtotal, "CREDIT", f"Sales Revenue (RCM): {invoice_number}"))
        else:
            tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
            # Customer is debited for subtotal + taxes. Round-off handled separately below.
            invoice_total = net_subtotal + tax_total

            lines.append(JournalLineDraft(customer_account_id, invoice_total, "DEBIT", f"Receivable: {invoice_number}"))
            lines.append(JournalLineDraft(sales_revenue_account_id, net_subtotal, "CREDIT", f"Sales Revenue: {invoice_number}"))

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
                # Customer pays MORE; increase receivable (debit customer)
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {invoice_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {invoice_number}"))
            else:
                # Customer pays LESS; decrease receivable (credit customer)
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {invoice_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {invoice_number}"))

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
        discount_total: Decimal = Decimal("0.00"),
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
        tds_account_id: Optional[uuid.UUID] = None,
        tds_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        """
        Generates Double Entry Posting for Purchase Bills (Payables).
        
        Debits:
          - Purchase Expense A/c (Inventory/COGS) -> Subtotal net of discount
          - Input Tax Accounts (CGST, SGST, IGST, etc.) -> tax splits
        Credits:
          - Vendor A/c (Accounts Payable) -> Bill Total minus TDS
          - TDS Payable A/c -> TDS deducted at source
        """
        lines: List[JournalLineDraft] = []
        net_subtotal = subtotal - discount_total
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        bill_total = net_subtotal + tax_total
        vendor_payable = bill_total - tds_amount

        # 1. Debit Purchase Expense (net of discount)
        lines.append(JournalLineDraft(purchase_expense_account_id, net_subtotal, "DEBIT", f"Expense: Bill {bill_number}"))

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

        # 3. Credit Accounts Payable (reduced by TDS)
        lines.append(JournalLineDraft(vendor_account_id, vendor_payable, "CREDIT", f"Payable: Bill {bill_number}"))

        # 4. Credit TDS Payable (if TDS deducted)
        if tds_amount > 0 and tds_account_id:
            lines.append(JournalLineDraft(tds_account_id, tds_amount, "CREDIT", f"TDS Deducted: Bill {bill_number}"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                # We pay MORE; increase payable (credit vendor)
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {bill_number}"))
                lines.append(JournalLineDraft(vendor_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {bill_number}"))
            else:
                # We pay LESS; decrease payable (debit vendor)
                lines.append(JournalLineDraft(vendor_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {bill_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {bill_number}"))

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
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        total = amount + tax_total

        lines.append(JournalLineDraft(expense_account_id, amount, "DEBIT", f"Expense: {expense_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "DEBIT", "CGST Input"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "DEBIT", "SGST Input"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "DEBIT", "IGST Input"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "DEBIT", "UTGST Input"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "DEBIT", "Cess Input"))

        lines.append(JournalLineDraft(cash_account_id, total, "CREDIT", f"Cash/Bank: {expense_number}"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {expense_number}"))
                lines.append(JournalLineDraft(cash_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {expense_number}"))
            else:
                lines.append(JournalLineDraft(cash_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {expense_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {expense_number}"))

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
    def create_expense_reversal_posting(
        tenant_id: uuid.UUID,
        expense_id: uuid.UUID,
        expense_number: str,
        cancel_date: date,
        expense_account_id: uuid.UUID,
        cash_account_id: uuid.UUID,
        amount: Decimal,
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
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        total = amount + tax_total

        lines.append(JournalLineDraft(cash_account_id, total, "DEBIT", f"Expense reversal: {expense_number}"))
        lines.append(JournalLineDraft(expense_account_id, amount, "CREDIT", f"Expense reversal: {expense_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "CREDIT", "CGST Input Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "CREDIT", "SGST Input Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "CREDIT", "IGST Input Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "CREDIT", "UTGST Input Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "CREDIT", "Cess Input Reversal"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(cash_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {expense_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {expense_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {expense_number}"))
                lines.append(JournalLineDraft(cash_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {expense_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{expense_number}",
            description=f"Reversal of expense {expense_number}",
            source_type="EXPENSE_REVERSAL",
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
        round_off_account_id: Optional[uuid.UUID] = None,
        round_off_amount: Decimal = Decimal("0.00"),
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

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {credit_note_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {credit_note_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {credit_note_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {credit_note_number}"))

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
        round_off_account_id: Optional[uuid.UUID] = None,
        round_off_amount: Decimal = Decimal("0.00"),
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

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {debit_note_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {debit_note_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {debit_note_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {debit_note_number}"))

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
    def create_credit_note_reversal_posting(
        tenant_id: uuid.UUID,
        credit_note_id: uuid.UUID,
        credit_note_number: str,
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
        round_off_account_id: Optional[uuid.UUID] = None,
        round_off_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        cn_total = subtotal + tax_total

        lines.append(JournalLineDraft(customer_account_id, cn_total, "DEBIT", f"Credit Note Cancellation: {credit_note_number}"))
        lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "CREDIT", f"Credit Note Cancellation: {credit_note_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "CREDIT", "CGST Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "CREDIT", "SGST Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "CREDIT", "IGST Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "CREDIT", "UTGST Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "CREDIT", "Cess Reversal"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                # Original CN: Credit customer, Debit round-off
                # Reversal: Debit customer, Credit round-off
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {credit_note_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {credit_note_number}"))
            else:
                # Original CN: Debit round-off, Credit customer
                # Reversal: Credit round-off, Debit customer
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {credit_note_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {credit_note_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{credit_note_number}",
            description=f"Reversal of credit note {credit_note_number}",
            source_type="CREDIT_NOTE_REVERSAL",
            source_id=credit_note_id,
            lines=lines
        )

    @staticmethod
    def create_debit_note_reversal_posting(
        tenant_id: uuid.UUID,
        debit_note_id: uuid.UUID,
        debit_note_number: str,
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
        round_off_account_id: Optional[uuid.UUID] = None,
        round_off_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        dn_total = subtotal + tax_total

        lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "DEBIT", f"Debit Note Cancellation: {debit_note_number}"))
        lines.append(JournalLineDraft(customer_account_id, dn_total, "CREDIT", f"Debit Note Cancellation: {debit_note_number}"))

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

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {debit_note_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {debit_note_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {debit_note_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {debit_note_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{debit_note_number}",
            description=f"Reversal of debit note {debit_note_number}",
            source_type="DEBIT_NOTE_REVERSAL",
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
        discount_total: Decimal = Decimal("0.00"),
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
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        net_subtotal = subtotal - discount_total
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        total = net_subtotal + tax_total

        lines.append(JournalLineDraft(sales_revenue_account_id, net_subtotal, "DEBIT", f"Cancellation: {invoice_number}"))
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

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {invoice_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {invoice_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {invoice_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {invoice_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{invoice_number}",
            description=f"Reversal of invoice {invoice_number}",
            source_type="INVOICE_REVERSAL",
            source_id=invoice_id,
            lines=lines
        )

    @staticmethod
    def create_bill_reversal_posting(
        tenant_id: uuid.UUID,
        bill_id: uuid.UUID,
        bill_number: str,
        cancel_date: date,
        vendor_account_id: uuid.UUID,
        purchase_expense_account_id: uuid.UUID,
        subtotal: Decimal,
        discount_total: Decimal = Decimal("0.00"),
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
        tds_account_id: Optional[uuid.UUID] = None,
        tds_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        net_subtotal = subtotal - discount_total
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        bill_total = net_subtotal + tax_total
        vendor_payable = bill_total - tds_amount

        lines.append(JournalLineDraft(vendor_account_id, vendor_payable, "DEBIT", f"Reversal of vendor bill: {bill_number}"))
        lines.append(JournalLineDraft(purchase_expense_account_id, net_subtotal, "CREDIT", f"Reversal of purchase expense: {bill_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "CREDIT", "CGST Input Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "CREDIT", "SGST Input Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "CREDIT", "IGST Input Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "CREDIT", "UTGST Input Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "CREDIT", "Cess Input Reversal"))

        # TDS reversal: debit TDS Payable, credit vendor
        if tds_amount > 0 and tds_account_id:
            lines.append(JournalLineDraft(tds_account_id, tds_amount, "DEBIT", f"TDS Reversal: {bill_number}"))
            lines.append(JournalLineDraft(vendor_account_id, tds_amount, "CREDIT", f"TDS Reversal: {bill_number}"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(vendor_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {bill_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {bill_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off Reversal: {bill_number}"))
                lines.append(JournalLineDraft(vendor_account_id, abs(round_off_amount), "DEBIT", f"Round-off Reversal: {bill_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{bill_number}",
            description=f"Reversal of vendor bill {bill_number}",
            source_type="BILL_REVERSAL",
            source_id=bill_id,
            lines=lines
        )

    @staticmethod
    def create_payment_receipt_reversal_posting(
        tenant_id: uuid.UUID,
        payment_id: uuid.UUID,
        payment_number: str,
        cancel_date: date,
        bank_or_cash_account_id: uuid.UUID,
        customer_account_id: uuid.UUID,
        amount: Decimal,
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        lines.append(JournalLineDraft(customer_account_id, amount, "DEBIT", f"Payment receipt reversal: {payment_number}"))
        lines.append(JournalLineDraft(bank_or_cash_account_id, amount, "CREDIT", f"Payment receipt reversal: {payment_number}"))
        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{payment_number}",
            description=f"Reversal of payment receipt {payment_number}",
            source_type="PAYMENT_REVERSAL",
            source_id=payment_id,
            lines=lines
        )

    @staticmethod
    def create_payment_out_reversal_posting(
        tenant_id: uuid.UUID,
        payment_id: uuid.UUID,
        payment_number: str,
        cancel_date: date,
        bank_or_cash_account_id: uuid.UUID,
        vendor_account_id: uuid.UUID,
        amount: Decimal,
    ) -> JournalEntryDraft:
        lines: List[JournalLineDraft] = []
        lines.append(JournalLineDraft(bank_or_cash_account_id, amount, "DEBIT", f"Vendor payment reversal: {payment_number}"))
        lines.append(JournalLineDraft(vendor_account_id, amount, "CREDIT", f"Vendor payment reversal: {payment_number}"))
        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=cancel_date,
            reference_number=f"REV-{payment_number}",
            description=f"Reversal of vendor payment {payment_number}",
            source_type="PAYMENT_REVERSAL",
            source_id=payment_id,
            lines=lines
        )

    # ── Sales Return Posting ──
    @staticmethod
    def create_sales_return_posting(
        tenant_id: uuid.UUID,
        return_id: uuid.UUID,
        return_number: str,
        return_date: date,
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
    ) -> JournalEntryDraft:
        """Sales Return: reverse revenue, reverse tax, reduce receivable."""
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        total = subtotal + tax_total

        lines.append(JournalLineDraft(sales_revenue_account_id, subtotal, "DEBIT", f"Sales Return: {return_number}"))
        lines.append(JournalLineDraft(customer_account_id, total, "CREDIT", f"Sales Return: {return_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "DEBIT", "CGST Output Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "DEBIT", "SGST Output Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "DEBIT", "IGST Output Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "DEBIT", "UTGST Output Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "DEBIT", "Cess Output Reversal"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {return_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {return_number}"))
            else:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {return_number}"))
                lines.append(JournalLineDraft(customer_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {return_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=return_date,
            reference_number=return_number,
            description=f"Sales Return {return_number}",
            source_type="SALES_RETURN",
            source_id=return_id,
            lines=lines
        )

    # ── Purchase Return Posting ──
    @staticmethod
    def create_purchase_return_posting(
        tenant_id: uuid.UUID,
        return_id: uuid.UUID,
        return_number: str,
        return_date: date,
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
        cess_amount: Decimal = Decimal("0.00"),
        round_off_account_id: Optional[uuid.UUID] = None,
        round_off_amount: Decimal = Decimal("0.00"),
    ) -> JournalEntryDraft:
        """Purchase Return: reduce payable, reverse purchase, reverse input tax."""
        lines: List[JournalLineDraft] = []
        tax_total = cgst_amount + sgst_amount + igst_amount + utgst_amount + cess_amount
        total = subtotal + tax_total

        lines.append(JournalLineDraft(vendor_account_id, total, "DEBIT", f"Purchase Return: {return_number}"))
        lines.append(JournalLineDraft(purchase_expense_account_id, subtotal, "CREDIT", f"Purchase Return: {return_number}"))

        if cgst_amount > 0 and cgst_account_id:
            lines.append(JournalLineDraft(cgst_account_id, cgst_amount, "CREDIT", "CGST Input Reversal"))
        if sgst_amount > 0 and sgst_account_id:
            lines.append(JournalLineDraft(sgst_account_id, sgst_amount, "CREDIT", "SGST Input Reversal"))
        if igst_amount > 0 and igst_account_id:
            lines.append(JournalLineDraft(igst_account_id, igst_amount, "CREDIT", "IGST Input Reversal"))
        if utgst_amount > 0 and utgst_account_id:
            lines.append(JournalLineDraft(utgst_account_id, utgst_amount, "CREDIT", "UTGST Input Reversal"))
        if cess_amount > 0 and cess_account_id:
            lines.append(JournalLineDraft(cess_account_id, cess_amount, "CREDIT", "Cess Input Reversal"))

        if round_off_amount != 0 and round_off_account_id:
            if round_off_amount > 0:
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {return_number}"))
                lines.append(JournalLineDraft(vendor_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {return_number}"))
            else:
                lines.append(JournalLineDraft(vendor_account_id, abs(round_off_amount), "DEBIT", f"Round-off: {return_number}"))
                lines.append(JournalLineDraft(round_off_account_id, abs(round_off_amount), "CREDIT", f"Round-off: {return_number}"))

        return JournalEntryDraft(
            tenant_id=tenant_id,
            entry_date=return_date,
            reference_number=return_number,
            description=f"Purchase Return {return_number}",
            source_type="PURCHASE_RETURN",
            source_id=return_id,
            lines=lines
        )


# ---------------------------------------------------------------------------
# Standard Chart of Accounts — Indian Accounting Standards
# ---------------------------------------------------------------------------
# Each account has: name, code, type, group (for UI grouping)
# Groups follow Indian Schedule III / common business practice

_STANDARD_ACCOUNTS: Dict[str, Dict[str, str]] = {
    # ══════════════════════════════════════════════════════════════════════
    # ASSETS
    # ══════════════════════════════════════════════════════════════════════

    # ── Current Assets: Cash & Bank ──
    "assets.cash":        {"name": "Cash on Hand",           "code": "1001", "type": "ASSET", "group": "Cash & Bank"},
    "assets.bank":        {"name": "Bank Account",           "code": "1002", "type": "ASSET", "group": "Cash & Bank"},
    "assets.upi":         {"name": "UPI Collections",        "code": "1003", "type": "ASSET", "group": "Cash & Bank"},
    "assets.pos":         {"name": "POS Collections",        "code": "1004", "type": "ASSET", "group": "Cash & Bank"},
    "assets.petty_cash":  {"name": "Petty Cash",             "code": "1005", "type": "ASSET", "group": "Cash & Bank"},

    # ── Current Assets: Receivables ──
    # (customer.<uuid> accounts are auto-created per contact)

    # ── Current Assets: Inventory ──
    "assets.inventory":   {"name": "Inventory",              "code": "1300", "type": "ASSET", "group": "Inventory"},

    # ── Current Assets: Input Tax ──
    "cgst_input":         {"name": "CGST Input Tax",         "code": "1401", "type": "ASSET", "group": "Input Tax Credit"},
    "sgst_input":         {"name": "SGST Input Tax",         "code": "1402", "type": "ASSET", "group": "Input Tax Credit"},
    "igst_input":         {"name": "IGST Input Tax",         "code": "1403", "type": "ASSET", "group": "Input Tax Credit"},
    "utgst_input":        {"name": "UTGST Input Tax",        "code": "1404", "type": "ASSET", "group": "Input Tax Credit"},
    "cess_input":         {"name": "Cess Input Tax",         "code": "1405", "type": "ASSET", "group": "Input Tax Credit"},
    "tds_receivable":     {"name": "TDS Receivable",         "code": "1410", "type": "ASSET", "group": "Input Tax Credit"},

    # ── Current Assets: Other ──
    "assets.prepaid":     {"name": "Prepaid Expenses",       "code": "1500", "type": "ASSET", "group": "Other Current Assets"},
    "assets.security_deposit": {"name": "Security Deposits", "code": "1510", "type": "ASSET", "group": "Other Current Assets"},
    "assets.advance_vendor":   {"name": "Advance to Vendors","code": "1520", "type": "ASSET", "group": "Other Current Assets"},

    # ── Non-Current Assets: Fixed Assets ──
    "assets.furniture":   {"name": "Furniture & Fixtures",   "code": "2001", "type": "ASSET", "group": "Fixed Assets"},
    "assets.computer":    {"name": "Computer & Equipment",   "code": "2002", "type": "ASSET", "group": "Fixed Assets"},
    "assets.vehicle":     {"name": "Motor Vehicle",          "code": "2003", "type": "ASSET", "group": "Fixed Assets"},
    "assets.plant":       {"name": "Plant & Machinery",      "code": "2004", "type": "ASSET", "group": "Fixed Assets"},
    "assets.building":    {"name": "Building",               "code": "2005", "type": "ASSET", "group": "Fixed Assets"},
    "assets.land":        {"name": "Land",                   "code": "2006", "type": "ASSET", "group": "Fixed Assets"},

    # ── Non-Current Assets: Accumulated Depreciation ──
    "assets.depr_furniture": {"name": "Accum. Depreciation - Furniture", "code": "2101", "type": "ASSET", "group": "Accumulated Depreciation"},
    "assets.depr_computer":  {"name": "Accum. Depreciation - Computer",  "code": "2102", "type": "ASSET", "group": "Accumulated Depreciation"},
    "assets.depr_vehicle":   {"name": "Accum. Depreciation - Vehicle",   "code": "2103", "type": "ASSET", "group": "Accumulated Depreciation"},
    "assets.depr_plant":     {"name": "Accum. Depreciation - Plant",     "code": "2104", "type": "ASSET", "group": "Accumulated Depreciation"},
    "assets.depr_building":  {"name": "Accum. Depreciation - Building",  "code": "2105", "type": "ASSET", "group": "Accumulated Depreciation"},

    # ══════════════════════════════════════════════════════════════════════
    # LIABILITIES
    # ══════════════════════════════════════════════════════════════════════

    # ── Current Liabilities: Payables ──
    # (vendor.<uuid> accounts are auto-created per contact)

    # ── Current Liabilities: GST Output ──
    "cgst_output":        {"name": "CGST Output Tax",        "code": "3001", "type": "LIABILITY", "group": "GST Output"},
    "sgst_output":        {"name": "SGST Output Tax",        "code": "3002", "type": "LIABILITY", "group": "GST Output"},
    "igst_output":        {"name": "IGST Output Tax",        "code": "3003", "type": "LIABILITY", "group": "GST Output"},
    "utgst_output":       {"name": "UTGST Output Tax",       "code": "3004", "type": "LIABILITY", "group": "GST Output"},
    "cess_output":        {"name": "Cess Output Tax",        "code": "3005", "type": "LIABILITY", "group": "GST Output"},

    # ── Current Liabilities: Statutory ──
    "liability.tds":      {"name": "TDS Payable",            "code": "3101", "type": "LIABILITY", "group": "Statutory Liabilities"},
    "liability.gst_payable": {"name": "GST Payable",         "code": "3102", "type": "LIABILITY", "group": "Statutory Liabilities"},
    "liability.pf":       {"name": "PF Payable",             "code": "3103", "type": "LIABILITY", "group": "Statutory Liabilities"},
    "liability.esi":      {"name": "ESI Payable",            "code": "3104", "type": "LIABILITY", "group": "Statutory Liabilities"},
    "liability.professional_tax": {"name": "Professional Tax Payable", "code": "3105", "type": "LIABILITY", "group": "Statutory Liabilities"},

    # ── Current Liabilities: Other ──
    "liability.advance":  {"name": "Advance from Customers", "code": "3201", "type": "LIABILITY", "group": "Other Current Liabilities"},
    "liability.salary_payable": {"name": "Salary Payable",   "code": "3202", "type": "LIABILITY", "group": "Other Current Liabilities"},
    "liability.expense_payable": {"name": "Expenses Payable","code": "3203", "type": "LIABILITY", "group": "Other Current Liabilities"},

    # ── Non-Current Liabilities ──
    "liability.loan":     {"name": "Loan Account",           "code": "3301", "type": "LIABILITY", "group": "Long-term Liabilities"},
    "liability.term_loan": {"name": "Term Loan",             "code": "3302", "type": "LIABILITY", "group": "Long-term Liabilities"},

    # ══════════════════════════════════════════════════════════════════════
    # EQUITY
    # ══════════════════════════════════════════════════════════════════════

    "equity.capital":     {"name": "Owner's Capital",        "code": "4001", "type": "EQUITY", "group": "Capital"},
    "equity.drawings":    {"name": "Drawings",               "code": "4002", "type": "EQUITY", "group": "Capital"},
    "equity.retained":    {"name": "Retained Earnings",      "code": "4003", "type": "EQUITY", "group": "Capital"},
    "equity.current_year": {"name": "Current Year Earnings", "code": "4004", "type": "EQUITY", "group": "Capital"},

    # ══════════════════════════════════════════════════════════════════════
    # REVENUE
    # ══════════════════════════════════════════════════════════════════════

    "sales_revenue":      {"name": "Sales Revenue",          "code": "5001", "type": "REVENUE", "group": "Sales"},
    "sales_discount":     {"name": "Sales Discount",         "code": "5002", "type": "REVENUE", "group": "Sales"},
    "service_revenue":    {"name": "Service Revenue",        "code": "5010", "type": "REVENUE", "group": "Sales"},

    "interest_income":    {"name": "Interest Income",        "code": "5101", "type": "REVENUE", "group": "Other Income"},
    "rental_income":      {"name": "Rental Income",          "code": "5102", "type": "REVENUE", "group": "Other Income"},
    "commission_income":  {"name": "Commission Income",      "code": "5103", "type": "REVENUE", "group": "Other Income"},
    "other_income":       {"name": "Other Income",           "code": "5199", "type": "REVENUE", "group": "Other Income"},

    # ══════════════════════════════════════════════════════════════════════
    # EXPENSES
    # ══════════════════════════════════════════════════════════════════════

    # ── Cost of Goods Sold ──
    "purchases":          {"name": "Purchases",              "code": "6001", "type": "EXPENSE", "group": "Cost of Goods Sold"},
    "purchase_discount":  {"name": "Purchase Discount",      "code": "6002", "type": "EXPENSE", "group": "Cost of Goods Sold"},
    "freight_in":         {"name": "Freight Inward",         "code": "6003", "type": "EXPENSE", "group": "Cost of Goods Sold"},

    # ── Direct Expenses ──
    "expense.salary":     {"name": "Salary & Wages",         "code": "6101", "type": "EXPENSE", "group": "Direct Expenses"},
    "expense.freight_out": {"name": "Freight Outward",       "code": "6102", "type": "EXPENSE", "group": "Direct Expenses"},
    "expense.job_work":   {"name": "Job Work Charges",       "code": "6103", "type": "EXPENSE", "group": "Direct Expenses"},

    # ── Administrative Expenses ──
    "expense.rent":       {"name": "Rent",                   "code": "6201", "type": "EXPENSE", "group": "Admin Expenses"},
    "expense.office":     {"name": "Office Supplies & Stationery", "code": "6202", "type": "EXPENSE", "group": "Admin Expenses"},
    "expense.telephone":  {"name": "Telephone & Internet",   "code": "6203", "type": "EXPENSE", "group": "Admin Expenses"},
    "expense.electricity": {"name": "Electricity & Utilities","code": "6204", "type": "EXPENSE", "group": "Admin Expenses"},
    "expense.tea":        {"name": "Tea & Refreshments",     "code": "6205", "type": "EXPENSE", "group": "Admin Expenses"},
    "expense.cleaning":   {"name": "Cleaning & Housekeeping","code": "6206", "type": "EXPENSE", "group": "Admin Expenses"},
    "expense.security":   {"name": "Security Charges",       "code": "6207", "type": "EXPENSE", "group": "Admin Expenses"},

    # ── Selling & Distribution ──
    "expense.advertising": {"name": "Advertising & Marketing","code": "6301", "type": "EXPENSE", "group": "Selling Expenses"},
    "expense.commission_paid": {"name": "Commission Paid",   "code": "6302", "type": "EXPENSE", "group": "Selling Expenses"},
    "expense.transport":  {"name": "Transport & Travel",     "code": "6303", "type": "EXPENSE", "group": "Selling Expenses"},
    "expense.packing":    {"name": "Packing & Forwarding",   "code": "6304", "type": "EXPENSE", "group": "Selling Expenses"},

    # ── Financial Expenses ──
    "expense.interest_paid": {"name": "Interest Paid",       "code": "6401", "type": "EXPENSE", "group": "Financial Expenses"},
    "expense.bank_charges": {"name": "Bank Charges",         "code": "6402", "type": "EXPENSE", "group": "Financial Expenses"},
    "expense.loan_processing": {"name": "Loan Processing Fee","code": "6403", "type": "EXPENSE", "group": "Financial Expenses"},

    # ── Depreciation & Amortization ──
    "expense.depreciation": {"name": "Depreciation",         "code": "6501", "type": "EXPENSE", "group": "Depreciation"},
    "expense.amortization": {"name": "Amortization",         "code": "6502", "type": "EXPENSE", "group": "Depreciation"},

    # ── Employee Benefits ──
    "expense.staff_welfare": {"name": "Staff Welfare",       "code": "6601", "type": "EXPENSE", "group": "Employee Benefits"},
    "expense.insurance":  {"name": "Insurance",              "code": "6602", "type": "EXPENSE", "group": "Employee Benefits"},

    # ── Repairs & Maintenance ──
    "expense.repairs":    {"name": "Repairs & Maintenance",  "code": "6701", "type": "EXPENSE", "group": "Repairs & Maintenance"},

    # ── Professional Fees ──
    "expense.professional": {"name": "Professional Fees",    "code": "6801", "type": "EXPENSE", "group": "Professional Fees"},
    "expense.legal":      {"name": "Legal Fees",             "code": "6802", "type": "EXPENSE", "group": "Professional Fees"},
    "expense.audit":      {"name": "Audit & Accounting Fees","code": "6803", "type": "EXPENSE", "group": "Professional Fees"},

    # ── Miscellaneous ──
    "round_off":          {"name": "Round Off Account",      "code": "6901", "type": "EXPENSE", "group": "Miscellaneous"},
    "expense.misc":       {"name": "Miscellaneous Expense",  "code": "6999", "type": "EXPENSE", "group": "Miscellaneous"},
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
        from sqlalchemy import func

        definition = _STANDARD_ACCOUNTS.get(key)
        if definition is None:
            raise LedgerValidationError(f"Unknown standard account key: {key}")

        account_id = uuid.uuid5(uuid.NAMESPACE_DNS, f"account.{key}-{self.tenant_id}")

        # 1. Try deterministic UUID lookup
        existing = self.db.query(Account).filter(
            Account.id == account_id,
            Account.tenant_id == self.tenant_id,
            Account.deleted_at == None,
        ).first()
        if existing is not None:
            return existing.id

        # 2. Try code lookup (handles accounts created with different UUIDs,
        #    e.g. from imports, or before deterministic UUID was used)
        existing_by_code = self.db.query(Account).filter(
            Account.tenant_id == self.tenant_id,
            func.upper(Account.code) == definition["code"].upper(),
            Account.deleted_at == None,
        ).first()
        if existing_by_code is not None:
            return existing_by_code.id

        # 3. Create new account with deterministic UUID
        account = Account(
            id=account_id,
            tenant_id=self.tenant_id,
            name=definition["name"],
            code=definition["code"],
            account_type=definition["type"],
            account_group=definition.get("group"),
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
        from sqlalchemy import func

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

        # Guard against historical duplicate contacts: if another contact with
        # the same visible name already created the same AR/AP account, reuse it.
        candidates = self.db.query(Account).filter(
            Account.tenant_id == self.tenant_id,
            Account.account_type == account_type,
            func.lower(func.trim(Account.name)) == account_name.strip().lower(),
            Account.deleted_at == None,
        ).all()
        if candidates:
            non_zero = [a for a in candidates if a.current_balance and a.current_balance != 0]
            return (non_zero[0] if non_zero else candidates[0]).id

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

        op_bal = account.opening_balance or Decimal("0.0000")
        if account.account_type in ("ASSET", "EXPENSE"):
            account.current_balance = (op_bal + debit_sum - credit_sum).quantize(Decimal("0.0001"))
        else:
            account.current_balance = (op_bal + credit_sum - debit_sum).quantize(Decimal("0.0001"))

    # NOTE: Caller is responsible for db.commit()


def commit_ledger_draft(db: Session, tenant_id: uuid.UUID, draft: JournalEntryDraft) -> "JournalEntry":
    from src.infrastructure.database.models import JournalEntry, JournalLine

    journal_entry = JournalEntry(
        tenant_id=draft.tenant_id,
        entry_date=draft.entry_date,
        reference_number=draft.reference_number,
        description=draft.description,
        source_type=draft.source_type,
        source_id=draft.source_id,
        lines=[
            JournalLine(
                account_id=line.account_id,
                amount=line.amount,
                direction=line.direction,
                narration=line.narration
            )
            for line in draft.lines
        ]
    )
    db.add(journal_entry)
    db.flush()
    affected = {line.account_id for line in draft.lines}
    update_account_balances(db, tenant_id, affected)
    return journal_entry


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
        raw_balance = balance_map.get(account.id, Decimal("0.0000"))
        # Apply correct sign: ASSET/EXPENSE use debit-positive, others use credit-positive
        op_bal = account.opening_balance or Decimal("0.0000")
        if account.account_type in ("ASSET", "EXPENSE"):
            account.current_balance = (op_bal + raw_balance).quantize(Decimal("0.0001"))
        else:
            account.current_balance = (op_bal - raw_balance).quantize(Decimal("0.0001"))

    # NOTE: Caller is responsible for db.commit()
