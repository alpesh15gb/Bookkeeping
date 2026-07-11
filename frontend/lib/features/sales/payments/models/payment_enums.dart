/// Payment mode values (backend: CASH|BANK|UPI|POS|CHEQUE|NEFT_RTGS|OTHER).
library;

enum PaymentMode {
  cash('CASH'),
  bank('BANK'),
  upi('UPI'),
  pos('POS'),
  cheque('CHEQUE'),
  neftRtgs('NEFT_RTGS'),
  other('OTHER');

  const PaymentMode(this.value);
  final String value;

  static PaymentMode fromString(String s) =>
      PaymentMode.values.firstWhere((e) => e.value == s, orElse: () => other);
}

/// Payment lifecycle status.
enum PaymentStatus {
  active('ACTIVE'),
  cancelled('CANCELLED');

  const PaymentStatus(this.value);
  final String value;

  static PaymentStatus fromString(String s) => PaymentStatus.values.firstWhere(
    (e) => e.value == s,
    orElse: () => active,
  );

  bool get isActive => this == active;
  bool get isCancelled => this == cancelled;
  bool get isCancellable => isActive;
}
