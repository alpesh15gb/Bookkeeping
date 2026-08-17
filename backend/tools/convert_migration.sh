#!/usr/bin/env bash
#
# convert_migration.sh — convert Vyapar (.vyb) / Tally (.xml) to reviewable CSVs
# using the SAME import code the ApexBooks app runs in production (tools/legacy_to_csv.py).
# The CSVs you review are literally what would land in the books.
#
# Usage:
#   ./tools/convert_migration.sh                 # 'all': auto-detect Vyapar, Tally via TALLY_XML
#   ./tools/convert_migration.sh vyapar FILE     # convert one Vyapar backup
#   ./tools/convert_migration.sh tally  FILE     # convert one Tally XML export
#
# Env overrides:
#   APEX_BACKEND_DIR    backend repo root        (default: parent of this script's dir)
#   APEX_MIGRATION_OUT  output directory         (default: ./migration-<timestamp>)
#   TALLY_XML           path to Tally export     (used by 'all' mode)
#
# Output (in the output dir):
#   14 CSVs, report.txt (reconciliation), summary.json, bundle.xlsx (if openpyxl),
#   and a migration-bundle-<timestamp>.zip of just the CSVs, ready for the app's
#   Migration screen (Validate → confirm → Import).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${APEX_BACKEND_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
TOOL="$BACKEND_DIR/tools/legacy_to_csv.py"

if [ ! -f "$TOOL" ]; then
  echo "ERROR: converter not found at $TOOL" >&2
  echo "Pull the backend repo first:  git -C \"$BACKEND_DIR\" pull origin master" >&2
  exit 1
fi

# ── Find Python: project venv first, then system ─────────────────────────
PY=""
for cand in \
  "$BACKEND_DIR/.venv313/Scripts/python.exe" \
  "$BACKEND_DIR/.venv313/bin/python" \
  "$BACKEND_DIR/.venv/Scripts/python.exe" \
  "$BACKEND_DIR/.venv/bin/python"; do
  if [ -x "$cand" ]; then PY="$cand"; break; fi
done
if [ -z "$PY" ]; then
  PY="$(command -v python3 || command -v python || true)"
fi
if [ -z "$PY" ]; then
  echo "ERROR: no Python found. Install one or set the venv path." >&2
  exit 1
fi

# Git Bash on Windows: the Windows Python can't read POSIX paths — convert.
to_win () {
  if [[ "$PY" == *.exe ]] && command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# Excel bundle is optional — only when openpyxl is installed.
XLSX_FLAG=""
if "$PY" -c "import openpyxl" >/dev/null 2>&1; then XLSX_FLAG="--xlsx"; fi

# ── Parse args ────────────────────────────────────────────────────────────
MODE="${1:-all}"
shift || true
for a in "$@"; do
  case "$a" in
    --xlsx) XLSX_FLAG="--xlsx" ;;
    --no-xlsx) XLSX_FLAG="" ;;
    -*) echo "ERROR: unknown flag: $a" >&2; exit 1 ;;
  esac
done

OUT="${APEX_MIGRATION_OUT:-$(pwd)/migration-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

convert_one () {  # convert_one <kind> <file>
  local kind="$1" file="$2"
  if [ ! -f "$file" ]; then
    echo "ERROR: $kind file not found: $file" >&2
    exit 1
  fi
  echo "── Converting $kind: $file"
  ( cd "$BACKEND_DIR" && "$PY" -m tools.legacy_to_csv \
      "$kind" "$(to_win "$file")" --out "$(to_win "$OUT")" $XLSX_FLAG )
}

# ── Decide what to convert ────────────────────────────────────────────────
DO_VYAPAR=""
DO_TALLY=""

if [ "$MODE" = "vyapar" ]; then DO_VYAPAR="${1:?usage: convert_migration.sh vyapar FILE}"; fi
if [ "$MODE" = "tally"  ]; then DO_TALLY="${1:?usage: convert_migration.sh tally FILE}"; fi

if [ "$MODE" = "all" ]; then
  # Auto-detect Vyapar in common locations (override with APEX_VYAPAR)
  for cand in \
    "${APEX_VYAPAR:-}" \
    "$HOME/vyapar-backup/Vyapar.vyb" \
    "/e/vyapar-backup/Vyapar.vyb" \
    "$(pwd)/Vyapar.vyb" \
    "$(pwd)"/*.vyb; do
    [ -n "$cand" ] && [ -f "$cand" ] && DO_VYAPAR="$cand" && break
  done

  # Tally via env, or a lone .xml in cwd; otherwise just note it.
  for cand in "${TALLY_XML:-}" "$(pwd)"/*.xml; do
    [ -n "$cand" ] && [ -f "$cand" ] && DO_TALLY="$cand" && break
  done

  if [ -z "$DO_VYAPAR" ] && [ -z "$DO_TALLY" ]; then
    echo "ERROR: nothing found to convert." >&2
    echo "Run with explicit files:" >&2
    echo "  $0 vyapar /path/to/backup.vyb" >&2
    echo "  $0 tally  /path/to/tally-export.xml" >&2
    exit 1
  fi
fi

# ── Convert ───────────────────────────────────────────────────────────────
[ -n "$DO_VYAPAR" ] && convert_one vyapar "$DO_VYAPAR"
[ -n "$DO_TALLY"  ] && convert_one tally  "$DO_TALLY"
if [ "$MODE" = "all" ] && [ -z "$DO_TALLY" ]; then
  echo "── (no Tally XML found — skipped. Pass one with: $0 tally FILE, or set TALLY_XML)"
fi

# ── Zip just the CSVs for the app's Migration screen ──────────────────────
ZIP="$(pwd)/migration-bundle-$(date +%Y%m%d-%H%M%S).zip"
"$PY" - "$(to_win "$OUT")" "$(to_win "$ZIP")" <<'PYEOF'
import sys, zipfile
from pathlib import Path
out_dir, zip_path = Path(sys.argv[1]), Path(sys.argv[2])
csvs = sorted(out_dir.glob("*.csv"))
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
    for csv in csvs:
        zf.write(csv, csv.name)
print(f"   Zipped {len(csvs)} CSVs -> {zip_path}")
PYEOF

# ── Report ────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  CONVERSION COMPLETE"
echo "  Output: $OUT"
echo "  Upload bundle: $ZIP"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "── Reconciliation report (report.txt) ──"
sed -n '1,60p' "$OUT/report.txt" 2>/dev/null || cat "$OUT/report.txt" 2>/dev/null || true
echo ""
echo "── Next: in the app, go to Migration → upload $ZIP →"
echo "   Validate (dry run) → check the totals → confirm → Import."
echo "   The .xlsx is review-only; never re-import from it."
