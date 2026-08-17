"""End-to-end tests for the CSV migration import endpoint.

``POST /api/v1/import/csv`` consumes the exact schema produced by
``tools/legacy_to_csv.py``.  These tests exercise the money-safety contract:

* dry-run validates and writes nothing
* commit writes everything in one transaction
* tampered totals, settlement mismatches, unallocated payments, header drift,
  unbalanced opening balances and duplicates are all rejected *before* any
  write — the DB stays untouched.
"""
import io
import os
import unittest
import zipfile
from datetime import date
from decimal import Decimal

from fastapi.testclient import TestClient

import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.main import app
from src.core.database import Base, engine


def _csv(rows):
    """rows = list of dicts → CSV text with header row from the first dict."""
    if not rows:
        return ""
    headers = list(rows[0].keys())
    lines = [",".join(headers)]
    for r in rows:
        lines.append(",".join(str(r.get(h, "")) for h in headers))
    return "\n".join(lines)


def _bundle():
    """A fully consistent migration bundle (all 14 files) as ZIP bytes."""
    files = {
        "contacts.csv": _csv([
            {"name": "Acme Traders", "contact_type": "CUSTOMER", "gstin": "27AABCU9603R1ZM",
             "pan": "AABCU9603R", "email": "", "phone": "9876543210", "state_code": "27",
             "billing_address": "", "opening_balance": "0"},
            {"name": "Sundaram Suppliers", "contact_type": "VENDOR", "gstin": "27AAACS1234F1Z3",
             "pan": "", "email": "", "phone": "", "state_code": "27",
             "billing_address": "", "opening_balance": "0"},
        ]),
        "products.csv": _csv([
            {"name": "Widget", "sku": "WID-01", "hsn_sac": "84716060", "product_type": "GOODS",
             "uom": "NOS", "sales_price": "1000", "purchase_price": "800", "gst_rate": "18",
             "opening_stock": "10", "current_stock": "10", "reorder_level": "2"},
            {"name": "Raw Material", "sku": "", "hsn_sac": "7208", "product_type": "GOODS",
             "uom": "KGS", "sales_price": "0", "purchase_price": "1000", "gst_rate": "18",
             "opening_stock": "0", "current_stock": "0", "reorder_level": "0"},
        ]),
        "invoices.csv": _csv([
            {"invoice_number": "INV/2026/001", "customer": "Acme Traders", "issue_date": "2026-04-01",
             "due_date": "2026-04-15", "pos_state_code": "27", "status": "PARTIALLY_PAID",
             "subtotal": "10000", "discount_total": "0", "cgst_amount": "900", "sgst_amount": "900",
             "igst_amount": "0", "cess_amount": "0", "round_off": "0", "shipping_charges": "0",
             "total": "11800", "amount_paid": "5000"},
        ]),
        "invoice_lines.csv": _csv([
            {"invoice_number": "INV/2026/001", "product": "Widget", "description": "Widget",
             "hsn_sac": "84716060", "quantity": "10", "rate": "1000", "discount": "0",
             "subtotal": "10000", "gst_rate": "18", "cgst_amount": "900", "sgst_amount": "900",
             "igst_amount": "0", "total": "11800"},
        ]),
        "bills.csv": _csv([
            {"bill_number": "BILL/2026/001", "vendor": "Sundaram Suppliers", "issue_date": "2026-04-02",
             "due_date": "2026-04-20", "pos_state_code": "27", "status": "PAID",
             "subtotal": "4000", "discount_total": "0", "cgst_amount": "360", "sgst_amount": "360",
             "igst_amount": "0", "cess_amount": "0", "round_off": "0", "shipping_charges": "0",
             "total": "4720", "amount_paid": "4720", "tds_amount": "0"},
        ]),
        "bill_lines.csv": _csv([
            {"bill_number": "BILL/2026/001", "product": "Raw Material", "description": "Raw Material",
             "hsn_sac": "7208", "quantity": "4", "rate": "1000", "discount": "0",
             "subtotal": "4000", "gst_rate": "18", "cgst_amount": "360", "sgst_amount": "360",
             "igst_amount": "0", "total": "4720"},
        ]),
        "payments.csv": _csv([
            {"payment_number": "PAY/1", "customer": "Acme Traders", "payment_date": "2026-04-10",
             "payment_mode": "BANK", "amount": "5000", "reference_number": "", "status": "ACTIVE"},
        ]),
        "bill_payments.csv": _csv([
            {"payment_number": "BPAY/1", "vendor": "Sundaram Suppliers", "payment_date": "2026-04-12",
             "payment_mode": "BANK", "amount": "4720", "reference_number": "NEFT-1", "status": "ACTIVE"},
        ]),
        "payment_allocations.csv": _csv([
            {"payment_number": "PAY/1", "invoice_number": "INV/2026/001", "amount": "5000"},
        ]),
        "bill_payment_allocations.csv": _csv([
            {"payment_number": "BPAY/1", "bill_number": "BILL/2026/001", "amount": "4720"},
        ]),
        "expenses.csv": _csv([
            {"expense_number": "EXP/1", "category": "Rent", "expense_date": "2026-04-05",
             "vendor_name": "Landlord", "description": "April rent", "amount": "1000",
             "gst_rate": "18", "cgst_amount": "90", "sgst_amount": "90", "igst_amount": "0",
             "total": "1180", "status": "POSTED"},
        ]),
        "stock_ledger.csv": _csv([
            {"product": "Widget", "entry_date": "2026-04-01", "reference_type": "VYAPAR_OPENING",
             "quantity": "10", "balance_quantity": "10", "rate": "800"},
        ]),
        "accounts.csv": _csv([
            {"code": "1001", "account_name": "Cash on Hand", "account_type": "ASSET", "opening_balance": "0"},
            {"code": "1002", "account_name": "Bank Account", "account_type": "ASSET", "opening_balance": "50000"},
            {"code": "9100", "account_name": "Opening Capital", "account_type": "EQUITY", "opening_balance": "50000"},
        ]),
        "proforma_invoices.csv": _csv([
            {"proforma_number": "EST/1", "customer": "Acme Traders", "issue_date": "2026-04-01",
             "due_date": "2026-04-30", "status": "ISSUED", "total": "20000"},
        ]),
    }
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, text in files.items():
            zf.writestr(name, text)
    return buf.getvalue()


