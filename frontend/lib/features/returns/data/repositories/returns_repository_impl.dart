library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/ids/id_generator.dart';
import '../../../../core/sync/sync_engine.dart';
import '../../../../core/sync/sync_operation.dart';
import '../../../../core/sync/sync_status.dart';
import '../../domain/commands/returns_commands.dart';
import '../../domain/entities/returns_entities.dart';
import '../../domain/repositories/returns_repository.dart';

class ReturnsRepositoryImpl implements ReturnsRepository {
  ReturnsRepositoryImpl({
    required AppDatabase db,
    required SyncEngine syncEngine,
    required Dio dio,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() companyIdProvider,
    required Future<String> Function() actorIdProvider,
  }) : _db = db,
       _syncEngine = syncEngine,
       _dio = dio,
       _deviceIdProvider = deviceIdProvider,
       _companyIdProvider = companyIdProvider,
       _actorIdProvider = actorIdProvider {
    _syncEngine.registerPusher('sales_return', (op) => _push(op));
    _syncEngine.registerPusher('purchase_return', (op) => _push(op));
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  // ── Sales return (customer returns goods) ───────────────────────────────────

  @override
  Future<SalesReturnEntity> postSalesReturn(PostSalesReturnCommand cmd) async {
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final localId = IdGenerator.newId();
    final journalLocalId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    if (cmd.totalPaise <= 0) {
      throw const ValidationException('Return total must be > 0.');
    }

    await _db.transaction(() async {
      await _db
          .into(_db.salesReturns)
          .insert(
            SalesReturnsCompanion(
              localId: Value(localId),
              companyId: Value(companyId),
              returnDate: Value(cmd.returnDate),
              customerId: Value(cmd.customerId),
              customerName: Value(cmd.customerName),
              sourceInvoiceLocalId: Value(cmd.sourceInvoiceLocalId),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              totalPaise: Value(cmd.totalPaise),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      for (final l in cmd.lines) {
        await _db
            .into(_db.salesReturnLines)
            .insert(
              SalesReturnLinesCompanion(
                localId: Value(IdGenerator.newId()),
                returnLocalId: Value(localId),
                sourceInvoiceLineLocalId: Value(l.sourceInvoiceLineLocalId),
                productName: Value(l.productName),
                unit: Value(l.unit),
                quantity: Value(l.quantity),
                unitPricePaise: Value(l.unitPricePaise),
                totalPaise: Value(l.totalPaise),
              ),
            );
        // Increase inventory, reverse COGS.
        final qty = double.tryParse(l.quantity) ?? 0;
        if (qty > 0) {
          final stock =
              await (_db.select(_db.stockItems)..where(
                    (s) =>
                        s.companyId.equals(companyId) &
                        s.name.equals(l.productName) &
                        s.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
          if (stock != null) {
            final cur = double.tryParse(stock.currentQuantity) ?? 0;
            final newQty = cur + qty;
            await (_db.update(
              _db.stockItems,
            )..where((s) => s.localId.equals(stock.localId))).write(
              StockItemsCompanion(
                currentQuantity: Value(newQty.toStringAsFixed(3)),
                updatedAt: Value(now),
              ),
            );
            await _db
                .into(_db.inventoryBalances)
                .insertOnConflictUpdate(
                  InventoryBalancesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: Value(companyId),
                    stockItemId: Value(stock.localId),
                    quantityOnHand: Value(newQty.toStringAsFixed(3)),
                    averageCostPaise: Value(stock.unitCostPaise),
                    updatedAt: Value(now),
                  ),
                );
            await _db
                .into(_db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: Value(companyId),
                    stockItemId: Value(stock.localId),
                    movementType: const Value('CUSTOMER_RETURN'),
                    quantity: Value(l.quantity),
                    balanceAfter: Value(newQty.toStringAsFixed(3)),
                    unitCostPaise: Value(stock.unitCostPaise),
                    totalPaise: Value((qty * stock.unitCostPaise).round()),
                    movementDate: Value(cmd.returnDate),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: Value(deviceId),
                  ),
                );
          }
        }
      }
      // Reverse COGS journal: DEBIT inventory, CREDIT COGS.
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(cmd.returnDate),
              description: Value('Sales return: ${cmd.customerName}'),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      for (final entry in [
        {
          'account_id': 'inventory',
          'account_name': 'Inventory',
          'direction': 'DEBIT',
        },
        {
          'account_id': 'cogs',
          'account_name': 'Cost of Goods Sold',
          'direction': 'CREDIT',
        },
      ]) {
        await _db
            .into(_db.journalLines)
            .insert(
              JournalLinesCompanion(
                localId: Value(IdGenerator.newId()),
                journalLocalId: Value(journalLocalId),
                accountId: Value(entry['account_id']!),
                accountCode: const Value(''),
                accountName: Value(entry['account_name']!),
                direction: Value(entry['direction']!),
                amountPaise: Value(cmd.totalPaise),
                sortOrder: const Value(0),
              ),
            );
      }
      // Outbox.
      final payload = jsonEncode({
        'event_id': localId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'sales_return',
        'aggregate_id': localId,
        'event_type': 'sales_return.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'invoice_id': cmd.sourceInvoiceLocalId,
          'party_id': cmd.customerId,
          'customer_id': cmd.customerId,
          'customer_name': cmd.customerName,
          'return_date': cmd.returnDate,
          'total_paise': cmd.totalPaise,
          'lines': cmd.lines
              .map(
                (l) => {
                  'source_invoice_line_id': l.sourceInvoiceLineLocalId,
                  'product_name': l.productName,
                  'quantity': l.quantity,
                  'unit_price_paise': l.unitPricePaise,
                  'total_paise': l.totalPaise,
                },
              )
              .toList(),
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('sales_return'),
              entityLocalId: Value(localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('returns', 'sales', localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });
    return _salesReturnEntity(await _getSalesReturn(localId), cmd.lines);
  }

  // ── Purchase return (return goods to supplier) ──────────────────────────────

  @override
  Future<PurchaseReturnEntity> postPurchaseReturn(
    PostPurchaseReturnCommand cmd,
  ) async {
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final localId = IdGenerator.newId();
    final journalLocalId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    if (cmd.totalPaise <= 0) {
      throw const ValidationException('Return total must be > 0.');
    }

    await _db.transaction(() async {
      // Validate sufficient stock for items being returned.
      for (final l in cmd.lines) {
        final qty = double.tryParse(l.quantity) ?? 0;
        if (qty <= 0) continue;
        final stock =
            await (_db.select(_db.stockItems)..where(
                  (s) =>
                      s.companyId.equals(companyId) &
                      s.name.equals(l.productName) &
                      s.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (stock != null) {
          final onHand = double.tryParse(stock.currentQuantity) ?? 0;
          if (qty > onHand + 0.001) {
            throw ValidationException(
              'Insufficient stock to return ${l.productName}: $onHand available, $qty required.',
            );
          }
        }
      }

      await _db
          .into(_db.purchaseReturns)
          .insert(
            PurchaseReturnsCompanion(
              localId: Value(localId),
              companyId: Value(companyId),
              returnDate: Value(cmd.returnDate),
              supplierId: Value(cmd.supplierId),
              supplierName: Value(cmd.supplierName),
              sourceReceiptLocalId: Value(cmd.sourceReceiptLocalId),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              totalPaise: Value(cmd.totalPaise),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      for (final l in cmd.lines) {
        await _db
            .into(_db.purchaseReturnLines)
            .insert(
              PurchaseReturnLinesCompanion(
                localId: Value(IdGenerator.newId()),
                returnLocalId: Value(localId),
                sourceReceiptLineLocalId: Value(l.sourceReceiptLineLocalId),
                productName: Value(l.productName),
                unit: Value(l.unit),
                quantity: Value(l.quantity),
                unitCostPaise: Value(l.unitCostPaise),
                totalPaise: Value(l.totalPaise),
              ),
            );
        // Decrease inventory.
        final qty = double.tryParse(l.quantity) ?? 0;
        if (qty > 0) {
          final stock =
              await (_db.select(_db.stockItems)..where(
                    (s) =>
                        s.companyId.equals(companyId) &
                        s.name.equals(l.productName) &
                        s.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
          if (stock != null) {
            final cur = double.tryParse(stock.currentQuantity) ?? 0;
            final newQty = cur - qty;
            await (_db.update(
              _db.stockItems,
            )..where((s) => s.localId.equals(stock.localId))).write(
              StockItemsCompanion(
                currentQuantity: Value(newQty.toStringAsFixed(3)),
                updatedAt: Value(now),
              ),
            );
            await _db
                .into(_db.inventoryBalances)
                .insertOnConflictUpdate(
                  InventoryBalancesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: Value(companyId),
                    stockItemId: Value(stock.localId),
                    quantityOnHand: Value(newQty.toStringAsFixed(3)),
                    averageCostPaise: Value(stock.unitCostPaise),
                    updatedAt: Value(now),
                  ),
                );
            await _db
                .into(_db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: Value(companyId),
                    stockItemId: Value(stock.localId),
                    movementType: const Value('SUPPLIER_RETURN'),
                    quantity: Value('-${l.quantity}'),
                    balanceAfter: Value(newQty.toStringAsFixed(3)),
                    unitCostPaise: Value(stock.unitCostPaise),
                    totalPaise: Value((qty * stock.unitCostPaise).round()),
                    movementDate: Value(cmd.returnDate),
                    createdAt: Value(now),
                    updatedAt: Value(now),
                    originDeviceId: Value(deviceId),
                  ),
                );
          }
        }
      }
      // Reverse GRIN/AP journal: DEBIT AP/GRIR, CREDIT inventory.
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(cmd.returnDate),
              description: Value('Purchase return: ${cmd.supplierName}'),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      for (final entry in [
        {
          'account_id': 'ap',
          'account_name': 'Accounts Payable',
          'direction': 'DEBIT',
        },
        {
          'account_id': 'purchases',
          'account_name': 'Purchases',
          'direction': 'CREDIT',
        },
      ]) {
        await _db
            .into(_db.journalLines)
            .insert(
              JournalLinesCompanion(
                localId: Value(IdGenerator.newId()),
                journalLocalId: Value(journalLocalId),
                accountId: Value(entry['account_id']!),
                accountCode: const Value(''),
                accountName: Value(entry['account_name']!),
                direction: Value(entry['direction']!),
                amountPaise: Value(cmd.totalPaise),
                sortOrder: const Value(0),
              ),
            );
      }
      // Outbox.
      final payload = jsonEncode({
        'event_id': localId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'purchase_return',
        'aggregate_id': localId,
        'event_type': 'purchase_return.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'bill_id': cmd.sourceReceiptLocalId,
          'supplier_id': cmd.supplierId,
          'party_id': cmd.supplierId,
          'supplier_name': cmd.supplierName,
          'return_date': cmd.returnDate,
          'total_paise': cmd.totalPaise,
          'lines': cmd.lines
              .map(
                (l) => {
                  'source_receipt_line_id': l.sourceReceiptLineLocalId,
                  'product_name': l.productName,
                  'quantity': l.quantity,
                  'unit_cost_paise': l.unitCostPaise,
                  'total_paise': l.totalPaise,
                },
              )
              .toList(),
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('purchase_return'),
              entityLocalId: Value(localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('returns', 'purchase', localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });
    return _purchaseReturnEntity(await _getPurchaseReturn(localId), cmd.lines);
  }

  // ── Streams ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<SalesReturnEntity>> watchSalesReturns({
    String? companyId,
  }) async* {
    final q = _db.select(_db.salesReturns)
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (companyId != null) q.where((r) => r.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows.map((r) => _salesReturnEntity(r, [])).toList();
    }
  }

  @override
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturns({
    String? companyId,
  }) async* {
    final q = _db.select(_db.purchaseReturns)
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (companyId != null) q.where((r) => r.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows.map((r) => _purchaseReturnEntity(r, [])).toList();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  SalesReturnEntity _salesReturnEntity(
    SalesReturn row,
    List<SalesReturnLineCommand> lines,
  ) => SalesReturnEntity(
    localId: row.localId,
    companyId: row.companyId,
    returnDate: row.returnDate,
    customerId: row.customerId,
    customerName: row.customerName,
    sourceInvoiceLocalId: row.sourceInvoiceLocalId,
    referenceNumber: row.referenceNumber,
    description: row.description,
    totalPaise: row.totalPaise,
    lifecycleStatus: row.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: row.createdAt,
    syncError: row.syncError,
  );

  PurchaseReturnEntity _purchaseReturnEntity(
    PurchaseReturn row,
    List<PurchaseReturnLineCommand> lines,
  ) => PurchaseReturnEntity(
    localId: row.localId,
    companyId: row.companyId,
    returnDate: row.returnDate,
    supplierId: row.supplierId,
    supplierName: row.supplierName,
    sourceReceiptLocalId: row.sourceReceiptLocalId,
    referenceNumber: row.referenceNumber,
    description: row.description,
    totalPaise: row.totalPaise,
    lifecycleStatus: row.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: row.createdAt,
    syncError: row.syncError,
  );

  @override
  Future<SalesReturnEntity?> getSalesReturn(String localId) async {
    final row = await (_db.select(_db.salesReturns)
          ..where((r) => r.localId.equals(localId) & r.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final lines = await (_db.select(_db.salesReturnLines)
          ..where((l) => l.returnLocalId.equals(localId)))
        .get();
    return _salesReturnEntity(
      row,
      lines
          .map(
            (l) => SalesReturnLineCommand(
              sourceInvoiceLineLocalId: l.sourceInvoiceLineLocalId ?? '',
              productName: l.productName,
              unit: l.unit,
              quantity: l.quantity,
              unitPricePaise: l.unitPricePaise,
              totalPaise: l.totalPaise,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<PurchaseReturnEntity?> getPurchaseReturn(String localId) async {
    final row = await (_db.select(_db.purchaseReturns)
          ..where((r) => r.localId.equals(localId) & r.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    final lines = await (_db.select(_db.purchaseReturnLines)
          ..where((l) => l.returnLocalId.equals(localId)))
        .get();
    return _purchaseReturnEntity(
      row,
      lines
          .map(
            (l) => PurchaseReturnLineCommand(
              sourceReceiptLineLocalId: l.sourceReceiptLineLocalId ?? '',
              productName: l.productName,
              unit: l.unit,
              quantity: l.quantity,
              unitCostPaise: l.unitCostPaise,
              totalPaise: l.totalPaise,
            ),
          )
          .toList(),
    );
  }

  Future<SalesReturn> _getSalesReturn(String localId) => (_db.select(
    _db.salesReturns,
  )..where((r) => r.localId.equals(localId))).getSingle();

  Future<PurchaseReturn> _getPurchaseReturn(String localId) => (_db.select(
    _db.purchaseReturns,
  )..where((r) => r.localId.equals(localId))).getSingle();

  Future<SyncPushResult> _push(OutboxRecord op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    try {
      final res = await _dio.post(
        '/apexbooks/sync/push',
        data: {
          'events': [payload],
        },
        options: Options(headers: {'Idempotency-Key': op.idempotencyKey}),
      );
      return parseSyncPushResponse(
        res.data,
        payload,
        entityLabel: op.entityType.replaceAll('_', ' '),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 422) {
        throw const PermanentSyncException('Validation error');
      }
      if (code != null && code >= 500) {
        throw RetryableSyncException('Server error ($code).');
      }
      throw RetryableSyncException('Network error.', cause: e);
    }
  }
}
