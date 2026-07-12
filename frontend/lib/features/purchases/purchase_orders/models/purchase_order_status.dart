/// Purchase order lifecycle status values (mirrors backend CheckConstraint).
library;

/// Status values for purchase orders.
///
/// Lifecycle: Draft → Confirmed → Received → Cancelled
enum PurchaseOrderStatus {
  draft('DRAFT'),
  confirmed('CONFIRMED'),
  received('RECEIVED'),
  cancelled('CANCELLED');

  const PurchaseOrderStatus(this.value);
  final String value;

  static PurchaseOrderStatus fromString(String s) => PurchaseOrderStatus.values
      .firstWhere((e) => e.value == s, orElse: () => draft);

  bool get isEditable => this == draft;
  bool get isConfirmed => this == confirmed;
  bool get isReceived => this == received;
  bool get isCancelled => this == cancelled;
  bool get isFinalized => this == confirmed || this == received;
  bool get isCancellable => this == draft || this == confirmed;
}
