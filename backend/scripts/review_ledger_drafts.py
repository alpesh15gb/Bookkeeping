#!/usr/bin/env python3
"""
Draft Review Report — read-only inventory of DRAFT ledger documents.

Phase 0 tooling. This script NEVER posts, deletes, archives, or modifies any
data. It connects with a read-only transaction (PostgreSQL) or the SQLite
`query_only` pragma, runs only SELECTs, and prints a review report so a human
can decide the disposition of every legacy draft before the Phase 2 migration
removes the DRAFT status from ledger documents.

Usage:
    python scripts/review_ledger_drafts.py [--db-url URL] [--tenant UUID]
        [--format table|csv|json] [--out FILE]

Fields reported per draft:
  document type / id / number, tenant, created date, created by (from the
  audit log), customer/vendor/account, transaction date, amount, status,
  whether a journal entry exists, whether a stock-ledger entry exists,
  whether the document appears safe to post, validation problems,
  suggested disposition (POST / REVIEW / ARCHIVE), and any suspicious or
  inconsistent records.

Disposition rules (suggestions only — the human decides):
  * POST    — passes all validation checks and has no ledger/stock records.
  * REVIEW  — has validation problems, missing data, or an inconsistent
              partial posting (journal/stock exists while still DRAFT).
  * ARCHIVE — zero-value or line-less draft that cannot be meaningfully
              posted; candidate for the non-ledger pending/archive mechanism.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import uuid
from datetime import date, datetime
from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy import event, func
from sqlalchemy.orm import Session, sessionmaker

# Make `src` importable regardless of the working directory.
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(_HERE, "..")))
sys.path.insert(0, os.path.abspath(os.path.join(_HERE, "..", "src")))

from src.infrastructure.database import models as M  # noqa: E402


# ---------------------------------------------------------------------------
# Read-only engine construction
# ---------------------------------------------------------------------------

def build_engine(db_url: str):
    connect_args = {}
    if db_url.startswith("postgresql"):
        # Enforce read-only at the server transaction level.
        connect_args["options"] = "-c default_transaction_read_only=on"
    engine = sa.create_engine(db_url, connect_args=connect_args, pool_pre_ping=True)

    if engine.dialect.name == "sqlite":
        @event.listens_for(engine, "connect")
        def _sqlite_read_only(dbapi_conn, _record):
            dbapi_conn.execute("PRAGMA query_only = ON")

    return engine


# ---------------------------------------------------------------------------
# Document-type specification
# ---------------------------------------------------------------------------

def _total_formula_ok(row) -> bool:
    """Compare the header total against its parts (mirrors DB CHECKs)."""
    from decimal import Decimal as D
    taxes = D(0)
    for col in ("cgst_amount", "sgst_amount", "igst_amount", "utgst_amount", "cess_amount"):
        taxes += D(str(getattr(row, col) or 0))
    subtotal = D(str(row.subtotal or 0))
    round_off = D(str(row.round_off or 0))
    if hasattr(row, "discount_total"):
        total = subtotal + taxes + round_off - D(str(row.discount_total or 0))
        if hasattr(row, "shipping_charges"):
            total += D(str(row.shipping_charges or 0))
    elif hasattr(row, "amount"):  # Expense: amount is the taxable base
        total = D(str(row.amount or 0)) + taxes + round_off
    else:  # Credit/Debit note and returns: subtotal + taxes + round-off
        total = subtotal + taxes + round_off
    return (D(str(row.total or 0)).quantize(D("0.01")) == total.quantize(D("0.01")))


def _lines_count(db: Session, model, doc_id) -> int:
    line_model = {
        M.Invoice: M.InvoiceLine,
        M.Bill: M.BillLine,
        M.CreditNote: M.CreditNoteLine,
        M.DebitNote: M.DebitNoteLine,
        M.SalesReturn: M.SalesReturnLine,
        M.PurchaseReturn: M.PurchaseReturnLine,
        M.Expense: None,
    }.get(model)
    if line_model is None:
        return 0
    fk = [c for c in line_model.__table__.columns if c.foreign_keys][0]
    return db.query(func.count(line_model.id)).filter(fk == doc_id).scalar() or 0


def _line_subtotals_consistent(db: Session, model, doc_id, header_subtotal) -> bool:
    line_model = {
        M.Invoice: M.InvoiceLine,
        M.Bill: M.BillLine,
        M.CreditNote: M.CreditNoteLine,
        M.DebitNote: M.DebitNoteLine,
    }.get(model)
    if line_model is None:
        return True
    fk = [c for c in line_model.__table__.columns if c.foreign_keys][0]
    total = db.query(func.coalesce(func.sum(line_model.subtotal), 0)).filter(fk == doc_id).scalar()
    return abs(Decimal(str(total or 0)) - Decimal(str(header_subtotal or 0))) <= Decimal("0.01")


def _party_name(db: Session, row) -> str:
    if isinstance(row, M.Expense):
        return row.vendor_name or ""
    contact_id = getattr(row, "contact_id", None)
    if contact_id is None and isinstance(row, (M.CreditNote, M.DebitNote, M.SalesReturn, M.PurchaseReturn)):
        linked = db.query(M.Invoice).filter(M.Invoice.id == row.invoice_id).first()
        contact_id = linked.contact_id if linked else None
    if contact_id:
        contact = db.query(M.Contact.name).filter(M.Contact.id == contact_id).first()
        return contact[0] if contact else ""
    return ""


def _created_by(db: Session, entity_type: str, entity_id) -> tuple:
    """Look up the creating actor from the audit log (never trusted client data)."""
    row = (
        db.query(M.AuditLog.actor_id, M.AuditLog.actor_email)
        .filter(
            M.AuditLog.entity_type == entity_type,
            M.AuditLog.entity_id == entity_id,
        )
        .order_by(M.AuditLog.timestamp.asc())
        .first()
    )
    if row and row.actor_id:
        user = db.query(M.User.full_name).filter(M.User.id == row.actor_id).first()
        return row.actor_id, row.actor_email or (user[0] if user else None)
    return None, None


def _financial_year_open(db: Session, tenant_id, doc_date) -> bool:
    fy = (
        db.query(M.FinancialYear.status)
        .filter(
            M.FinancialYear.tenant_id == tenant_id,
            M.FinancialYear.start_date <= doc_date,
            M.FinancialYear.end_date >= doc_date,
        )
        .first()
    )
    if fy is None:
        return False
    return fy.status in ("CURRENT", "READY_TO_CLOSE")


DOC_SPECS = [
    {
        "type": "Invoice", "model": M.Invoice, "journal_source": "INVOICE",
        "stock_ref": "INVOICE", "number": M.Invoice.invoice_number,
        "date": M.Invoice.issue_date, "amount": M.Invoice.total,
    },
    {
        "type": "Bill", "model": M.Bill, "journal_source": "BILL",
        "stock_ref": "BILL", "number": M.Bill.bill_number,
        "date": M.Bill.issue_date, "amount": M.Bill.total,
    },
    {
        "type": "Expense", "model": M.Expense, "journal_source": "EXPENSE",
        "stock_ref": None, "number": M.Expense.expense_number,
        "date": M.Expense.expense_date, "amount": M.Expense.total,
    },
    {
        "type": "CreditNote", "model": M.CreditNote, "journal_source": "CREDIT_NOTE",
        "stock_ref": "CREDIT_NOTE", "number": M.CreditNote.credit_note_number,
        "date": M.CreditNote.issue_date, "amount": M.CreditNote.total,
    },
    {
        "type": "DebitNote", "model": M.DebitNote, "journal_source": "DEBIT_NOTE",
        "stock_ref": "DEBIT_NOTE", "number": M.DebitNote.debit_note_number,
        "date": M.DebitNote.issue_date, "amount": M.DebitNote.total,
    },
]


def build_report(db: Session, tenant_filter: uuid.UUID | None) -> list[dict]:
    records: list[dict] = []

    for spec in DOC_SPECS:
        model = spec["model"]
        q = db.query(model).filter(model.status == "DRAFT", model.deleted_at.is_(None))
        if tenant_filter:
            q = q.filter(model.tenant_id == tenant_filter)
        rows = q.all()

        for row in rows:
            tenant = db.query(M.Tenant.legal_name).filter(M.Tenant.id == row.tenant_id).first()
            problems: list[str] = []
            suspicious: list[str] = []

            journal_exists = (
                db.query(M.JournalEntry.id)
                .filter(
                    M.JournalEntry.tenant_id == row.tenant_id,
                    M.JournalEntry.source_type == spec["journal_source"],
                    M.JournalEntry.source_id == row.id,
                )
                .first()
                is not None
            )
            stock_exists = False
            if spec["stock_ref"]:
                stock_exists = (
                    db.query(M.StockLedger.id)
                    .filter(
                        M.StockLedger.tenant_id == row.tenant_id,
                        M.StockLedger.reference_type == spec["stock_ref"],
                        M.StockLedger.reference_id == row.id,
                    )
                    .first()
                    is not None
                )

            doc_date = getattr(row, spec["date"].key)
            amount = getattr(row, spec["amount"].key) or Decimal("0")
            party = _party_name(db, row)

            # ── Validation findings ──
            if journal_exists:
                suspicious.append("DRAFT record already has a journal entry (partial posting)")
            if stock_exists:
                suspicious.append("DRAFT record already has stock-ledger entries")
            if not isinstance(row, M.Expense) and _lines_count(db, model, row.id) == 0:
                problems.append("No line items")
            if not isinstance(row, M.Expense) and not _line_subtotals_consistent(
                db, model, row.id, row.subtotal
            ):
                problems.append("Line subtotals do not match header subtotal")
            if not _total_formula_ok(row):
                problems.append("Header total does not match its tax/discount parts")
            if amount <= 0:
                problems.append("Amount is not positive")
            if isinstance(row, M.Expense):
                if not row.expense_category_id:
                    problems.append("No expense category (no linked account)")
                if not row.bank_account_id:
                    problems.append("No cash/bank account selected")
            elif getattr(row, "contact_id", None) is None and isinstance(row, (M.Invoice, M.Bill)):
                problems.append("No customer/vendor contact")
            if not _financial_year_open(db, row.tenant_id, doc_date):
                problems.append("No open financial year covers the transaction date")

            created_by_id, created_by_email = _created_by(db, spec["type"], row.id)

            safe_to_post = (not problems) and (not suspicious) and (not journal_exists) and (not stock_exists)

            if journal_exists or stock_exists:
                disposition = "REVIEW"
            elif safe_to_post:
                disposition = "POST"
            elif amount == 0 or problems.count("No line items") > 0:
                disposition = "ARCHIVE"
            else:
                disposition = "REVIEW"

            records.append({
                "document_type": spec["type"],
                "document_id": str(row.id),
                "document_number": getattr(row, spec["number"].key, ""),
                "tenant_id": str(row.tenant_id),
                "tenant_name": tenant[0] if tenant else "",
                "created_at": row.created_at.isoformat() if row.created_at else "",
                "created_by": str(created_by_id) if created_by_id else "",
                "created_by_email": created_by_email or "",
                "party": party,
                "transaction_date": str(doc_date),
                "amount": str(amount),
                "status": row.status,
                "journal_entry_exists": journal_exists,
                "stock_ledger_exists": stock_exists,
                "safe_to_post": safe_to_post,
                "validation_problems": "; ".join(problems),
                "suggested_disposition": disposition,
                "suspicious": "; ".join(suspicious),
            })

    return records


# ---------------------------------------------------------------------------
# Gate 2 — anomaly scan across ALL ledger documents (not just drafts)
# ---------------------------------------------------------------------------

STOCK_SOURCE_TYPES = {"INVOICE", "BILL", "CREDIT_NOTE", "DEBIT_NOTE",
                      "SALES_RETURN", "PURCHASE_RETURN"}


def _journal_for(db: Session, source_type: str, source_id) -> M.JournalEntry | None:
    return (
        db.query(M.JournalEntry)
        .filter(
            M.JournalEntry.source_type == source_type,
            M.JournalEntry.source_id == source_id,
        )
        .first()
    )


def _doc_lines_goods(db: Session, model, doc_id) -> bool:
    """True if any line of the document references a GOODS product."""
    line_model = {
        M.Invoice: M.InvoiceLine, M.Bill: M.BillLine,
        M.CreditNote: M.CreditNoteLine, M.DebitNote: M.DebitNoteLine,
        M.SalesReturn: M.SalesReturnLine, M.PurchaseReturn: M.PurchaseReturnLine,
    }.get(model)
    if line_model is None:
        return False
    fk = [c for c in line_model.__table__.columns if c.foreign_keys][0]
    goods = (
        db.query(line_model.product_id)
        .join(M.Product, M.Product.id == line_model.product_id)
        .filter(fk == doc_id, M.Product.product_type == "GOODS")
        .first()
    )
    return goods is not None


def _account_missing(db: Session, account_id) -> bool:
    if account_id is None:
        return False
    return db.query(M.Account.id).filter(M.Account.id == account_id).first() is None


def build_anomalies(db: Session, tenant_filter: uuid.UUID | None) -> list[dict]:
    """Cross-document integrity anomalies (read-only).

    Covers: posted-without-journal, draft-with-journal, stock-without-journal,
    journal-without-stock (goods docs), unbalanced journals, orphan
    reversal/replacement links, duplicate source linkage, invalid totals,
    missing financial year, missing account mapping, orphan stock links.
    """
    anomalies: list[dict] = []

    def add(category, doc_type, doc_id, doc_number, tenant_id, detail):
        anomalies.append({
            "category": category,
            "document_type": doc_type,
            "document_id": str(doc_id) if doc_id else "",
            "document_number": doc_number or "",
            "tenant_id": str(tenant_id) if tenant_id else "",
            "detail": detail,
        })

    for spec in DOC_SPECS:
        model = spec["model"]
        q = db.query(model).filter(model.deleted_at.is_(None))
        if tenant_filter:
            q = q.filter(model.tenant_id == tenant_filter)
        for row in q.all():
            journal = _journal_for(db, spec["journal_source"], row.id)
            doc_date = getattr(row, spec["date"].key)
            amount = getattr(row, spec["amount"].key) or Decimal("0")

            # 1. POSTED (or paid) without any journal entry.
            if row.status in ("POSTED", "PARTIALLY_PAID", "PAID") and journal is None:
                add("POSTED_WITHOUT_JOURNAL", spec["type"], row.id,
                    getattr(row, spec["number"].key, ""), row.tenant_id,
                    f"status={row.status} but no {spec['journal_source']} journal entry")

            # 2. DRAFT with a journal entry (partial posting).
            if row.status == "DRAFT" and journal is not None:
                add("DRAFT_WITH_JOURNAL", spec["type"], row.id,
                    getattr(row, spec["number"].key, ""), row.tenant_id,
                    f"status=DRAFT but {spec['journal_source']} journal exists")

            # 3. Stock movement without a journal entry.
            if spec["stock_ref"] and spec["stock_ref"] in STOCK_SOURCE_TYPES:
                stock_exists = (
                    db.query(M.StockLedger.id)
                    .filter(M.StockLedger.reference_type == spec["stock_ref"],
                            M.StockLedger.reference_id == row.id)
                    .first()
                    is not None
                )
                if stock_exists and journal is None:
                    add("STOCK_WITHOUT_JOURNAL", spec["type"], row.id,
                        getattr(row, spec["number"].key, ""), row.tenant_id,
                        "stock movement exists but no journal entry")
                if journal is not None and not stock_exists and _doc_lines_goods(db, model, row.id):
                    # Invoices converted from delivery challans deliberately have
                    # no INVOICE stock rows (stock moved at challan dispatch), so
                    # skip that legitimate class to avoid false positives.
                    challan_sourced = isinstance(row, M.Invoice) and (
                        db.query(M.DeliveryChallan.id)
                        .filter(M.DeliveryChallan.converted_to_invoice_id == row.id)
                        .first()
                        is not None
                    )
                    if not challan_sourced:
                        add("JOURNAL_WITHOUT_STOCK", spec["type"], row.id,
                            getattr(row, spec["number"].key, ""), row.tenant_id,
                            "journal exists but goods document has no stock movement")

            # 4. Invalid totals on non-draft documents.
            if row.status != "DRAFT" and not _total_formula_ok(row):
                add("INVALID_TOTALS", spec["type"], row.id,
                    getattr(row, spec["number"].key, ""), row.tenant_id,
                    "header total does not match tax/discount parts")

            # 5. Missing open financial year.
            if not _financial_year_open(db, row.tenant_id, doc_date):
                add("MISSING_FINANCIAL_YEAR", spec["type"], row.id,
                    getattr(row, spec["number"].key, ""), row.tenant_id,
                    f"no open financial year covers {doc_date}")

            # 6. Expenses without required account mapping.
            if isinstance(row, M.Expense):
                missing = []
                if not row.expense_category_id:
                    missing.append("no category")
                if not row.bank_account_id:
                    missing.append("no cash/bank account")
                if missing:
                    add("MISSING_ACCOUNT_MAPPING", "Expense", row.id, row.expense_number,
                        row.tenant_id, ", ".join(missing))

            # 7. Journal lines referencing a missing account.
            if journal is not None:
                bad = [ln.account_id for ln in journal.lines if _account_missing(db, ln.account_id)]
                if bad:
                    add("MISSING_ACCOUNT_MAPPING", spec["type"], row.id,
                        getattr(row, spec["number"].key, ""), row.tenant_id,
                        f"journal lines reference missing accounts")

            # 8. Amount <= 0 on posted documents.
            if row.status != "DRAFT" and amount <= 0:
                add("INVALID_TOTALS", spec["type"], row.id,
                    getattr(row, spec["number"].key, ""), row.tenant_id,
                    f"posted amount {amount} is not positive")

    # ── Unbalanced journals (any source) ──
    jq = db.query(M.JournalEntry).filter(M.JournalEntry.is_locked.is_(True))
    if tenant_filter:
        jq = jq.filter(M.JournalEntry.tenant_id == tenant_filter)
    for je in jq.all():
        debit = sum((l.amount or 0) for l in je.lines if l.direction == "DEBIT")
        credit = sum((l.amount or 0) for l in je.lines if l.direction == "CREDIT")
        if abs(Decimal(str(debit)) - Decimal(str(credit))) > Decimal("0.01"):
            add("UNBALANCED_JOURNAL", je.source_type, je.id, je.reference_number or "",
                je.tenant_id, f"debits={debit} credits={credit}")

    # ── Orphan reversal / replacement / movement links ──
    for je in db.query(M.JournalEntry).filter(
        M.JournalEntry.reversal_transaction_id.isnot(None),
    ).all():
        target = db.query(M.JournalEntry.id).filter(
            M.JournalEntry.id == je.reversal_transaction_id
        ).first()
        if target is None:
            add("ORPHAN_REVERSAL_LINK", je.source_type, je.id, je.reference_number or "",
                je.tenant_id, "reversal_transaction_id points at a missing entry")
    for je in db.query(M.JournalEntry).filter(
        M.JournalEntry.replacement_transaction_id.isnot(None),
    ).all():
        if db.query(M.JournalEntry.id).filter(
            M.JournalEntry.id == je.replacement_transaction_id
        ).first() is None:
            add("ORPHAN_REPLACEMENT_LINK", je.source_type, je.id, je.reference_number or "",
                je.tenant_id, "replacement link points at a missing entry")
    for move in db.query(M.StockLedger).filter(
        M.StockLedger.reverses_movement_id.isnot(None),
    ).all():
        if db.query(M.StockLedger.id).filter(
            M.StockLedger.id == move.reverses_movement_id
        ).first() is None:
            add("ORPHAN_STOCK_LINK", move.reference_type, move.id, "", move.tenant_id,
                "reverses_movement_id points at a missing movement")

    # ── Duplicate source linkage (stock) — exact duplicate movements ──
    dup_rows = (
        db.query(
            M.StockLedger.tenant_id, M.StockLedger.reference_type,
            M.StockLedger.reference_id, M.StockLedger.product_id,
            M.StockLedger.quantity, M.StockLedger.warehouse_id,
            func.count(M.StockLedger.id),
        )
        .group_by(
            M.StockLedger.tenant_id, M.StockLedger.reference_type,
            M.StockLedger.reference_id, M.StockLedger.product_id,
            M.StockLedger.quantity, M.StockLedger.warehouse_id,
        )
        .having(func.count(M.StockLedger.id) > 1)
        .all()
    )
    for d in dup_rows:
        add("DUPLICATE_SOURCE_LINKAGE", d[1], d[2], "", d[0],
            f"{d[4]}x duplicate stock movement for product {d[3]} (count={d[6]})")

    return anomalies


def render_anomalies(records: list[dict], fmt: str, out) -> None:
    if not records:
        if fmt == "json":
            out.write('"anomalies": []')
        return
    if fmt == "json":
        json.dump(records, out, indent=2, default=str)
        return
    if fmt == "csv":
        fields = ["category", "document_type", "document_id", "document_number",
                  "tenant_id", "detail"]
        writer = csv.DictWriter(out, fieldnames=fields)
        writer.writeheader()
        for r in records:
            writer.writerow(r)
        return
    header = ("CATEGORY", "DOC", "NUMBER", "TENANT", "DETAIL")
    widths = [26, 14, 16, 22, 70]
    out.write("\n── Integrity anomalies (all statuses) ──\n")
    out.write("  ".join(str(v)[:w].ljust(w) for v, w in zip(header, widths)) + "\n")
    out.write("-" * sum(widths) + "\n")
    for r in records:
        out.write("  ".join(str(r[k])[:w].ljust(w) for k, w in zip(
            ("category", "document_type", "document_number", "tenant_id", "detail"), widths)) + "\n")


def render(records: list[dict], fmt: str, out) -> None:
    if fmt == "json":
        json.dump({"generated_at": datetime.now().isoformat(), "drafts": records},
                  out, indent=2, default=str)
        out.write("\n")
        return

    if fmt == "csv":
        fields = [
            "document_type", "document_id", "document_number", "tenant_id",
            "tenant_name", "created_at", "created_by", "created_by_email",
            "party", "transaction_date", "amount", "status",
            "journal_entry_exists", "stock_ledger_exists", "safe_to_post",
            "validation_problems", "suggested_disposition", "suspicious",
        ]
        writer = csv.DictWriter(out, fieldnames=fields)
        writer.writeheader()
        for r in records:
            writer.writerow(r)
        return

    # Table
    header = ("TYPE", "NUMBER", "TENANT", "PARTY", "DATE", "AMOUNT",
              "JRNL", "STOCK", "SAFE", "DISPOSITION", "PROBLEMS / SUSPICIOUS")
    widths = [10, 16, 22, 20, 10, 14, 5, 5, 5, 11, 60]
    def fmt_row(values):
        return "  ".join(str(v)[:w].ljust(w) for v, w in zip(values, widths))
    out.write(fmt_row(header) + "\n")
    out.write("-" * sum(widths) + "\n")
    for r in records:
        problems = r["validation_problems"]
        if r["suspicious"]:
            problems = f'{problems}; SUSPICIOUS: {r["suspicious"]}'.lstrip("; ")
        out.write(fmt_row((
            r["document_type"], r["document_number"], r["tenant_name"],
            r["party"], r["transaction_date"], r["amount"],
            "Y" if r["journal_entry_exists"] else "N",
            "Y" if r["stock_ledger_exists"] else "N",
            "Y" if r["safe_to_post"] else "N",
            r["suggested_disposition"], problems,
        )) + "\n")


def summarize(records: list[dict], anomalies: list[dict] | None = None) -> str:
    anomalies = anomalies or []
    lines = ["", "── Summary ──"]
    by_type: dict[str, int] = {}
    by_disp: dict[str, int] = {}
    suspicious = 0
    for r in records:
        by_type[r["document_type"]] = by_type.get(r["document_type"], 0) + 1
        by_disp[r["suggested_disposition"]] = by_disp.get(r["suggested_disposition"], 0) + 1
        if r["suspicious"]:
            suspicious += 1
    by_cat: dict[str, int] = {}
    for a in anomalies:
        by_cat[a["category"]] = by_cat.get(a["category"], 0) + 1
    lines.append(f"Total DRAFT ledger documents: {len(records)}")
    lines.append("By type: " + ", ".join(f"{k}={v}" for k, v in sorted(by_type.items())))
    lines.append("Suggested disposition: " + ", ".join(f"{k}={v}" for k, v in sorted(by_disp.items())))
    lines.append(f"Suspicious/inconsistent draft records: {suspicious}")
    lines.append(f"Integrity anomalies (all statuses): {len(anomalies)}")
    if by_cat:
        lines.append("Anomalies by category: " + ", ".join(
            f"{k}={v}" for k, v in sorted(by_cat.items())))
    lines.append("")
    lines.append("Reminder: this report is read-only. No draft was posted, deleted, or archived.")
    return "\n".join(lines)


def main() -> int:
    # Console encodings on Windows (cp1252) cannot represent the box-drawing
    # characters used in the summary; normalize to UTF-8 with replacement.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-url", default=os.getenv("DATABASE_URL", "sqlite:///./bookkeeping.db"))
    parser.add_argument("--tenant", type=uuid.UUID, default=None)
    parser.add_argument("--format", choices=["table", "csv", "json"], default="table")
    parser.add_argument("--out", default=None, help="Output file (default: stdout)")
    args = parser.parse_args()

    engine = build_engine(args.db_url)
    session_factory = sessionmaker(bind=engine)
    with session_factory() as db:
        records = build_report(db, args.tenant)
        anomalies = build_anomalies(db, args.tenant)

    def _emit(out):
        if args.format == "json":
            json.dump({
                "generated_at": datetime.now().isoformat(),
                "drafts": records,
                "anomalies": anomalies,
            }, out, indent=2, default=str)
            out.write("\n")
        elif args.format == "csv":
            render(records, "csv", out)
            out.write("\nANOMALIES\n")
            render_anomalies(anomalies, "csv", out)
        else:
            render(records, "table", out)
            render_anomalies(anomalies, "table", out)

    if args.out:
        with open(args.out, "w", newline="", encoding="utf-8") as fh:
            _emit(fh)
    else:
        _emit(sys.stdout)

    # Human summary goes to stderr for machine-readable formats so stdout
    # stays parseable JSON/CSV; for the table format it follows the report.
    print(summarize(records, anomalies), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
