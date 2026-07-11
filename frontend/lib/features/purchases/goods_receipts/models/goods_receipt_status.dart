/// Goods receipt status values.
library;

enum GoodsReceiptStatus {
  draft('DRAFT'),
  confirmed('CONFIRMED'),
  cancelled('CANCELLED');

  const GoodsReceiptStatus(this.value);
  final String value;

  static GoodsReceiptStatus fromString(String s) => GoodsReceiptStatus.values
      .firstWhere((e) => e.value == s, orElse: () => draft);

  bool get isEditable => this == draft;
  bool get isConfirmed => this == confirmed;
  bool get isCancellable => this == confirmed;
}
