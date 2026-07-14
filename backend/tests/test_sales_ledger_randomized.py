"""Deterministic property test for high-volume Sales double-entry invariants."""
import random
import uuid
from datetime import date
from decimal import Decimal

from src.domains.accounting.services import LedgerPostingEngine


def test_five_thousand_random_sales_transactions_preserve_accounting_equation():
    rng = random.Random(20260714)
    tenant = uuid.uuid4()
    customer, bank, sales, cgst, sgst = (uuid.uuid4() for _ in range(5))
    balances = {account: Decimal("0") for account in (customer, bank, sales, cgst, sgst)}

    for sequence in range(5000):
        taxable = Decimal(rng.randrange(100, 1_000_000)) / Decimal("100")
        tax = (taxable * Decimal("0.09")).quantize(Decimal("0.01"))
        gross = taxable + tax + tax
        document_id = uuid.uuid4()
        kind = rng.choice(("invoice", "receipt", "advance", "cancel", "credit_note", "refund"))

        if kind == "invoice":
            draft = LedgerPostingEngine.create_invoice_posting(
                tenant, document_id, f"INV-{sequence}", date.today(), customer, sales,
                taxable, cgst_account_id=cgst, cgst_amount=tax,
                sgst_account_id=sgst, sgst_amount=tax,
            )
        elif kind in ("receipt", "advance"):
            draft = LedgerPostingEngine.create_payment_receipt_posting(
                tenant, document_id, f"RCT-{sequence}", date.today(), bank, customer, gross
            )
        elif kind == "cancel":
            draft = LedgerPostingEngine.create_invoice_reversal_posting(
                tenant, document_id, f"INV-{sequence}", date.today(), customer, sales,
                taxable, cgst_account_id=cgst, cgst_amount=tax,
                sgst_account_id=sgst, sgst_amount=tax,
            )
        elif kind == "credit_note":
            draft = LedgerPostingEngine.create_credit_note_posting(
                tenant, document_id, f"CN-{sequence}", date.today(), customer, sales,
                taxable, cgst_account_id=cgst, cgst_amount=tax,
                sgst_account_id=sgst, sgst_amount=tax,
            )
        else:
            draft = LedgerPostingEngine.create_payment_receipt_reversal_posting(
                tenant, document_id, f"RCT-{sequence}", date.today(), bank, customer, gross
            )

        debits = sum(line.amount for line in draft.lines if line.direction == "DEBIT")
        credits = sum(line.amount for line in draft.lines if line.direction == "CREDIT")
        assert debits == credits
        for line in draft.lines:
            balances[line.account_id] += line.amount if line.direction == "DEBIT" else -line.amount

    assets = balances[customer] + balances[bank]
    liabilities = -(balances[cgst] + balances[sgst])
    equity = -balances[sales]
    assert assets == liabilities + equity
