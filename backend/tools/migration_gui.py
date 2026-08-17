#!/usr/bin/env python3
"""
ApexBooks Migration Converter — standalone desktop tool.

Converts a Vyapar (.vyb) backup or a Tally XML export into reviewable CSVs by
running the SAME import code the ApexBooks app uses in production against a
throwaway database. The CSVs are then zipped into `migration-bundle.zip`,
which you upload to the app's Migration screen (Validate -> confirm -> Import).

No installation needed: the packaged .exe bundles Python and every library.

Usage
-----
    ApexBooksMigration.exe                 # opens the GUI
    ApexBooksMigration.exe vyapar FILE --out DIR [--xlsx]
    ApexBooksMigration.exe tally  FILE --out DIR [--xlsx]
"""
from __future__ import annotations

import argparse
import os
import sys
import threading
import traceback
import zipfile
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

# In a frozen (PyInstaller --windowed) build there is no console: keep prints
# from crashing and route output to a log file instead.
STDOUT_BACKUP = sys.stdout


def _console(*args, **kwargs):
    """Print to a real console if one exists; otherwise no-op."""
    try:
        if sys.stdout is not None:
            print(*args, **kwargs)
    except Exception:
        pass


from tools import legacy_to_csv  # noqa: E402


def run_conversion(source_format: str, source_file: Path, out_dir: Path,
                   with_xlsx: bool) -> dict:
    """Convert, zip the CSVs, and return the summary for display."""
    source_file = Path(source_file)
    out_dir = Path(out_dir)
    code = legacy_to_csv.convert(source_format, source_file, out_dir, with_xlsx)

    # Zip just the CSVs -> the upload artifact for the app.
    zip_path = out_dir / "migration-bundle.zip"
    csvs = sorted(out_dir.glob("*.csv"))
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for csv in csvs:
            zf.write(csv, csv.name)

    summary = json_load(out_dir / "summary.json")
    summary["exit_code"] = code
    summary["bundle_zip"] = str(zip_path)
    summary["csv_count"] = len(csvs)
    summary["output_dir"] = str(out_dir)
    return summary


def json_load(path: Path) -> dict:
    import json
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _report_text(out_dir: Path) -> str:
    report = out_dir / "report.txt"
    try:
        return report.read_text(encoding="utf-8")
    except Exception:
        return ""


# ── CLI mode ──────────────────────────────────────────────────────────────
def cli_main(argv) -> int:
    parser = argparse.ArgumentParser(
        prog="ApexBooksMigration",
        description="Convert Vyapar .vyb or Tally XML to CSVs for ApexBooks migration.",
    )
    parser.add_argument("source_format", choices=["vyapar", "tally"])
    parser.add_argument("file", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="output folder")
    parser.add_argument("--xlsx", action="store_true", help="also emit a review-only Excel bundle")
    args = parser.parse_args(argv)

    if not Path(args.file).exists():
        _console(f"error: file not found: {args.file}")
        return 2
    try:
        summary = run_conversion(args.source_format, args.file, args.out, args.xlsx)
        _console(_report_text(args.out))
        _console(f"CSVs:    {summary['csv_count']} files in {summary['output_dir']}")
        _console(f"Upload:  {summary['bundle_zip']}")
        return summary.get("exit_code", 1)
    except Exception:
        tb = traceback.format_exc()
        try:
            traceback.print_exc()
        except Exception:
            pass
        try:
            args.out.mkdir(parents=True, exist_ok=True)
            (args.out / "conversion-error.log").write_text(tb, encoding="utf-8")
        except Exception:
            import tempfile
            try:
                p = Path(tempfile.gettempdir()) / "apex-migration-error.log"
                p.write_text(tb, encoding="utf-8")
            except Exception:
                pass
        return 1


