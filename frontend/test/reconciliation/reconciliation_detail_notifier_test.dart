/// Tests for [ReconciliationDetailNotifier] — the reconciliation matching
/// workflow state machine.
///
/// Uses verified fixtures from [reconciliation_contract_test] and a fake
/// [ReconciliationService] so failure modes and edge cases are exercised
/// without a live backend.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/accounting/reconciliation/models/reconciliation_models.dart';
import 'package:apexbooks/features/accounting/reconciliation/services/reconciliation_service.dart';
import 'package:apexbooks/features/accounting/reconciliation/presentation/reconciliation_detail_notifier.dart';

// ── Fake service ─────────────────────────────────────────────────────────────

class FakeReconciliationService implements ReconciliationService {
  FakeReconciliationService({
    this.reconciliation,
    this.suggestions = const [],
    this.bulkReconcileResult,
  });

  final BankReconciliation? reconciliation;
  final List<MatchSuggestion> suggestions;
  final Result<BankReconciliation>? bulkReconcileResult;

  /// Captured bulk-reconcile payloads for verification.
  final capturedPayloads = <List<Map<String, dynamic>>>[];

  @override
  Future<Result<List<BankReconciliationListItem>>> list({
    int page = 1,
    int limit = 50,
  }) => Future(() => const Success([]));

  @override
  Future<Result<BankReconciliation>> get(String id) async {
    if (reconciliation != null) return Success(reconciliation!);
    return const Failure(ApiError(message: 'Not found', statusCode: 404));
  }

  @override
  Future<Result<BankReconciliation>> uploadStatement({
    required String bankingProfileId,
    required String filePath,
  }) => Future(() => const Failure(ApiError(message: 'Not implemented')));

  @override
  Future<Result<BankReconciliation>> reconcileTransaction({
    required String transactionId,
    required String journalEntryId,
  }) => Future(() => const Failure(ApiError(message: 'Not implemented')));

  @override
  Future<Result<BankReconciliation>> bulkReconcile({
    required String reconciliationId,
    required List<Map<String, dynamic>> matches,
  }) async {
    capturedPayloads.add(matches);
    return bulkReconcileResult ??
        const Failure(ApiError(message: 'Not implemented'));
  }

  @override
  Future<Result<BankReconciliation>> undo(String id) =>
      Future(() => const Failure(ApiError(message: 'Not implemented')));

