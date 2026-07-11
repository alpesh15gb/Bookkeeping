// Tests for Ledger Engine — reads from posted journals.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/ledger/models/ledger_line.dart';
import 'package:apexbooks/features/accounting/ledger/models/ledger_report.dart';

void main() {
  group('LedgerLine', () {
    test('fromJson', () {
      final line = LedgerLine.fromJson({
        'entry_date': '2025-07-01',
        'reference_number': 'REF-001',
        'description': 'Test entry',
        'debit_amount': '500.00',
        'credit_amount': '0',
        'running_balance': '500.00',
      });
      expect(line.entryDate, '2025-07-01');
      expect(line.debitAmount, 500);
      expect(line.creditAmount, 0);
      expect(line.runningBalance, 500);
    });
  });

  group('LedgerReport', () {
    test('fromJson', () {
      final report = LedgerReport.fromJson({
        'account_id': 'acct1',
        'account_name': 'Cash',
        'account_code': '10001',
        'opening_balance': '0',
        'closing_balance': '1000',
        'total_lines': 2,
        'lines': [
          {
            'entry_date': '2025-07-01',
            'reference_number': 'REF-001',
            'description': 'Test',
            'debit_amount': '500',
            'credit_amount': '0',
            'running_balance': '500',
          },
          {
            'entry_date': '2025-07-02',
            'reference_number': 'REF-002',
            'description': 'Test 2',
            'debit_amount': '500',
            'credit_amount': '0',
            'running_balance': '1000',
          },
        ],
      });
      expect(report.accountName, 'Cash');
      expect(report.lines.length, 2);
      expect(report.totalDebits, 1000);
      expect(report.closingBalance, 1000);
    });
  });
}
