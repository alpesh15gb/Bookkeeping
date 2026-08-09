#!/usr/bin/env python3
"""
Legacy ledger analysis — read-only categorization for Phase 1 Gate 3.

Read-only. Connects with a read-only transaction (PostgreSQL) or the SQLite
`query_only` pragma, runs only SELECTs, and reports:

* how many JournalEntry rows exist with is_locked=False, categorized by why
  they are unlocked (system roll-forward vs draft-era document vs manual),
  broken down by source_type and tenant
* of those, how many already carry created_by / posted_by / source_channel
* backfill determinability: for entries without created_by, whether the audit
  log can identify the actor (audit record matching the entry's source
  document) — the only acceptable source for backfill
* the same attribution analysis for StockLedger rows (created_by /
  source_channel NULL counts)

It NEVER writes, locks, or backfills anything — it produces the plan input so
a human can decide what to lock and what to leave for review.

Usage:
    python scripts/analyze_legacy_ledger.py [--db-url URL] [--tenant UUID]
        [--format table|csv|json]
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import uuid
from datetime import datetime
from decimal import Decimal

import sqlalchemy as sa
from sqlalchemy import event, func
from sqlalchemy.orm import Session, sessionmaker

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(_HERE, "..")))
sys.path.insert(0, os.path.abspath(os.path.join(_HERE, "..", "src")))

from src.infrastructure.database import models as M  # noqa: E402


SYSTEM_SOURCE_TYPES = frozenset({"YEAR_END", "OPENING_BALANCE"})
DOCUMENT_SOURCE_TYPES = frozenset({
    "INVOICE", "BILL", "EXPENSE", "CREDIT_NOTE", "DEBIT_NOTE",
    "SALES_RETURN", "PURCHASE_RETURN", "PAYMENT", "BILL_PAYMENT",
    "JOURNAL_REVERSAL", "INVOICE_REVERSAL", "BILL_REVERSAL",
    "CREDIT_NOTE_REVERSAL", "DEBIT_NOTE_REVERSAL",
})


def build_engine(db_url: str):
    connect_args = {}
    if db_url.startswith("postgresql"):
        connect_args["options"] = "-c default_transaction_read_only=on"
    engine = sa.create_engine(db_url, connect_args=connect_args, pool_pre_ping=True)

    if engine.dialect.name == "sqlite":
        @event.listens_for(engine, "connect")
        def _sqlite_read_only(dbapi_conn, _record):
            dbapi_conn.execute("PRAGMA query_only = ON")

    return engine


def _audit_actor_for(db: Session, source_type: str, source_id) -> tuple | None:
    """Best-effort actor from the audit log (never invented)."""
    entity_type = {
        "INVOICE": "Invoice", "BILL": "Bill", "EXPENSE": "Expense",
        "CREDIT_NOTE": "CreditNote", "DEBIT_NOTE": "DebitNote",
        "SALES_RETURN": "SalesReturn", "PURCHASE_RETURN": "PurchaseReturn",
        "PAYMENT": "Payment",
    }.get(source_type)
    if entity_type is None or source_id is None:
        return None
    row = (
        db.query(M.AuditLog.actor_id, M.AuditLog.actor_email)
        .filter(M.AuditLog.entity_type == entity_type, M.AuditLog.entity_id == source_id)
        .order_by(M.AuditLog.timestamp.asc())
        .first()
    )
    if row and row.actor_id:
        return row.actor_id, row.actor_email
    return None


def analyze(db: Session, tenant_filter: uuid.UUID | None) -> dict:
    result = {
        "journal_unlocked": [],     # per-entry summary rows
        "journal_locked_total": 0,
        "stock_attribution": {},    # NULL-count summary
        "journal_attribution": {},  # NULL-count summary (all entries)
    }

    jq = db.query(M.JournalEntry)
    if tenant_filter:
        jq = jq.filter(M.JournalEntry.tenant_id == tenant_filter)

    total = 0
    locked = 0
    unlocked = 0
    attr_missing = {"created_by": 0, "posted_by": 0, "posted_at": 0, "source_channel": 0}
    backfill_determinable = 0
    backfill_unknown = 0

    for je in jq.all():
        total += 1
        if je.is_locked:
            locked += 1
        else:
            unlocked += 1
            if not je.created_by:
                attr_missing["created_by"] += 1
            if not je.posted_by:
                attr_missing["posted_by"] += 1
            if not je.posted_at:
                attr_missing["posted_at"] += 1
            if not je.source_channel:
                attr_missing["source_channel"] += 1

            if je.source_type in SYSTEM_SOURCE_TYPES:
                category = "system_rollforward"
            elif je.source_type in DOCUMENT_SOURCE_TYPES:
                category = "draft_era_document"
            elif je.source_type == "MANUAL":
                category = "draft_era_manual"
            else:
                category = "other"

            actor = _audit_actor_for(db, je.source_type, je.source_id)
            if je.created_by:
                actor_status = "present"
            elif actor:
                actor_status = "determinable_from_audit"
                backfill_determinable += 1
            else:
                actor_status = "unknown"
                backfill_unknown += 1

            tenant = db.query(M.Tenant.legal_name).filter(M.Tenant.id == je.tenant_id).first()
            result["journal_unlocked"].append({
                "journal_id": str(je.id),
                "tenant_id": str(je.tenant_id),
                "tenant_name": tenant[0] if tenant else "",
                "source_type": je.source_type,
                "reference_number": je.reference_number or "",
                "entry_date": str(je.entry_date),
                "category": category,
                "created_by_present": bool(je.created_by),
                "posted_by_present": bool(je.posted_by),
                "source_channel_present": bool(je.source_channel),
                "actor_status": actor_status,
            })

    result["journal_locked_total"] = locked
    result["journal_unlocked_total"] = unlocked
    result["journal_attribution"] = attr_missing

    # Stock attribution (all rows).
    sq = db.query(M.StockLedger)
    if tenant_filter:
        sq = sq.filter(M.StockLedger.tenant_id == tenant_filter)
    stock_total = 0
    stock_missing = {"created_by": 0, "source_channel": 0}
    for move in sq.all():
        stock_total += 1
        if not move.created_by:
            stock_missing["created_by"] += 1
        if not move.source_channel:
            stock_missing["source_channel"] += 1
    result["stock_attribution"] = {"total": stock_total, **stock_missing}
    result["backfill"] = {
        "determinable_from_audit": backfill_determinable,
        "unknown": backfill_unknown,
    }
    return result


def _render(result: dict, fmt: str, out) -> None:
    if fmt == "json":
        json.dump({"generated_at": datetime.now().isoformat(), **result}, out, indent=2, default=str)
        out.write("\n")
        return
    if fmt == "csv":
        fields = ["journal_id", "tenant_id", "tenant_name", "source_type",
                  "reference_number", "entry_date", "category",
                  "created_by_present", "posted_by_present", "source_channel_present",
                  "actor_status"]
        writer = csv.DictWriter(out, fieldnames=fields)
        writer.writeheader()
        for r in result["journal_unlocked"]:
            writer.writerow(r)
        return

    out.write("\n── Legacy unlocked journal entries ──\n")
    header = ("SOURCE", "REFERENCE", "TENANT", "DATE", "CATEGORY", "ACTOR")
    widths = [22, 18, 22, 10, 22, 30]
    out.write("  ".join(str(v)[:w].ljust(w) for v, w in zip(header, widths)) + "\n")
    out.write("-" * sum(widths) + "\n")
    for r in result["journal_unlocked"]:
        out.write("  ".join(str(r[k])[:w].ljust(w) for k, w in zip(
            ("source_type", "reference_number", "tenant_name", "entry_date",
             "category", "actor_status"), widths)) + "\n")


def summarize(result: dict) -> str:
    lines = ["", "── Legacy ledger analysis ──"]
    j = result["journal_attribution"]
    lines.append(f"Journal entries total locked: {result['journal_locked_total']}")
    lines.append(f"Journal entries UNLOCKED (is_locked=False): {result['journal_unlocked_total']}")
    lines.append("  Unlocked by category: ")
    by_cat: dict[str, int] = {}
    for r in result["journal_unlocked"]:
        by_cat[r["category"]] = by_cat.get(r["category"], 0) + 1
    lines.append("    " + ", ".join(f"{k}={v}" for k, v in sorted(by_cat.items())))
    lines.append("  Missing attribution on unlocked entries: "
                 f"created_by={j['created_by']} posted_by={j['posted_by']} "
                 f"posted_at={j['posted_at']} source_channel={j['source_channel']}")
    lines.append("  Actor backfill: "
                 f"determinable_from_audit={result['backfill']['determinable_from_audit']}, "
                 f"unknown={result['backfill']['unknown']} (leave NULL — never invent)")
    s = result["stock_attribution"]
    lines.append(f"Stock movements total: {s['total']}; missing created_by={s['created_by']}, "
                 f"source_channel={s['source_channel']}")
    lines.append("")
    lines.append("Reminder: read-only. Nothing was locked, backfilled, or modified.")
    return "\n".join(lines)


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-url", default=os.getenv("DATABASE_URL", "sqlite:///./bookkeeping.db"))
    parser.add_argument("--tenant", type=uuid.UUID, default=None)
    parser.add_argument("--format", choices=["table", "csv", "json"], default="table")
    args = parser.parse_args()

    engine = build_engine(args.db_url)
    session_factory = sessionmaker(bind=engine)
    with session_factory() as db:
        result = analyze(db, args.tenant)

    if args.format == "json":
        json.dump({"generated_at": datetime.now().isoformat(), **result},
                  sys.stdout, indent=2, default=str)
        sys.stdout.write("\n")
    else:
        _render(result, args.format, sys.stdout)
        print(summarize(result), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
