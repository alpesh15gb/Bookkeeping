/// Implementation of [PurchasingRepository].
///
/// Every cross-domain mutation (PO → receipt → inventory → journal → outbox)
/// is one Drift transaction.  Partial failure rolls back every entity.
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
import '../../domain/commands/purchasing_commands.dart';
import '../../domain/entities/purchasing_entities.dart';
import '../../domain/repositories/purchasing_repository.dart';

class PurchasingRepositoryImpl implements PurchasingRepository {
  PurchasingRepositoryImpl({
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
    _syncEngine.registerPusher('purchase_order', (op) => _push(op));
    _syncEngine.registerPusher('purchase_receipt', (op) => _push(op));
    _syncEngine.registerPusher('purchase_invoice', (op) => _push(op));
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;

  // ── Purchase orders ──────────────────────────────────────────────────────

  @override
  Stream<List<PurchaseOrderEntity>> watchPurchaseOrders({
    String? companyId,
  }) async* {
    final q = _db.select(_db.purchaseOrders)
      ..where((p) => p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    if (companyId != null) q.where((p) => p.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      final r = <PurchaseOrderEntity>[];
      for (final row in rows) {
        final lines =
            await (_db.select(_db.purchaseOrderLines)
                  ..where((l) => l.purchaseOrderLocalId.equals(row.localId))
                  ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
                .get();
        r.add(_poEntity(row, lines));
      }
      yield r;
    }
  }

  @override
  Future<PurchaseOrderEntity?> getPurchaseOrder(String localId) async {
    final row =
        await (_db.select(_db.purchaseOrders)
              ..where((p) => p.localId.equals(localId) & p.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    final lines =
        await (_db.select(_db.purchaseOrderLines)
              ..where((l) => l.purchaseOrderLocalId.equals(localId))
              ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
            .get();
    return _poEntity(row, lines);
  }

  @override
  Future<PurchaseOrderEntity> savePurchaseOrderDraft(
    SavePurchaseOrderDraftCommand cmd,
  ) async {
    final localId = IdGenerator.newId();
    final now = DateTime.now().toUtc();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();

    await _db
        .into(_db.purchaseOrders)
        .insert(
          PurchaseOrdersCompanion(
            localId: Value(localId),
            companyId: Value(companyId),
            orderDate: Value(cmd.orderDate),
            supplierId: Value(cmd.supplierId),
            supplierName: Value(cmd.supplierName),
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
          .into(_db.purchaseOrderLines)
          .insert(
            PurchaseOrderLinesCompanion(
              localId: Value(IdGenerator.newId()),
              purchaseOrderLocalId: Value(localId),
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
    return (await getPurchaseOrder(localId))!;
  }

  // ── Goods receipt (cross-domain transaction) ─────────────────────────────

  @override
  Future<PurchaseReceiptEntity> receiveGoods(ReceiveGoodsCommand cmd) async {
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    final deviceId = await _deviceIdProvider();
    final actorId = await _actorIdProvider();
    final now = DateTime.now().toUtc();
    final receiptLocalId = IdGenerator.newId();
    final journalLocalId = IdGenerator.newId();
    final opId = IdGenerator.newId();

    // Load PO to validate.
    final po =
        await (_db.select(_db.purchaseOrders)
              ..where((p) => p.localId.equals(cmd.purchaseOrderLocalId)))
            .getSingleOrNull();
    if (po == null) {
      throw const ValidationException('Purchase order not found.');
    }
    if (po.companyId != companyId) {
      throw const ValidationException(
        'Purchase order belongs to another company.',
      );
    }
    final supplier =
        await (_db.select(_db.contacts)..where(
              (contact) =>
                  contact.localId.equals(cmd.supplierId) &
                  contact.companyId.equals(companyId) &
                  contact.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (supplier == null ||
        (supplier.contactType != 'vendor' && supplier.contactType != 'both')) {
      throw const ValidationException(
        'Select an active supplier from this company.',
      );
    }
    if (cmd.lines.isEmpty) {
      throw const ValidationException(
        'Goods receipt must contain at least one line.',
      );
    }
    final productByName = <String, StockItem>{};
    for (final line in cmd.lines) {
      final quantity = double.tryParse(line.quantityReceived) ?? 0;
      if (quantity <= 0 || line.unitCostPaise < 0) {
        throw const ValidationException(
          'Received quantities must be positive and costs cannot be negative.',
        );
      }
      final matches =
          await (_db.select(_db.stockItems)..where(
                (item) =>
                    item.companyId.equals(companyId) &
                    item.name.equals(line.productName) &
                    item.isActive.equals(true) &
                    item.deletedAt.isNull(),
              ))
              .get();
      if (matches.length != 1) {
        throw ValidationException(
          'Product "${line.productName}" is missing or ambiguous. '
          'Sync master data and try again.',
        );
      }
      productByName[line.productName] = matches.single;
    }
    final inventoryAccount =
        await (_db.select(_db.accounts)..where(
              (account) =>
                  account.companyId.equals(companyId) &
                  account.code.equals('1300') &
                  account.isActive.equals(true),
            ))
            .getSingleOrNull();
    final grirAccount =
        await (_db.select(_db.accounts)..where(
              (account) =>
                  account.companyId.equals(companyId) &
                  account.code.equals('3204') &
                  account.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (inventoryAccount == null || grirAccount == null) {
      throw const ValidationException(
        'Offline accounting setup is incomplete. Connect once to refresh it.',
      );
    }

    await _db.transaction(() async {
      // 1. Create receipt + lines.
      await _db
          .into(_db.purchaseReceipts)
          .insert(
            PurchaseReceiptsCompanion(
              localId: Value(receiptLocalId),
              companyId: Value(companyId),
              purchaseOrderLocalId: Value(cmd.purchaseOrderLocalId),
              receiptDate: Value(cmd.receiptDate),
              supplierId: Value(cmd.supplierId),
              supplierName: Value(cmd.supplierName),
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

      for (final rl in cmd.lines) {
        // Insert receipt line.
        await _db
            .into(_db.purchaseReceiptLines)
            .insert(
              PurchaseReceiptLinesCompanion(
                localId: Value(IdGenerator.newId()),
                receiptLocalId: Value(receiptLocalId),
                purchaseOrderLineLocalId: Value(rl.purchaseOrderLineLocalId),
                productName: Value(rl.productName),
                unit: Value(rl.unit),
                quantityReceived: Value(rl.quantityReceived),
                unitCostPaise: Value(rl.unitCostPaise),
                totalPaise: Value(
                  ((double.tryParse(rl.quantityReceived) ?? 0) *
                          rl.unitCostPaise)
                      .round(),
                ),
                sortOrder: Value(rl.sortOrder),
              ),
            );

        // 2. Update inventory: load or create stock item by name + company.
        final qty = double.tryParse(rl.quantityReceived) ?? 0;
        if (qty > 0) {
          final stockItem = productByName[rl.productName];

          final now2 = DateTime.now().toUtc();
          if (stockItem != null) {
            final curQty = double.tryParse(stockItem.currentQuantity) ?? 0;
            final newQty = curQty + qty;
            final newQtyStr2 = newQty.toStringAsFixed(3);
            final curCost = stockItem.unitCostPaise;
            final avgCost = curQty > 0
                ? ((curQty * curCost) + (qty * rl.unitCostPaise)) /
                      (curQty + qty)
                : rl.unitCostPaise;

            await (_db.update(
              _db.stockItems,
            )..where((s) => s.localId.equals(stockItem.localId))).write(
              StockItemsCompanion(
                currentQuantity: Value(newQtyStr2),
                unitCostPaise: Value(avgCost.round()),
                updatedAt: Value(now2),
              ),
            );

            // Upsert balance.
            await _db
                .into(_db.inventoryBalances)
                .insertOnConflictUpdate(
                  InventoryBalancesCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: Value(companyId),
                    stockItemId: Value(stockItem.localId),
                    quantityOnHand: Value(newQtyStr2),
                    averageCostPaise: Value(avgCost.round()),
                    updatedAt: Value(now2),
                  ),
                );

            // Movement.
            await _db
                .into(_db.inventoryMovements)
                .insert(
                  InventoryMovementsCompanion(
                    localId: Value(IdGenerator.newId()),
                    companyId: Value(companyId),
                    stockItemId: Value(stockItem.localId),
                    movementType: const Value('RECEIPT'),
                    quantity: Value(rl.quantityReceived),
                    balanceAfter: Value(newQtyStr2),
                    unitCostPaise: Value(rl.unitCostPaise),
                    totalPaise: Value((qty * rl.unitCostPaise).round()),
                    movementDate: Value(cmd.receiptDate),
                    referenceNumber: Value(cmd.referenceNumber),
                    createdAt: Value(now2),
                    updatedAt: Value(now2),
                    originDeviceId: Value(deviceId),
                  ),
                );
          }
        }

        // 3. Update PO line received quantity.
        final poLine =
            await (_db.select(_db.purchaseOrderLines)
                  ..where((l) => l.localId.equals(rl.purchaseOrderLineLocalId)))
                .getSingleOrNull();
        if (poLine != null) {
          final prevRecv = double.tryParse(poLine.quantityReceived) ?? 0;
          await (_db.update(
            _db.purchaseOrderLines,
          )..where((l) => l.localId.equals(rl.purchaseOrderLineLocalId))).write(
            PurchaseOrderLinesCompanion(
              quantityReceived: Value((prevRecv + qty).toStringAsFixed(3)),
            ),
          );
        }
      }

      // 4. Create journal: DEBIT inventory, CREDIT GRIR/suspense.
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(cmd.receiptDate),
              description: Value('GRN: ${cmd.supplierName}'),
              sourceType: const Value('AUTO'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );

      final totalReceiptPaise = cmd.lines.fold<int>(
        0,
        (s, l) =>
            s +
            ((double.tryParse(l.quantityReceived) ?? 0) * l.unitCostPaise)
                .round(),
      );

      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: Value(inventoryAccount.localId),
              accountCode: Value(inventoryAccount.code),
              accountName: Value(inventoryAccount.name),
              direction: const Value('DEBIT'),
              amountPaise: Value(totalReceiptPaise),
              sortOrder: const Value(0),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: Value(grirAccount.localId),
              accountCode: Value(grirAccount.code),
              accountName: Value(grirAccount.name),
              direction: const Value('CREDIT'),
              amountPaise: Value(totalReceiptPaise),
              sortOrder: const Value(1),
            ),
          );

      // 5. Outbox.
      final payload = jsonEncode({
        'event_id': receiptLocalId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'purchase_receipt',
        'aggregate_id': receiptLocalId,
        'event_type': 'purchase_receipt.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'receipt_date': cmd.receiptDate,
          'supplier_id': cmd.supplierId,
          'supplier_name': cmd.supplierName,
          'reference_number': cmd.referenceNumber,
          'notes': cmd.description,
          'lines': cmd.lines
              .map(
                (l) => {
                  'item_id': productByName[l.productName]!.localId,
                  'product_name': l.productName,
                  'quantity_micros':
                      ((double.tryParse(l.quantityReceived) ?? 0) * 10000)
                          .round(),
                  'unit_cost_micros': l.unitCostPaise * 100,
                },
              )
              .toList(),
          'total_paise': totalReceiptPaise,
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('purchase_receipt'),
              entityLocalId: Value(receiptLocalId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('purchase', 'receive', receiptLocalId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return _receiptEntity(await _getReceiptRow(receiptLocalId), cmd.lines);
  }

  // ── Supplier invoice ─────────────────────────────────────────────────────

  @override
  Future<PurchaseInvoiceEntity> postSupplierInvoice(
    PostSupplierInvoiceCommand cmd,
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
      throw const ValidationException('Invoice total must be > 0.');
    }

    final productIds = <String, String>{};
    for (final l in cmd.lines) {
      final stockItem = await (_db.select(_db.stockItems)
            ..where((s) => s.companyId.equals(companyId) & s.name.equals(l.productName) & s.deletedAt.isNull()))
          .getSingleOrNull();
      if (stockItem != null) {
        productIds[l.productName] = stockItem.localId;
      }
    }

    await _db.transaction(() async {
      await _db
          .into(_db.purchaseInvoices)
          .insert(
            PurchaseInvoicesCompanion(
              localId: Value(localId),
              companyId: Value(companyId),
              invoiceNumber: Value(cmd.invoiceNumber),
              invoiceDate: Value(cmd.invoiceDate),
              supplierId: Value(cmd.supplierId),
              supplierName: Value(cmd.supplierName),
              referenceNumber: Value(cmd.referenceNumber),
              description: Value(cmd.description),
              totalBeforeTaxPaise: Value(cmd.totalBeforeTaxPaise),
              taxPaise: Value(cmd.taxPaise),
              totalPaise: Value(cmd.totalPaise),
              lifecycleStatus: const Value('POSTED'),
              syncStatus: const Value('pending'),
              isDirty: const Value(true),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      for (int i = 0; i < cmd.lines.length; i++) {
        final l = cmd.lines[i];
        await _db
            .into(_db.purchaseInvoiceLines)
            .insert(
              PurchaseInvoiceLinesCompanion(
                localId: Value(IdGenerator.newId()),
                invoiceLocalId: Value(localId),
                productName: Value(l.productName),
                description: Value(l.description),
                unit: Value(l.unit),
                unitPricePaise: Value(l.unitPricePaise),
                quantity: Value(l.quantity),
                totalPaise: Value(l.totalPaise),
                sortOrder: Value(l.sortOrder),
              ),
            );
      }

      // Journal: DEBIT expense/asset, CREDIT AP.
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(cmd.invoiceDate),
              description: Value(
                'Purchase: ${cmd.supplierName} ${cmd.invoiceNumber}',
              ),
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
              accountId: const Value('purchases'),
              accountCode: const Value(''),
              accountName: const Value('Purchases'),
              direction: const Value('DEBIT'),
              amountPaise: Value(cmd.totalPaise),
              sortOrder: const Value(0),
            ),
          );
      await _db
          .into(_db.journalLines)
          .insert(
            JournalLinesCompanion(
              localId: Value(IdGenerator.newId()),
              journalLocalId: Value(journalLocalId),
              accountId: const Value('ap'),
              accountCode: const Value(''),
              accountName: const Value('Accounts Payable'),
              direction: const Value('CREDIT'),
              amountPaise: Value(cmd.totalPaise),
              sortOrder: const Value(1),
            ),
          );

      final linesPayload = cmd.lines
          .map(
            (l) => {
              'item_id': productIds[l.productName] ?? '',
              'product_name': l.productName,
              'description': l.description ?? l.productName,
              'quantity_micros': ((double.tryParse(l.quantity) ?? 0) * 10000).round(),
              'rate_micros': l.unitPricePaise * 100,
              'line_total_micros': l.totalPaise * 100,
            },
          )
          .toList();

      final payload = jsonEncode({
        'event_id': localId,
        'company_id': companyId,
        'device_id': deviceId,
        'aggregate_type': 'purchase_invoice',
        'aggregate_id': localId,
        'event_type': 'purchase_invoice.posted',
        'event_version': 1,
        'occurred_at': now.toIso8601String(),
        'payload': {
          'invoice_number': cmd.invoiceNumber,
          'invoice_date': cmd.invoiceDate,
          'party_id': cmd.supplierId,
          'supplier_id': cmd.supplierId,
          'supplier_name': cmd.supplierName,
          'total_paise': cmd.totalPaise,
          'subtotal_micros': cmd.totalBeforeTaxPaise * 100,
          'tax_micros': cmd.taxPaise * 100,
          'total_micros': cmd.totalPaise * 100,
          'lines': linesPayload,
        },
      });
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('purchase_invoice'),
              entityLocalId: Value(localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              operationType: const Value('create'),
              payload: Value(payload),
              idempotencyKey: Value(
                IdGenerator.actionKey('purchase', 'invoice', localId),
              ),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return _piEntity(await _getPiRow(localId), cmd.lines);
  }

  // ── Read helpers ─────────────────────────────────────────────────────────

  @override
  Stream<List<PurchaseReceiptEntity>> watchReceipts({
    String? companyId,
  }) async* {
    final q = _db.select(_db.purchaseReceipts)
      ..where((r) => r.deletedAt.isNull())
      ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]);
    if (companyId != null) q.where((r) => r.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      yield rows.map((r) => _receiptEntity(r, [])).toList();
    }
  }

  @override
  Future<PurchaseReceiptEntity?> getReceipt(String localId) async {
    final row =
        await (_db.select(_db.purchaseReceipts)
              ..where((r) => r.localId.equals(localId) & r.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    final lines = await (_db.select(
      _db.purchaseReceiptLines,
    )..where((l) => l.receiptLocalId.equals(localId))).get();
    return _receiptEntity(
      row,
      lines
          .map(
            (l) => ReceiveLineCommand(
              purchaseOrderLineLocalId: l.purchaseOrderLineLocalId,
              productName: l.productName,
              unit: l.unit,
              quantityReceived: l.quantityReceived,
              unitCostPaise: l.unitCostPaise,
              sortOrder: l.sortOrder,
            ),
          )
          .toList(),
    );
  }

  @override
  Stream<List<PurchaseInvoiceEntity>> watchPurchaseInvoices({
    String? companyId,
  }) async* {
    final q = _db.select(_db.purchaseInvoices)
      ..where((i) => i.deletedAt.isNull())
      ..orderBy([(i) => OrderingTerm.desc(i.createdAt)]);
    if (companyId != null) q.where((i) => i.companyId.equals(companyId));
    await for (final rows in q.watch()) {
      final r = <PurchaseInvoiceEntity>[];
      for (final row in rows) {
        final lines = await (_db.select(
          _db.purchaseInvoiceLines,
        )..where((l) => l.invoiceLocalId.equals(row.localId))).get();
        r.add(_piEntityFromRow(row, lines));
      }
      yield r;
    }
  }

  @override
  Future<PurchaseInvoiceEntity?> getPurchaseInvoice(String localId) async {
    final row =
        await (_db.select(_db.purchaseInvoices)
              ..where((i) => i.localId.equals(localId) & i.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    final lines = await (_db.select(
      _db.purchaseInvoiceLines,
    )..where((l) => l.invoiceLocalId.equals(localId))).get();
    return _piEntityFromRow(row, lines);
  }

  // ── Entity mapping ───────────────────────────────────────────────────────

  PurchaseOrderEntity _poEntity(
    PurchaseOrder row,
    List<PurchaseOrderLine> lines,
  ) => PurchaseOrderEntity(
    localId: row.localId,
    remoteId: row.remoteId,
    companyId: row.companyId,
    orderDate: row.orderDate,
    supplierId: row.supplierId,
    supplierName: row.supplierName,
    referenceNumber: row.referenceNumber,
    description: row.description,
    status: row.status,
    totalPaise: row.totalPaise,
    receivedQuantity: row.receivedQuantity,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: row.createdAt,
    syncError: row.syncError,
    lines: lines
        .map(
          (l) => PurchaseOrderLineEntity(
            localId: l.localId,
            purchaseOrderLocalId: l.purchaseOrderLocalId,
            productName: l.productName,
            description: l.description,
            unit: l.unit,
            unitPricePaise: l.unitPricePaise,
            quantityOrdered: l.quantityOrdered,
            quantityReceived: l.quantityReceived,
            totalPaise: l.totalPaise,
            sortOrder: l.sortOrder,
          ),
        )
        .toList(),
  );

  PurchaseReceiptEntity _receiptEntity(
    PurchaseReceipt row,
    List<ReceiveLineCommand> lines,
  ) => PurchaseReceiptEntity(
    localId: row.localId,
    companyId: row.companyId,
    purchaseOrderLocalId: row.purchaseOrderLocalId,
    receiptDate: row.receiptDate,
    supplierId: row.supplierId,
    supplierName: row.supplierName,
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
          (l) => PurchaseReceiptLineEntity(
            localId: '',
            receiptLocalId: row.localId,
            purchaseOrderLineLocalId: l.purchaseOrderLineLocalId,
            productName: l.productName,
            unit: l.unit,
            quantityReceived: l.quantityReceived,
            unitCostPaise: l.unitCostPaise,
            totalPaise:
                ((double.tryParse(l.quantityReceived) ?? 0) * l.unitCostPaise)
                    .round(),
            sortOrder: l.sortOrder,
          ),
        )
        .toList(),
  );

  Future<PurchaseReceipt> _getReceiptRow(String localId) => (_db.select(
    _db.purchaseReceipts,
  )..where((r) => r.localId.equals(localId))).getSingle();

  PurchaseInvoiceEntity _piEntity(
    PurchaseInvoice row,
    List<SupplierInvoiceLineCommand> lines,
  ) => PurchaseInvoiceEntity(
    localId: row.localId,
    companyId: row.companyId,
    invoiceNumber: row.invoiceNumber,
    invoiceDate: row.invoiceDate,
    supplierId: row.supplierId,
    supplierName: row.supplierName,
    referenceNumber: row.referenceNumber,
    description: row.description,
    totalBeforeTaxPaise: row.totalBeforeTaxPaise,
    taxPaise: row.taxPaise,
    totalPaise: row.totalPaise,
    lifecycleStatus: row.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: row.createdAt,
    syncError: row.syncError,
    lines: lines
        .map(
          (l) => PurchaseInvoiceLineEntity(
            localId: '',
            invoiceLocalId: row.localId,
            productName: l.productName,
            description: l.description,
            unit: l.unit,
            unitPricePaise: l.unitPricePaise,
            quantity: l.quantity,
            totalPaise: l.totalPaise,
            sortOrder: l.sortOrder,
          ),
        )
        .toList(),
  );

  PurchaseInvoiceEntity _piEntityFromRow(
    PurchaseInvoice row,
    List<PurchaseInvoiceLine> lines,
  ) => PurchaseInvoiceEntity(
    localId: row.localId,
    companyId: row.companyId,
    invoiceNumber: row.invoiceNumber,
    invoiceDate: row.invoiceDate,
    supplierId: row.supplierId,
    supplierName: row.supplierName,
    referenceNumber: row.referenceNumber,
    description: row.description,
    totalBeforeTaxPaise: row.totalBeforeTaxPaise,
    taxPaise: row.taxPaise,
    totalPaise: row.totalPaise,
    lifecycleStatus: row.lifecycleStatus,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == row.syncStatus,
      orElse: () => SyncStatus.localOnly,
    ),
    createdAt: row.createdAt,
    syncError: row.syncError,
    lines: lines
        .map(
          (l) => PurchaseInvoiceLineEntity(
            localId: l.localId,
            invoiceLocalId: l.invoiceLocalId,
            productName: l.productName,
            description: l.description,
            unit: l.unit,
            unitPricePaise: l.unitPricePaise,
            quantity: l.quantity,
            totalPaise: l.totalPaise,
            sortOrder: l.sortOrder,
          ),
        )
        .toList(),
  );

  Future<PurchaseInvoice> _getPiRow(String localId) => (_db.select(
    _db.purchaseInvoices,
  )..where((i) => i.localId.equals(localId))).getSingle();

  // ── Sync pusher ──────────────────────────────────────────────────────────

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