  @override
  Future<Result<List<MatchSuggestion>>> getSuggestions(
    String statementId,
  ) async {
    return Success(suggestions);
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

final _kReconciliation = BankReconciliation.fromJson({
  'id': 'rec-a1b2c3d4',
  'banking_profile_id': 'bp-001',
  'banking_profile_name': 'HDFC Current Account',
  'statement_date': '2026-07-01',
  'closing_balance': '1250000.0000',
  'statement_balance': '1250000.0000',
  'difference': '0.0000',
  'status': 'IN_PROGRESS',
  'transactions': [
    {
      'id': 'txn-001',
      'transaction_date': '2026-07-05',
      'amount': '150000.0000',
      'description': 'UPI-SALE',
      'reference_number': 'REF-001',
      'status': 'PENDING',
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    },
    {
      'id': 'txn-002',
      'transaction_date': '2026-07-06',
      'amount': '-25000.0000',
      'description': 'RENT',
      'reference_number': 'REF-002',
      'status': 'PENDING',
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    },
    {
      'id': 'txn-003',
      'transaction_date': '2026-07-07',
      'amount': '5000.0000',
      'description': 'INTEREST',
      'reference_number': null,
      'status': 'PENDING',
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    },
  ],
  'matches': [],
  'created_at': '2026-07-01T10:00:00Z',
});

final _kSuggestions = [
  const MatchSuggestion(
    transactionId: 'txn-001',
    transactionDate: '2026-07-05',
    transactionAmount: '150000.0000',
    transactionDescription: 'UPI-SALE',
    suggestedMatches: [
      SuggestedMatch(
        type: 'payment',
        id: 'pmt-001',
        amount: '150000.0000',
        date: '2026-07-05',
        reference: 'INV-001',
        score: 95,
      ),
    ],
  ),
  const MatchSuggestion(
    transactionId: 'txn-002',
    transactionDate: '2026-07-06',
    transactionAmount: '-25000.0000',
    transactionDescription: 'RENT',
    suggestedMatches: [
      SuggestedMatch(
        type: 'bill_payment',
        id: 'bp-001',
        amount: '25000.0000',
        date: '2026-07-06',
        reference: 'BILL-042',
        score: 88,
      ),
    ],
  ),
];

void main() {
  group('ReconciliationDetailNotifier', () {
    test('load → reconciliation and suggestions populated', () async {
      final service = FakeReconciliationService(
        reconciliation: _kReconciliation,
        suggestions: _kSuggestions,
      );
      final notifier = ReconciliationDetailNotifier(service);

      await notifier.load('rec-a1b2c3d4');

      expect(notifier.state.loading, isFalse);
      expect(notifier.state.reconciliation, isNotNull);
      expect(notifier.state.reconciliation!.id, 'rec-a1b2c3d4');
      expect(notifier.state.suggestions.length, 2);
      expect(notifier.state.stats.totalTransactions, 3);
      expect(notifier.state.stats.matchedTransactions, 0);
    });

    test('load → error when reconciliation not found', () async {
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(),
      );

      await notifier.load('nonexistent');

      expect(notifier.state.loading, isFalse);
      expect(notifier.state.error, isNotNull);
    });

    test('selectTransaction toggles selection', () {
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );

      notifier.selectTransaction('txn-001');
      expect(notifier.state.selectedTransactionId, 'txn-001');

      notifier.selectTransaction(null);
      expect(notifier.state.selectedTransactionId, isNull);
    });

    test('applySuggestion registers pending match', () {
      const match = SuggestedMatch(
        type: 'payment',
        id: 'pmt-001',
        amount: '150000.0000',
        date: '2026-07-05',
        reference: 'INV-001',
        score: 95,
      );
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );

      notifier.applySuggestion('txn-001', match);

      final pending = notifier.state.pendingMatches['txn-001'];
      expect(pending, isNotNull);
      expect(pending!.action, MatchAction.match);
      expect(pending.suggestedMatch?.id, 'pmt-001');
      expect(notifier.state.hasPendingChanges, isTrue);
    });

    test('unmatch removes pending match', () {
      const match = SuggestedMatch(
        type: 'payment',
        id: 'pmt-001',
        amount: '150000',
        date: '2026-07-05',
        reference: 'REF',
        score: 95,
      );
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );

      notifier.applySuggestion('txn-001', match);
      expect(notifier.state.pendingMatches.containsKey('txn-001'), isTrue);

      notifier.unmatchTransaction('txn-001');
      expect(notifier.state.pendingMatches.containsKey('txn-001'), isFalse);
      expect(notifier.state.hasPendingChanges, isFalse);
    });

