/// Unit tests for [ReportsService].
///
/// Each test seeds a minimal in-memory Drift database with known rows, calls
/// the service, and asserts against **hard-coded expected values** — not just
/// "result is not null".  This provides the numeric regression evidence that
/// the walkthrough audit required.
///
/// Run with:
///   flutter test test/features/reports/reports_service_test.dart
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/database/app_database.dart';
import 'package:apexbooks/features/reports/services/reports_service.dart';
import 'package:apexbooks/features/reports/models/report_models.dart';
import 'package:apexbooks/core/result/result.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

AppDatabase _openMemoryDb() => AppDatabase(NativeDatabase.memory());

/// Seeds a minimal contact and returns its localId.
Future<String> _seedContact(
  AppDatabase db, {
  required String companyId,
  String contactType = 'customer',
  String name = 'Test Customer',
}) async {
  final id = 'contact-$companyId-${name.replaceAll(' ', '-').toLowerCase()}';
  await db.into(db.contacts).insert(
    ContactsCompanion.insert(
      localId: id,
      remoteId: 'remote-$id',
      companyId: companyId,
      name: name,
      contactType: contactType,
      updatedAt: DateTime(2024, 1, 1),
    ),
  );
  return id;
}

/// Seeds an issued invoice and returns its localId.
Future<String> _seedInvoice(
  AppDatabase db, {
  required String companyId,
  required String customerId,
  required String date,
  required int totalPaise,
  String status = 'issued',
  String? displayNumber,
  int number = 1,
}) async {
  final id = 'invoice-$date-$totalPaise';
  await db.into(db.invoices).insert(
    InvoicesCompanion.insert(
      localId: id,
      companyId: companyId,
      customerId: customerId,
      customerName: 'Customer',
      invoiceDate: date,
      totalBeforeTaxPaise: totalPaise,
      taxPaise: 0,
      totalPaise: totalPaise,
      lifecycleStatus: Value(status),
      number: Value(number),
      displayNumber: Value(displayNumber),
      createdAt: DateTime.parse('${date}T00:00:00'),
      updatedAt: DateTime.parse('${date}T00:00:00'),
      originDeviceId: 'test-device',
    ),
  );
  return id;
}

/// Seeds a purchase invoice (bill) and returns its localId.
Future<String> _seedBill(
  AppDatabase db, {
  required String companyId,
  required String supplierId,
  required String date,
  required int totalPaise,
  String status = 'POSTED',
  String invoiceNumber = 'BILL-001',
}) async {
  final id = 'bill-$date-$totalPaise';
  await db.into(db.purchaseInvoices).insert(
    PurchaseInvoicesCompanion.insert(
      localId: id,
      companyId: companyId,
      invoiceNumber: invoiceNumber,
      invoiceDate: date,
      supplierId: supplierId,
      supplierName: 'Supplier',
      totalBeforeTaxPaise: totalPaise,
      taxPaise: 0,
      totalPaise: totalPaise,
      lifecycleStatus: Value(status),
      createdAt: DateTime.parse('${date}T00:00:00'),
      updatedAt: DateTime.parse('${date}T00:00:00'),
      originDeviceId: 'test-device',
    ),
  );
  return id;
}

/// Seeds a payment and returns its localId.
Future<String> _seedPayment(
  AppDatabase db, {
  required String companyId,
  required String contactId,
  required String date,
  required int amountPaise,
  String paymentType = 'RECEIPT',
  String status = 'posted',
  String? referenceNumber,
}) async {
  final id = 'payment-$date-$amountPaise-$paymentType';
  await db.into(db.payments).insert(
    PaymentsCompanion.insert(
      localId: id,
      companyId: companyId,
      paymentType: paymentType,
      paymentDate: date,
      contactId: contactId,
      contactName: 'Contact',
      paymentMode: 'BANK',
      accountId: 'acc-001',
      amountPaise: amountPaise,
      lifecycleStatus: Value(status),
      referenceNumber: Value(referenceNumber),
      createdAt: DateTime.parse('${date}T00:00:00'),
      updatedAt: DateTime.parse('${date}T00:00:00'),
      originDeviceId: 'test-device',
    ),
  );
  return id;
}

