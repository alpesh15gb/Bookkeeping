/// Vendor payment status values.
library;

enum VendorPaymentStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const VendorPaymentStatus(this.value);
  final String value;

  static VendorPaymentStatus fromString(String s) => VendorPaymentStatus.values
      .firstWhere((e) => e.value == s, orElse: () => active);

  bool get isActive => this == active;
  bool get isCancelled => this == cancelled;
  bool get isCancellable => this == active;
}

/// Payment modes (mirrors backend pattern for bills).
enum PaymentMode {
  cash('CASH'),
  bank('BANK'),
  upi('UPI'),
  pos('POS'),
  other('OTHER');

  const PaymentMode(this.value);
  final String value;

  static PaymentMode fromString(String s) =>
      PaymentMode.values.firstWhere((e) => e.value == s, orElse: () => cash);
}
