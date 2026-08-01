/// Implementation of [SalesRepository].
///
/// Delivery is a multi-entity transaction: delivery → stock → movement →
/// COGS journal → order status → outbox.  All or nothing.
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
import '../../domain/commands/sales_commands.dart';
import '../../domain/entities/sales_entities.dart';
import '../../domain/repositories/sales_repository.dart';

class SalesRepositoryImpl implements SalesRepository {
  SalesRepositoryImpl({
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
    _syncEngine.registerPusher('sales_delivery', (op) => _push(op));
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  // ── Sales orders ──────────────────────────────────────────────────────────

  @override
  Stream<List<SalesOrderEntity>> watchSalesOrders({String? companyId}) async* {
    final q = _db.select(_db.salesOrders)
      ..where((o) => o.deletedAt.isNull())
      ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    if (companyId != null) q.where((o) => o.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      final r = <SalesOrderEntity>[];
      for (final row in rows) {
        final lines =
            await (_db.select(_db.salesOrderLines)
                  ..where((l) => l.salesOrderLocalId.equals(row.localId))
                  ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
                .get();
        r.add(_soEntity(row, lines));
      }
      yield r;
    }
  }

  @override
  Future<SalesOrderEntity?> getSalesOrder(String localId) async {
    final row =
        await (_db.select(_db.salesOrders)
              ..where((o) => o.localId.equals(localId) & o.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    final lines =
        await (_db.select(_db.salesOrderLines)
              ..where((l) => l.salesOrderLocalId.equals(localId))
              ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
            .get();
    return _soEntity(row, lines);
  }

  @override
  Future<SalesOrderEntity> saveSalesOrderDraft(
    SaveSalesOrderDraftCommand cmd,
  ) async {
    final localId = IdGenerator.newId();
    final now = DateTime.now().toUtc();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();

    await _db
        .into(_db.salesOrders)
        .insert(
          SalesOrdersCompanion(
            localId: Value(localId),
            companyId: Value(companyId),
            orderDate: Value(cmd.orderDate),
            customerId: Value(cmd.customerId),
            customerName: Value(cmd.customerName),
            referenceNumber: Value(cmd.referenceNumber),
            description: Value(cmd.description),
            totalPaise: Value(cmd.totalPaise),
            createdAt: Value(now),
            updatedAt: Value(now),
            originDeviceId: Value(await _deviceIdProvider()),
          ),
        );
    for (int i = 0; i < cmd.lines.length; i++) {
      final l = cmd.lines[i];
      await _db
          .into(_db.salesOrderLines)
          .insert(
            SalesOrderLinesCompanion(
              localId: Value(IdGenerator.newId()),
              salesOrderLocalId: Value(localId),
              productName: Value(l.productName),
              description: Value(l.description),
              unit: Value(l.unit),
              unitPricePaise: Value(l.unitPricePaise),
              quantityOrdered: Value(l.quantityOrdered),
              totalPaise: Value(l.totalPaise),
              sortOrder: Value(l.sortOrder),
            ),
          );
    }
    return (await getSalesOrder(localId))!;
  }

  // ── Deliver goods (multi-entity transaction) ──────────────────────────────

  @override
  Future<SalesDeliveryEntity> deliverGoods(DeliverGoodsCommand cmd) async {
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final deliveryLocalId = IdGenerator.newId();
    final journalLocalId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    // Load the sales order.
    final so = await (_db.select(
      _db.salesOrders,
    )..where((o) => o.localId.equals(cmd.salesOrderLocalId))).getSingleOrNull();
    if (so == null) throw const ValidationException('Sales order not found.');

    // Pre-validate quantities and stock availability.
    for (final dl in cmd.lines) {
      final soLine =
          await (_db.select(_db.salesOrderLines)
                ..where((l) => l.localId.equals(dl.salesOrderLineLocalId)))
              .getSingleOrNull();
      if (soLine == null) {
        throw const ValidationException('Order line not found.');
      }
      final ordered = double.tryParse(soLine.quantityOrdered) ?? 0;
      final delivered = double.tryParse(soLine.quantityDelivered) ?? 0;
      final nowDelivering = double.tryParse(dl.quantityDelivered) ?? 0;
      if (delivered + nowDelivering > ordered + 0.001) {
        throw ValidationException(
          'Cannot deliver ${dl.productName}: exceeds ordered quantity.',
        );
      }

      // Check stock.
      final stock =
          await (_db.select(_db.stockItems)..where(
                (s) =>
                    s.companyId.equals(companyId) &
                    s.name.equals(dl.productName) &
                    s.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      if (stock == null) {
        throw ValidationException('No stock item found for ${dl.productName}.');
      }
      final onHand = double.tryParse(stock.currentQuantity) ?? 0;
      if (nowDelivering > onHand + 0.001) {
        throw ValidationException(
          'Insufficient stock for ${dl.productName}: $onHand available, $nowDelivering required.',
        );
      }
    }

    // Compute total COGS.
    int totalCogsPaise = 0;

    await _db.transaction(() async {
      // 1. Create delivery + lines.
      await _db
          .into(_db.salesDeliveries)
          .insert(
            SalesDeliveriesCompanion(
              localId: Value(deliveryLocalId),
              companyId: Value(companyId),
              salesOrderLocalId: Value(cmd.salesOrderLocalId),
              deliveryDate: Value(cmd.deliveryDate),
              customerId: Value(cmd.customerId),
              customerName: Value(cmd.customerName),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );

      for (final dl in cmd.lines) {
        final qty = double.tryParse(dl.quantityDelivered) ?? 0;
        await _db
            .into(_db.salesDeliveryLines)
            .insert(
              SalesDeliveryLinesCompanion(
                localId: Value(IdGenerator.newId()),
                deliveryLocalId: Value(deliveryLocalId),
                salesOrderLineLocalId: Value(dl.salesOrderLineLocalId),
                productName: Value(dl.productName),
                unit: Value(dl.unit),
                quantityDelivered: Value(dl.quantityDelivered),
                unitPricePaise: Value(dl.unitPricePaise),
                totalPaise: Value((qty * dl.unitPricePaise).round()),
                sortOrder: Value(dl.sortOrder),
              ),
            );

        // 2. Reduce stock, record ISSUE movement.
        if (qty > 0) {
          final stock =
              await (_db.select(_db.stockItems)..where(
                    (s) =>
                        s.companyId.equals(companyId) &
                        s.name.equals(dl.productName) &
                        s.deletedAt.isNull(),
                  ))
                  .getSingle();
          final curQty = double.tryParse(stock.currentQuantity) ?? 0;
          final newQty = curQty - qty;
          final newQtyStr = newQty.toStringAsFixed(3);
          final unitCost = stock.unitCostPaise;
          final lineCogs = (qty * unitCost).round();
          totalCogsPaise += lineCogs;

          await (_db.update(
            _db.stockItems,
          )..where((s) => s.localId.equals(stock.localId))).write(
            StockItemsCompanion(
              currentQuantity: Value(newQtyStr),
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
                  quantityOnHand: Value(newQtyStr),
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
                  movementType: const Value('ISSUE'),
                  quantity: Value('-${dl.quantityDelivered}'),
                  balanceAfter: Value(newQtyStr),
                  unitCostPaise: Value(unitCost),
                  totalPaise: Value(lineCogs),
                  movementDate: Value(cmd.deliveryDate),
                  referenceNumber: Value(cmd.referenceNumber),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                  originDeviceId: Value(deviceId),
                ),
              );
        }

        // 3. Update SO line delivered quantity.
        final soLine =
            await (_db.select(_db.salesOrderLines)
                  ..where((l) => l.localId.equals(dl.salesOrderLineLocalId)))
                .getSingle();
        final prevDelivered = double.tryParse(soLine.quantityDelivered) ?? 0;
        await (_db.update(
          _db.salesOrderLines,
        )..where((l) => l.localId.equals(dl.salesOrderLineLocalId))).write(
          SalesOrderLinesCompanion(
            quantityDelivered: Value((prevDelivered + qty).toStringAsFixed(3)),
          ),
        );
      }

      // 4. Update order status to DELIVERING or DELIVERED.
      final allLines = await (_db.select(
        _db.salesOrderLines,
      )..where((l) => l.salesOrderLocalId.equals(cmd.salesOrderLocalId))).get();
      final allDelivered = allLines.every((l) {
        final ordered = double.tryParse(l.quantityOrdered) ?? 0;
        final delivered = double.tryParse(l.quantityDelivered) ?? 0;
        return delivered >= ordered - 0.001;
      });
      await (_db.update(
        _db.salesOrders,
      )..where((o) => o.localId.equals(cmd.salesOrderLocalId))).write(
        SalesOrdersCompanion(
          status: Value(allDelivered ? 'DELIVERED' : 'DELIVERING'),
          updatedAt: Value(now),
        ),
      );

      // 5. Create COGS journal.
      if (totalCogsPaise > 0) {
        await _db
            .into(_db.journalEntries)
            .insert(
              JournalEntriesCompanion(
                localId: Value(journalLocalId),
                companyId: Value(companyId),
                entryDate: Value(cmd.deliveryDate),
                description: Value('COGS: ${cmd.customerName} delivery'),
                sourceType: const Value('AUTO'),
                lifecycleStatus: const Value('posted'),
                syncStatus: const Value('localOnly'),
                createdAt: Value(now),
                updatedAt: Value(now),
                originDeviceId: Value(deviceId),
              ),
            );
        await _db
            .into(_db.journalLines)
            .insert(
              JournalLinesCompanion(
                localId: Value(IdGenerator.newId()),
                journalLocalId: Value(journalLocalId),
                accountId: const Value('cogs'),
                accountCode: const Value(''),
                accountName: const Value('Cost of Goods Sold'),
                direction: const Value('DEBIT'),
                amountPaise: Value(totalCogsPaise),
                sortOrder: const Value(0),
              ),
            );
        await _db
            .into(_db.journalLines)
            .insert(
              JournalLinesCompanion(
                localId: Value(IdGenerator.newId()),
                journalLocalId: Value(journalLocalId),
                accountId: const Value('inventory'),
                accountCode: const Value(''),
                accountName: const Value('Inventory'),
                direction: const Value('CREDIT'),
                amountPaise: Value(totalCogsPaise),
                sortOrder: const Value(1),
              ),
            );
      }

      // 6. Outbox.
      final payload = jsonEncode({
        'event_id': deliveryLocalId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'sales_delivery',
        'aggregate_id': deliveryLocalId,
        'event_type': 'sales_delivery.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'sales_order_id': cmd.salesOrderLocalId,
          'delivery_date': cmd.deliveryDate,
          'customer_name': cmd.customerName,
          'lines': cmd.lines
              .map(
                (l) => ({
                  'product_name': l.productName,
                  'quantity': l.quantityDelivered,
                  'unit_price_paise': l.unitPricePaise,
                }),
              )
              .toList(),
          'total_cogs_paise': totalCogsPaise,
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('sales_delivery'),
              entityLocalId: Value(deliveryLocalId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('sales', 'deliver', deliveryLocalId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return _deliveryEntity(await _getDeliveryRow(deliveryLocalId), cmd.lines);
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  @override
  Stream<List<SalesDeliveryEntity>> watchDeliveries({
    String? companyId,
  }) async* {
    final q = _db.select(_db.salesDeliveries)
      ..where((d) => d.deletedAt.isNull())
      ..orderBy([(d) => OrderingTerm.desc(d.createdAt)]);
    if (companyId != null) q.where((d) => d.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows.map((r) => _deliveryEntity(r, [])).toList();
    }
  }

  @override
  Future<SalesDeliveryEntity?> getDelivery(String localId) async {
    final row =
        await (_db.select(_db.salesDeliveries)
              ..where((d) => d.localId.equals(localId) & d.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    final lines = await (_db.select(
      _db.salesDeliveryLines,
    )..where((l) => l.deliveryLocalId.equals(localId))).get();
    return _deliveryEntity(
      row,
      lines
          .map(
            (l) => SalesDeliveryLineCommand(
              salesOrderLineLocalId: l.salesOrderLineLocalId,
              productName: l.productName,
              unit: l.unit,
              quantityDelivered: l.quantityDelivered,
              unitPricePaise: l.unitPricePaise,
              sortOrder: l.sortOrder,
            ),
          )
          .toList(),
    );
  }

  // ── Entity mapping ───────────────────────────────────────────────────────

  SalesOrderEntity _soEntity(SalesOrder row, List<SalesOrderLine> lines) =>
      SalesOrderEntity(
        localId: row.localId,
        remoteId: row.remoteId,
        companyId: row.companyId,
        orderDate: row.orderDate,
        customerId: row.customerId,
        customerName: row.customerName,
        referenceNumber: row.referenceNumber,
        description: row.description,
        status: row.status,
        totalPaise: row.totalPaise,
        syncStatus: SyncStatus.values.firstWhere(
          (s) => s.name == row.syncStatus,
          orElse: () => SyncStatus.localOnly,
        ),
        createdAt: row.createdAt,
        syncError: row.syncError,
        lines: lines
            .map(
              (l) => SalesOrderLineEntity(
                localId: l.localId,
                salesOrderLocalId: l.salesOrderLocalId,
                productName: l.productName,
                description: l.description,
                unit: l.unit,
                unitPricePaise: l.unitPricePaise,
                quantityOrdered: l.quantityOrdered,
                quantityDelivered: l.quantityDelivered,
                quantityInvoiced: l.quantityInvoiced,
                totalPaise: l.totalPaise,
                sortOrder: l.sortOrder,
              ),
            )
            .toList(),
      );

  SalesDeliveryEntity _deliveryEntity(
    SalesDelivery row,
    List<SalesDeliveryLineCommand> lines,
  ) => SalesDeliveryEntity(
    localId: row.localId,
    companyId: row.companyId,
    salesOrderLocalId: row.salesOrderLocalId,
    deliveryDate: row.deliveryDate,
    customerId: row.customerId,
    customerName: row.customerName,
    referenceNumber: row.referenceNumber,
    description: row.description,
    lifecycleStatus: row.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: row.createdAt,
    syncError: row.syncError,
    lines: lines
        .map(
          (l) => SalesDeliveryLineEntity(
            localId: '',
            deliveryLocalId: row.localId,
            salesOrderLineLocalId: l.salesOrderLineLocalId,
            productName: l.productName,
            unit: l.unit,
            quantityDelivered: l.quantityDelivered,
            unitPricePaise: l.unitPricePaise,
            totalPaise:
                ((double.tryParse(l.quantityDelivered) ?? 0) * l.unitPricePaise)
                    .round(),
            sortOrder: l.sortOrder,
          ),
        )
        .toList(),
  );

  Future<SalesDelivery> _getDeliveryRow(String localId) => (_db.select(
    _db.salesDeliveries,
  )..where((d) => d.localId.equals(localId))).getSingle();

  // ── Create invoice from delivery ──────────────────────────────────────────

  @override
  Future<SalesOrderEntity> createInvoiceFromDelivery(
    CreateInvoiceFromDeliveryCommand cmd,
  ) async {
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final invoiceLocalId = IdGenerator.newId();
    final journalLocalId = IdGenerator.newId();
    final opId = IdGenerator.newId();
    final idempotencyKey = IdGenerator.actionKey(
      'invoice',
      'from-delivery',
      cmd.deliveryLocalId,
    );

    // Load delivery.
    final delivery = await _getDeliveryRow(cmd.deliveryLocalId);
    if (delivery.lifecycleStatus != 'posted') {
      throw const ValidationException(
        'Delivery must be posted before invoicing.',
      );
    }
    final deliveryLines = await (_db.select(
      _db.salesDeliveryLines,
    )..where((l) => l.deliveryLocalId.equals(cmd.deliveryLocalId))).get();

    // Compute total before tax from delivery lines.
    final subtotal = deliveryLines.fold<int>(0, (s, l) => s + l.totalPaise);
    // Check for uninvoiced quantities.
    final uninvoicedAmt = deliveryLines.fold<int>(0, (s, l) {
      final qty = double.tryParse(l.quantityDelivered) ?? 0;
      final inv = double.tryParse(l.quantityInvoiced) ?? 0;
      return s + ((qty - inv) * l.unitPricePaise).round();
    });
    if (uninvoicedAmt <= 0) {
      throw const ValidationException(
        'All delivery quantities are already invoiced.',
      );
    }

    final productIds = <String, String>{};
    for (final dl in deliveryLines) {
      final stockItem = await (_db.select(_db.stockItems)
            ..where((s) => s.companyId.equals(companyId) & s.name.equals(dl.productName) & s.deletedAt.isNull()))
          .getSingleOrNull();
      if (stockItem != null) {
        productIds[dl.productName] = stockItem.localId;
      }
    }

    await _db.transaction(() async {
      // 1. Consume number allocation.
      final alloc =
          await (_db.select(_db.numberAllocations)..where(
                (a) =>
                    a.companyId.equals(companyId) &
                    a.deviceId.equals(deviceId) &
                    a.series.equals(cmd.series) &
                    a.documentType.equals('INVOICE') &
                    a.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (alloc == null ||
          (alloc.toNum - alloc.fromNum + 1 - alloc.used) <= 0) {
        throw const ValidationException(
          'No invoice number available. Sync to request more numbers.',
        );
      }
      final number = alloc.fromNum + alloc.used;

      await (_db.update(
        _db.numberAllocations,
      )..where((a) => a.id.equals(alloc.id))).write(
        NumberAllocationsCompanion(
          used: Value(alloc.used + 1),
          updatedAt: Value(now),
        ),
      );

      // 2. Freeze invoice.
      await _db
          .into(_db.invoices)
          .insert(
            InvoicesCompanion(
              localId: Value(invoiceLocalId),
              companyId: Value(companyId),
              number: Value(number),
              allocationId: Value(alloc.allocationId),
              invoiceDate: Value(cmd.invoiceDate),
              customerId: Value(cmd.customerId),
              customerName: Value(cmd.customerName),
              totalBeforeTaxPaise: Value(subtotal),
              taxPaise: Value(cmd.taxPaise),
              totalPaise: Value(
                cmd.totalPaise > 0 ? cmd.totalPaise : subtotal + cmd.taxPaise,
              ),
              lifecycleStatus: const Value('issued'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );

      // Invoice lines from delivery lines.
      for (final dl in deliveryLines) {
        final qty = double.tryParse(dl.quantityDelivered) ?? 0;
        final alreadyInvoiced = double.tryParse(dl.quantityInvoiced) ?? 0;
        if (qty - alreadyInvoiced <= 0.001) continue;
        await _db
            .into(_db.invoiceLines)
            .insert(
              InvoiceLinesCompanion(
                localId: Value(IdGenerator.newId()),
                invoiceLocalId: Value(invoiceLocalId),
                productId: const Value(null),
                productName: Value(dl.productName),
                unitPricePaise: Value(dl.unitPricePaise),
                quantity: Value(dl.quantityDelivered),
                amountPaise: Value(dl.totalPaise),
                discountPaise: const Value(0),
                netPaise: Value(dl.totalPaise),
                sortOrder: Value(dl.sortOrder),
              ),
            );
      }

      // 3. Journal: DEBIT Accounts Receivable, CREDIT Revenue/Sales.
      final totalInvPaise = cmd.totalPaise > 0 ? cmd.totalPaise : subtotal;
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(cmd.invoiceDate),
              description: Value('Invoice #$number: ${cmd.customerName}'),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: const Value('receivables'),
              accountCode: const Value(''),
              accountName: const Value('Accounts Receivable'),
              direction: const Value('DEBIT'),
              amountPaise: Value(totalInvPaise),
              sortOrder: const Value(0),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: const Value('revenue'),
              accountCode: const Value(''),
              accountName: const Value('Sales Revenue'),
              direction: const Value('CREDIT'),
              amountPaise: Value(totalInvPaise),
              sortOrder: const Value(1),
            ),
          );

      // 4. Update delivery line invoiced quantities.
      for (final dl in deliveryLines) {
        final alreadyInv = double.tryParse(dl.quantityInvoiced) ?? 0;
        final qty = double.tryParse(dl.quantityDelivered) ?? 0;
        await (_db.update(
          _db.salesDeliveryLines,
        )..where((l) => l.localId.equals(dl.localId))).write(
          SalesDeliveryLinesCompanion(
            quantityInvoiced: Value((alreadyInv + qty).toStringAsFixed(3)),
          ),
        );
      }

      // 5. Update SO lines invoiced quantities.
      for (final dl in deliveryLines) {
        final soLine =
            await (_db.select(_db.salesOrderLines)
                  ..where((l) => l.localId.equals(dl.salesOrderLineLocalId)))
                .getSingleOrNull();
        if (soLine != null) {
          final prevInv = double.tryParse(soLine.quantityInvoiced) ?? 0;
          final qty = double.tryParse(dl.quantityDelivered) ?? 0;
          await (_db.update(
            _db.salesOrderLines,
          )..where((l) => l.localId.equals(dl.salesOrderLineLocalId))).write(
            SalesOrderLinesCompanion(
              quantityInvoiced: Value((prevInv + qty).toStringAsFixed(3)),
            ),
          );
        }
      }

      // 6. Update SO status.
      final soLines =
          await (_db.select(_db.salesOrderLines)..where(
                (l) => l.salesOrderLocalId.equals(delivery.salesOrderLocalId),
              ))
              .get();
      final allInvoiced = soLines.every((l) {
        final ordered = double.tryParse(l.quantityOrdered) ?? 0;
        final invoiced = double.tryParse(l.quantityInvoiced) ?? 0;
        return invoiced >= ordered - 0.001;
      });
      await (_db.update(
        _db.salesOrders,
      )..where((o) => o.localId.equals(delivery.salesOrderLocalId))).write(
        SalesOrdersCompanion(
          status: Value(allInvoiced ? 'INVOICED' : 'DELIVERED'),
          updatedAt: Value(now),
        ),
      );

      // 7. Outbox.
      final payload = jsonEncode({
        'event_id': invoiceLocalId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'invoice',
        'aggregate_id': invoiceLocalId,
        'event_type': 'invoice.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'kind': 'sale',
          'number': number,
          'allocation_id': alloc.allocationId,
          'invoice_date': cmd.invoiceDate,
          'party_id': cmd.customerId,
          'customer_id': cmd.customerId,
          'customer_name': cmd.customerName,
          'total_paise': totalInvPaise,
          'subtotal_micros': subtotal * 100,
          'tax_micros': cmd.taxPaise * 100,
          'total_micros': totalInvPaise * 100,
          'lines': deliveryLines
              .map(
                (l) => ({
                  'item_id': productIds[l.productName] ?? '',
                  'product_name': l.productName,
                  'quantity': l.quantityDelivered,
                  'quantity_micros': ((double.tryParse(l.quantityDelivered) ?? 0) * 10000).round(),
                  'unit_price_paise': l.unitPricePaise,
                  'rate_micros': l.unitPricePaise * 100,
                  'line_total_micros': l.totalPaise * 100,
                }),
              )
              .toList(),
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('invoice'),
              entityLocalId: Value(invoiceLocalId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(idempotencyKey),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await getSalesOrder(delivery.salesOrderLocalId))!;
  }

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
