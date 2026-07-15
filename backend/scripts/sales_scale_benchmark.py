"""Read-only Sales release benchmark for a production-shaped PostgreSQL dataset.

Example:
  python backend/scripts/sales_scale_benchmark.py --database-url postgresql+psycopg://... \
    --base-url https://staging.example.com/api/v1 --token ... --tenant-id ...
"""
from __future__ import annotations

import argparse
import json
import statistics
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

from sqlalchemy import create_engine, text


WORKLOADS = {
    "invoice_list": ("/invoices?page=1&limit=50", 2.0),
    "outstanding_ar": ("/reports/outstanding/receivables", 5.0),
    "ar_aging": ("/reports/aging/receivables", 5.0),
}


def _request(base_url: str, path: str, token: str, tenant_id: str) -> float:
    request = urllib.request.Request(
        urllib.parse.urljoin(base_url.rstrip("/") + "/", path.lstrip("/")),
        headers={"Authorization": f"Bearer {token}", "X-Tenant-ID": tenant_id},
    )
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        if response.status != 200:
            raise RuntimeError(f"{path}: HTTP {response.status}: {body[:300]!r}")
    return time.perf_counter() - started


def main() -> int:
    parser = argparse.ArgumentParser(description="ApexBooks Sales scale release gate")
    parser.add_argument("--database-url", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--tenant-id", required=True)
    parser.add_argument("--requests", type=int, default=100)
    parser.add_argument("--workers", type=int, default=10)
    args = parser.parse_args()

    engine = create_engine(args.database_url, pool_pre_ping=True)
    if engine.dialect.name != "postgresql":
        raise SystemExit("Release performance evidence must be collected on PostgreSQL.")
    with engine.connect() as connection:
        counts = connection.execute(text("""
            SELECT
              (SELECT count(*) FROM invoices WHERE tenant_id=:tenant) AS invoices,
              (SELECT count(*) FROM journal_lines jl JOIN journal_entries je ON je.id=jl.entry_id
                 WHERE je.tenant_id=:tenant) AS ledger_entries,
              (SELECT count(*) FROM payments WHERE tenant_id=:tenant) AS receipts
        """), {"tenant": args.tenant_id}).mappings().one()
    minimums = {"invoices": 100_000, "ledger_entries": 1_000_000, "receipts": 500_000}
    shortfalls = {key: (counts[key], minimum) for key, minimum in minimums.items() if counts[key] < minimum}
    if shortfalls:
        raise SystemExit(f"Dataset is below release scale: {shortfalls}")

    results = {"row_counts": dict(counts), "workloads": {}}
    failed = False
    for name, (path, p95_limit) in WORKLOADS.items():
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = [executor.submit(_request, args.base_url, path, args.token, args.tenant_id)
                       for _ in range(args.requests)]
            timings = [future.result() for future in as_completed(futures)]
        timings.sort()
        p95 = timings[max(0, int(len(timings) * 0.95) - 1)]
        results["workloads"][name] = {
            "requests": len(timings), "median_seconds": statistics.median(timings),
            "p95_seconds": p95, "max_seconds": max(timings), "p95_limit_seconds": p95_limit,
        }
        failed |= p95 > p95_limit
    print(json.dumps(results, indent=2, default=str))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