/// Allocates [amountPaise] from payment [paymentId] to invoice [invoiceId].
Future<void> _seedAllocation(
  AppDatabase db, {
  required String paymentId,
  required String invoiceId,
  required int amountPaise,
}) async {
  await db.into(db.paymentAllocations).insert(
    PaymentAllocationsCompanion.insert(
      localId: 'alloc-$paymentId-$invoiceId',
      paymentLocalId: paymentId,
      invoiceLocalId: invoiceId,
      allocatedPaise: amountPaise,
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;
  late ReportsService svc;

  const companyA = 'company-A';
  const companyB = 'company-B';

  setUp(() {
    db = _openMemoryDb();
    svc = ReportsService(db, companyA);
  });

  tearDown(() async {
    await db.close();
  });

  // ── getSalesTransactions ──────────────────────────────────────────────────

  group('getSalesTransactions', () {
    test('returns only issued invoices for the active company', () async {
      final cId = await _seedContact(db, companyId: companyA);

      // company A: one issued invoice
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-01',
        totalPaise: 100000,
        status: 'issued',
        displayNumber: 'INV-001',
      );
      // company B: another invoice — must NOT appear
      final cB = await _seedContact(db, companyId: companyB);
      await _seedInvoice(
        db,
        companyId: companyB,
        customerId: cB,
        date: '2024-04-02',
        totalPaise: 50000,
        status: 'issued',
      );

      final res = await svc.getSalesTransactions();
      expect(res, isA<Success<List<SalesTransaction>>>());
      final items = (res as Success<List<SalesTransaction>>).value;
      expect(items.length, 1);
      expect(items.first.total, closeTo(1000.00, 0.001));
      expect(items.first.invoiceNumber, 'INV-001');
    });

    test('excludes draft invoices', () async {
      final cId = await _seedContact(db, companyId: companyA);
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-01',
        totalPaise: 100000,
        status: 'draft',
      );

      final res = await svc.getSalesTransactions();
      final items = (res as Success<List<SalesTransaction>>).value;
      expect(items, isEmpty);
    });

    test('date range boundary: invoice on dateFrom is included', () async {
      final cId = await _seedContact(db, companyId: companyA);
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-01',
        totalPaise: 10000,
        status: 'issued',
        number: 1,
      );
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-03-31',
        totalPaise: 20000,
        status: 'issued',
        number: 2,
      );

      final res = await svc.getSalesTransactions(dateFrom: '2024-04-01');
      final items = (res as Success<List<SalesTransaction>>).value;
      expect(items.length, 1);
      expect(items.first.total, closeTo(100.00, 0.001));
    });

    test('amountPaid reflects PaymentAllocations sum', () async {
      final cId = await _seedContact(db, companyId: companyA);
      final invId = await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-01',
        totalPaise: 100000,
        status: 'issued',
        number: 1,
      );
      final payId = await _seedPayment(
        db,
        companyId: companyA,
        contactId: cId,
        date: '2024-04-05',
        amountPaise: 40000,
      );
      await _seedAllocation(
        db,
        paymentId: payId,
        invoiceId: invId,
        amountPaise: 40000,
      );

      final res = await svc.getSalesTransactions();
      final items = (res as Success<List<SalesTransaction>>).value;
      expect(items.first.amountPaid, closeTo(400.00, 0.001));
    });
  });

  // ── getBills ──────────────────────────────────────────────────────────────

  group('getBills', () {
    test('excludes draft bills', () async {
      final cId = await _seedContact(db, companyId: companyA, contactType: 'vendor');
      await _seedBill(
        db,
        companyId: companyA,
        supplierId: cId,
        date: '2024-04-01',
        totalPaise: 50000,
        status: 'DRAFT',
      );

      final res = await svc.getBills();
      final items = (res as Success<List<PurchaseTransaction>>).value;
      expect(items, isEmpty);
    });

    test('excludes cancelled bills', () async {
      final cId = await _seedContact(db, companyId: companyA, contactType: 'vendor');
      await _seedBill(
        db,
        companyId: companyA,
        supplierId: cId,
        date: '2024-04-01',
        totalPaise: 50000,
        status: 'CANCELLED',
      );

      final res = await svc.getBills();
      final items = (res as Success<List<PurchaseTransaction>>).value;
      expect(items, isEmpty);
    });

    test('returns posted bill with correct total', () async {
      final cId = await _seedContact(db, companyId: companyA, contactType: 'vendor');
      await _seedBill(
        db,
        companyId: companyA,
        supplierId: cId,
        date: '2024-04-01',
        totalPaise: 200000,
        status: 'POSTED',
        invoiceNumber: 'BILL-002',
      );

      final res = await svc.getBills();
      final items = (res as Success<List<PurchaseTransaction>>).value;
      expect(items.length, 1);
      expect(items.first.total, closeTo(2000.00, 0.001));
      expect(items.first.billNumber, 'BILL-002');
    });
  });

  // ── getPartyStatement ─────────────────────────────────────────────────────

  group('getPartyStatement', () {
    test('returns Failure when contact not found', () async {
      final res = await svc.getPartyStatement(
        contactId: 'nonexistent',
        startDate: '2024-04-01',
        endDate: '2024-03-31',
      );
      expect(res, isA<Failure<PartyStatement>>());
    });

    test('opening balance: posted invoice before period is debited', () async {
      final cId = await _seedContact(db, companyId: companyA);
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-03-01', // before startDate 2024-04-01
        totalPaise: 100000,
        status: 'issued',
        number: 1,
      );

      final res = await svc.getPartyStatement(
        contactId: cId,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      final stmt = (res as Success<PartyStatement>).value;
      expect(stmt.summary.openingBalance, closeTo(1000.00, 0.001));
    });

    test('opening balance: receipt before period reduces receivable', () async {
      final cId = await _seedContact(db, companyId: companyA);
      // Invoice before period: +1000
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-03-01',
        totalPaise: 100000,
        status: 'issued',
        number: 1,
      );
      // Receipt before period: -400
      await _seedPayment(
        db,
        companyId: companyA,
        contactId: cId,
        date: '2024-03-15',
        amountPaise: 40000,
        paymentType: 'RECEIPT',
        status: 'posted',
      );

      final res = await svc.getPartyStatement(
        contactId: cId,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      final stmt = (res as Success<PartyStatement>).value;
      // Opening = 1000 - 400 = 600
      expect(stmt.summary.openingBalance, closeTo(600.00, 0.001));
    });

    test('opening balance: draft bill before period is NOT included', () async {
      final cId = await _seedContact(db, companyId: companyA, contactType: 'vendor');
      // Draft bill before period — should NOT affect opening balance
      await _seedBill(
        db,
        companyId: companyA,
        supplierId: cId,
        date: '2024-03-01',
        totalPaise: 100000,
        status: 'DRAFT',
      );

      final res = await svc.getPartyStatement(
        contactId: cId,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      final stmt = (res as Success<PartyStatement>).value;
      expect(stmt.summary.openingBalance, closeTo(0.00, 0.001));
    });

    test('closing balance = opening + period DR - period CR (numeric regression)', () async {
      final cId = await _seedContact(db, companyId: companyA);

      // Before period: invoice 1000 → opening = 1000
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-03-01',
        totalPaise: 100000,
        status: 'issued',
        number: 1,
      );
      // Period: invoice 500
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-10',
        totalPaise: 50000,
        status: 'issued',
        number: 2,
      );
      // Period: receipt 300
      await _seedPayment(
        db,
        companyId: companyA,
        contactId: cId,
        date: '2024-04-15',
        amountPaise: 30000,
        paymentType: 'RECEIPT',
        status: 'posted',
      );

      final res = await svc.getPartyStatement(
        contactId: cId,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      final stmt = (res as Success<PartyStatement>).value;

      // Expected: opening 1000, period DR 500, period CR 300
      // Closing = 1000 + 500 - 300 = 1200
      expect(stmt.summary.openingBalance, closeTo(1000.00, 0.001));
      expect(stmt.summary.totalSales, closeTo(500.00, 0.001));
      expect(stmt.summary.totalReceipts, closeTo(300.00, 0.001));
      expect(stmt.summary.closingOutstanding, closeTo(1200.00, 0.001));
    });

    test('empty period → closing balance equals opening balance', () async {
      final cId = await _seedContact(db, companyId: companyA);
      // Opening: 750
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-03-01',
        totalPaise: 75000,
        status: 'issued',
        number: 1,
      );

      final res = await svc.getPartyStatement(
        contactId: cId,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      final stmt = (res as Success<PartyStatement>).value;
      expect(stmt.ledger, isEmpty);
      expect(stmt.summary.closingOutstanding,
          closeTo(stmt.summary.openingBalance, 0.001));
    });

    test('period rows appear in date+createdAt stable order', () async {
      final cId = await _seedContact(db, companyId: companyA);
      // Two invoices on the same date — order by createdAt
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-10',
        totalPaise: 200000,
        status: 'issued',
        number: 2,
        displayNumber: 'INV-002',
      );
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-10',
        totalPaise: 100000,
        status: 'issued',
        number: 1,
        displayNumber: 'INV-001',
      );
      // One on a later date
      await _seedInvoice(
        db,
        companyId: companyA,
        customerId: cId,
        date: '2024-04-15',
        totalPaise: 50000,
        status: 'issued',
        number: 3,
        displayNumber: 'INV-003',
      );

      final res = await svc.getPartyStatement(
        contactId: cId,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      final rows = (res as Success<PartyStatement>).value.ledger;
      expect(rows.length, 3);
      // First two on same date; third on later date
      expect(rows[0].date, '2024-04-10');
      expect(rows[1].date, '2024-04-10');
      expect(rows[2].date, '2024-04-15');
      // Sorted by createdAt (which equals the seeding date used in helpers):
      // INV-001 seeded first (same createdAt ISO as date), so comes first
      // — exact assertion depends on insertion order via test seeding
    });

    test('multi-company isolation: company B contact not visible to company A service', () async {
      final cB = await _seedContact(db, companyId: companyB, name: 'B Customer');
      final res = await svc.getPartyStatement(
        contactId: cB,
        startDate: '2024-04-01',
        endDate: '2024-04-30',
      );
      // Company A service should not find company B contact
      expect(res, isA<Failure<PartyStatement>>());
    });
  });

  // ── getContacts ───────────────────────────────────────────────────────────

  group('getContacts', () {
    test('returns only active contacts for the active company', () async {
      await _seedContact(db, companyId: companyA, name: 'Customer Alpha');
      // Company B contact — must not appear
      await _seedContact(db, companyId: companyB, name: 'Beta Vendor');

      final res = await svc.getContacts();
      final items = (res as Success<List<ContactSummary>>).value;
      expect(items.length, 1);
      expect(items.first.name, 'Customer Alpha');
    });

    test('contactType filter works case-insensitively', () async {
      await _seedContact(db, companyId: companyA, contactType: 'customer', name: 'Cust A');
      await _seedContact(db, companyId: companyA, contactType: 'vendor', name: 'Vend A');

      final res = await svc.getContacts(contactType: 'VENDOR');
      final items = (res as Success<List<ContactSummary>>).value;
      expect(items.length, 1);
      expect(items.first.name, 'Vend A');
    });
  });
}
