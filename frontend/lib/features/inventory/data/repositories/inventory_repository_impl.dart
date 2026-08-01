/// Implementation of [InventoryRepository].
///
/// All inventory mutations are atomic: movement → balance → stock item → outbox
/// in one Drift transaction.
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
import '../../domain/commands/inventory_commands.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/repositories/inventory_repository.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  InventoryRepositoryImpl({
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
    _syncEngine.registerPusher('inventory', (op) => _pushInventory(op));
    _syncEngine.registerPusher('stock_item', (op) => _pushInventory(op));
    _syncEngine.registerPullApplicator(
      'stock.adjusted',
      _applyPulledAdjustment,
    );
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  // ── Stock items ──────────────────────────────────────────────────────────

  @override
  Stream<List<StockItemEntity>> watchStockItems({String? companyId}) async* {
    final query = _db.select(_db.stockItems)
      ..where((s) => s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm.asc(s.name)]);
    if (companyId != null) query.where((s) => s.companyId.equals(companyId));

    await for (final rows in query.watch()) {
      yield rows.map(_toStockItem).toList();
    }
  }

  @override
  Future<StockItemEntity?> getStockItem(
    String localId, {
    String? companyId,
  }) async {
    final q = _db.select(_db.stockItems)
      ..where((s) => s.localId.equals(localId) & s.deletedAt.isNull());
    if (companyId != null) q.where((s) => s.companyId.equals(companyId));
    final row = await q.getSingleOrNull();
    return row != null ? _toStockItem(row) : null;
  }

  @override
  Future<StockItemEntity> createStockItem(CreateStockItemCommand cmd) async {
    final localId = IdGenerator.newId();
    final now = DateTime.now().toUtc();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final operationId = IdGenerator.newId();

    final openingQty = double.tryParse(cmd.openingQuantity) ?? 0;
    if (openingQty < 0) {
      throw const ValidationException('Opening quantity cannot be negative.');
    }
    await _db.transaction(() async {
      await _db
          .into(_db.stockItems)
          .insert(
            StockItemsCompanion(
              localId: Value(localId),
              companyId: Value(companyId),
              name: Value(cmd.name.trim()),
              sku: Value(cmd.sku?.trim()),
              unit: Value(cmd.unit.toUpperCase()),
              currentQuantity: Value(cmd.openingQuantity),
              unitCostPaise: Value(cmd.unitCostPaise),
              syncStatus: const Value('pending'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );

      if (openingQty > 0) {
        await _db
            .into(_db.inventoryBalances)
            .insert(
              InventoryBalancesCompanion(
                localId: Value(IdGenerator.newId()),
                companyId: Value(companyId),
                stockItemId: Value(localId),
                quantityOnHand: Value(cmd.openingQuantity),
                averageCostPaise: Value(cmd.unitCostPaise),
                updatedAt: Value(now),
              ),
            );
      }

      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(operationId),
              entityType: const Value('stock_item'),
              entityLocalId: Value(localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(
                jsonEncode({
                  'event_id': operationId,
                  'company_id': companyId,
                  'device_id': deviceId,
                  'aggregate_type': 'item',
                  'aggregate_id': localId,
                  'event_type': 'item.created',
                  'event_version': 1,
                  'occurred_at': now.toIso8601String(),
                  'payload': {
                    'name': cmd.name.trim(),
                    'sku': cmd.sku?.trim(),
                    'unit': cmd.unit.toUpperCase(),
                    'opening_quantity_micros': (openingQty * 10000).round(),
                    'purchase_price_micros': cmd.unitCostPaise * 100,
                    'sale_price_micros': cmd.unitCostPaise * 100,
                    'default_tax_rate_basis_points': 0,
                  },
                }),
              ),
              idempotencyKey: Value(
                IdGenerator.actionKey('stock_item', 'create', localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await _getStockItemByLocalId(localId))!;
  }

  // ── Movements ────────────────────────────────────────────────────────────

  @override
  Future<InventoryMovementEntity> createMovement(
    CreateMovementCommand cmd,
  ) async {
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final localId = IdGenerator.newId();
    final opId = IdGenerator.newId();
    final idempotencyKey = IdGenerator.actionKey(
      'inventory',
      'movement',
      localId,
    );

    // Resolve current quantity.
    final stockItem = await _getStockItemByLocalId(cmd.stockItemId);
    if (stockItem == null) {
      throw const ValidationException('Stock item not found.');
    }

    final currentQty = double.tryParse(stockItem.currentQuantity) ?? 0;
    final movementQty = double.tryParse(cmd.quantity) ?? 0;
    final newQty = currentQty + movementQty;

    if (newQty < 0) {
      throw const ValidationException('Insufficient stock for this movement.');
    }

    final newQtyStr = newQty.toStringAsFixed(3);

    // Cost: use provided unit cost or existing average.
    final effectiveCost = cmd.unitCostPaise > 0
        ? cmd.unitCostPaise
        : stockItem.unitCostPaise;

    // Recompute average cost on inbound movements.
    int newAvgCost;
    if (movementQty > 0 && currentQty > 0) {
      newAvgCost = computeWeightedAverage(
        currentQty,
        stockItem.unitCostPaise,
        movementQty,
        effectiveCost,
      );
    } else if (movementQty > 0) {
      newAvgCost = effectiveCost;
    } else {
      newAvgCost = stockItem.unitCostPaise;
    }

    await _db.transaction(() async {
      // 1. Insert movement.
      await _db
          .into(_db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion(
              localId: Value(localId),
              companyId: Value(companyId),
              stockItemId: Value(cmd.stockItemId),
              movementType: Value(cmd.movementType),
              quantity: Value(cmd.quantity),
              balanceAfter: Value(newQtyStr),
              unitCostPaise: Value(effectiveCost),
              totalPaise: Value((movementQty * effectiveCost).round()),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              movementDate: Value(cmd.movementDate),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );

      // 2. Update stock item current quantity.
      await (_db.update(
        _db.stockItems,
      )..where((s) => s.localId.equals(cmd.stockItemId))).write(
        StockItemsCompanion(
          currentQuantity: Value(newQtyStr),
          unitCostPaise: Value(newAvgCost),
          updatedAt: Value(now),
        ),
      );

      // 3. Upsert balance.
      await _db
          .into(_db.inventoryBalances)
          .insertOnConflictUpdate(
            InventoryBalancesCompanion(
              localId: Value(IdGenerator.newId()),
              companyId: Value(companyId),
              stockItemId: Value(cmd.stockItemId),
              locationId: const Value('default'),
              quantityOnHand: Value(newQtyStr),
              averageCostPaise: Value(newAvgCost),
              updatedAt: Value(now),
            ),
          );

      // 4. Queue sync.
      final payloadJson = jsonEncode({
        'event_id': localId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'inventory',
        'aggregate_id': localId,
        'event_type': 'stock.adjusted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'item_id': stockItem.remoteId ?? stockItem.localId,
          'movement_type': cmd.movementType,
          'quantity_micros': (movementQty * 10000).round(),
          'unit_cost_micros': effectiveCost * 100,
          'balance_after': newQtyStr,
          'reference': cmd.referenceNumber ?? cmd.description,
          'movement_date': cmd.movementDate,
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('inventory'),
              entityLocalId: Value(localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payloadJson),
              idempotencyKey: Value(idempotencyKey),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return _toMovement(await _getMovementRow(localId));
  }

  @override
  Stream<List<InventoryMovementEntity>> watchMovements(
    String stockItemId,
  ) async* {
    final query = _db.select(_db.inventoryMovements)
      ..where((m) => m.stockItemId.equals(stockItemId) & m.deletedAt.isNull())
      ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]);

    await for (final rows in query.watch()) {
      yield rows.map(_toMovement).toList();
    }
  }

  @override
  Future<List<InventoryMovementEntity>> getMovements(String stockItemId) async {
    final rows =
        await (_db.select(_db.inventoryMovements)
              ..where(
                (m) => m.stockItemId.equals(stockItemId) & m.deletedAt.isNull(),
              )
              ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
            .get();
    return rows.map(_toMovement).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<StockItemEntity?> _getStockItemByLocalId(String localId) async {
    final row = await (_db.select(
      _db.stockItems,
    )..where((s) => s.localId.equals(localId))).getSingleOrNull();
    return row != null ? _toStockItem(row) : null;
  }

  Future<InventoryMovement> _getMovementRow(String localId) async {
    return (await (_db.select(
      _db.inventoryMovements,
    )..where((m) => m.localId.equals(localId))).getSingle());
  }

  StockItemEntity _toStockItem(StockItem row) => StockItemEntity(
    localId: row.localId,
    remoteId: row.remoteId,
    companyId: row.companyId,
    name: row.name,
    sku: row.sku,
    unit: row.unit,
    currentQuantity: row.currentQuantity,
    unitCostPaise: row.unitCostPaise,
    isActive: row.isActive,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.synced,
    ),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  InventoryMovementEntity _toMovement(InventoryMovement row) =>
      InventoryMovementEntity(
        localId: row.localId,
        companyId: row.companyId,
        stockItemId: row.stockItemId,
        movementType: row.movementType,
        quantity: row.quantity,
        balanceAfter: row.balanceAfter,
        unitCostPaise: row.unitCostPaise,
        totalPaise: row.totalPaise,
        referenceNumber: row.referenceNumber,
        description: row.description,
        movementDate: row.movementDate,
        syncStatus: SyncStatus.values.firstWhere(
          (s) => s.name == row.syncStatus,
          orElse: () => SyncStatus.localOnly,
        ),
        createdAt: row.createdAt,
        syncError: row.syncError,
      );

  Future<bool> _applyPulledAdjustment(Map<String, dynamic> event) async {
    final payload =
        event['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final companyId = event['company_id']?.toString() ?? '';
    final movementId = event['aggregate_id']?.toString() ?? '';
    final itemId = payload['item_id']?.toString() ?? '';
    if (companyId.isEmpty || movementId.isEmpty || itemId.isEmpty) {
      throw const FormatException(
        'Pulled stock adjustment identity is incomplete.',
      );
    }
    final stockItem =
        await (_db.select(_db.stockItems)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  (row.localId.equals(itemId) | row.remoteId.equals(itemId)),
            ))
            .getSingleOrNull();
    if (stockItem == null) {
      throw StateError('Pulled stock item is not available locally.');
    }
    final existing = await (_db.select(
      _db.inventoryMovements,
    )..where((row) => row.localId.equals(movementId))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    final quantityMicros = _inventoryInt(payload['quantity_micros']);
    final balanceMicros = payload['server_balance_micros'] != null
        ? _inventoryInt(payload['server_balance_micros'])
        : payload['balance_after'] != null
        ? ((double.tryParse(payload['balance_after'].toString()) ?? 0) * 10000)
              .round()
        : ((double.tryParse(stockItem.currentQuantity) ?? 0) * 10000).round() +
              quantityMicros;
    final unitCostPaise = _inventoryMicrosToPaise(payload['unit_cost_micros']);
    final balance = (balanceMicros / 10000).toString();
    if (existing == null) {
      await _db
          .into(_db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion(
              localId: Value(movementId),
              companyId: Value(companyId),
              stockItemId: Value(stockItem.localId),
              movementType: Value(
                payload['movement_type']?.toString() ?? 'ADJUSTMENT',
              ),
              quantity: Value((quantityMicros / 10000).toString()),
              balanceAfter: Value(balance),
              unitCostPaise: Value(unitCostPaise),
              totalPaise: Value(
                (quantityMicros.abs() * unitCostPaise / 10000).round(),
              ),
              referenceNumber: Value(payload['reference']?.toString()),
              movementDate: Value(
                payload['movement_date']?.toString() ??
                    event['occurred_at']?.toString().split('T').first ??
                    '',
              ),
              syncStatus: Value(SyncStatus.synced.name),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastSyncedAt: Value(now),
              originDeviceId: Value(event['device_id']?.toString() ?? ''),
            ),
          );
    } else {
      await (_db.update(
        _db.inventoryMovements,
      )..where((row) => row.localId.equals(movementId))).write(
        InventoryMovementsCompanion(
          balanceAfter: Value(balance),
          syncStatus: Value(SyncStatus.synced.name),
          isDirty: const Value(false),
          lastSyncedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
    await (_db.update(
      _db.stockItems,
    )..where((row) => row.localId.equals(stockItem.localId))).write(
      StockItemsCompanion(
        currentQuantity: Value(balance),
        unitCostPaise: Value(
          unitCostPaise > 0 ? unitCostPaise : stockItem.unitCostPaise,
        ),
        updatedAt: Value(now),
      ),
    );
    await _db
        .into(_db.inventoryBalances)
        .insertOnConflictUpdate(
          InventoryBalancesCompanion(
            localId: Value('${companyId}_${stockItem.localId}_default'),
            companyId: Value(companyId),
            stockItemId: Value(stockItem.localId),
            locationId: const Value('default'),
            quantityOnHand: Value(balance),
            averageCostPaise: Value(
              unitCostPaise > 0 ? unitCostPaise : stockItem.unitCostPaise,
            ),
            updatedAt: Value(now),
          ),
        );
    return true;
  }

  Future<SyncPushResult> _pushInventory(OutboxRecord op) async {
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
        entityLabel: 'inventory movement',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 422) {
        throw const PermanentSyncException(
          'Validation error',
          userAction: 'Review the inventory movement.',
        );
      }
      if (code != null && code >= 500) {
        throw RetryableSyncException('Server error ($code).');
      }
      throw RetryableSyncException('Network error.', cause: e);
    }
  }
}

int _inventoryInt(Object? value) =>
    value is num ? value.round() : int.tryParse(value?.toString() ?? '') ?? 0;

int _inventoryMicrosToPaise(Object? value) =>
    (_inventoryInt(value) / 100).round();

int computeWeightedAverage(
  double currentQty,
  int currentCost,
  double incomingQty,
  int incomingCost,
) {
  final totalValue = (currentQty * currentCost) + (incomingQty * incomingCost);
  final totalQty = currentQty + incomingQty;
  if (totalQty <= 0) return 0;
  return (totalValue / totalQty).round();
}
