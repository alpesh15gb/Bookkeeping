/// Domain lifecycle status for a journal entry.
///
/// This is distinct from [SyncStatus], which tracks delivery to the server.
/// A journal can be posted + pending (waiting for server confirmation),
/// posted + synced (confirmed), or any other valid combination.
///
/// Use two separate columns in the Drift table rather than encoding both
/// dimensions into a single enum, so the product of all valid combinations
/// is naturally representable.
library;

/// The journal's own lifecycle state, independent of sync delivery.
enum JournalLifecycleStatus {
  /// The journal is a work-in-progress draft that can be edited.
  draft,

  /// The journal has been submitted locally — double-entry validation passed.
  /// It is immutable from the user's perspective, even if the sync engine
  /// has not yet confirmed it with the server.
  posted,

  /// A reversal journal entry has been created against a previously posted
  /// journal.  The original entry retains this status — it is not a new
  /// reversal on the original row, but the reversal entry itself carries
  /// this status.
  reversed;

  String get name => switch (this) {
    draft => 'draft',
    posted => 'posted',
    reversed => 'reversed',
  };

  static JournalLifecycleStatus fromName(String name) =>
      JournalLifecycleStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => JournalLifecycleStatus.draft,
      );

  /// True if the entry is mutable (editable by the user).
  bool get isMutable => this == draft;

  /// True if the entry has been posted (locally or remotely) and is
  /// therefore immutable from the user's perspective.
  bool get isPostedOrReversed => this == posted || this == reversed;
}
