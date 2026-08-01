/// Monetary value type for ApexBooks.
///
/// All money amounts are stored internally as integer **paise** (₹1 = 100 paise).
/// This avoids floating-point rounding errors in accounting totals.
///
/// ## Backend encoding
/// The `/apexbooks/sync` endpoints use a non-standard "micros" unit where
/// **10,000 backend-micros = ₹1** (NOT the standard 1,000,000 = ₹1).
/// This conversion is isolated here — callers must never write that factor
/// themselves. Use [Money.fromBackendMicros] / [Money.toBackendMicros].
///
/// ## Storage
/// Drift columns store [Money] as `INTEGER` (paise). See [MoneyConverter].
///
/// ## What is NOT [Money]
/// Tax rates, inventory quantities, exchange rates, and unit prices with
/// more than 2 decimal places use separate fixed-precision types (Dart
/// [String] via e.g. `"18.5000"` compatible with backend `Numeric(5,2)`).
library;

import 'package:flutter/foundation.dart';

@immutable
final class Money {
  const Money._(this.paise);

  final int paise;

  // ── Unit constants ────────────────────────────────────────────────────────

  static const int paisePerRupee = 100;

  /// Backend sync unit: 10,000 backend-micros = ₹1.
  /// This is NOT the standard "micros" (1,000,000). Do not generalise.
  static const int backendMicrosPerRupee = 10000;

  // ── Constructors ──────────────────────────────────────────────────────────

  const Money.zero() : paise = 0;

  factory Money.fromPaise(int value) => Money._(value);

  factory Money.fromRupees(num value) =>
      Money._((value * paisePerRupee).round());

  /// Converts from the backend's custom micros encoding (10,000 = ₹1).
  factory Money.fromBackendMicros(int value) {
    // backendMicros × (100 paise/rupee) ÷ (10,000 micros/rupee) = paise
    final p = (value * paisePerRupee) ~/ backendMicrosPerRupee;
    return Money._(p);
  }

  /// Safe parse from a dynamic value (String, int, double) from an API response.
  /// Returns [Money.zero] only when [value] is explicitly `null` or an empty string.
  /// Throws [ArgumentError] for genuinely unparseable values so callers notice.
  factory Money.parse(dynamic value) {
    if (value == null || (value is String && value.isEmpty)) {
      return const Money.zero();
    }
    if (value is int) return Money.fromPaise((value * paisePerRupee).round());
    if (value is double) return Money.fromRupees(value);
    if (value is String) {
      // Indian comma-formatted amounts: "1,00,000.50"
      final cleaned = value.replaceAll(',', '');
      final d = double.tryParse(cleaned);
      if (d != null) return Money.fromRupees(d);
    }
    throw ArgumentError.value(value, 'value', 'Cannot parse as Money');
  }

  // ── Conversions ───────────────────────────────────────────────────────────

  int toPaise() => paise;

  /// Converts to the backend's custom micros encoding (10,000 = ₹1).
  int toBackendMicros() => (paise * backendMicrosPerRupee) ~/ paisePerRupee;

  double toRupees() => paise / paisePerRupee;

  // ── Arithmetic ────────────────────────────────────────────────────────────

  Money operator +(Money other) => Money._(paise + other.paise);
  Money operator -(Money other) => Money._(paise - other.paise);
  Money operator -() => Money._(-paise);

  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  Money abs() => Money._(paise.abs());

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool get isPositive => paise > 0;

  // ── Object ────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => '₹${toRupees().toStringAsFixed(2)}';
}
