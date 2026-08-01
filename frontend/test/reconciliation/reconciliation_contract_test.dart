/// Contract verification tests for reconciliation models.
///
/// Fixtures are derived from the backend response schemas in:
///   backend/src/schemas/bill_schemas.py
///   backend/src/api/v1/bank_reconciliation.py
///
/// Each test uses JSON shaped exactly as the backend sends it, NOT as the
/// frontend wishes to receive it.  These tests catch field-name, type, and
/// nullability mismatches before they reach a user.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/reconciliation/models/reconciliation_models.dart';

/// Fixture: backend GET /bank-reconciliation/reconciliations/{id} response
///
/// Derived from BankReconciliationResponse + BankTransactionResponse schemas:
///   BankTransactionResponse:
///     id, transaction_date, amount (signed Decimal), description?,
///     reference_number?, status, created_at, updated_at
///   BankReconciliationResponse:
///     id, bank_transaction_id, amount, notes?, created_at, updated_at
///
/// NOTE: The backend sends `amount` as a *single signed Decimal* (positive =
/// credit/deposit, negative = debit/withdrawal), NOT separate debit_amount/
/// credit_amount fields.  The frontend model must handle this.
final kReconciliationPayload = {
  'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
  'banking_profile_id': 'b1c2d3e4-f5a6-7890-bcde-f12345678901',
  'banking_profile_name': 'HDFC Current Account',
  'statement_date': '2026-07-01',
  'closing_balance': '1250000.0000',
  'statement_balance': '1250000.0000',
  'difference': '0.0000',
  'status': 'IN_PROGRESS',
  'transactions': [
    {
      'id': 't1a2b3c4-d5e6-7890-abcd-ef1234567890',
      'transaction_date': '2026-07-05',
      'amount': '150000.0000', // ← signed Decimal as string (credit)
      'description': 'UPI-PAYTM-SALE-JUL',
      'reference_number': 'UPI-REF-001',
      'status': 'PENDING',
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    },
    {
      'id': 't2a3b4c5-d6e7-8901-abcd-ef1234567890',
      'transaction_date': '2026-07-06',
      'amount': '-25000.0000', // ← negative = debit (withdrawal)
      'description': 'RENT-PAYMENT',
      'reference_number': 'CHQ-0042',
      'status': 'PENDING',
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    },
    {
      'id': 't3a4b5c6-d7e8-9012-abcd-ef1234567890',
      'transaction_date': '2026-07-07',
      'amount': '0.0000', // ← zero amount edge case
      'description': null,
      'reference_number': null,
      'status': 'PENDING',
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    },
  ],
  'matches': [],
  'created_at': '2026-07-01T10:00:00Z',
};

/// Fixture: backend GET /bank-reconciliation/statements/{id}/suggestions
///
/// Derived from the MatchSuggestion pydantic model + candidate dicts in
/// bank_reconciliation.py lines 850–892.
final kSuggestionsPayload = [
  {
    'transaction_id': 't1a2b3c4-d5e6-7890-abcd-ef1234567890',
    'transaction_date': '2026-07-05',
    'transaction_amount': '150000.0000',
    'transaction_description': 'UPI-PAYTM-SALE-JUL',
    'suggested_matches': [
      {
        'type': 'payment',
        'id': 'p1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'amount': '150000.0000',
        'date': '2026-07-05',
        'reference': 'INV-2026-001',
        'score': 95,
      },
    ],
  },
  {
    'transaction_id': 't2a3b4c5-d6e7-8901-abcd-ef1234567890',
    'transaction_date': '2026-07-06',
    'transaction_amount': '-25000.0000',
    'transaction_description': 'RENT-PAYMENT',
    'suggested_matches': [
      {
        'type': 'bill_payment',
        'id': 'bp1c2d3e4-f5a6-7890-bcde-f12345678901',
        'amount': '25000.0000',
        'date': '2026-07-06',
        'reference': 'BILL-2026-042',
        'score': 88,
      },
      {
        'type': 'bill_payment',
        'id': 'bp2c3d4e5-f6a7-8901-cdef-123456789012',
        'amount': '25000.0000',
        'date': '2026-07-04',
        'reference': 'BILL-2026-041',
        'score': 45, // ← low confidence
      },
    ],
  },
  {
    'transaction_id': 't3a4b5c6-d7e8-9012-abcd-ef1234567890',
    'transaction_date': '2026-07-07',
    'transaction_amount': '0.0000',
    'transaction_description': null,
    'suggested_matches': [], // ← empty suggestions
  },
];

