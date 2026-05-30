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

print("=== kb_tax_code (first 10) ===")
taxcodes = conn.execute("SELECT * FROM kb_tax_code LIMIT 10").fetchall()
for t in taxcodes:
    print(dict(t))

print("\n=== kb_lineitems columns ===")
cols = conn.execute("PRAGMA table_info(kb_lineitems)").fetchall()
for c in cols:
    print(f"  {c[1]}: {c[2]}")

print("\n=== All lineitems ===")
lines = conn.execute("SELECT * FROM kb_lineitems").fetchall()
for l in lines:
    d = dict(l)
    print(f"  txn_id={d.get('lineitem_txn_id')} item_id={d.get('item_id')} qty={d.get('quantity')} rate={d.get('priceperunit')} tax={d.get('lineitem_tax_amount')} total={d.get('total_amount')} disc={d.get('lineitem_discount_amount')}")

print("\n=== txn_payment_mapping ===")
pm = conn.execute("SELECT * FROM txn_payment_mapping LIMIT 10").fetchall()
for p in pm:
    print(dict(p))

conn.close()
os.unlink(tmp.name)
