/// Journal line direction — DEBIT or CREDIT (mirrors backend CheckConstraint).
library;

enum Direction {
  debit('DEBIT'),
  credit('CREDIT');

  const Direction(this.value);
  final String value;

  static Direction fromString(String s) =>
      Direction.values.firstWhere((e) => e.value == s, orElse: () => debit);

  bool get isDebit => this == debit;
  bool get isCredit => this == credit;
}
