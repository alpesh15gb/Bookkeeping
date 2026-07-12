// Tests for Bank Reconciliation — statement import, matching, undo.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/reconciliation/models/reconciliation_models.dart';

void main() {
  group('BankTransaction', () {
    test('fromJson', () {
      final txn = BankTransaction.fromJson({
        'id': 'txn1',
        'transaction_date': '2025-07-01',
        'description': 'Payment received',
        'reference_number': 'CHQ-001',
        'debit_amount': '0',
        'credit_amount': '50000',
        'balance': '50000',
        'is_reconciled': false,
      });
      expect(txn.description, 'Payment received');
      expect(txn.creditAmount, 50000);
      expect(txn.isReconciled, false);
    });
  });

  group('ReconciliationMatch', () {
    test('fromJson', () {
      final m = ReconciliationMatch.fromJson({
        'bank_transaction_id': 'txn1',
        'journal_entry_id': 'je1',
        'matched_amount': '50000',
      });
      expect(m.bankTransactionId, 'txn1');
      expect(m.matchedAmount, 50000);
    });
  });

  group('BankReconciliation', () {
    test('isBalanced when diff is zero', () {
      final rec = BankReconciliation(
        id: 'rec1',
        closingBalance: 1000,
        statementBalance: 1000,
        difference: 0,
        status: 'COMPLETED',
      );
      expect(rec.isBalanced, true);
    });

    test('fromJson', () {
      final rec = BankReconciliation.fromJson({
        'id': 'rec1',
        'banking_profile_id': 'bp1',
        'banking_profile_name': 'HDFC Current',
        'statement_date': '2025-07-31',
        'closing_balance': '100000',
        'statement_balance': '99500',
        'difference': '-500',
        'status': 'DIFFERENCE',
        'transactions': [
          {
            'id': 'txn1',
            'transaction_date': '2025-07-01',
            'description': 'Payment',
            'credit_amount': '50000',
            'balance': '50000',
            'is_reconciled': true,
          },
        ],
        'matches': [
          {
            'bank_transaction_id': 'txn1',
            'journal_entry_id': 'je1',
            'matched_amount': '50000',
          },
        ],
      });
      expect(rec.bankingProfileName, 'HDFC Current');
      expect(rec.isBalanced, false);
      expect(rec.transactions.length, 1);
      expect(rec.matches.length, 1);
    });
  });

  group('BankReconciliationListItem', () {
    test('fromJson', () {
      final item = BankReconciliationListItem.fromJson({
        'id': 'rec1',
        'banking_profile_name': 'HDFC Current',
        'statement_date': '2025-07-31',
        'closing_balance': '100000',
        'difference': '0',
        'status': 'COMPLETED',
      });
      expect(item.status, 'COMPLETED');
      expect(item.difference, 0);
    });
  });
}
