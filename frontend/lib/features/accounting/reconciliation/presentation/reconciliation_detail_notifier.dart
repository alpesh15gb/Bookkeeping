/// Reconciliation detail state management — Riverpod StateNotifier.
///
/// Manages the side-by-side matching workflow: loading a reconciliation,
/// computing suggestions, tracking pending matches, and committing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/reconciliation_models.dart';
import '../services/reconciliation_service.dart';

/// State for the reconciliation detail/matching screen.
class ReconciliationDetailState {
  const ReconciliationDetailState({
    this.reconciliation,
    this.suggestions = const [],
    this.pendingMatches = const {},
    this.loading = true,
    this.saving = false,
    this.error,
    this.successMessage,
    this.selectedTransactionId,
  });

  final BankReconciliation? reconciliation;
  final List<MatchSuggestion> suggestions;
  final Map<String, PendingMatch> pendingMatches; // txn id -> pending match
  final bool loading;
  final bool saving;
  final String? error;
  final String? successMessage;
  final String? selectedTransactionId;

  ReconciliationStats get stats => reconciliation != null
      ? ReconciliationStats.fromReconciliation(reconciliation!)
      : const ReconciliationStats();

  bool get hasPendingChanges =>
      pendingMatches.values.any((m) => m.suggestedMatch != null);

  ReconciliationDetailState copyWith({
    BankReconciliation? reconciliation,
    List<MatchSuggestion>? suggestions,
    Map<String, PendingMatch>? pendingMatches,
    bool? loading,
    bool? saving,
    String? error,
    String? successMessage,
    String? selectedTransactionId,
    bool clearError = false,
    bool clearSuccess = false,
    bool clearSelectedTransaction = false,
  }) {
    return ReconciliationDetailState(
      reconciliation: reconciliation ?? this.reconciliation,
      suggestions: suggestions ?? this.suggestions,
      pendingMatches: pendingMatches ?? this.pendingMatches,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      successMessage: clearSuccess
          ? null
          : (successMessage ?? this.successMessage),
      selectedTransactionId: clearSelectedTransaction
          ? null
          : selectedTransactionId ?? this.selectedTransactionId,
    );
  }
}

