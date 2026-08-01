/// Contract verification tests for expense models.
///
/// Fixtures derived from:
///   backend/src/schemas/expense_schemas.py — ExpenseResponse,
///     ExpenseListResponse
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/expenses/services/expense_service.dart';

/// Fixture: backend GET /expenses response (list item)
///
/// Based on ExpenseListResponse (expense_schemas.py lines 58–70):
///   id, expense_number, expense_date, vendor_name?, description?, amount,
///   total, status, notes?, reference_number?, category_name?, created_at
///
/// The full ExpenseResponse also includes:
///   gst_rate, cgst_amount, sgst_amount, igst_amount, round_off, etc.
final kExpenseListPayload = {
  'id': 'exp-a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'expense_number': 'EXP-2026-001',
  'expense_date': '2026-07-10',
  'vendor_name': 'Mumbai Property Solutions',
  'description': 'Office rent for July 2026',
  'amount': '50000.0000',
  'total': '59000.0000',
  'status': 'POSTED',
  'category_name': 'Rent & Utilities',
  'reference_number': 'RENT-JUL-2026',
  'created_at': '2026-07-10T09:00:00Z',
};

/// Fixture: a minimal expense (no optional fields)
final kExpenseMinimalPayload = {
  'id': 'exp-b2c3d4e5-f6a7-8901-bcde-f12345678901',
  'expense_number': 'EXP-2026-002',
  'expense_date': '2026-07-11',
  'amount': '1500.0000',
  'total': '1500.0000',
  'status': 'DRAFT',
};

void main() {
  group('ExpenseRecord — contract', () {
    test('parses full expense list response from backend', () {
      final expense = ExpenseRecord.fromJson(kExpenseListPayload);

      expect(expense.id, 'exp-a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(expense.number, 'EXP-2026-001');
      expect(expense.date, '2026-07-10');
      expect(expense.amount, 50000.0);
      expect(expense.total, 59000.0);
      expect(expense.status, 'POSTED');
      expect(expense.category, 'Rent & Utilities');
      expect(expense.vendor, 'Mumbai Property Solutions');
      expect(expense.description, 'Office rent for July 2026');
    });

    test('parses amount and total as doubles from Decimal strings', () {
      final expense = ExpenseRecord.fromJson(kExpenseListPayload);

      // Backend sends Numeric(15,4) as string — frontend must parse to double
      expect(expense.amount, isA<double>());
      expect(expense.total, isA<double>());
      expect(expense.amount, 50000.0);
      expect(expense.total, 59000.0);
    });

    test('handles null optional fields', () {
      final expense = ExpenseRecord.fromJson(kExpenseMinimalPayload);

      expect(expense.category, isNull);
      expect(expense.vendor, isNull);
      expect(expense.description, isNull);
    });

    test(
      'handles amount as integer (backend may send 0 instead of "0.0000")',
      () {
        final payload = Map<String, dynamic>.from(kExpenseListPayload);
        payload['amount'] = 0;

        final expense = ExpenseRecord.fromJson(payload);

        expect(expense.amount, 0);
      },
    );

    test('handles amount as string with Indian comma formatting', () {
      final payload = Map<String, dynamic>.from(kExpenseListPayload);
      payload['amount'] = '1,50,000.0000';

      final expense = ExpenseRecord.fromJson(payload);

      // _amount() now strips commas before parsing.
      expect(expense.amount, 150000.0);
    });

    test('handles total as Decimal-as-string', () {
      final payload = Map<String, dynamic>.from(kExpenseListPayload);
      payload['total'] = '59000.0000';

      final expense = ExpenseRecord.fromJson(payload);

      expect(expense.total, 59000.0);
    });

    test('handles null amount', () {
      final payload = Map<String, dynamic>.from(kExpenseListPayload);
      payload['amount'] = null;

      final expense = ExpenseRecord.fromJson(payload);

      expect(expense.amount, 0);
    });

    test('handles amount as raw int (not string)', () {
      final payload = Map<String, dynamic>.from(kExpenseListPayload);
      payload['amount'] = 75000;

      final expense = ExpenseRecord.fromJson(payload);

      expect(expense.amount, 75000.0);
    });

    test('handles empty expense number gracefully', () {
      final payload = Map<String, dynamic>.from(kExpenseMinimalPayload);
      payload['expense_number'] = '';

      final expense = ExpenseRecord.fromJson(payload);

      expect(expense.number, isEmpty);
    });

    test('tolerates unknown extra fields', () {
      final payload = Map<String, dynamic>.from(kExpenseListPayload);
      payload['unknown_field'] = 'should not crash';

      expect(() => ExpenseRecord.fromJson(payload), returnsNormally);
    });
  });
}
