import zipfile, io, tempfile, os, sqlite3, json

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

# Check kb_transactions structure
print("=== kb_transactions columns ===")
cols = conn.execute("PRAGMA table_info(kb_transactions)").fetchall()
for c in cols:
    print(f"  {c[1]}: {c[2]}")

print("\n=== Sample transactions ===")
txns = conn.execute("SELECT * FROM kb_transactions LIMIT 5").fetchall()
for t in txns:
    print(dict(t))

print("\n=== Transaction types ===")
types = conn.execute("SELECT DISTINCT txn_type, COUNT(*) as cnt FROM kb_transactions GROUP BY txn_type").fetchall()
for t in types:
    print(f"  type={t[0]}: {t[1]} rows")

print("\n=== kb_names columns ===")
cols = conn.execute("PRAGMA table_info(kb_names)").fetchall()
for c in cols:
    print(f"  {c[1]}: {c[2]}")

print("\n=== Sample names ===")
names = conn.execute("SELECT * FROM kb_names").fetchall()
for n in names:
    print(dict(n))

print("\n=== kb_items columns ===")
cols = conn.execute("PRAGMA table_info(kb_items)").fetchall()
for c in cols:
    print(f"  {c[1]}: {c[2]}")

print("\n=== Sample items ===")
items = conn.execute("SELECT * FROM kb_items LIMIT 5").fetchall()
for i in items:
    print(dict(i))

print("\n=== kb_lineitems columns ===")
cols = conn.execute("PRAGMA table_info(kb_lineitems)").fetchall()
for c in cols:
    print(f"  {c[1]}: {c[2]}")

print("\n=== Sample lineitems ===")
lines = conn.execute("SELECT * FROM kb_lineitems LIMIT 5").fetchall()
for l in lines:
    print(dict(l))

print("\n=== kb_firms ===")
firm = conn.execute("SELECT * FROM kb_firms").fetchall()
for f in firm:
    print(dict(f))

conn.close()
os.unlink(tmp.name)