/// Notifier for the reconciliation detail/matching workflow.
class ReconciliationDetailNotifier
    extends StateNotifier<ReconciliationDetailState> {
  ReconciliationDetailNotifier(this._service)
    : super(const ReconciliationDetailState());

  final ReconciliationService _service;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setState(ReconciliationDetailState newState) {
    if (!_disposed) state = newState;
  }

  /// Load a reconciliation by ID and fetch suggestions.
  Future<void> load(String id) async {
    _setState(state.copyWith(loading: true, clearError: true));

    // Load reconciliation
    final recResult = await _service.get(id);
    if (_disposed) return;

    final BankReconciliation reconciliation;
    switch (recResult) {
      case Success<BankReconciliation>(:final value):
        reconciliation = value;
      case Failure<BankReconciliation>(:final error):
        _setState(state.copyWith(loading: false, error: error.message));
        return;
      case Loading<BankReconciliation>():
        return;
    }

    // Try to load suggestions
    List<MatchSuggestion> suggestions = [];
    final statementId = reconciliation.id;
    if (statementId.isNotEmpty) {
      final sugResult = await _service.getSuggestions(statementId);
      if (sugResult case Success<List<MatchSuggestion>>(
        :final value,
      ) when !_disposed) {
        suggestions = value;
      }
    }

    // Build initial pending matches from existing reconciliations
    final pendingMatches = <String, PendingMatch>{};
    for (final txn in reconciliation.transactions) {
      final existingMatch = reconciliation.matches
          .where((m) => m.bankTransactionId == txn.id)
          .firstOrNull;
      if (existingMatch != null) {
        pendingMatches[txn.id] = PendingMatch(
          bankTransactionId: txn.id,
          suggestedMatch: SuggestedMatch(
            type: 'existing',
            id: existingMatch.journalEntryId,
            amount: existingMatch.matchedAmount.toString(),
            date: '',
            score: 100,
          ),
          action: MatchAction.match,
        );
      }
    }

    _setState(
      state.copyWith(
        reconciliation: reconciliation,
        suggestions: suggestions,
        pendingMatches: pendingMatches,
        loading: false,
      ),
    );
  }

  /// Select a transaction to view details.
  void selectTransaction(String? id) {
    _setState(
      state.copyWith(
        selectedTransactionId: id,
        clearSelectedTransaction: id == null,
      ),
    );
  }

  /// Suggest a match for a transaction (user picks a suggestion).
  void applySuggestion(String transactionId, SuggestedMatch match) {
    final pending =
        state.pendingMatches[transactionId] ??
        PendingMatch(bankTransactionId: transactionId);
    _setState(
      state.copyWith(
        pendingMatches: {
          ...state.pendingMatches,
          transactionId: pending.copyWith(
            suggestedMatch: match,
            action: MatchAction.match,
          ),
        },
      ),
    );
  }

  /// Categorize a transaction (create a new entry instead of matching).
  void categorizeTransaction(
    String transactionId, {
    String? accountId,
    String? notes,
  }) {
    final pending =
        state.pendingMatches[transactionId] ??
        PendingMatch(bankTransactionId: transactionId);
    _setState(
      state.copyWith(
        pendingMatches: {
          ...state.pendingMatches,
          transactionId: pending.copyWith(
            suggestedMatch: null,
            action: MatchAction.categorize,
            categoryAccountId: accountId,
            notes: notes,
            clearMatch: true,
          ),
        },
      ),
    );
  }

  /// Exclude a transaction from reconciliation.
  void excludeTransaction(String transactionId) {
    final pending =
        state.pendingMatches[transactionId] ??
        PendingMatch(bankTransactionId: transactionId);
    _setState(
      state.copyWith(
        pendingMatches: {
          ...state.pendingMatches,
          transactionId: pending.copyWith(
            action: MatchAction.exclude,
            clearMatch: true,
          ),
        },
      ),
    );
  }

  /// Unmatch a previously matched transaction.
  void unmatchTransaction(String transactionId) {
    _setState(
      state.copyWith(
        pendingMatches: {...state.pendingMatches}..remove(transactionId),
      ),
    );
  }

  /// Remove all pending matches.
  void clearAllPending() {
    _setState(state.copyWith(pendingMatches: <String, PendingMatch>{}));
  }

  /// Commit pending matches to the backend.
  Future<bool> commitMatches() async {
    if (_disposed) return false;

    final reconciliation = state.reconciliation;
    if (reconciliation == null) return false;
    if (!state.hasPendingChanges) {
      _setState(state.copyWith(error: 'No matches to commit.'));
      return false;
    }

    _setState(
      state.copyWith(saving: true, clearError: true, clearSuccess: true),
    );

    // Collect all match decisions
    final matches = <Map<String, dynamic>>[];
    for (final entry in state.pendingMatches.entries) {
      final pending = entry.value;
      if (pending.action == MatchAction.match &&
          pending.suggestedMatch != null) {
        matches.add({
          'transaction_id': pending.bankTransactionId,
          'journal_entry_id': pending.suggestedMatch!.id,
          'amount': pending.suggestedMatch!.amount,
        });
      }
    }

    if (matches.isEmpty) {
      _setState(state.copyWith(saving: false, error: 'No matches to commit.'));
      return false;
    }

    final result = await _service.bulkReconcile(
      reconciliationId: reconciliation.id,
      matches: matches,
    );

    if (_disposed) return false;

    switch (result) {
      case Success<BankReconciliation>(:final value):
        _setState(
          state.copyWith(
            saving: false,
            reconciliation: value,
            pendingMatches: <String, PendingMatch>{},
            successMessage:
                '${matches.length} transaction(s) reconciled successfully.',
          ),
        );
        return true;
      case Failure<BankReconciliation>(:final error):
        _setState(state.copyWith(saving: false, error: error.message));
        return false;
      case Loading<BankReconciliation>():
        _setState(state.copyWith(saving: false));
        return false;
    }
  }

  /// Complete and finish the reconciliation.
  Future<bool> finalize() async {
    // First commit any pending matches
    if (state.hasPendingChanges) {
      final committed = await commitMatches();
      if (!committed) return false;
    }
    _setState(state.copyWith(successMessage: 'Reconciliation completed.'));
    return true;
  }
}

final reconciliationDetailProvider = StateNotifierProvider.autoDispose
    .family<ReconciliationDetailNotifier, ReconciliationDetailState, String>((
      ref,
      id,
    ) {
      final service = ref.watch(reconciliationServiceProvider);
      final notifier = ReconciliationDetailNotifier(service);
      Future.microtask(() => notifier.load(id));
      return notifier;
    });
