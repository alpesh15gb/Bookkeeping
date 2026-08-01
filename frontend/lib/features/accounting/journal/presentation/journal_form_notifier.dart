/// Journal form state management — Riverpod StateNotifier.
///
/// Migrated to offline-first: the [save] method now calls the local
/// [JournalRepository] instead of the remote [JournalService].  The journal
/// is immediately persisted to SQLite; the sync engine uploads it in the
/// background.
///
/// The [JournalService] is still available for direct-API access but is no
/// longer used by this notifier.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/direction.dart';
import '../models/journal_line.dart';
import '../../../../features/journals/domain/commands/journal_commands.dart';
import '../../../../features/journals/presentation/providers/journal_providers.dart';
import '../../../../features/auth/presentation/auth_controller.dart';
import '../../../../features/journals/domain/entities/journal_entity.dart';

/// Immutable state for the journal entry form.
class JournalFormState {
  const JournalFormState({
    this.entryDate = '',
    this.referenceNumber = '',
    this.description = '',
    this.lines = const [
      JournalLine(direction: Direction.debit),
      JournalLine(direction: Direction.credit),
    ],
    this.saving = false,
    this.error,
    this.draftId,
  });

  final String entryDate;
  final String referenceNumber;
  final String description;
  final List<JournalLine> lines;
  final bool saving;
  final String? error;
  final String? draftId;

  double get totalDebit =>
      lines.where((l) => l.direction.isDebit).fold(0.0, (s, l) => s + l.amount);
  double get totalCredit => lines
      .where((l) => l.direction.isCredit)
      .fold(0.0, (s, l) => s + l.amount);
  double get difference => (totalDebit - totalCredit).abs();
  bool get isBalanced =>
      lines.length >= 2 && totalDebit > 0 && difference < 0.005;

  JournalFormState copyWith({
    String? entryDate,
    String? referenceNumber,
    String? description,
    List<JournalLine>? lines,
    bool? saving,
    String? error,
    String? draftId,
    bool clearError = false,
  }) {
    return JournalFormState(
      entryDate: entryDate ?? this.entryDate,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      description: description ?? this.description,
      lines: lines ?? this.lines,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      draftId: draftId ?? this.draftId,
    );
  }
}

/// Notifier for journal entry form state.
class JournalFormNotifier extends StateNotifier<JournalFormState> {
  JournalFormNotifier(this._ref, this._initialEntry)
    : super(_stateFromEntry(_initialEntry)) {
    if (_initialEntry == null) {
      final now = DateTime.now();
      state = state.copyWith(
        entryDate:
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      );
    }
  }

  final Ref _ref;
  final JournalEntryEntity? _initialEntry;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _setState(JournalFormState newState) {
    if (!_disposed) state = newState;
  }

  void setDate(String date) => _setState(state.copyWith(entryDate: date));
  void setReference(String ref) =>
      _setState(state.copyWith(referenceNumber: ref));
  void setDescription(String desc) =>
      _setState(state.copyWith(description: desc));

  void updateLine(int index, JournalLine line) {
    final lines = [...state.lines]..[index] = line;
    _setState(state.copyWith(lines: lines, clearError: true));
  }

  void addLine() {
    _setState(state.copyWith(lines: [...state.lines, const JournalLine()]));
  }

  void removeLine(int index) {
    if (state.lines.length <= 2) return;
    final lines = [...state.lines]..removeAt(index);
    _setState(state.copyWith(lines: lines));
  }

  /// Auto-balance: fill the remaining amount on the first empty line
  /// of the opposite direction to make debits == credits.
  void autoBalance() {
    if (state.isBalanced) return;
    final diff = state.totalDebit - state.totalCredit;
    if (diff.abs() < 0.005) return;

    final lines = [...state.lines];
    final targetDirection = diff > 0 ? Direction.credit : Direction.debit;
    final targetAmount = diff.abs();

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].direction == targetDirection &&
          lines[i].amount == 0 &&
          lines[i].accountId.isNotEmpty) {
        lines[i] = lines[i].copyWith(amount: targetAmount);
        _setState(state.copyWith(lines: lines));
        return;
      }
    }
  }

  static JournalFormState _stateFromEntry(JournalEntryEntity? entry) {
    if (entry == null) return const JournalFormState();
    return JournalFormState(
      entryDate: entry.entryDate,
      referenceNumber: entry.referenceNumber ?? '',
      description: entry.description,
      draftId: entry.localId,
      lines: entry.lines
          .map(
            (line) => JournalLine(
              id: line.localId,
              accountId: line.accountId,
              accountName: line.accountName,
              accountCode: line.accountCode,
              amount: line.amount.toRupees(),
              direction: line.direction,
              narration: line.narration,
            ),
          )
          .toList(),
    );
  }

  /// Save the journal locally as a draft using the offline-first [JournalRepository].
  ///
  /// The journal is immediately written to SQLite and a sync operation is
  /// queued in the outbox.  This method returns `true` as long as the local
  /// write succeeds — network connectivity is not required.
  Future<bool> saveDraft() async {
    if (state.saving) return false;

    // Client-side validation (mirrors server-side rules).
    if (state.entryDate.isEmpty || DateTime.tryParse(state.entryDate) == null) {
      _setState(state.copyWith(error: 'Enter a valid posting date.'));
      return false;
    }
    if (state.description.trim().isEmpty) {
      _setState(state.copyWith(error: 'Enter a clear journal narration.'));
      return false;
    }
    if (state.lines.length < 2 || state.lines.any((l) => !l.isValid)) {
      _setState(
        state.copyWith(
          error: 'Select an account and positive amount on every line.',
        ),
      );
      return false;
    }
    _setState(state.copyWith(saving: true, clearError: true));

    try {
      final auth = _ref.read(authControllerProvider);
      final companyId = auth.activeMembership?.tenantId ?? '';

      final command = CreateJournalCommand(
        companyId: companyId,
        entryDate: state.entryDate,
        referenceNumber: state.referenceNumber.trim(),
        description: state.description.trim(),
        lines: state.lines,
      );

      // Local write — always succeeds offline. The active UI creates posted
      // journals, so immediately transition the local draft to posted; the
      // repository queues the outbox payload for background sync.
      final repository = _ref.read(journalRepositoryProvider);
      final draft = _initialEntry == null
          ? await repository.saveDraft(command)
          : await repository.updateDraft(
              UpdateJournalCommand(
                localId: _initialEntry.localId,
                companyId: companyId,
                entryDate: state.entryDate,
                referenceNumber: state.referenceNumber.trim(),
                description: state.description.trim(),
                lines: state.lines,
              ),
            );

      if (_disposed) return false;
      _setState(state.copyWith(saving: false, draftId: draft.localId));
      return true;
    } catch (e) {
      if (_disposed) return false;
      _setState(state.copyWith(saving: false, error: e.toString()));
      return false;
    }
  }

  Future<bool> post() async {
    if (state.draftId == null && !await saveDraft()) return false;
    try {
      final companyId =
          _ref.read(authControllerProvider).activeMembership?.tenantId ?? '';
      await _ref
          .read(journalRepositoryProvider)
          .postJournal(
            PostJournalCommand(localId: state.draftId!, companyId: companyId),
          );
      return true;
    } catch (e) {
      _setState(state.copyWith(error: e.toString()));
      return false;
    }
  }
}

/// Provider for the journal form notifier.
final journalFormProvider = StateNotifierProvider.autoDispose
    .family<JournalFormNotifier, JournalFormState, JournalEntryEntity?>(
      (ref, entry) => JournalFormNotifier(ref, entry),
    );
