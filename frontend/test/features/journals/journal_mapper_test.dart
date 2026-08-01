/// Tests for the journal mapper — particularly the amount encoding
/// contract between local paise and backend micros.
library;

import 'dart:convert';

import 'package:apexbooks/core/utils/money.dart';
import 'package:apexbooks/features/accounting/journal/models/direction.dart';
import 'package:apexbooks/features/accounting/journal/models/journal_line.dart';
import 'package:apexbooks/features/journals/data/mappers/journal_mapper.dart';
import 'package:apexbooks/features/journals/domain/commands/journal_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JournalMapper.toCreatePayloadJson', () {
    const cmd = CreateJournalCommand(
      companyId: 'company-uuid',
      entryDate: '2026-07-27',
      description: 'Test journal',
      referenceNumber: '',
      lines: [
        JournalLine(
          accountId: 'acc-debit',
          accountCode: '1001',
          accountName: 'Cash',
          direction: Direction.debit,
          amount: 1800.0, // ₹1,800.00
        ),
        JournalLine(
          accountId: 'acc-credit',
          accountCode: '4001',
          accountName: 'Revenue',
          direction: Direction.credit,
          amount: 1800.0,
        ),
      ],
    );

    late Map<String, dynamic> payload;

    setUp(() {
      final json = JournalMapper.toCreatePayloadJson(
        cmd,
        'local-id-123',
        'device-uuid',
        DateTime.utc(2026, 7, 27, 10, 0, 0),
        'company-uuid',
      );
      final event = jsonDecode(json) as Map<String, dynamic>;
      payload = event['payload'] as Map<String, dynamic>;
    });

    test('event type is journal.posted', () {
      final json = JournalMapper.toCreatePayloadJson(
        cmd,
        'local-id-123',
        'device-uuid',
        DateTime.utc(2026, 7, 27, 10, 0, 0),
        'company-uuid',
      );
      final event = jsonDecode(json) as Map<String, dynamic>;
      expect(event['event_type'], 'journal.posted');
    });

    test('aggregate_id equals the localId', () {
      final json = JournalMapper.toCreatePayloadJson(
        cmd,
        'local-id-123',
        'device-uuid',
        DateTime.utc(2026, 7, 27),
        'company-uuid',
      );
      final event = jsonDecode(json) as Map<String, dynamic>;
      expect(event['aggregate_id'], 'local-id-123');
    });

    test('entry_date is included in payload', () {
      expect(payload['entry_date'], '2026-07-27');
    });

    test('AMOUNT ENCODING CONTRACT: ₹1,800 = 18,000,000 backend micros', () {
      // ₹1,800 in paise = 180,000
      // backend micros = paise × 100 = 18,000,000
      // (because 10,000 backend-micros = ₹1 → 180,000 paise × 100 = 18,000,000)
      final lines = payload['lines'] as List;
      expect(lines.length, 2);

      final debit =
          lines.firstWhere((l) => (l as Map)['direction'] == 'DEBIT') as Map;
      final credit =
          lines.firstWhere((l) => (l as Map)['direction'] == 'CREDIT') as Map;

      // The contract: paise × 100 = backend micros
      final expectedMicros = Money.fromRupees(1800).toBackendMicros();
      expect(debit['debit_micros'], expectedMicros);
      expect(credit['credit_micros'], expectedMicros);
      expect(debit.containsKey('credit_micros'), false);
      expect(credit.containsKey('debit_micros'), false);
    });

    test('lines contain account_id and direction', () {
      final lines = payload['lines'] as List;
      for (final line in lines) {
        final l = line as Map;
        expect(l.containsKey('account_id'), true);
        expect(l.containsKey('direction'), true);
        expect(
          l.containsKey('debit_micros') || l.containsKey('credit_micros'),
          true,
        );
      }
    });
  });
}
