#!/usr/bin/env python3
"""CI helper: fail unless the Alembic script directory has exactly one head.

Runs from backend/ (the alembic.ini lives there).  The squashed-baseline
chain is linear: 20260524_0001 .. 20260810_0001 (legacy) ->
20260811_0000_squashed_baseline -> .. -> 20260811_0004_least_privilege_grants,
so exactly one head must be reported.
"""

import subprocess
import sys


def main() -> int:
    proc = subprocess.run(
        [sys.executable, "-m", "alembic", "heads"],
        capture_output=True,
        text=True,
    )
    output = proc.stdout + proc.stderr
    heads = [line for line in proc.stdout.splitlines() if "(head)" in line]
    if proc.returncode:
        print(output, file=sys.stderr)
        print("FAIL: alembic heads errored", file=sys.stderr)
        return 1
    if len(heads) != 1:
        print(output, file=sys.stderr)
        print(f"FAIL: expected exactly one Alembic head, found {len(heads)}", file=sys.stderr)
        return 1
    print(output)
    print(f"OK: exactly one Alembic head -> {heads[0].strip()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
