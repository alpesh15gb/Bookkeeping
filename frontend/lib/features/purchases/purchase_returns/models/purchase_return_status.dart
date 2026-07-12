/// Purchase return status values.
library;

enum PurchaseReturnStatus {
  draft('DRAFT'),
  posted('POSTED'),
  cancelled('CANCELLED');

  const PurchaseReturnStatus(this.value);
  final String value;

  static PurchaseReturnStatus fromString(String s) => PurchaseReturnStatus
      .values
      .firstWhere((e) => e.value == s, orElse: () => draft);

  bool get isEditable => this == draft;
  bool get isPosted => this == posted;
  bool get isCancellable => this == posted;
}
