import zipfile, io, tempfile, os, sqlite3

with open(r'C:\Bookkeeping-master\test.vyb', 'rb') as f:
    data = f.read()

zf = zipfile.ZipFile(io.BytesIO(data))
vyp = [n for n in zf.namelist() if n.endswith('.vyp')][0]
inner = zf.read(vyp)
zf.close()

tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
tmp.write(inner)
tmp.close()

conn = sqlite3.connect(tmp.name)
conn.row_factory = sqlite3.Row

# Check transaction columns
print("=== kb_transactions columns ===")
cols = conn.execute("PRAGMA table_info(kb_transactions)").fetchall()
for c in cols:
    print(f"  {c[1]}: {c[2]}")

print("\n=== All transactions ===")
txns = conn.execute("SELECT * FROM kb_transactions").fetchall()
for t in txns:
    d = dict(t)
    print(f"  txn_id={d.get('txn_id')} type={d.get('txn_type')} name_id={d.get('txn_name_id')} date={d.get('txn_date')} cash={d.get('txn_cash_amount')} bal={d.get('txn_balance_amount')} total={d.get('txn_total_amount')}")

print("\n=== kb_tax_mapping ===")
tax = conn.execute("SELECT * FROM kb_tax_mapping").fetchall()
for t in tax:
    print(dict(t))

print("\n=== kb_extra_charges ===")
ec = conn.execute("SELECT * FROM kb_extra_charges").fetchall()
for e in ec:
    print(dict(e))

conn.close()
os.unlink(tmp.name)
