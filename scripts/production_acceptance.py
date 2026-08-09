"""Run the ApexBooks production acceptance gate on Windows or Linux.

Usage:
    python scripts/production_acceptance.py
    python scripts/production_acceptance.py --backend-only
    python scripts/production_acceptance.py --frontend-only

The default gate intentionally runs the complete backend and Flutter suites.
It does not run synthetic scale benchmarks; this gate protects correctness,
workflow continuity, accounting, GST, inventory, reports, audit and UI code.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
FRONTEND = ROOT / "frontend"


def run(label: str, command: list[str], cwd: Path, env: dict | None = None) -> None:
    print(f"\n=== {label} ===", flush=True)
    result = subprocess.run(command, cwd=cwd, check=False, env=env)
    if result.returncode:
        raise SystemExit(f"{label} failed with exit code {result.returncode}.")


def verify_single_alembic_head(python: str) -> None:
    print("\n=== Single Alembic head ===", flush=True)
    result = subprocess.run(
        [python, "-m", "alembic", "heads"],
        cwd=BACKEND,
        check=False,
        capture_output=True,
        text=True,
    )
    output = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    if output:
        print(output, flush=True)
    heads = [line for line in result.stdout.splitlines() if "(head)" in line]
    if result.returncode or len(heads) != 1:
        raise SystemExit(
            "Alembic migration graph must contain exactly one head; "
            f"found {len(heads)}."
        )


def run_backend_suites(python: str) -> None:
    # A number of legacy unittest modules rebuild the shared SQLite schema.
    # Run each file in its own process so no workflow inherits another file's
    # tenants, numbering series or schema state.
    suites = sorted(
        path.relative_to(BACKEND).as_posix()
        for path in (BACKEND / "tests").rglob("test_*.py")
    )
    for suite in suites:
        command = [python, "-m", "pytest", suite]
        if suite.endswith("test_uat_business_simulation.py"):
            # Phase 7 contains timing/volume benchmarks, intentionally outside
            # this correctness and usability stabilization gate.
            command.extend(["-k", "not TestUAT_Phase7_Stress"])
        run(f"Backend regression: {suite}", command, BACKEND)

    # PostgreSQL integration suite: MANDATORY in the production acceptance
    # gate (REQUIRE_POSTGRES_TESTS=1 turns an unavailable PostgreSQL into a
    # hard failure, never a silent skip).  The suite creates its own test
    # database and runs the real Alembic migrations.
    env = dict(os.environ)
    env["REQUIRE_POSTGRES_TESTS"] = "1"
    if "TEST_DATABASE_URL" not in env:
        env["TEST_DATABASE_URL"] = "postgresql://postgres:postgres@localhost:5432/postgres"
    run(
        "PostgreSQL integration (RLS / roles / concurrency / idempotency)",
        [python, "-m", "pytest", "pg_tests", "-q"],
        BACKEND,
        env=env,
    )


def executable(name: str) -> str:
    value = shutil.which(name)
    if not value:
        raise SystemExit(f"Required executable '{name}' was not found on PATH.")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description="ApexBooks production acceptance gate")
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--backend-only", action="store_true")
    scope.add_argument("--frontend-only", action="store_true")
    args = parser.parse_args()

    if not args.frontend_only:
        python = executable("python")
        verify_single_alembic_head(python)
        run_backend_suites(python)

    if not args.backend_only:
        flutter = executable("flutter")
        run("Flutter static analysis", [flutter, "analyze", "--no-fatal-infos"], FRONTEND)
        run("Flutter UI and domain regression", [flutter, "test"], FRONTEND)

    print("\nApexBooks production acceptance gate PASSED.", flush=True)


if __name__ == "__main__":
    main()
