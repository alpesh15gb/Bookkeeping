/// Invoice lifecycle status values (mirrors backend CheckConstraint).
library;

/// Status values for invoices.
enum InvoiceStatus {
  draft('DRAFT'),
  posted('POSTED'),
  sent('SENT'),
  partiallyPaid('PARTIALLY_PAID'),
  paid('PAID'),
  overdue('OVERDUE'),
  cancelled('CANCELLED');

  const InvoiceStatus(this.value);
  final String value;

  static InvoiceStatus fromString(String? s) =>
      InvoiceStatus.values.firstWhere((e) => e.value == s, orElse: () => draft);

  bool get isEditable => this == draft;
  bool get isFinalized =>
      this == posted ||
      this == partiallyPaid ||
      this == paid ||
      this == overdue;
  bool get isCancellable => isFinalized;
  bool get isDeletable => this == draft;
}

/// E-Invoice IRN status.
enum EInvoiceStatus {
  pending('PENDING'),
  generated('GENERATED'),
  cancelled('CANCELLED'),
  failed('FAILED');

  const EInvoiceStatus(this.value);
  final String value;

  static EInvoiceStatus fromString(String s) => EInvoiceStatus.values
      .firstWhere((e) => e.value == s, orElse: () => pending);
}
