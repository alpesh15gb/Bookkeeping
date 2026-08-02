/// Purchase order lifecycle status values (mirrors backend CheckConstraint).
library;

/// Status values for purchase orders.
///
/// Lifecycle: Draft → Pending → Approved → Partial → Completed → Cancelled
enum PurchaseOrderStatus {
  draft('DRAFT'),
  pending('PENDING'),
  approved('APPROVED'),
  partial('PARTIAL'),
  completed('COMPLETED'),
  confirmed('CONFIRMED'),
  received('RECEIVED'),
  cancelled('CANCELLED');

  const PurchaseOrderStatus(this.value);
  final String value;

  static PurchaseOrderStatus fromString(String s) => PurchaseOrderStatus.values
      .firstWhere((e) => e.value == s, orElse: () => draft);

  bool get isEditable => this == draft;
  bool get isConfirmed => this == confirmed || this == approved;
  bool get isReceived => this == received || this == completed || this == partial;
  bool get isCancelled => this == cancelled;
  bool get isFinalized => this == confirmed || this == received || this == approved || this == completed || this == partial;
  bool get isCancellable => this == draft || this == confirmed || this == approved;
}
