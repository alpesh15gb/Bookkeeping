/// Journal entry validation — balanced entries only, Debit == Credit.
library;

import '../models/journal_entry.dart';
import '../models/journal_line.dart';

class JournalValidationService {
  const JournalValidationService();

  /// Validate a journal entry before submission.
  /// Returns `null` if valid, or an error message.
  String? validateForCreate(JournalEntry entry) {
    if (entry.entryDate.isEmpty) return 'Entry date is required';
    if (entry.description.isEmpty) return 'Description is required';
    if (entry.lines.length < 2) {
      return 'A journal entry must have at least 2 lines (debit and credit)';
    }

    for (final line in entry.lines) {
      final err = validateLine(line);
      if (err != null) return err;
    }

    // Must have at least one debit and one credit.
    final hasDebit = entry.lines.any((l) => l.direction.isDebit);
    final hasCredit = entry.lines.any((l) => l.direction.isCredit);
    if (!hasDebit) return 'At least one debit line is required';
    if (!hasCredit) return 'At least one credit line is required';

    // Balanced entry check: TOTAL DEBIT == TOTAL CREDIT.
    if (!entry.isBalanced) {
      final diff = entry.totalDebit - entry.totalCredit;
      return 'Journal entry is not balanced. '
          'Total Debit (${entry.totalDebit.toStringAsFixed(2)}) '
          '≠ Total Credit (${entry.totalCredit.toStringAsFixed(2)}). '
          'Difference: ${diff.toStringAsFixed(2)}';
    }

    return null;
  }

  String? validateLine(JournalLine line) {
    if (line.accountId.isEmpty) return 'Account is required on all lines';
    if (line.amount <= 0)
      return 'Amount must be greater than zero on all lines';
    return null;
  }

  /// Validate that a reversal entry can be created for the given original entry.
  String? validateReversal(JournalEntry original) {
    if (original.sourceType != 'MANUAL') {
      return 'Only manual journal entries can be reversed';
    }
    return null;
  }
}