    test('exclude marks as excluded', () {
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );

      notifier.excludeTransaction('txn-002');

      expect(
        notifier.state.pendingMatches['txn-002']!.action,
        MatchAction.exclude,
      );
    });

    test('clearAllPending removes all', () {
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );
      notifier.applySuggestion(
        'txn-001',
        const SuggestedMatch(
          type: 'payment',
          id: 'pmt-001',
          amount: '150000',
          date: '2026-07-05',
          reference: 'R',
          score: 95,
        ),
      );
      notifier.applySuggestion(
        'txn-002',
        const SuggestedMatch(
          type: 'bill_payment',
          id: 'bp-001',
          amount: '25000',
          date: '2026-07-06',
          reference: 'R',
          score: 88,
        ),
      );

      notifier.clearAllPending();

      expect(notifier.state.pendingMatches, isEmpty);
      expect(notifier.state.hasPendingChanges, isFalse);
    });

    test('commitMatches builds correct bulk-reconcile payload', () async {
      final service = FakeReconciliationService(
        reconciliation: _kReconciliation,
        bulkReconcileResult: Success(_kReconciliation),
      );
      final notifier = ReconciliationDetailNotifier(service);
      await notifier.load('rec-a1b2c3d4');

      notifier.applySuggestion(
        'txn-001',
        const SuggestedMatch(
          type: 'payment',
          id: 'pmt-001',
          amount: '150000.0000',
          date: '2026-07-05',
          reference: 'INV-001',
          score: 95,
        ),
      );

      final ok = await notifier.commitMatches();

      expect(ok, isTrue);
      expect(service.capturedPayloads.length, 1);
      expect(service.capturedPayloads.first.length, 1);
      expect(service.capturedPayloads.first[0]['transaction_id'], 'txn-001');
      expect(service.capturedPayloads.first[0]['journal_entry_id'], 'pmt-001');
      expect(service.capturedPayloads.first[0]['amount'], '150000.0000');
    });

    test('commitMatches fails when no pending matches', () async {
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );
      await notifier.load('rec-a1b2c3d4');

      expect(await notifier.commitMatches(), isFalse);
      expect(notifier.state.error, isNotNull);
    });

    test('commitMatches surfaces service failure', () async {
      final service = FakeReconciliationService(
        reconciliation: _kReconciliation,
        bulkReconcileResult: const Failure(
          ApiError(message: 'Server error', statusCode: 500),
        ),
      );
      final notifier = ReconciliationDetailNotifier(service);
      await notifier.load('rec-a1b2c3d4');

      notifier.applySuggestion(
        'txn-001',
        const SuggestedMatch(
          type: 'payment',
          id: 'pmt-001',
          amount: '150000',
          date: '2026-07-05',
          reference: 'R',
          score: 95,
        ),
      );

      expect(await notifier.commitMatches(), isFalse);
      expect(notifier.state.error, contains('Server error'));
      expect(notifier.state.saving, isFalse);
    });

    test('success message after commit', () async {
      final service = FakeReconciliationService(
        reconciliation: _kReconciliation,
        bulkReconcileResult: Success(_kReconciliation),
      );
      final notifier = ReconciliationDetailNotifier(service);
      await notifier.load('rec-a1b2c3d4');

      notifier.applySuggestion(
        'txn-001',
        const SuggestedMatch(
          type: 'payment',
          id: 'pmt-001',
          amount: '150000',
          date: '2026-07-05',
          reference: 'R',
          score: 95,
        ),
      );

      await notifier.commitMatches();

      expect(notifier.state.successMessage, isNotNull);
    });

    test('state flow: loading → data → saving → data', () async {
      final service = FakeReconciliationService(
        reconciliation: _kReconciliation,
        suggestions: _kSuggestions,
        bulkReconcileResult: Success(_kReconciliation),
      );
      final notifier = ReconciliationDetailNotifier(service);

      expect(notifier.state.loading, isTrue);

      await notifier.load('rec-a1b2c3d4');
      expect(notifier.state.loading, isFalse);
      expect(notifier.state.reconciliation, isNotNull);

      notifier.applySuggestion(
        'txn-001',
        const SuggestedMatch(
          type: 'payment',
          id: 'pmt-001',
          amount: '150000',
          date: '2026-07-05',
          reference: 'R',
          score: 95,
        ),
      );
      expect(notifier.state.hasPendingChanges, isTrue);

      expect(await notifier.commitMatches(), isTrue);
      expect(notifier.state.saving, isFalse);
    });

    test('rejects commit after disposal', () async {
      final notifier = ReconciliationDetailNotifier(
        FakeReconciliationService(reconciliation: _kReconciliation),
      );
      await notifier.load('rec-a1b2c3d4');

      notifier.applySuggestion(
        'txn-001',
        const SuggestedMatch(
          type: 'payment',
          id: 'pmt-001',
          amount: '150000',
          date: '2026-07-05',
          reference: 'R',
          score: 95,
        ),
      );

      notifier.dispose();
      final ok = await notifier.commitMatches();

      // After disposal, the notifier should guard without reading or setting state.
      expect(ok, isFalse);
    });
  });
}
