#!/usr/bin/env python3
"""CI helper: run the SQLite regression suite one test file per process.

Some legacy SQLite test modules rebuild / mutate the shared ``test.db``
schema (setUp/tearDown call ``Base.metadata.drop_all`` + ``create_all``), so
running the whole suite in a single pytest process lets one file's schema
state leak into the next.  ``scripts/production_acceptance.py`` documents this
and runs each file in its own process; CI mirrors that here.

Runs from backend/.  Prints each file's pytest summary and an aggregate
pass/fail count, and exits non-zero if any file fails (the PostgreSQL suite is
run separately and is mandatory in CI via REQUIRE_POSTGRES_TESTS=1).
"""

import os
import re
import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
LOCK = BACKEND / ".ci_sqlite_suite.lock"


def _acquire_lock() -> None:
    """Refuse to run concurrently: two instances racing on the same test.db
    produce spurious sqlite3 'database schema has changed' errors (stale
    prepared statements across connections).  CI runs one instance, and this
    guard makes accidental parallel runs fail loudly instead of corrupting
    results."""
    try:
        fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        sys.exit(
            "[ci] Another ci_run_sqlite_suite.py instance is running (lock "
            f"{LOCK} exists). Refusing to run concurrently."
        )
    os.write(fd, str(os.getpid()).encode())
    os.close(fd)


def _release_lock() -> None:
    try:
        os.unlink(LOCK)
    except FileNotFoundError:
        pass


def _parse_summary(output: str) -> tuple[int, int]:
    passed = 0
    failed = 0
    for line in output.splitlines():
        stripped = line.strip()
        if " passed" in stripped or " failed" in stripped or " error" in stripped:
            pass
        m = re.search(r"(\d+) passed", stripped)
        if m:
            passed += int(m.group(1))
        m = re.search(r"(\d+) failed", stripped)
        if m:
            failed += int(m.group(1))
        m = re.search(r"(\d+) error", stripped)
        if m:
            failed += int(m.group(1))
    return passed, failed


def main() -> int:
    _acquire_lock()
    try:
        return _run()
    finally:
        _release_lock()


def _run() -> int:
    suites = sorted(
        path.relative_to(BACKEND).as_posix()
        for path in (BACKEND / "tests").rglob("test_*.py")
    )
    # Start from a clean database so results are deterministic and independent
    # of previous local runs (the SQLite suite rebuilds its schema in-place).
    for stale in (BACKEND / "test.db",):
        if stale.exists():
            stale.unlink()
    failed_files = []
    total_passed = 0
    total_failed = 0
    for suite in suites:
        command = [sys.executable, "-m", "pytest", suite, "-q"]
        if suite.endswith("test_uat_business_simulation.py"):
            # Phase 7 contains timing/volume benchmarks, intentionally outside
            # this correctness and stabilization gate (same as the production
            # acceptance runner).
            command.extend(["-k", "not TestUAT_Phase7_Stress"])
        proc = subprocess.run(command, cwd=BACKEND, capture_output=True, text=True)
        output = proc.stdout + proc.stderr
        passed, failed = _parse_summary(output)
        total_passed += passed
        total_failed += failed
        if proc.returncode:
            failed_files.append(suite)
            print(output[-4000:], file=sys.stderr)
        print(f"[ci] {suite}: {passed} passed, {failed} failed/errored", flush=True)

    if failed_files:
        print(
            f"[ci] FAIL: {len(failed_files)}/{len(suites)} SQLite test files "
            f"failed: {', '.join(failed_files)}",
            file=sys.stderr,
        )
        print(f"[ci] SQLite regression total: {total_passed} passed, {total_failed} failed/errored", flush=True)
        return 1
    print(
        f"[ci] SQLite regression: all {len(suites)} files, "
        f"{total_passed} passed, {total_failed} failed/errored",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
