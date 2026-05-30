import zipfile, io, tempfile, os, sqlite3

with open(r'C:\Bookkeeping-master\test.vyb', 'rb') as f:
    data = f.read()

print(f"File size: {len(data)} bytes")
print(f"First 8 bytes (hex): {data[:8].hex()}")

# Check if it's a ZIP
try:
    zf = zipfile.ZipFile(io.BytesIO(data))
    print('ZIP contents:', zf.namelist())
    vyp = [n for n in zf.namelist() if n.endswith('.vyp')]
    db_files = [n for n in zf.namelist() if n.endswith('.db') or n.endswith('.sqlite')]
    print('VYP files:', vyp)
    print('DB files:', db_files)
    
    target = vyp[0] if vyp else (db_files[0] if db_files else zf.namelist()[0] if zf.namelist() else None)
    if target:
        inner = zf.read(target)
        print(f'Inner file: {target}, size: {len(inner)}')
        print(f'Inner first 8 bytes: {inner[:8].hex()}')
        
        # Try inner as zip
        try:
            zf2 = zipfile.ZipFile(io.BytesIO(inner))
            print('Inner is ZIP:', zf2.namelist())
        except Exception:
            pass
        
        # Try as sqlite
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        tmp.write(inner)
        tmp.close()
        try:
            conn = sqlite3.connect(tmp.name)
            conn.row_factory = sqlite3.Row
            tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
            print('SQLite tables:', [t[0] for t in tables])
            for tbl in tables:
                count = conn.execute(f"SELECT COUNT(*) FROM [{tbl[0]}]").fetchone()[0]
                print(f"  {tbl[0]}: {count} rows")
            conn.close()
        except Exception as e:
            print(f'Not SQLite: {e}')
        finally:
            os.unlink(tmp.name)
    zf.close()
except zipfile.BadZipFile as e:
    print(f'Not a ZIP: {e}')
    # Try direct sqlite
    try:
        conn = sqlite3.connect(r'C:\Bookkeeping-master\test.vyb')
        tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
        print('Direct SQLite tables:', [t[0] for t in tables])
        for tbl in tables:
            count = conn.execute(f"SELECT COUNT(*) FROM [{tbl[0]}]").fetchone()[0]
            print(f"  {tbl[0]}: {count} rows")
        conn.close()
    except Exception as e2:
        print(f'Not SQLite either: {e2}')
