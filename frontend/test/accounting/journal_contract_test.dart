/// Contract verification tests for journal entry models.
///
/// Fixtures derived from:
///   backend/src/schemas/accounting_schemas.py — JournalEntryResponse,
///     JournalLineResponse, TrialBalanceResponse, ProfitLossResponse,
///     BalanceSheetResponse
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/journal/models/direction.dart';
import 'package:apexbooks/features/accounting/journal/models/journal_entry.dart';
import 'package:apexbooks/features/accounting/journal/models/journal_line.dart';

/// Fixture: backend GET /journal-entries response (list)
///
/// Based on JournalEntryResponse (accounting_schemas.py lines 34–44):
///   id, tenant_id, entry_date, reference_number, description, source_type,
///   source_id?, created_at, updated_at, lines[]
///
/// JournalLineResponse (lines 25–32):
///   id, account_id, account_name, account_code, amount, direction, narration?
final kJournalEntryPayload = {
  'id': 'je-a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'tenant_id': 't1a2b3c4-d5e6-7890-abcd-ef1234567890',
  'entry_date': '2026-07-15',
  'reference_number': 'JE-2026-001',
  'description': 'Monthly rent payment recorded',
  'source_type': 'MANUAL',
  'source_id': null,
  'created_at': '2026-07-15T14:30:00Z',
  'updated_at': '2026-07-15T14:30:00Z',
  'lines': [
    {
      'id': 'jl-b1c2d3e4-f5a6-7890-bcde-f12345678901',
      'account_id': 'ac-001-rent-expense',
      'account_name': 'Rent Expenses',
      'account_code': '50001',
      'amount': '50000.0000',
      'direction': 'DEBIT',
      'narration': 'July office rent',
    },
    {
      'id': 'jl-c2d3e4f5-a6b7-8901-cdef-123456789012',
      'account_id': 'ac-002-bank',
      'account_name': 'HDFC Current Account',
      'account_code': '10001',
      'amount': '50000.0000',
      'direction': 'CREDIT',
      'narration': null,
    },
  ],
};

/// Fixture: backend GET /trial-balance response
///
/// Based on TrialBalanceResponse (accounting_schemas.py lines 76–83):
///   lines[], total_opening_debits, total_opening_credits, total_debits,
///   total_credits, total_closing_debits, total_closing_credits
final kTrialBalancePayload = {
  'lines': [
    {
      'account_id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      'account_name': 'Cash in Hand',
      'account_code': '10001',
      'account_type': 'ASSET',
      'opening_balance': '100000.0000',
      'total_debits': '50000.0000',
      'total_credits': '30000.0000',
      'closing_balance': '120000.0000',
    },
    {
      'account_id': 'b2c3d4e5-f6a7-8901-bcde-f12345678901',
      'account_name': 'Sales Revenue',
      'account_code': '40001',
      'account_type': 'REVENUE',
      'opening_balance': '0.0000',
      'total_debits': '0.0000',
      'total_credits': '200000.0000',
      'closing_balance': '200000.0000',
    },
  ],
  'total_opening_debits': '100000.0000',
  'total_opening_credits': '0.0000',
  'total_debits': '50000.0000',
  'total_credits': '230000.0000',
  'total_closing_debits': '120000.0000',
  'total_closing_credits': '200000.0000',
};

void main() {
  group('JournalEntry — contract', () {
    test('parses full journal entry from backend', () {
      final entry = JournalEntry.fromJson(kJournalEntryPayload);

      expect(entry.id, 'je-a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(entry.entryDate, '2026-07-15');
      expect(entry.description, 'Monthly rent payment recorded');
      expect(entry.sourceType, 'MANUAL');
      expect(entry.lines.length, 2);
    });

    test('parses debit/credit directions correctly', () {
      final entry = JournalEntry.fromJson(kJournalEntryPayload);

      expect(entry.lines[0].direction, Direction.debit);
      expect(entry.lines[1].direction, Direction.credit);
    });

    test('parses amount as Decimal string', () {
      final entry = JournalEntry.fromJson(kJournalEntryPayload);

      expect(entry.lines[0].amount, 50000.0);
      expect(entry.lines[1].amount, 50000.0);
    });

    test('computes totalDebit and totalCredit', () {
      final entry = JournalEntry.fromJson(kJournalEntryPayload);

      expect(entry.totalDebit, 50000.0);
      expect(entry.totalCredit, 50000.0);
      expect(entry.isBalanced, isTrue);
    });

    test('handles null narration', () {
      final entry = JournalEntry.fromJson(kJournalEntryPayload);

      expect(entry.lines[0].narration, 'July office rent');
      expect(entry.lines[1].narration, isNull);
    });

    test('handles null source_id', () {
      final entry = JournalEntry.fromJson(kJournalEntryPayload);

      expect(entry.sourceId, isNull);
    });

    test('handles empty lines list', () {
      final payload = Map<String, dynamic>.from(kJournalEntryPayload);
      payload['lines'] = [];

      final entry = JournalEntry.fromJson(payload);

      expect(entry.lines, isEmpty);
      expect(entry.totalDebit, 0);
      expect(entry.totalCredit, 0);
    });

    test('tolerates unknown extra fields', () {
      final payload = Map<String, dynamic>.from(kJournalEntryPayload);
      payload['extra_field'] = 'should not crash';

      expect(() => JournalEntry.fromJson(payload), returnsNormally);
    });

    test('toCreatePayload produces correct API shape', () {
      const line = JournalLine(
        accountId: 'ac-001-rent-expense',
        amount: 50000.0,
        direction: Direction.debit,
        narration: 'July office rent',
      );

      final payload = line.toCreatePayload();

      expect(payload['account_id'], 'ac-001-rent-expense');
      expect(payload['amount'], 50000.0);
      expect(payload['direction'], 'DEBIT');
      expect(payload['narration'], 'July office rent');
    });
  });

  group('JournalLine — contract', () {
    test('copyWith preserves unset fields', () {
      const line = JournalLine(accountId: 'ac-001', amount: 100.0);

      final modified = line.copyWith(amount: 200.0);

      expect(modified.accountId, 'ac-001');
      expect(modified.amount, 200.0);
      expect(modified.direction, Direction.debit); // unchanged default
    });

    test('isValid requires accountId and positive amount', () {
      expect(const JournalLine().isValid, isFalse);
      expect(const JournalLine(accountId: 'ac-001').isValid, isFalse);
      expect(
        const JournalLine(accountId: 'ac-001', amount: 100).isValid,
        isTrue,
      );
    });
  });

  group('Direction — contract', () {
    test('fromString parses backend values', () {
      expect(Direction.fromString('DEBIT'), Direction.debit);
      expect(Direction.fromString('CREDIT'), Direction.credit);
    });

    test('fromString falls back to debit for unknown values', () {
      expect(Direction.fromString('UNKNOWN'), Direction.debit);
      expect(Direction.fromString(''), Direction.debit);
    });

    test('wire values match backend expectations', () {
      expect(Direction.debit.value, 'DEBIT');
      expect(Direction.credit.value, 'CREDIT');
    });
  });
}
