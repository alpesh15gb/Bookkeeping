/// Command for creating a new journal entry draft locally.
///
/// All business inputs come from the form screen.  The repository validates
/// and then persists the command to SQLite inside a transaction, queuing a
/// sync operation in the outbox at the same time.
library;

import 'package:flutter/foundation.dart';
import '../../../../../../features/accounting/journal/models/journal_line.dart';

@immutable
class CreateJournalCommand {
  const CreateJournalCommand({
    required this.companyId,
    required this.entryDate,
    required this.description,
    required this.lines,
    this.referenceNumber = '',
  });

  final String companyId;

  /// ISO 8601 date string, e.g. `'2026-07-27'`.
  final String entryDate;

  final String description;
  final String referenceNumber;

  /// The ledger lines (at least 2, balanced to post).
  final List<JournalLine> lines;
}

@immutable
class PostJournalCommand {
  const PostJournalCommand({required this.localId, required this.companyId});
  final String localId;
  final String companyId;
}

@immutable
class UpdateJournalCommand {
  const UpdateJournalCommand({
    required this.localId,
    required this.companyId,
    required this.entryDate,
    required this.description,
    required this.lines,
    this.referenceNumber = '',
  });

  final String localId;
  final String companyId;
  final String entryDate;
  final String description;
  final String referenceNumber;
  final List<JournalLine> lines;
}

@immutable
class ReverseJournalCommand {
  const ReverseJournalCommand({
    required this.localId,
    required this.companyId,
    required this.reversalDate,
    this.description = '',
  });

  final String localId;
  final String companyId;

  /// ISO 8601 date of the reversal entry.
  final String reversalDate;
  final String description;
}
