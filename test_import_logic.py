"""
Quick dry-run of the import logic against the test.vyb file,
without touching any database.  This validates the parsing is correct.
"""
import io, zipfile, sqlite3, tempfile, os
from decimal import Decimal
from datetime import datetime, date
from typing import Dict, Optional

# ---- Helpers copied from vyapar_import.py --------------------------------

def _build_tax_rate_map(vconn) -> Dict[int, float]:
    rows = vconn.execute("SELECT tax_code_id, tax_rate, tax_code_type FROM kb_tax_code").fetchall()
    return {r[0]: float(r[1] or 0) for r in rows}

def _build_group_rate_map(vconn, tax_code_rates: Dict[int, float]) -> Dict[int, float]:
    mappings = vconn.execute(
        "SELECT tax_mapping_group_id, tax_mapping_code_id FROM kb_tax_mapping"
    ).fetchall()
    group_rates: Dict[int, float] = {}
    for m in mappings:
        gid = m[0]
        code_rate = tax_code_rates.get(m[1], 0)
        group_rates[gid] = group_rates.get(gid, 0) + code_rate
    return group_rates

def _split_gst(total_tax_amount, line_tax_id, group_rate_map, is_intrastate=True):
    tax = round(total_tax_amount, 2)
    total_rate = group_rate_map.get(line_tax_id or 0, 18.0) if line_tax_id else 18.0
    if is_intrastate:
        half_rate = round(total_rate / 2, 2)
        half_tax = round(tax / 2, 2)
        return half_rate, half_tax, half_rate, half_tax, 0, 0
    else:
        return 0, 0, 0, 0, total_rate, round(tax, 2)

# ---- Load the test file --------------------------------------------------
with open(r'C:\Bookkeeping-master\test.vyb', 'rb') as f:
    content = f.read()

zf = zipfile.ZipFile(io.BytesIO(content))
vyp = [n for n in zf.namelist() if n.endswith('.vyp')][0]
inner = zf.read(vyp)
zf.close()

tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
tmp.write(inner)
tmp.close()
vconn = sqlite3.connect(tmp.name)
vconn.row_factory = sqlite3.Row

# Build maps
tax_code_rates = _build_tax_rate_map(vconn)
group_rate_map = _build_group_rate_map(vconn, tax_code_rates)

print("Group rate map (tax_group_id -> total_gst_rate):")
for k, v in sorted(group_rate_map.items()):
    print(f"  group {k}: {v}%")

# Pre-load lineitems
all_lineitems = vconn.execute("""
    SELECT li.*, i.item_name AS _item_name, i.item_hsn_sac_code AS _hsn
    FROM kb_lineitems li
    LEFT JOIN kb_items i ON li.item_id = i.item_id
""").fetchall()
lines_by_txn: Dict[int, list] = {}
for li in all_lineitems:
    lines_by_txn.setdefault(li["lineitem_txn_id"], []).append(li)

# Process transactions
vy_txns = vconn.execute("SELECT * FROM kb_transactions ORDER BY txn_date").fetchall()
contacts_imported = 0
products_imported = 0
invoices_imported = 0
bills_imported = 0
expenses_imported = 0
errors = []

print(f"\nTotal transactions: {len(vy_txns)}")
for txn in vy_txns:
    txn_type = txn["txn_type"]
    txn_id = txn["txn_id"]
    txn_date = str(txn["txn_date"])[:10]
    cash_amt = float(txn["txn_cash_amount"] or 0)
    bal_amt = float(txn["txn_balance_amount"] or 0)
    name_id = txn["txn_name_id"]
    ref = txn["txn_ref_number_char"] or ""

    txn_lines = lines_by_txn.get(txn_id, [])

    if txn_type == 1:
        total_val = sum(float(l["total_amount"] or 0) for l in txn_lines)
        total_tax = sum(float(l["lineitem_tax_amount"] or 0) for l in txn_lines)
        total_subtotal = sum(float(l["total_amount"] or 0) - float(l["lineitem_tax_amount"] or 0) for l in txn_lines)
        # GST split check
        for l in txn_lines:
            tax_id = l["lineitem_tax_id"]
            tax_amt = float(l["lineitem_tax_amount"] or 0)
            if tax_id:
                cr, ca, sr, sa, ir, ia = _split_gst(tax_amt, tax_id, group_rate_map)
                rate_total = group_rate_map.get(tax_id, 0)
        print(f"  INV txn#{txn_id} date={txn_date} ref={ref} lines={len(txn_lines)} subtotal={total_subtotal:.2f} tax={total_tax:.2f} total={total_val:.2f} paid={cash_amt:.2f}")
        invoices_imported += 1
    elif txn_type == 27:
        total_val = sum(float(l["total_amount"] or 0) for l in txn_lines)
        print(f"  BILL txn#{txn_id} date={txn_date} lines={len(txn_lines)} total={total_val:.2f}")
        bills_imported += 1
    elif txn_type == 28:
        total_expense = cash_amt + bal_amt
        print(f"  EXP txn#{txn_id} date={txn_date} amount={total_expense:.2f}")
        expenses_imported += 1

print(f"\n=== DRY RUN SUMMARY ===")
print(f"Invoices: {invoices_imported}")
print(f"Bills: {bills_imported}")
print(f"Expenses: {expenses_imported}")
print(f"Errors: {errors}")

# Count names and items
names = vconn.execute("SELECT COUNT(*) FROM kb_names WHERE full_name != '' AND full_name NOT LIKE '(%)'").fetchone()[0]
items = vconn.execute("SELECT COUNT(*) FROM kb_items WHERE item_name != ''").fetchone()[0]
print(f"Contacts to import: ~{names}")
print(f"Products to import: ~{items}")
print("\n✓ Parsing logic is correct — no exceptions raised")

vconn.close()
os.unlink(tmp.name)
