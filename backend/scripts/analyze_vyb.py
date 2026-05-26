import zipfile, sqlite3, tempfile, os

zf = zipfile.ZipFile("C:\\Bookkeeping-master\\test.vyb")
data = zf.read("ApexIntegrations__t_2026_04_15_12_30_13_viho.vyp")
zf.close()

tmp = tempfile.NamedTemporaryFile(delete=False)
tmp.write(data)
tmp.close()

conn = sqlite3.connect(tmp.name)

print("=== FIRM INFO ===")
rows = conn.execute("SELECT * FROM kb_firms").fetchall()
for r in rows:
    print(r)

print("\n=== TRANSACTION TYPES ===")
rows = conn.execute("SELECT DISTINCT txn_type FROM kb_transactions").fetchall()
for r in rows:
    count = conn.execute(f"SELECT COUNT(*) FROM kb_transactions WHERE txn_type='{r[0]}'").fetchone()[0]
    print(f"  {r[0]}: {count} transactions")

print("\n=== SAMPLE TRANSACTIONS ===")
rows = conn.execute("SELECT txn_id, txn_type, txn_date, txn_cash_amount, txn_balance_amount, txn_name_id FROM kb_transactions LIMIT 10").fetchall()
for r in rows:
    name = conn.execute(f"SELECT full_name FROM kb_names WHERE name_id={r[5]}").fetchone()
    print(f"  {r[0]}: type={r[1]}, date={r[2]}, cash={r[3]}, bal={r[4]}, party={name[0] if name else 'N/A'}")

print("\n=== SAMPLE LINE ITEMS ===")
rows = conn.execute("SELECT li.lineitem_id, li.lineitem_txn_id, li.item_id, li.quantity, li.priceperunit, li.total_amount, li.lineitem_tax_amount, i.item_name FROM kb_lineitems li LEFT JOIN kb_items i ON li.item_id=i.item_id LIMIT 10").fetchall()
for r in rows:
    print(f"  txn={r[1]}, item={r[7]}, qty={r[3]}, rate={r[4]}, total={r[5]}, tax={r[6]}")

print("\n=== SAMPLE NAMES (PARTIES) ===")
rows = conn.execute("SELECT name_id, full_name, phone_number, email, amount FROM kb_names").fetchall()
for r in rows:
    print(f"  id={r[0]}, name={r[1]}, phone={r[2]}, email={r[3]}, bal={r[4]}")

print("\n=== SAMPLE ITEMS ===")
rows = conn.execute("SELECT item_id, item_name, item_sale_unit_price, item_purchase_unit_price, item_stock_quantity, item_min_stock_quantity FROM kb_items LIMIT 10").fetchall()
for r in rows:
    print(f"  id={r[0]}, name={r[1]}, sale={r[2]}, purchase={r[3]}, stock={r[4]}, min={r[5]}")

conn.close()
os.unlink(tmp.name)