void main() {
  group('BankReconciliation — contract', () {
    test('parses full reconciliation payload from backend', () {
      final rec = BankReconciliation.fromJson(kReconciliationPayload);

      expect(rec.id, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(rec.bankingProfileName, 'HDFC Current Account');
      expect(rec.statementDate, '2026-07-01');
      expect(rec.status, 'IN_PROGRESS');
      expect(rec.transactions.length, 3);
      expect(rec.matches.length, 0);
      expect(rec.isBalanced, isTrue); // difference = 0
    });

    test('parses bank transaction with signed amount field', () {
      // Backend sends `amount` as signed Decimal string —
      // positive = credit, negative = debit
      final rec = BankReconciliation.fromJson(kReconciliationPayload);
      final creditTxn = rec.transactions[0];
      final debitTxn = rec.transactions[1];

      // Frontend model should derive debitAmount/creditAmount from signed amount
      expect(creditTxn.creditAmount, greaterThan(0));
      expect(creditTxn.debitAmount, 0);

      expect(debitTxn.debitAmount, greaterThan(0));
      expect(debitTxn.creditAmount, 0);
    });

    test('handles null description and reference fields', () {
      final rec = BankReconciliation.fromJson(kReconciliationPayload);
      final nullTxn = rec.transactions[2];

      expect(nullTxn.description, isEmpty);
      expect(nullTxn.referenceNumber, isEmpty);
    });

    test('handles zero-amount transaction', () {
      final rec = BankReconciliation.fromJson(kReconciliationPayload);
      final zeroTxn = rec.transactions[2];

      expect(zeroTxn.debitAmount, 0);
      expect(zeroTxn.creditAmount, 0);
    });

    test('parses signed amount correctly: positive → credit', () {
      // Backend convention: positive amount = credit (deposit)
      final txn = BankTransaction.fromJson({
        'id': 'test-1',
        'transaction_date': '2026-07-01',
        'amount': '150000.0000',
      });

      expect(txn.creditAmount, 150000.0);
      expect(txn.debitAmount, 0);
    });

    test('parses signed amount correctly: negative → debit', () {
      // Backend convention: negative amount = debit (withdrawal)
      final txn = BankTransaction.fromJson({
        'id': 'test-2',
        'transaction_date': '2026-07-01',
        'amount': '-25000.0000',
      });

      expect(txn.debitAmount, 25000.0);
      expect(txn.creditAmount, 0);
    });

    test(
      'falls back to legacy debit_amount/credit_amount when amount absent',
      () {
        final txn = BankTransaction.fromJson({
          'id': 'test-3',
          'transaction_date': '2026-07-01',
          'debit_amount': '5000.0000',
          'credit_amount': '10000.0000',
        });

        expect(txn.debitAmount, 5000.0);
        expect(txn.creditAmount, 10000.0);
      },
    );

    test('handles Indian comma formatting in amount', () {
      final txn = BankTransaction.fromJson({
        'id': 'test-4',
        'transaction_date': '2026-07-01',
        'amount': '1,50,000.0000',
      });

      expect(txn.creditAmount, 150000.0);
    });

    test('handles null amount field', () {
      final txn = BankTransaction.fromJson({
        'id': 'test-5',
        'transaction_date': '2026-07-01',
        'amount': null,
      });

      expect(txn.debitAmount, 0);
      expect(txn.creditAmount, 0);
    });

    test('handles amount as raw int (backend may short-form)', () {
      final txn = BankTransaction.fromJson({
        'id': 'test-6',
        'transaction_date': '2026-07-01',
        'amount': 150000,
      });

      expect(txn.creditAmount, 150000.0);
      expect(txn.debitAmount, 0);
    });

    test('handles malformed amount string without crashing', () {
      final txn = BankTransaction.fromJson({
        'id': 'test-7',
        'transaction_date': '2026-07-01',
        'amount': 'not-a-number',
      });

      expect(txn.debitAmount, 0);
      expect(txn.creditAmount, 0);
    });

    test('empty transactions list does not crash', () {
      final payload = Map<String, dynamic>.from(kReconciliationPayload);
      payload['transactions'] = [];

      final rec = BankReconciliation.fromJson(payload);

      expect(rec.transactions, isEmpty);
      expect(rec.matches, isEmpty);
    });

    test('handles missing optional fields gracefully', () {
      final minimal = {
        'id': 'minimal-id',
        'banking_profile_id': '',
        'statement_date': '',
        'closing_balance': 0,
        'statement_balance': 0,
        'difference': 0,
        'status': '',
      };

      final rec = BankReconciliation.fromJson(minimal);

      expect(rec.id, 'minimal-id');
      expect(rec.transactions, isEmpty);
      expect(rec.matches, isEmpty);
    });

    test('tolerates unknown extra fields without throwing', () {
      final payload = Map<String, dynamic>.from(kReconciliationPayload);
      payload['unknown_field'] = 'should not crash';
      payload['nested_extra'] = {'a': 1};

      expect(() => BankReconciliation.fromJson(payload), returnsNormally);
    });
  });

  group('MatchSuggestion — contract', () {
    test('parses suggestions payload from backend', () {
      final suggestions = kSuggestionsPayload
          .map((e) => MatchSuggestion.fromJson(e))
          .toList();

      expect(suggestions.length, 3);

      // First transaction has 1 suggestion with high confidence
      expect(
        suggestions[0].transactionId,
        't1a2b3c4-d5e6-7890-abcd-ef1234567890',
      );
      expect(suggestions[0].suggestedMatches.length, 1);
      expect(suggestions[0].suggestedMatches[0].score, 95);
      expect(suggestions[0].suggestedMatches[0].confidenceLabel, 'High');
      expect(suggestions[0].suggestedMatches[0].type, 'payment');

      // Second transaction has 2 suggestions (one low confidence)
      expect(suggestions[1].suggestedMatches.length, 2);
      expect(suggestions[1].suggestedMatches[0].score, 88);
      expect(suggestions[1].suggestedMatches[0].confidenceLabel, 'Good');
      expect(suggestions[1].suggestedMatches[1].score, 45);
      expect(suggestions[1].suggestedMatches[1].confidenceLabel, 'Low');

      // Third transaction has empty suggestions
      expect(suggestions[2].suggestedMatches, isEmpty);
    });

    test('handles null description in suggestion', () {
      final sug = MatchSuggestion.fromJson(kSuggestionsPayload[2]);

      expect(sug.transactionDescription, isNull);
    });

    test('handles amount as Decimal string', () {
      final sug = MatchSuggestion.fromJson(kSuggestionsPayload[0]);

      expect(sug.transactionAmount, '150000.0000');
      expect(double.tryParse(sug.transactionAmount), 150000.0);
    });

    test('SuggestedMatch.amount is parseable to double', () {
      final sug = MatchSuggestion.fromJson(kSuggestionsPayload[0]);
      final match = sug.suggestedMatches[0];

      expect(double.tryParse(match.amount), 150000.0);
    });
  });

  group('ReconciliationStats — contract', () {
    test('computes stats from BankReconciliation', () {
      final rec = BankReconciliation.fromJson(kReconciliationPayload);
      final stats = ReconciliationStats.fromReconciliation(rec);

      expect(stats.totalTransactions, 3);
      expect(stats.matchedTransactions, 0);
      expect(stats.pendingTransactions, 3);
      expect(stats.progress, 0.0);
    });

    test('reflects matched transactions', () {
      // Add a match like the backend would after reconcile
      final payload = Map<String, dynamic>.from(kReconciliationPayload);
      payload['matches'] = [
        {
          'bank_transaction_id': 't1a2b3c4-d5e6-7890-abcd-ef1234567890',
          'journal_entry_id': 'je1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'matched_amount': '150000.0000',
        },
      ];

      final rec = BankReconciliation.fromJson(payload);
      final stats = ReconciliationStats.fromReconciliation(rec);

      expect(stats.matchedTransactions, 1);
      expect(stats.pendingTransactions, 2);
      expect(stats.progress, greaterThan(0));
    });
  });
}
