/// Implementation of [InvoiceRepository].
///
/// Draft saves write to SQLite with no number consumed.
/// Issue atomically:  reserve number → freeze invoice → create journal → outbox.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/core/errors/app_exception.dart';
import 'package:apexbooks/core/ids/id_generator.dart';
import 'package:apexbooks/core/sync/sync_engine.dart';
import 'package:apexbooks/core/sync/sync_operation.dart';
import 'package:apexbooks/core/sync/sync_status.dart';
import 'package:apexbooks/features/invoices/domain/commands/invoice_commands.dart';
import 'package:apexbooks/features/invoices/domain/entities/invoice_entity.dart';
import 'package:apexbooks/features/invoices/domain/repositories/invoice_repository.dart';

class InvoiceRepositoryImpl implements InvoiceRepository {
  InvoiceRepositoryImpl({
    required AppDatabase db,
    required SyncEngine syncEngine,
    required Dio dio,
    required Future<String> Function() deviceIdProvider,
    required Future<String> Function() companyIdProvider,
    required Future<String> Function() actorIdProvider,
    required Future<String> Function() financialYearIdProvider,
  }) : _db = db,
       _syncEngine = syncEngine,
       _dio = dio,
       _deviceIdProvider = deviceIdProvider,
       _companyIdProvider = companyIdProvider,
       _actorIdProvider = actorIdProvider,
       _financialYearIdProvider = financialYearIdProvider {
    _syncEngine.registerPusher('invoice', (op) => _pushInvoice(op));
    _syncEngine.registerPullApplicator('invoice.posted', _applyPulledInvoice);
  }

  final AppDatabase _db;
  final SyncEngine _syncEngine;
  final Dio _dio;
  final Future<String> Function() _deviceIdProvider;
  final Future<String> Function() _companyIdProvider;
  final Future<String> Function() _actorIdProvider;
  final Future<String> Function() _financialYearIdProvider;

  // ── Number allocations ────────────────────────────────────────────────────

  @override
  Future<NumberAllocationEntity?> currentAllocation({
    required String companyId,
    required String deviceId,
    required String financialYearId,
    required String series,
    required String documentType,
  }) async {
    final row =
        await (_db.select(_db.numberAllocations)..where(
              (a) =>
                  a.companyId.equals(companyId) &
                  a.deviceId.equals(deviceId) &
                  a.financialYearId.equals(financialYearId) &
                  a.series.equals(series) &
                  a.documentType.equals(documentType) &
                  a.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _toAllocationEntity(row);
  }

  @override
  Future<NumberAllocationEntity?> ensureAllocation({
    String companyId = '',
    String deviceId = '',
    String financialYearId = '',
    String series = 'SALES',
    String documentType = 'INVOICE',
  }) async {
    final resolvedCompanyId = companyId.isNotEmpty
        ? companyId
        : await _companyIdProvider();
    final resolvedDeviceId = deviceId.isNotEmpty
        ? deviceId
        : await _deviceIdProvider();
    final normalizedSeries = series.trim().toUpperCase();
    final normalizedDocumentType = documentType.trim().toUpperCase();

    final query = _db.select(_db.numberAllocations)
      ..where(
        (row) =>
            row.companyId.equals(resolvedCompanyId) &
            row.deviceId.equals(resolvedDeviceId) &
            row.series.equals(normalizedSeries) &
            row.documentType.equals(normalizedDocumentType) &
            row.isActive.equals(true),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.allocatedAt)])
      ..limit(1);
    if (financialYearId.isNotEmpty) {
      query.where((row) => row.financialYearId.equals(financialYearId));
    }
    final currentRow = await query.getSingleOrNull();
    final current = currentRow == null ? null : _toAllocationEntity(currentRow);
    if (current != null && !current.isExhausted) return current;

    try {
      final response = await _dio.post(
        '/apexbooks/number-allocations',
        data: {
          'device_id': resolvedDeviceId,
          'document_type': normalizedDocumentType,
          'series': normalizedSeries,
          'batch_size': 100,
          if (current != null) 'previous_allocation_id': current.allocationId,
        },
      );
      final data = (response.data as Map).cast<String, dynamic>();
      final now = DateTime.now().toUtc();
      final allocationId = data['allocation_id'].toString();
      final newRow = NumberAllocationsCompanion(
        id: Value(allocationId),
        allocationId: Value(allocationId),
        companyId: Value(data['company_id'].toString()),
        deviceId: Value(data['device_id'].toString()),
        financialYearId: Value(data['financial_year_id'].toString()),
        series: Value(data['series'].toString()),
        documentType: Value(data['document_type'].toString()),
        prefix: Value(data['prefix']?.toString() ?? ''),
        suffix: Value(data['suffix']?.toString()),
        paddingDigits: Value(
          int.tryParse(data['padding_digits'].toString()) ?? 4,
        ),
        fromNum: Value(int.parse(data['from_num'].toString())),
        toNum: Value(int.parse(data['to_num'].toString())),
        used: const Value(0),
        isActive: const Value(true),
        allocatedAt: Value(
          DateTime.tryParse(data['allocated_at']?.toString() ?? '')?.toUtc() ??
              now,
        ),
        updatedAt: Value(now),
      );
      await _db.transaction(() async {
        await (_db.update(_db.numberAllocations)..where(
              (row) =>
                  row.companyId.equals(resolvedCompanyId) &
                  row.deviceId.equals(resolvedDeviceId) &
                  row.series.equals(normalizedSeries) &
                  row.documentType.equals(normalizedDocumentType),
            ))
            .write(const NumberAllocationsCompanion(isActive: Value(false)));
        await _db.into(_db.numberAllocations).insertOnConflictUpdate(newRow);
      });
      final saved = await (_db.select(
        _db.numberAllocations,
      )..where((row) => row.allocationId.equals(allocationId))).getSingle();
      return _toAllocationEntity(saved);
    } on DioException catch (error) {
      if (error.response == null) return null;
      final detail = error.response?.data is Map
          ? (error.response!.data as Map)['detail']?.toString()
          : null;
      throw ValidationException(
        detail ?? 'Unable to reserve document numbers.',
      );
    }
  }

