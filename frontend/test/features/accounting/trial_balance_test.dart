// Tests for Trial Balance — must always balance.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/trial_balance/models/trial_balance.dart';

void main() {
  group('TrialBalanceReport', () {
    test('isBalanced when totals match', () {
      final tb = TrialBalanceReport(
        totalOpeningDebits: 1000,
        totalOpeningCredits: 1000,
        totalDebits: 5000,
        totalCredits: 5000,
        totalClosingDebits: 6000,
        totalClosingCredits: 6000,
      );
      expect(tb.isBalanced, true);
    });

    test('isBalanced false when debits != credits', () {
      final tb = TrialBalanceReport(
        totalOpeningDebits: 1000,
        totalOpeningCredits: 1000,
        totalDebits: 5000,
        totalCredits: 4900,
        totalClosingDebits: 6000,
        totalClosingCredits: 5900,
      );
      expect(tb.isBalanced, false);
    });

    test('fromJson', () {
      final tb = TrialBalanceReport.fromJson({
        'total_opening_debits': '1000',
        'total_opening_credits': '1000',
        'total_debits': '5000',
        'total_credits': '5000',
        'total_closing_debits': '6000',
        'total_closing_credits': '6000',
        'lines': [
          {
            'account_id': 'a1',
            'account_name': 'Cash',
            'account_code': '10001',
            'account_type': 'Asset',
            'opening_balance': '0',
            'total_debits': '5000',
            'total_credits': '0',
            'closing_balance': '5000',
          },
        ],
      });
      expect(tb.totalDebits, 5000);
      expect(tb.lines.length, 1);
      expect(tb.lines[0].accountName, 'Cash');
      expect(tb.isBalanced, true);
    });
  });
}
