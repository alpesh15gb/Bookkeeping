// Tests for Journal Engine — balanced entries, state, reversal.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/journal/models/direction.dart';
import 'package:apexbooks/features/accounting/journal/models/journal_line.dart';
import 'package:apexbooks/features/accounting/journal/models/journal_entry.dart';
import 'package:apexbooks/features/accounting/journal/services/journal_validation_service.dart';

void main() {
  const valSvc = JournalValidationService();

  group('Direction', () {
    test('fromString', () {
      expect(Direction.fromString('DEBIT'), Direction.debit);
      expect(Direction.fromString('CREDIT'), Direction.credit);
      expect(Direction.fromString('X'), Direction.debit);
    });
    test('isDebit / isCredit', () {
      expect(Direction.debit.isDebit, true);
      expect(Direction.credit.isCredit, true);
    });
  });

  group('JournalLine', () {
    test('toCreatePayload', () {
      final line = JournalLine(
        accountId: 'acct1',
        amount: 1000,
        direction: Direction.debit,
      );
      final p = line.toCreatePayload();
      expect(p['account_id'], 'acct1');
      expect(p['amount'], 1000);
      expect(p['direction'], 'DEBIT');
    });
    test('isValid', () {
      const valid = JournalLine(
        accountId: 'a1',
        amount: 100,
        direction: Direction.debit,
      );
      const invalid = JournalLine();
      expect(valid.isValid, true);
      expect(invalid.isValid, false);
    });
    test('fromJson', () {
      final line = JournalLine.fromJson({
        'id': 'l1',
        'account_id': 'acct1',
        'account_name': 'Cash',
        'account_code': '10001',
        'amount': '500.00',
        'direction': 'DEBIT',
      });
      expect(line.accountName, 'Cash');
      expect(line.amount, 500);
      expect(line.direction, Direction.debit);
    });
  });

  group('JournalEntry totals', () {
    test('totalDebit and totalCredit balanced', () {
      final entry = JournalEntry(
        id: 'je1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(
            accountId: 'a1',
            amount: 1000,
            direction: Direction.debit,
          ),
          JournalLine(
            accountId: 'a2',
            amount: 1000,
            direction: Direction.credit,
          ),
        ],
      );
      expect(entry.totalDebit, 1000);
      expect(entry.totalCredit, 1000);
      expect(entry.isBalanced, true);
    });

    test('isBalanced false when unbalanced', () {
      final entry = JournalEntry(
        id: 'je1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(
            accountId: 'a1',
            amount: 1000,
            direction: Direction.debit,
          ),
          JournalLine(
            accountId: 'a2',
            amount: 500,
            direction: Direction.credit,
          ),
        ],
      );
      expect(entry.isBalanced, false);
    });

    test('toCreatePayload', () {
      final entry = JournalEntry(
        id: 'je1',
        entryDate: '2025-07-01',
        description: 'Test entry',
        referenceNumber: 'REF-001',
        lines: [
          JournalLine(accountId: 'a1', amount: 500, direction: Direction.debit),
          JournalLine(
            accountId: 'a2',
            amount: 500,
            direction: Direction.credit,
          ),
        ],
      );
      final p = entry.toCreatePayload();
      expect(p['entry_date'], '2025-07-01');
      expect(p['reference_number'], 'REF-001');
      expect((p['lines'] as List).length, 2);
    });

    test('fromJson', () {
      final entry = JournalEntry.fromJson({
        'id': 'je1',
        'tenant_id': 't1',
        'entry_date': '2025-07-01',
        'reference_number': 'REF-001',
        'description': 'Test',
        'source_type': 'MANUAL',
        'lines': [
          {
            'id': 'l1',
            'account_id': 'a1',
            'account_name': 'Cash',
            'account_code': '10001',
            'amount': '1000',
            'direction': 'DEBIT',
          },
          {
            'id': 'l2',
            'account_id': 'a2',
            'account_name': 'Bank',
            'account_code': '10002',
            'amount': '1000',
            'direction': 'CREDIT',
          },
        ],
      });
      expect(entry.id, 'je1');
      expect(entry.sourceType, 'MANUAL');
      expect(entry.lines.length, 2);
      expect(entry.isBalanced, true);
    });
  });

  group('validateForCreate', () {
    test('valid balanced entry passes', () {
      final entry = JournalEntry(
        id: 'j1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(accountId: 'a1', amount: 500, direction: Direction.debit),
          JournalLine(
            accountId: 'a2',
            amount: 500,
            direction: Direction.credit,
          ),
        ],
      );
      expect(valSvc.validateForCreate(entry), isNull);
    });

    test('missing date rejected', () {
      final entry = JournalEntry(
        id: 'j1',
        description: 'Test',
        lines: [
          JournalLine(accountId: 'a1', amount: 500, direction: Direction.debit),
          JournalLine(
            accountId: 'a2',
            amount: 500,
            direction: Direction.credit,
          ),
        ],
      );
      expect(valSvc.validateForCreate(entry), contains('date'));
    });

    test('unbalanced entry rejected', () {
      final entry = JournalEntry(
        id: 'j1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(accountId: 'a1', amount: 500, direction: Direction.debit),
          JournalLine(
            accountId: 'a2',
            amount: 400,
            direction: Direction.credit,
          ),
        ],
      );
      expect(valSvc.validateForCreate(entry), contains('not balanced'));
    });

    test('single line rejected', () {
      final entry = JournalEntry(
        id: 'j1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(accountId: 'a1', amount: 500, direction: Direction.debit),
        ],
      );
      expect(valSvc.validateForCreate(entry), contains('at least 2'));
    });

    test('missing debit rejected', () {
      final entry = JournalEntry(
        id: 'j1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(
            accountId: 'a1',
            amount: 500,
            direction: Direction.credit,
          ),
          JournalLine(
            accountId: 'a2',
            amount: 500,
            direction: Direction.credit,
          ),
        ],
      );
      expect(valSvc.validateForCreate(entry), contains('debit'));
    });

    test('zero amount rejected', () {
      final entry = JournalEntry(
        id: 'j1',
        entryDate: '2025-07-01',
        description: 'Test',
        lines: [
          JournalLine(accountId: 'a1', amount: 0, direction: Direction.debit),
          JournalLine(accountId: 'a2', amount: 0, direction: Direction.credit),
        ],
      );
      expect(valSvc.validateForCreate(entry), contains('greater than zero'));
    });
  });

  group('validateReversal', () {
    test('manual entries can be reversed', () {
      final entry = JournalEntry(
        id: 'j1',
        sourceType: 'MANUAL',
        entryDate: '2025-07-01',
        description: 'Test',
      );
      expect(valSvc.validateReversal(entry), isNull);
    });
    test('auto entries cannot be reversed', () {
      final entry = JournalEntry(
        id: 'j1',
        sourceType: 'INVOICE',
        entryDate: '2025-07-01',
        description: 'Test',
      );
      expect(valSvc.validateReversal(entry), contains('manual'));
    });
  });
}