class TestCsvImport(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(bind=engine)
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

        reg = {
            "email": "csv@company.com",
            "password": "SecurePassword123!",
            "full_name": "CSV User",
            "phone_number": "+919999977777",
            "company_legal_name": "CSV Co Pvt Ltd",
            "company_gstin": "27AAAAA1111A1Z1",
            "company_pan": "AAAAA1111A",
        }
        self.client.post("/api/v1/auth/register", json=reg)
        login = self.client.post("/api/v1/auth/login", json={
            "email": reg["email"], "password": reg["password"],
        }).json()
        self.headers = {"Authorization": f"Bearer {login['access_token']}"}

        from src.core.database import SessionLocal
        from src.infrastructure.database.models import User, TenantMembership
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.email == reg["email"]).first()
            tenant_id = db.query(TenantMembership).filter(
                TenantMembership.user_id == user.id).first().tenant_id
        finally:
            db.close()
        self.headers["X-Tenant-ID"] = str(tenant_id)

    # ── helpers ────────────────────────────────────────────────────────────
    def _post(self, data: bytes, filename="bundle.zip", dry_run=None):
        url = "/api/v1/import/csv"
        if dry_run is not None:
            url += f"?dry_run={'true' if dry_run else 'false'}"
        return self.client.post(
            url,
            files={"file": (filename, data, "application/zip")},
            headers=self.headers,
        )

    def _counts(self):
        from src.core.database import SessionLocal
        from src.infrastructure.database.models import (
            Invoice, Bill, Payment, BillPayment, Contact, Product, Expense,
            StockLedger, Account,
        )
        db = SessionLocal()
        try:
            return {
                "invoices": db.query(Invoice).count(),
                "bills": db.query(Bill).count(),
                "payments": db.query(Payment).count(),
                "bill_payments": db.query(BillPayment).count(),
                "contacts": db.query(Contact).count(),
                "products": db.query(Product).count(),
                "expenses": db.query(Expense).count(),
                "stock": db.query(StockLedger).count(),
                "accounts": db.query(Account).count(),
            }
        finally:
            db.close()

    # ── happy paths ────────────────────────────────────────────────────────
    def test_dry_run_valid_writes_nothing(self):
        res = self._post(_bundle(), dry_run=True)
        self.assertEqual(res.status_code, 200, res.text)
        report = res.json()
        self.assertTrue(report["valid"], report["errors"])
        self.assertTrue(report["dry_run"])
        self.assertFalse(report["committed"])
        self.assertEqual(report["counts"], {})
        # Money totals are reported
        self.assertEqual(float(report["totals"]["invoice_total"]), 11800.00)
        self.assertEqual(float(report["totals"]["bill_total"]), 4720.00)
        self.assertEqual(float(report["totals"]["payments_received"]), 5000.00)
        self.assertEqual(float(report["totals"]["payments_made"]), 4720.00)
        self.assertEqual(float(report["totals"]["opening_balance_net"]), 0.00)
        # Nothing written
        counts = self._counts()
        self.assertEqual(counts["invoices"], 0)
        self.assertEqual(counts["contacts"], 0)

    def test_commit_imports_everything_in_one_transaction(self):
        res = self._post(_bundle(), dry_run=False)
        self.assertEqual(res.status_code, 200, res.text)
        report = res.json()
        self.assertTrue(report["valid"], report["errors"])
        self.assertTrue(report["committed"])
        self.assertEqual(report["counts"]["contacts_imported"], 2)
        self.assertEqual(report["counts"]["products_imported"], 2)
        self.assertEqual(report["counts"]["invoices_imported"], 1)
        self.assertEqual(report["counts"]["bills_imported"], 1)
        self.assertEqual(report["counts"]["payments_imported"], 1)
        self.assertEqual(report["counts"]["bill_payments_imported"], 1)
        self.assertEqual(report["counts"]["expenses_imported"], 1)
        self.assertEqual(report["counts"]["estimates_imported"], 1)
        self.assertEqual(report["counts"]["stock_entries_imported"], 1)
        self.assertEqual(report["counts"]["accounts_set"], 3)

        from src.core.database import SessionLocal
        from src.infrastructure.database.models import (
            Invoice, InvoiceLine, Bill, Payment, PaymentAllocation,
            BillPayment, BillPaymentAllocation, Product, Expense, Account,
            ProformaInvoice, StockLedger,
        )
        db = SessionLocal()
        try:
            inv = db.query(Invoice).filter(Invoice.invoice_number == "INV/2026/001").first()
            self.assertIsNotNone(inv)
            self.assertEqual(float(inv.total), 11800.00)
            self.assertEqual(inv.status, "PARTIALLY_PAID")
            self.assertEqual(float(inv.amount_paid), 5000.00)
            self.assertEqual(inv.issue_date, date(2026, 4, 1))
            self.assertEqual(db.query(InvoiceLine).filter(
                InvoiceLine.invoice_id == inv.id).count(), 1)

            bill = db.query(Bill).filter(Bill.bill_number == "BILL/2026/001").first()
            self.assertIsNotNone(bill)
            self.assertEqual(bill.status, "PAID")
            self.assertTrue(bill.itc_eligible)

            pay = db.query(Payment).filter(Payment.payment_number == "PAY/1").first()
            self.assertEqual(float(pay.amount), 5000.00)
            alloc = db.query(PaymentAllocation).filter(
                PaymentAllocation.payment_id == pay.id).first()
            self.assertEqual(float(alloc.amount), 5000.00)
            self.assertEqual(alloc.invoice_id, inv.id)

            bp = db.query(BillPayment).filter(BillPayment.payment_number == "BPAY/1").first()
            self.assertEqual(float(bp.amount), 4720.00)
            self.assertEqual(bp.reference_number, "NEFT-1")

            widget = db.query(Product).filter(Product.name == "Widget").first()
            self.assertEqual(float(widget.current_stock), 10.00)
            self.assertEqual(db.query(StockLedger).filter(
                StockLedger.product_id == widget.id).count(), 1)

            bank = db.query(Account).filter(Account.code == "1002").first()
            self.assertEqual(float(bank.opening_balance), 50000.00)
            capital = db.query(Account).filter(Account.code == "9100").first()
            self.assertEqual(float(capital.opening_balance), 50000.00)

            exp = db.query(Expense).filter(Expense.expense_number == "EXP/1").first()
            self.assertEqual(float(exp.total), 1180.00)
            self.assertEqual(exp.status, "POSTED")

            est = db.query(ProformaInvoice).filter(ProformaInvoice.proforma_number == "EST/1").first()
            self.assertIsNotNone(est)

            # The import must post journals in the same transaction: AR/AP
            # and GST books must not stay empty while documents show rupees.
            # Every posted document gets exactly one balanced journal entry.
            from src.infrastructure.database.models import JournalEntry, JournalLine
            expected = [
                ("INVOICE", inv.id),
                ("BILL", bill.id),
                ("PAYMENT", pay.id),
                ("PAYMENT", bp.id),
                ("EXPENSE", exp.id),
            ]
            for source_type, source_id in expected:
                entry = db.query(JournalEntry).filter(
                    JournalEntry.tenant_id == inv.tenant_id,
                    JournalEntry.source_type == source_type,
                    JournalEntry.source_id == source_id,
                ).first()
                self.assertIsNotNone(
                    entry, f"missing journal for {source_type}:{source_id}"
                )
                lines = db.query(JournalLine).filter(JournalLine.entry_id == entry.id).all()
                self.assertGreaterEqual(len(lines), 2, f"unbalanced {source_type}:{source_id}")
                debits = sum((l.amount for l in lines if l.direction == "DEBIT"), Decimal("0"))
                credits = sum((l.amount for l in lines if l.direction == "CREDIT"), Decimal("0"))
                self.assertEqual(debits, credits, f"unbalanced {source_type}:{source_id}")
        finally:
            db.close()

    def test_commit_twice_rejected_and_second_import_writes_nothing(self):
        r1 = self._post(_bundle(), dry_run=False)
        self.assertTrue(r1.json()["committed"], r1.text)
        r2 = self._post(_bundle(), dry_run=False)
        self.assertEqual(r2.status_code, 200, r2.text)
        report = r2.json()
        self.assertFalse(report["valid"])
        self.assertFalse(report["committed"])
        self.assertTrue(any("already exists" in e for e in report["errors"]), report["errors"])
        # Still exactly one of everything
        counts = self._counts()
        self.assertEqual(counts["invoices"], 1)
        self.assertEqual(counts["contacts"], 2)
        self.assertEqual(counts["products"], 2)

    # ── rejection paths: nothing may be written ────────────────────────────
    def test_tampered_total_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        # The total column is the only 11800 in invoices.csv — inflate it
        files["invoices.csv"] = files["invoices.csv"].replace("11800", "12345")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=False)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertFalse(report["committed"])
        self.assertTrue(any("does not balance" in e for e in report["errors"]), report["errors"])
        counts = self._counts()
        self.assertEqual(counts["invoices"], 0)
        self.assertEqual(counts["contacts"], 0)

    def test_allocation_mismatch_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        files["payment_allocations.csv"] = "payment_number,invoice_number,amount\nPAY/1,INV/2026/001,4999\n"
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("allocations" in e for e in report["errors"]), report["errors"])
        self.assertEqual(self._counts()["invoices"], 0)

    def test_unallocated_active_payment_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        files["payment_allocations.csv"] = "payment_number,invoice_number,amount\n"
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("no allocations" in e for e in report["errors"]), report["errors"])

    def test_missing_column_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        # Drop the total column from invoices.csv
        lines = files["invoices.csv"].splitlines()
        header = [h for h in lines[0].split(",") if h != "total"]
        rows = []
        for line in lines[1:]:
            cells = [c for c, h in zip(line.split(","), lines[0].split(",")) if h != "total"]
            rows.append(",".join(cells))
        files["invoices.csv"] = "\n".join([",".join(header)] + rows)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("missing required columns" in e for e in report["errors"]), report["errors"])

    def test_unbalanced_opening_balances_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        files["accounts.csv"] = "code,account_name,account_type,opening_balance\n" + \
            "1001,Cash on Hand,ASSET,0\n1002,Bank Account,ASSET,50000\n9100,Opening Capital,EQUITY,49999\n"
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("net opening balance" in e for e in report["errors"]), report["errors"])

    def test_missing_customer_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        files["invoices.csv"] = files["invoices.csv"].replace("Acme Traders", "Nobody & Co")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("not in contacts.csv" in e for e in report["errors"]), report["errors"])

    def test_draft_document_rejected(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        files["invoices.csv"] = files["invoices.csv"].replace("PARTIALLY_PAID", "DRAFT")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("draft invoices are not imported" in e for e in report["errors"]), report["errors"])

    def test_line_totals_must_sum_to_header(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n).decode("utf-8") for n in zf.namelist()}
        files["invoice_lines.csv"] = files["invoice_lines.csv"].replace(
            "10000,18,900,900,0,11800", "10000,18,900,900,0,11700")
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
            for n, t in files.items():
                out.writestr(n, t)
        res = self._post(buf.getvalue(), dry_run=True)
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("line totals sum to" in e for e in report["errors"]), report["errors"])

    def test_excel_file_rejected(self):
        res = self.client.post(
            "/api/v1/import/csv",
            files={"file": ("bundle.xlsx", b"PK\x03\x04not really", "application/vnd.ms-excel")},
            headers=self.headers,
        )
        report = res.json()
        self.assertFalse(report["valid"])
        self.assertTrue(any("review-only" in e for e in report["errors"]), report["errors"])

    def test_multiple_csv_files_accepted(self):
        data = _bundle()
        zf = zipfile.ZipFile(io.BytesIO(data))
        files = {n: zf.read(n) for n in zf.namelist()}
        res = self.client.post(
            "/api/v1/import/csv?dry_run=true",
            files=[("files", (name, content, "text/csv")) for name, content in files.items()],
            headers=self.headers,
        )
        self.assertEqual(res.status_code, 200, res.text)
        self.assertTrue(res.json()["valid"], res.json()["errors"])


if __name__ == "__main__":
    unittest.main()
