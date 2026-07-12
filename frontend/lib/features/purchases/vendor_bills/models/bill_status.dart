/// Vendor bill lifecycle status values (mirrors backend CheckConstraint).
library;

enum BillStatus {
  draft('DRAFT'),
  posted('POSTED'),
  unpaid('UNPAID'),
  partiallyPaid('PARTIALLY_PAID'),
  paid('PAID'),
  cancelled('CANCELLED');

  const BillStatus(this.value);
  final String value;

  static BillStatus fromString(String s) =>
      BillStatus.values.firstWhere((e) => e.value == s, orElse: () => draft);

  bool get isEditable => this == draft;
  bool get isFinalized =>
      this == posted || this == unpaid || this == partiallyPaid || this == paid;
  bool get isCancellable => isFinalized;
  bool get isDeletable => this == draft;
  bool get hasOutstanding => this == unpaid || this == partiallyPaid;
}