# ── GUI mode ──────────────────────────────────────────────────────────────
def gui_main() -> int:
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk, scrolledtext

    root = tk.Tk()
    root.title("ApexBooks Migration Converter")
    root.geometry("760x640")
    root.minsize(640, 540)

    # Make the tk thread own the conversion state.
    state = {"running": False, "out_dir": None}

    def pick_source():
        path = filedialog.askopenfilename(
            title="Choose a Vyapar backup (.vyb) or Tally export (.xml)",
            filetypes=[("Vyapar backup / Tally XML", "*.vyb *.xml"), ("All files", "*.*")],
        )
        if path:
            src_var.set(path)
            detect_format(path)

    def detect_format(path: str):
        ext = Path(path).suffix.lower()
        if ext == ".vyb":
            fmt_var.set("vyapar")
            fmt_label.config(text="Detected: Vyapar backup (.vyb)")
        elif ext == ".xml":
            fmt_var.set("tally")
            fmt_label.config(text="Detected: Tally XML export (.xml)")
        else:
            fmt_label.config(text="Unknown file type — choose the format below.")

    def pick_out():
        path = filedialog.askdirectory(title="Choose where to save the CSVs")
        if path:
            out_var.set(path)

    def default_out():
        src = src_var.get().strip()
        if src:
            return str(Path(src).parent / "migration-output")
        return str(Path.home() / "migration-output")

    def open_output():
        d = state.get("out_dir")
        if d and Path(d).exists():
            os.startfile(d)  # Windows; harmless elsewhere

    def set_busy(busy: bool):
        state["running"] = busy
        convert_btn.config(state="disabled" if busy else "normal")
        open_btn.config(state="normal" if (not busy and state.get("out_dir")) else "disabled")
        status_var.set("Converting… this takes a few seconds (a console window may appear)." if busy else status_var.get())

    def worker():
        try:
            fmt = fmt_var.get()
            src = src_var.get().strip()
            out = out_var.get().strip() or default_out()
            if not src:
                raise ValueError("Choose a Vyapar or Tally file first.")
            if not Path(src).exists():
                raise ValueError(f"File not found:\n{src}")
            out_dir = Path(out)
            out_dir.mkdir(parents=True, exist_ok=True)
            state["out_dir"] = str(out_dir)
            summary = run_conversion(fmt, Path(src), out_dir, bool(xlsx_var.get()))
            report = _report_text(out_dir)
            if summary.get("warnings"):
                warn = "\n".join(f"  ⚠ {w}" for w in summary["warnings"])
                report = report + "\nWarnings\n--------\n" + warn + "\n"
            result = {
                "ok": summary.get("exit_code") == 0,
                "report": report,
                "summary": summary,
            }
        except Exception as exc:
            result = {"ok": False, "report": "", "summary": {},
                      "error": f"{exc}\n\n{traceback.format_exc()}"}
        root.after(0, lambda: on_done(result))

    def on_done(result):
        set_busy(False)
        if result["ok"]:
            s = result["summary"]
            status_var.set(
                f"✅ Done — {s.get('csv_count', 0)} CSVs + "
                f"{Path(s.get('bundle_zip', 'migration-bundle.zip')).name} ready to upload."
            )
            text.delete("1.0", tk.END)
            text.insert(tk.END, result["report"])
            text.insert(tk.END, f"\n\nUpload this file to the app (Migration screen):\n"
                                f"  {s.get('bundle_zip', '')}\n")
        else:
            status_var.set("❌ Conversion failed — see below.")
            text.delete("1.0", tk.END)
            text.insert(tk.END, result.get("error", "Unknown error"))
            messagebox.showerror("Conversion failed", result.get("error", "Unknown error"))

    def start():
        if state["running"]:
            return
        if not src_var.get().strip():
            messagebox.showwarning("No file", "Choose a Vyapar (.vyb) or Tally (.xml) file first.")
            return
        set_busy(True)
        text.delete("1.0", tk.END)
        status_var.set("Starting…")
        threading.Thread(target=worker, daemon=True).start()

    # ── Layout ──
    pad = {"padx": 12, "pady": 6}
    frm = ttk.Frame(root, padding=12)
    frm.pack(fill=tk.BOTH, expand=True)

    ttk.Label(frm, text="ApexBooks Migration Converter", font=("Segoe UI", 14, "bold")).pack(anchor=tk.W)
    ttk.Label(frm, text=(
        "Converts your Vyapar or Tally data into the exact CSVs the ApexBooks app "
        "imports — nothing is sent anywhere, everything runs on this computer."
    ), wraplength=700, justify=tk.LEFT).pack(anchor=tk.W, **pad)

    src_var = tk.StringVar()
    fmt_var = tk.StringVar(value="vyapar")
    out_var = tk.StringVar()
    xlsx_var = tk.BooleanVar(value=True)

    row1 = ttk.Frame(frm)
    row1.pack(fill=tk.X, **pad)
    ttk.Label(row1, text="Source file:").pack(side=tk.LEFT)
    ttk.Entry(row1, textvariable=src_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)
    ttk.Button(row1, text="Browse…", command=pick_source).pack(side=tk.RIGHT)

    fmt_label = ttk.Label(frm, text="Detected: —")
    fmt_label.pack(anchor=tk.W, padx=12)
    fmt_row = ttk.Frame(frm)
    fmt_row.pack(anchor=tk.W, **pad)
    ttk.Label(fmt_row, text="Format:").pack(side=tk.LEFT)
    ttk.Combobox(fmt_row, textvariable=fmt_var, values=("vyapar", "tally"), width=10,
                 state="readonly").pack(side=tk.LEFT, padx=6)

    row2 = ttk.Frame(frm)
    row2.pack(fill=tk.X, **pad)
    ttk.Label(row2, text="Output folder:").pack(side=tk.LEFT)
    ttk.Entry(row2, textvariable=out_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=6)
    ttk.Button(row2, text="Browse…", command=pick_out).pack(side=tk.RIGHT)
    ttk.Label(frm, text="(leave blank to save next to the source file)", foreground="#666").pack(anchor=tk.W, padx=12)

    ttk.Checkbutton(frm, text="Also create bundle.xlsx (Excel copy for review only — CSV is what gets uploaded)",
                    variable=xlsx_var).pack(anchor=tk.W, **pad)

    btn_row = ttk.Frame(frm)
    btn_row.pack(fill=tk.X, **pad)
    convert_btn = ttk.Button(btn_row, text="Convert", command=start)
    convert_btn.pack(side=tk.LEFT)
    open_btn = ttk.Button(btn_row, text="Open output folder", command=open_output, state="disabled")
    open_btn.pack(side=tk.LEFT, padx=6)

    status_var = tk.StringVar(value="Ready.")
    ttk.Label(frm, textvariable=status_var, foreground="#0a7d33", wraplength=700).pack(anchor=tk.W, **pad)

    text = scrolledtext.ScrolledText(frm, height=18, wrap=tk.WORD)
    text.pack(fill=tk.BOTH, expand=True, **pad)

    ttk.Label(frm, text=(
        "After converting, upload migration-bundle.zip in ApexBooks → Migration → "
        "Validate (dry run) → check the totals → confirm → Import. "
        "CSV is canonical; the .xlsx is only for reviewing in Excel."
    ), foreground="#666", wraplength=700, justify=tk.LEFT).pack(anchor=tk.W, **pad)

    # Top-level crash handler: surface it instead of dying silently.
    def excepthook(exc_type, exc, tb):
        traceback.print_exception(exc_type, exc, tb)
        try:
            messagebox.showerror("Unexpected error", "".join(traceback.format_exception(exc_type, exc, tb)))
        except Exception:
            pass

    sys.excepthook = excepthook
    root.mainloop()
    return 0


def main() -> int:
    argv = sys.argv[1:]
    # CLI when invoked with a format; otherwise the GUI.
    if argv and argv[0] in ("vyapar", "tally"):
        return cli_main(argv)
    return gui_main()


if __name__ == "__main__":
    sys.exit(main())
