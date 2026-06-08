import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static Database? _db;
  static const int _version = 2;

  static Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('Local database is not supported on web.');
    }
    _db ??= await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'apexbooks_cache.db');
    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Recreate cached_document_details with composite primary key
      await db.execute('DROP TABLE IF EXISTS cached_document_details');
      await db.execute('''
        CREATE TABLE cached_document_details (
          id TEXT,
          tenant_id TEXT,
          doc_type TEXT,
          json TEXT,
          synced_at TEXT,
          PRIMARY KEY (id, doc_type)
        )
      ''');
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Master data cache
    await db.execute('''
      CREATE TABLE cached_contacts (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        name TEXT,
        email TEXT,
        phone TEXT,
        contact_type TEXT,
        gstin TEXT,
        state_code TEXT,
        billing_address TEXT,
        json TEXT,
        synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_products (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        name TEXT,
        sku TEXT,
        hsn_sac TEXT,
        product_type TEXT,
        uom TEXT,
        sales_price REAL,
        purchase_price REAL,
        gst_rate REAL,
        current_stock REAL,
        json TEXT,
        synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_accounts (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        name TEXT,
        code TEXT,
        account_type TEXT,
        current_balance REAL,
        json TEXT,
        synced_at TEXT
      )
    ''');

    // Document list cache (summary only)
    await db.execute('''
      CREATE TABLE cached_invoices (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        invoice_number TEXT,
        issue_date TEXT,
        due_date TEXT,
        status TEXT,
        total REAL,
        amount_paid REAL,
        contact_name TEXT,
        reference_number TEXT,
        json TEXT,
        synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_bills (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        bill_number TEXT,
        issue_date TEXT,
        due_date TEXT,
        status TEXT,
        total REAL,
        amount_paid REAL,
        contact_name TEXT,
        json TEXT,
        synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE cached_expenses (
        id TEXT PRIMARY KEY,
        tenant_id TEXT,
        expense_number TEXT,
        expense_date TEXT,
        vendor_name TEXT,
        amount REAL,
        total REAL,
        status TEXT,
        category_name TEXT,
        json TEXT,
        synced_at TEXT
      )
    ''');

    // Full document detail cache
    await db.execute('''
      CREATE TABLE cached_document_details (
        id TEXT,
        tenant_id TEXT,
        doc_type TEXT,
        json TEXT,
        synced_at TEXT,
        PRIMARY KEY (id, doc_type)
      )
    ''');

    // Pending actions queue for offline writes
    await db.execute('''
      CREATE TABLE pending_actions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        body TEXT,
        headers TEXT,
        created_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        error TEXT
      )
    ''');

    // Sync metadata
    await db.execute('''
      CREATE TABLE sync_metadata (
        entity_type TEXT PRIMARY KEY,
        last_synced_at TEXT,
        record_count INTEGER DEFAULT 0
      )
    ''');
  }

  // ─── Generic helpers ──────────────────────────────────────────

  static Future<void> upsert(String table, Map<String, dynamic> row,
      {String? conflictKey = 'id'}) async {
    if (kIsWeb) return;
    final db = await database;
    await db.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> upsertMany(String table, List<Map<String, dynamic>> rows) async {
    if (kIsWeb) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final row in rows) {
        await txn.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  static Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (kIsWeb) return [];
    final db = await database;
    return db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  static Future<void> deleteWhere(String table,
      {String? where, List<Object?>? whereArgs}) async {
    if (kIsWeb) return;
    final db = await database;
    await db.delete(table, where: where, whereArgs: whereArgs);
  }

  static Future<void> clearTable(String table) async {
    if (kIsWeb) return;
    final db = await database;
    await db.delete(table);
  }

  static Future<void> deleteAll() async {
    if (kIsWeb) return;
    final db = await database;
    final tables = [
      'cached_contacts',
      'cached_products',
      'cached_accounts',
      'cached_invoices',
      'cached_bills',
      'cached_expenses',
      'cached_document_details',
      'pending_actions',
      'sync_metadata',
    ];
    for (final t in tables) {
      await db.delete(t);
    }
  }

  // ─── Pending Actions Queue ────────────────────────────────────

  static Future<int> enqueueAction({
    required String action,
    required String endpoint,
    required String method,
    String? body,
    String? headers,
  }) async {
    if (kIsWeb) return 0;
    final db = await database;
    return db.insert('pending_actions', {
      'action': action,
      'endpoint': endpoint,
      'method': method,
      'body': body,
      'headers': headers,
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingActions() async {
    if (kIsWeb) return [];
    final db = await database;
    return db.query('pending_actions', orderBy: 'created_at ASC');
  }

  static Future<void> removePendingAction(int id) async {
    if (kIsWeb) return;
    final db = await database;
    await db.delete('pending_actions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> incrementRetry(int id, String error) async {
    if (kIsWeb) return;
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_actions SET retry_count = retry_count + 1, error = ? WHERE id = ?',
      [error, id],
    );
  }

  static Future<void> clearPendingActions() async {
    if (kIsWeb) return;
    final db = await database;
    await db.delete('pending_actions');
  }

  // ─── Sync Metadata ────────────────────────────────────────────

  static Future<void> updateSyncMetadata(String entityType,
      {required DateTime lastSync, int recordCount = 0}) async {
    if (kIsWeb) return;
    final db = await database;
    await db.insert(
      'sync_metadata',
      {
        'entity_type': entityType,
        'last_synced_at': lastSync.toIso8601String(),
        'record_count': recordCount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getSyncMetadata(String entityType) async {
    if (kIsWeb) return null;
    final db = await database;
    final rows = await db.query(
      'sync_metadata',
      where: 'entity_type = ?',
      whereArgs: [entityType],
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  // ─── Entity-specific cache helpers ────────────────────────────

  static Future<void> cacheContacts(String tenantId, List<dynamic> contacts) async {
    if (kIsWeb) return;
    final rows = contacts.map((c) => {
      'id': c['id']?.toString() ?? '',
      'tenant_id': tenantId,
      'name': c['name']?.toString() ?? '',
      'email': c['email']?.toString() ?? '',
      'phone': c['phone']?.toString() ?? '',
      'contact_type': c['contact_type']?.toString() ?? '',
      'gstin': c['gstin']?.toString() ?? '',
      'state_code': c['state_code']?.toString() ?? '',
      'billing_address': c['billing_address'] != null ? jsonEncode(c['billing_address']) : null,
      'json': jsonEncode(c),
      'synced_at': DateTime.now().toIso8601String(),
    }).toList();
    await clearTable('cached_contacts');
    await upsertMany('cached_contacts', rows);
    await updateSyncMetadata('contacts', lastSync: DateTime.now(), recordCount: rows.length);
  }

  static Future<void> cacheProducts(String tenantId, List<dynamic> products) async {
    if (kIsWeb) return;
    final rows = products.map((p) => {
      'id': p['id']?.toString() ?? '',
      'tenant_id': tenantId,
      'name': p['name']?.toString() ?? '',
      'sku': p['sku']?.toString() ?? '',
      'hsn_sac': p['hsn_sac']?.toString() ?? '',
      'product_type': p['product_type']?.toString() ?? '',
      'uom': p['uom']?.toString() ?? '',
      'sales_price': double.tryParse(p['sales_price']?.toString() ?? '') ?? 0.0,
      'purchase_price': double.tryParse(p['purchase_price']?.toString() ?? '') ?? 0.0,
      'gst_rate': double.tryParse(p['gst_rate']?.toString() ?? '') ?? 0.0,
      'current_stock': double.tryParse(p['current_stock']?.toString() ?? '') ?? 0.0,
      'json': jsonEncode(p),
      'synced_at': DateTime.now().toIso8601String(),
    }).toList();
    await clearTable('cached_products');
    await upsertMany('cached_products', rows);
    await updateSyncMetadata('products', lastSync: DateTime.now(), recordCount: rows.length);
  }

  static Future<void> cacheInvoices(String tenantId, List<dynamic> invoices) async {
    if (kIsWeb) return;
    final rows = invoices.map((inv) => {
      'id': inv['id']?.toString() ?? '',
      'tenant_id': tenantId,
      'invoice_number': inv['invoice_number']?.toString() ?? '',
      'issue_date': inv['issue_date']?.toString() ?? '',
      'due_date': inv['due_date']?.toString() ?? '',
      'status': inv['status']?.toString() ?? '',
      'total': double.tryParse(inv['total']?.toString() ?? '') ?? 0.0,
      'amount_paid': double.tryParse(inv['amount_paid']?.toString() ?? '') ?? 0.0,
      'contact_name': inv['contact_name']?.toString() ?? '',
      'reference_number': inv['reference_number']?.toString() ?? '',
      'json': jsonEncode(inv),
      'synced_at': DateTime.now().toIso8601String(),
    }).toList();
    await clearTable('cached_invoices');
    await upsertMany('cached_invoices', rows);
    await updateSyncMetadata('invoices', lastSync: DateTime.now(), recordCount: rows.length);
  }

  static Future<void> cacheBills(String tenantId, List<dynamic> bills) async {
    if (kIsWeb) return;
    final rows = bills.map((b) => {
      'id': b['id']?.toString() ?? '',
      'tenant_id': tenantId,
      'bill_number': b['bill_number']?.toString() ?? '',
      'issue_date': b['issue_date']?.toString() ?? '',
      'due_date': b['due_date']?.toString() ?? '',
      'status': b['status']?.toString() ?? '',
      'total': double.tryParse(b['total']?.toString() ?? '') ?? 0.0,
      'amount_paid': double.tryParse(b['amount_paid']?.toString() ?? '') ?? 0.0,
      'contact_name': b['contact_name']?.toString() ?? '',
      'json': jsonEncode(b),
      'synced_at': DateTime.now().toIso8601String(),
    }).toList();
    await clearTable('cached_bills');
    await upsertMany('cached_bills', rows);
    await updateSyncMetadata('bills', lastSync: DateTime.now(), recordCount: rows.length);
  }

  static Future<void> cacheExpenses(String tenantId, List<dynamic> expenses) async {
    if (kIsWeb) return;
    final rows = expenses.map((e) => {
      'id': e['id']?.toString() ?? '',
      'tenant_id': tenantId,
      'expense_number': e['expense_number']?.toString() ?? '',
      'expense_date': e['expense_date']?.toString() ?? '',
      'vendor_name': e['vendor_name']?.toString() ?? '',
      'amount': double.tryParse(e['amount']?.toString() ?? '') ?? 0.0,
      'total': double.tryParse(e['total']?.toString() ?? '') ?? 0.0,
      'status': e['status']?.toString() ?? '',
      'category_name': e['category_name']?.toString() ?? '',
      'json': jsonEncode(e),
      'synced_at': DateTime.now().toIso8601String(),
    }).toList();
    await clearTable('cached_expenses');
    await upsertMany('cached_expenses', rows);
    await updateSyncMetadata('expenses', lastSync: DateTime.now(), recordCount: rows.length);
  }

  static Future<void> cacheDocumentDetail(String tenantId, String docType,
      String docId, Map<String, dynamic> data) async {
    if (kIsWeb) return;
    final db = await database;
    await db.insert(
      'cached_document_details',
      {
        'id': docId,
        'tenant_id': tenantId,
        'doc_type': docType,
        'json': jsonEncode(data),
        'synced_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getCachedDocumentDetail(
      String tenantId, String docType, String docId) async {
    if (kIsWeb) return null;
    final db = await database;
    final rows = await db.query(
      'cached_document_details',
      where: 'id = ? AND tenant_id = ? AND doc_type = ?',
      whereArgs: [docId, tenantId, docType],
    );
    if (rows.isEmpty) return null;
    final jsonStr = rows.first['json'] as String?;
    return jsonStr != null ? jsonDecode(jsonStr) : null;
  }
}
