import zipfile, sqlite3, tempfile, os, io

with open('test.vyb', 'rb') as f:
    content = f.read()

zf = zipfile.ZipFile(io.BytesIO(content), 'r')
vyp_names = [n for n in zf.namelist() if n.endswith('.vyp')]
vyp_data = zf.read(vyp_names[0])
zf.close()

tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
tmp.write(vyp_data)
tmp.close()

conn = sqlite3.connect(tmp.name)
conn.row_factory = sqlite3.Row

print('=== ALL TRANSACTIONS ===')
rows = conn.execute('SELECT txn_id, txn_type, txn_sub_type, txn_name_id, txn_payment_status, txn_ref_number_char, txn_cash_amount, txn_balance_amount FROM kb_transactions ORDER BY txn_id').fetchall()
for r in rows:
    print(f'txn_id={r["txn_id"]}, type={r["txn_type"]}, sub_type={r["txn_sub_type"]}, name_id={r["txn_name_id"]}, pay_status={r["txn_payment_status"]}, ref={r["txn_ref_number_char"]}, cash={r["txn_cash_amount"]}, bal={r["txn_balance_amount"]}')

print()
print('=== NAMES ===')
names = conn.execute('SELECT name_id, full_name, name_type FROM kb_names ORDER BY name_id').fetchall()
for n in names:
    print(f'name_id={n["name_id"]}, name={n["full_name"]}, type={n["name_type"]}')

print()
print('=== LINE ITEMS for txn 9, 11, 13 ===')
for txn_id in [9, 11, 13]:
    lines = conn.execute('SELECT lineitem_txn_id, item_id, quantity, priceperunit, total_amount FROM kb_lineitems WHERE lineitem_txn_id = ?', (txn_id,)).fetchall()
    print(f'  txn {txn_id}: {len(lines)} lines')
    for l in lines:
        print(f'    item={l["item_id"]}, qty={l["quantity"]}, rate={l["priceperunit"]}, total={l["total_amount"]}')

# Check if txn_sub_type matters
print()
print('=== UNIQUE txn_type + txn_sub_type combos ===')
combos = conn.execute('SELECT DISTINCT txn_type, txn_sub_type FROM kb_transactions ORDER BY txn_type, txn_sub_type').fetchall()
for c in combos:
    count = conn.execute('SELECT COUNT(*) FROM kb_transactions WHERE txn_type=? AND txn_sub_type=?', (c[0], c[1])).fetchone()[0]
    print(f'type={c[0]}, sub_type={c[1]}, count={count}')

# Check payment mapping for these txns
print()
print('=== PAYMENTS for txn 9, 11, 13 ===')
for txn_id in [9, 11, 13]:
    pays = conn.execute('SELECT * FROM txn_payment_mapping WHERE txn_id = ?', (txn_id,)).fetchall()
    print(f'  txn {txn_id}: {len(pays)} payments')
    for p in pays:
        print(f'    payment_id={p["payment_id"]}, amount={p["amount"]}')

conn.close()
os.unlink(tmp.name)