  // ── Invoice read ─────────────────────────────────────────────────────────

  @override
  Stream<List<InvoiceEntity>> watchInvoices({String? companyId}) async* {
    final query = _db.select(_db.invoices)..where((i) => i.deletedAt.isNull());
    if (companyId != null) {
      query.where((i) => i.companyId.equals(companyId));
    }
    query.orderBy([(i) => OrderingTerm.desc(i.createdAt)]);

    await for (final rows in query.watch()) {
      final entities = <InvoiceEntity>[];
      for (final row in rows) {
        final lines =
            await (_db.select(_db.invoiceLines)
                  ..where((l) => l.invoiceLocalId.equals(row.localId))
                  ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
                .get();
        entities.add(_toEntity(row, lines));
      }
      yield entities;
    }
  }

  @override
  Future<InvoiceEntity?> getInvoice(String localId) async {
    final row =
        await (_db.select(_db.invoices)
              ..where((i) => i.localId.equals(localId) & i.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    final lines =
        await (_db.select(_db.invoiceLines)
              ..where((l) => l.invoiceLocalId.equals(localId))
              ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
            .get();
    return _toEntity(row, lines);
  }

  // ── Draft ────────────────────────────────────────────────────────────────

  @override
  Future<InvoiceEntity> saveDraft(SaveInvoiceDraftCommand cmd) async {
    final localId = IdGenerator.newId();
    final now = DateTime.now().toUtc();
    final companyId = cmd.companyId.isNotEmpty
        ? cmd.companyId
        : await _companyIdProvider();
    if (cmd.lines.isEmpty) {
      throw const ValidationException('Add at least one invoice line.');
    }
    var subtotalPaise = 0;
    var discountPaise = 0;
    var taxPaise = 0;
    for (final line in cmd.lines) {
      final quantity = double.tryParse(line.quantity);
      if (line.productId == null ||
          line.productId!.isEmpty ||
          quantity == null ||
          quantity <= 0 ||
          line.unitPricePaise <= 0 ||
          line.discountPaise < 0 ||
          line.discountPaise > line.amountPaise) {
        throw const ValidationException(
          'Every invoice line needs a product, positive quantity and price, and a valid discount.',
        );
      }
      final product =
          await (_db.select(_db.stockItems)..where(
                (row) =>
                    row.companyId.equals(companyId) &
                    (row.localId.equals(line.productId!) |
                        row.remoteId.equals(line.productId!)) &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (product == null) {
        throw const ValidationException(
          'An invoice product is not available for this company.',
        );
      }
      subtotalPaise += line.amountPaise;
      discountPaise += line.discountPaise;
      taxPaise += line.taxPaise;
    }
    final totalBeforeTaxPaise = subtotalPaise - discountPaise;
    final totalPaise = totalBeforeTaxPaise + taxPaise + cmd.shippingPaise;

    await _db
        .into(_db.invoices)
        .insert(
          InvoicesCompanion(
            localId: Value(localId),
            companyId: Value(companyId),
            invoiceDate: Value(cmd.invoiceDate),
            customerId: Value(cmd.customerId),
            customerName: Value(cmd.customerName),
            customerGstin: Value(cmd.customerGstin),
            customerStateCode: Value(cmd.customerStateCode),
            dueDate: Value(cmd.dueDate),
            referenceNumber: Value(cmd.referenceNumber),
            paymentTerms: Value(cmd.paymentTerms),
            totalBeforeTaxPaise: Value(totalBeforeTaxPaise),
            taxPaise: Value(taxPaise),
            discountPaise: Value(discountPaise),
            shippingPaise: Value(cmd.shippingPaise),
            totalPaise: Value(totalPaise),
            lifecycleStatus: const Value('draft'),
            syncStatus: const Value('localOnly'),
            createdAt: Value(now),
            updatedAt: Value(now),
            originDeviceId: Value(await _deviceIdProvider()),
          ),
        );

    // Insert lines.
    for (final l in cmd.lines) {
      await _db
          .into(_db.invoiceLines)
          .insert(
            InvoiceLinesCompanion(
              localId: Value(IdGenerator.newId()),
              invoiceLocalId: Value(localId),
              productId: Value(l.productId),
              productName: Value(l.productName),
              description: Value(l.description),
              hsnSac: Value(l.hsnSac),
              unitPricePaise: Value(l.unitPricePaise),
              quantity: Value(l.quantity),
              amountPaise: Value(l.amountPaise),
              discountPaise: Value(l.discountPaise),
              netPaise: Value(l.netPaise),
              taxRateBasisPoints: Value(l.taxRateBasisPoints),
              taxPaise: Value(l.taxPaise),
              sortOrder: Value(l.sortOrder),
            ),
          );
    }

    return (await getInvoice(localId))!;
  }

  // ── Issue (number consumed) ─────────────────────────────────────────────

  @override
  Future<InvoiceEntity> issue(IssueInvoiceCommand cmd) async {
    final invoice = await getInvoice(cmd.localId);
    if (invoice == null) {
      throw const ValidationException('Invoice not found.');
    }
    if (!invoice.isDraft) {
      throw const ValidationException('Only draft invoices can be issued.');
    }
    if (invoice.totalPaise <= 0) {
      throw const ValidationException(
        'Invoice total must be greater than zero.',
      );
    }

    final deviceId = await _deviceIdProvider();
    final requestedFyId = cmd.financialYearId.isNotEmpty
        ? cmd.financialYearId
        : await _financialYearIdProvider();
    final actorId = await _actorIdProvider();
    final companyId = invoice.companyId;
    final contact =
        await (_db.select(_db.contacts)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  (row.localId.equals(invoice.customerId) |
                      row.remoteId.equals(invoice.customerId)),
            ))
            .getSingleOrNull();
    final receivableAccountId = contact?.receivableAccountId;
    final salesAccount =
        await (_db.select(_db.accounts)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  row.code.equals('5001') &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    final profile = await (_db.select(
      _db.companyProfiles,
    )..where((row) => row.companyId.equals(companyId))).getSingleOrNull();
    final isIntraState =
        profile?.originStateCode?.isNotEmpty == true &&
        invoice.customerStateCode == profile!.originStateCode;
    final requiredTaxCodes = invoice.taxPaise == 0
        ? const <String>[]
        : isIntraState
        ? const ['3001', '3002']
        : const ['3003'];
    final taxAccounts = requiredTaxCodes.isEmpty
        ? const <Account>[]
        : await (_db.select(_db.accounts)..where(
                (row) =>
                    row.companyId.equals(companyId) &
                    row.code.isIn(requiredTaxCodes) &
                    row.isActive.equals(true),
              ))
              .get();
    if (receivableAccountId == null ||
        receivableAccountId.isEmpty ||
        salesAccount == null ||
        taxAccounts.length != requiredTaxCodes.length) {
      throw const ValidationException(
        'Accounting references are incomplete. Connect once to refresh the chart of accounts before issuing.',
      );
    }

    // Load allocation.
    final alloc = await ensureAllocation(
      companyId: companyId,
      deviceId: deviceId,
      financialYearId: requestedFyId,
      series: cmd.series,
      documentType: 'INVOICE',
    );
    if (alloc == null || alloc.isExhausted) {
      throw const ValidationException(
        'No invoice number available. Sync to request more numbers.',
      );
    }
    final fyId = alloc.financialYearId;

    final number = alloc.nextNumber;
    final displayNumber = alloc.nextDisplayNumber;
    final allocationId = alloc.allocationId;
    final now = DateTime.now().toUtc();
    final opId = IdGenerator.newId();
    final journalLocalId = IdGenerator.newId();
    final idempotencyKey = IdGenerator.actionKey(
      'invoice',
      'issue',
      cmd.localId,
    );

    await _db.transaction(() async {
      // 1. Consume the number (update allocation).
      await (_db.update(
        _db.numberAllocations,
      )..where((a) => a.id.equals(alloc.localId))).write(
        NumberAllocationsCompanion(
          used: Value(alloc.used + 1),
          updatedAt: Value(now),
        ),
      );

      // 2. Freeze the invoice: assign number, set issued status.
      await (_db.update(
        _db.invoices,
      )..where((i) => i.localId.equals(cmd.localId))).write(
        InvoicesCompanion(
          number: Value(number),
          displayNumber: Value(displayNumber),
          allocationId: Value(allocationId),
          lifecycleStatus: const Value('issued'),
          syncStatus: const Value('pending'),
          isDirty: const Value(true),
          updatedAt: Value(now),
        ),
      );

      // 3. Persist the balanced local posting so offline reports immediately
      // reflect the issued invoice.
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion(
              localId: Value(journalLocalId),
              companyId: Value(companyId),
              entryDate: Value(invoice.invoiceDate),
              referenceNumber: Value(displayNumber),
              description: Value('Sales invoice $displayNumber'),
              sourceType: const Value('INVOICE'),
              lifecycleStatus: const Value('posted'),
              syncStatus: const Value('localOnly'),
              createdAt: Value(now),
              updatedAt: Value(now),
              originDeviceId: Value(deviceId),
            ),
          );
      var sortOrder = 0;
      Future<void> addJournalLine(
        String accountId,
        String code,
        String name,
        String direction,
        int amountPaise,
      ) async {
        if (amountPaise <= 0) return;
        await _db
            .into(_db.journalLines)
            .insert(
              JournalLinesCompanion(
                localId: Value(IdGenerator.newId()),
                journalLocalId: Value(journalLocalId),
                accountId: Value(accountId),
                accountCode: Value(code),
                accountName: Value(name),
                direction: Value(direction),
                amountPaise: Value(amountPaise),
                sortOrder: Value(sortOrder++),
              ),
            );
      }

      await addJournalLine(
        receivableAccountId,
        contact!.receivableAccountId == receivableAccountId ? 'AR' : '',
        'Accounts Receivable - ${invoice.customerName}',
        'DEBIT',
        invoice.totalPaise,
      );
      await addJournalLine(
        salesAccount.localId,
        salesAccount.code,
        salesAccount.name,
        'CREDIT',
        invoice.totalBeforeTaxPaise + invoice.shippingPaise,
      );
      if (invoice.taxPaise > 0 && isIntraState) {
        final cgst = invoice.taxPaise ~/ 2;
        final sgst = invoice.taxPaise - cgst;
        final cgstAccount = taxAccounts.firstWhere(
          (account) => account.code == '3001',
        );
        final sgstAccount = taxAccounts.firstWhere(
          (account) => account.code == '3002',
        );
        await addJournalLine(
          cgstAccount.localId,
          cgstAccount.code,
          cgstAccount.name,
          'CREDIT',
          cgst,
        );
        await addJournalLine(
          sgstAccount.localId,
          sgstAccount.code,
          sgstAccount.name,
          'CREDIT',
          sgst,
        );
      } else if (invoice.taxPaise > 0) {
        final igstAccount = taxAccounts.first;
        await addJournalLine(
          igstAccount.localId,
          igstAccount.code,
          igstAccount.name,
          'CREDIT',
          invoice.taxPaise,
        );
      }

      // 4. Queue sync operation.
      final payloadJson = _buildSyncPayload(
        invoice,
        number,
        displayNumber,
        allocationId,
        companyId,
        deviceId,
        now,
        actorId,
        fyId,
      );
      await _db
          .into(_db.syncOperations)
          .insert(
            SyncOperationsCompanion(
              id: Value(opId),
              entityType: const Value('invoice'),
              entityLocalId: Value(cmd.localId),
              companyId: Value(companyId),
              actorId: Value(actorId),
              deviceId: Value(deviceId),
              financialYearId: Value(fyId),
              operationType: const Value('create'),
              payload: Value(payloadJson),
              idempotencyKey: Value(idempotencyKey),
              status: Value(SyncStatus.pending.name),
              createdAt: Value(now),
            ),
          );
    });

    return (await getInvoice(cmd.localId))!;
  }

  // ── Sync ─────────────────────────────────────────────────────────────────

  @override
  Future<void> retrySync(String localId) async {
    await (_db.update(_db.syncOperations)..where(
          (o) =>
              o.entityLocalId.equals(localId) &
              o.entityType.equals('invoice') &
              o.status.equals(SyncStatus.failed.name),
        ))
        .write(
          const SyncOperationsCompanion(
            status: Value('pending'),
            lastError: Value(null),
          ),
        );
    await (_db.update(
      _db.invoices,
    )..where((i) => i.localId.equals(localId))).write(
      const InvoicesCompanion(
        syncStatus: Value('pending'),
        syncError: Value(null),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  InvoiceEntity _toEntity(Invoice row, List<InvoiceLine> lineRows) {
    return InvoiceEntity(
      localId: row.localId,
      remoteId: row.remoteId,
      companyId: row.companyId,
      number: row.number,
      displayNumber: row.displayNumber,
      allocationId: row.allocationId,
      invoiceDate: row.invoiceDate,
      dueDate: row.dueDate,
      customerId: row.customerId,
      customerName: row.customerName,
      customerGstin: row.customerGstin,
      customerStateCode: row.customerStateCode,
      currency: row.currency,
      paymentTerms: row.paymentTerms,
      referenceNumber: row.referenceNumber,
      totalBeforeTaxPaise: row.totalBeforeTaxPaise,
      taxPaise: row.taxPaise,
      discountPaise: row.discountPaise,
      shippingPaise: row.shippingPaise,
      totalPaise: row.totalPaise,
      lifecycleStatus: row.lifecycleStatus,
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == row.syncStatus,
        orElse: () => SyncStatus.localOnly,
      ),
      localRevision: row.localRevision,
      remoteRevision: row.remoteRevision,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      lastSyncedAt: row.lastSyncedAt,
      syncError: row.syncError,
      lines: lineRows
          .map(
            (l) => InvoiceLineEntity(
              localId: l.localId,
              invoiceLocalId: l.invoiceLocalId,
              productId: l.productId,
              productName: l.productName,
              description: l.description,
              hsnSac: l.hsnSac,
              unitPricePaise: l.unitPricePaise,
              quantity: l.quantity,
              amountPaise: l.amountPaise,
              discountPaise: l.discountPaise,
              taxRateBasisPoints: l.taxRateBasisPoints,
              taxPaise: l.taxPaise,
              netPaise: l.netPaise,
              sortOrder: l.sortOrder,
            ),
          )
          .toList(),
    );
  }

  NumberAllocationEntity _toAllocationEntity(NumberAllocation row) {
    return NumberAllocationEntity(
      localId: row.id,
      allocationId: row.allocationId,
      companyId: row.companyId,
      deviceId: row.deviceId,
      financialYearId: row.financialYearId,
      series: row.series,
      documentType: row.documentType,
      fromNum: row.fromNum,
      toNum: row.toNum,
      used: row.used,
      prefix: row.prefix,
      suffix: row.suffix,
      paddingDigits: row.paddingDigits,
    );
  }

  String _buildSyncPayload(
    InvoiceEntity inv,
    int number,
    String displayNumber,
    String allocationId,
    String companyId,
    String deviceId,
    DateTime now,
    String actorId,
    String fyId,
  ) {
    final linesPayload = inv.lines
        .map(
          (l) => {
            'item_id': l.productId,
            'description': l.description ?? l.productName,
            'quantity_micros': ((double.tryParse(l.quantity) ?? 0) * 10000)
                .round(),
            'rate_micros': l.unitPricePaise * 100,
            'discount_micros': l.discountPaise * 100,
            'line_total_micros': l.netPaise * 100,
            'tax_rate_basis_points': l.taxRateBasisPoints,
            'tax_micros': l.taxPaise * 100,
          },
        )
        .toList();

    return jsonEncode({
      'event_id': inv.localId,
      'company_id': companyId,
      'device_id': deviceId,
      'aggregate_type': 'invoice',
      'aggregate_id': inv.localId,
      'event_type': 'invoice.posted',
      'event_version': 1,
      'occurred_at': now.toIso8601String(),
      'payload': {
        'kind': 'sale',
        'number': number,
        'invoice_number': displayNumber,
        'allocation_id': allocationId,
        'financial_year_id': fyId,
        'invoice_date': inv.invoiceDate,
        'party_id': inv.customerId,
        'customer_id': inv.customerId,
        'customer_name': inv.customerName,
        'due_date': inv.dueDate,
        'reference_number': inv.referenceNumber,
        'place_of_supply_state_code': inv.customerStateCode,
        'lines': linesPayload,
        'subtotal_micros': inv.totalBeforeTaxPaise * 100,
        'tax_micros': inv.taxPaise * 100,
        'discount_micros': inv.discountPaise * 100,
        'shipping_micros': inv.shippingPaise * 100,
        'total_micros': inv.totalPaise * 100,
        'total_paise': inv.totalPaise,
      },
    });
  }

  Future<bool> _applyPulledInvoice(Map<String, dynamic> event) async {
    final payload =
        event['payload'] as Map<String, dynamic>? ?? <String, dynamic>{};
    if (payload['kind']?.toString() != 'sale') return false;
    final companyId = event['company_id']?.toString() ?? '';
    final invoiceId = event['aggregate_id']?.toString() ?? '';
    if (companyId.isEmpty || invoiceId.isEmpty) {
      throw const FormatException('Pulled invoice identity is incomplete.');
    }
    final existing = await (_db.select(
      _db.invoices,
    )..where((row) => row.localId.equals(invoiceId))).getSingleOrNull();
    if (existing?.isDirty == true) {
      throw StateError('Pulled invoice conflicts with an unsynced local edit.');
    }
    final now = DateTime.now().toUtc();
    final lines = payload['lines'] as List? ?? const [];
    final partyId =
        payload['party_id']?.toString() ??
        payload['customer_id']?.toString() ??
        '';
    final contact =
        await (_db.select(_db.contacts)..where(
              (row) =>
                  row.companyId.equals(companyId) &
                  (row.localId.equals(partyId) | row.remoteId.equals(partyId)),
            ))
            .getSingleOrNull();

    await _db
        .into(_db.invoices)
        .insertOnConflictUpdate(
          InvoicesCompanion(
            localId: Value(invoiceId),
            remoteId: Value(invoiceId),
            companyId: Value(companyId),
            number: Value(_asNullableInt(payload['number'])),
            displayNumber: Value(payload['invoice_number']?.toString()),
            allocationId: Value(payload['allocation_id']?.toString()),
            invoiceDate: Value(
              payload['invoice_date']?.toString() ??
                  event['occurred_at']?.toString().split('T').first ??
                  '',
            ),
            dueDate: Value(payload['due_date']?.toString()),
            customerId: Value(partyId),
            customerName: Value(
              payload['customer_name']?.toString() ?? contact?.name ?? '',
            ),
            customerGstin: Value(contact?.gstin),
            customerStateCode: Value(
              payload['place_of_supply_state_code']?.toString() ??
                  contact?.stateCode,
            ),
            referenceNumber: Value(payload['reference_number']?.toString()),
            totalBeforeTaxPaise: Value(
              _microsToPaise(payload['subtotal_micros']),
            ),
            taxPaise: Value(_microsToPaise(payload['tax_micros'])),
            totalPaise: Value(_microsToPaise(payload['total_micros'])),
            lifecycleStatus: const Value('issued'),
            syncStatus: Value(SyncStatus.synced.name),
            isDirty: const Value(false),
            remoteRevision: Value(_asNullableInt(event['server_sequence'])),
            createdAt: Value(existing?.createdAt ?? now),
            updatedAt: Value(now),
            lastSyncedAt: Value(now),
            originDeviceId: Value(event['device_id']?.toString() ?? ''),
          ),
        );
    await (_db.delete(
      _db.invoiceLines,
    )..where((line) => line.invoiceLocalId.equals(invoiceId))).go();
    for (var index = 0; index < lines.length; index++) {
      final line = Map<String, dynamic>.from(lines[index] as Map);
      final productId = line['item_id']?.toString();
      final product = productId == null
          ? null
          : await (_db.select(_db.stockItems)..where(
                  (row) =>
                      row.companyId.equals(companyId) &
                      (row.localId.equals(productId) |
                          row.remoteId.equals(productId)),
                ))
                .getSingleOrNull();
      final quantityMicros = _asNullableInt(line['quantity_micros']) ?? 0;
      final ratePaise = _microsToPaise(line['rate_micros']);
      final discountPaise = _microsToPaise(line['discount_micros']);
      final amountPaise = (ratePaise * quantityMicros / 10000).round();
      final taxRate = _asNullableInt(line['tax_rate_basis_points']) ?? 0;
      final netPaise = amountPaise - discountPaise;
      await _db
          .into(_db.invoiceLines)
          .insert(
            InvoiceLinesCompanion(
              localId: Value(
                '${invoiceId}_line_${index.toString().padLeft(4, '0')}',
              ),
              invoiceLocalId: Value(invoiceId),
              productId: Value(productId),
              productName: Value(
                product?.name ?? line['description']?.toString() ?? '',
              ),
              description: Value(line['description']?.toString()),
              hsnSac: Value(product?.hsnSac),
              unitPricePaise: Value(ratePaise),
              quantity: Value((quantityMicros / 10000).toString()),
              amountPaise: Value(amountPaise),
              discountPaise: Value(discountPaise),
              netPaise: Value(netPaise),
              taxRateBasisPoints: Value(taxRate),
              taxPaise: Value(
                _microsToPaise(line['tax_micros']) != 0
                    ? _microsToPaise(line['tax_micros'])
                    : (netPaise * taxRate / 10000).round(),
              ),
              sortOrder: Value(index),
            ),
          );
    }
    return true;
  }

  Future<SyncPushResult> _pushInvoice(OutboxRecord op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    try {
      final res = await _dio.post(
        '/apexbooks/sync/push',
        data: {
          'events': [payload],
        },
        options: Options(headers: {'Idempotency-Key': op.idempotencyKey}),
      );
      return parseSyncPushResponse(res.data, payload, entityLabel: 'invoice');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 422) {
        throw PermanentSyncException(
          (e.response?.data is Map)
              ? ((e.response!.data as Map)['detail'] ?? 'Validation error')
                    .toString()
              : 'Validation error',
          userAction: 'Review the invoice for errors.',
        );
      }
      if (code == 409) {
        throw ConflictException(
          'Invoice number conflict.',
          conflictId: payload['aggregate_id']?.toString(),
        );
      }
      if (code != null && code >= 500) {
        throw RetryableSyncException('Server error ($code).');
      }
      throw RetryableSyncException('Network error.', cause: e);
    }
  }
}

int _microsToPaise(Object? value) {
  final micros = value is num
      ? value.round()
      : int.tryParse(value?.toString() ?? '') ?? 0;
  return (micros / 100).round();
}

int? _asNullableInt(Object? value) {
  if (value == null) return null;
  return value is num ? value.round() : int.tryParse(value.toString());
}
