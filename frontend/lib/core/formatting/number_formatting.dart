/// Number formatting service. Centralises currency, quantity, percent, GST,
/// and negative-value formatting. Never format directly in widgets.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:apexbooks/features/settings/presentation/settings_providers.dart';

/// A single entry point for all number formatting in ApexBooks.
/// Adapts to locale and currency settings from the active company.
class NumberFormatter {
  NumberFormatter({
    this.locale = 'en_IN',
    this.currencySymbol = '\u20B9',
    this.decimalDigits = 2,
    this.quantityDigits = 2,
  });

  final String locale;
  final String currencySymbol;
  final int decimalDigits;
  final int quantityDigits;

  /// Formats a monetary amount, e.g. `₹1,23,456.78`.
  String currency(double? value, {String? symbol, bool showSymbol = true}) {
    if (value == null) return '—';
    final formatted = _format(value, decimalDigits);
    if (!showSymbol) return formatted;
    return '${symbol ?? currencySymbol}$formatted';
  }

  /// Formats a quantity, e.g. `1,234.50`.
  String quantity(double? value) {
    if (value == null) return '—';
    return _format(value, quantityDigits);
  }

  /// Formats a percentage, e.g. `18.00%`.
  String percent(double? value, {bool showSign = false}) {
    if (value == null) return '—';
    final formatted = _format(value, 2);
    return showSign && value >= 0 ? '+$formatted%' : '$formatted%';
  }

  /// Formats a GSTIN or tax rate — same as percent but with specific label.
  String gst(double? value) => percent(value);

  /// Formats a number with sign for negative values.
  String signed(double? value, {int digits = 2}) {
    if (value == null) return '—';
    final formatted = _format(value.abs(), digits);
    if (value < 0) return '($formatted)';
    return formatted;
  }

  /// Plain integer.
  String integer(int? value) {
    if (value == null) return '—';
    return _format(value.toDouble(), 0);
  }

  /// Core number formatting using Dart's intl. Falls back to basic formatting
  /// when intl is not available.
  String _format(double value, int fractionDigits) {
    try {
      // Use intl NumberFormat if available (added to pubspec).
      // ignore: depend_on_referenced_packages
      final fmt = NumberFormat('#,##0.${'0' * fractionDigits}', locale);
      return fmt.format(value);
    } catch (e) {
      debugPrint('NumberFormatter: intl formatting failed — $e');
      // Fallback for when intl is absent or another formatting error occurs.
      final negative = value < 0;
      final abs = value.abs();
      final intPart = abs.floor();
      final frac = ((abs - intPart) * (10 * fractionDigits)).round();
      final intStr = intPart.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(?!\d))'),
        (m) => '${m[1]},',
      );
      final fracStr = frac.toString().padLeft(fractionDigits, '0');
      final formatted = '$intStr.${fracStr.substring(0, fractionDigits)}';
      return negative ? '($formatted)' : formatted;
    }
  }
}

/// Provider for [NumberFormatter] — seeded from the active company's settings.
final numberFormatterProvider = Provider<NumberFormatter>((ref) {
  final preferences = ref.watch(userPreferencesProvider).valueOrNull;
  final currency = preferences?.currency ?? 'INR';
  final requestedLocale = preferences?.numberFormat ?? 'en_IN';
  final locale = requestedLocale == 'en_EU' ? 'de_DE' : requestedLocale;
  const symbols = <String, String>{
    'INR': '\u20B9',
    'USD': r'$',
    'EUR': '\u20AC',
    'GBP': '\u00A3',
    'AED': 'AED ',
    'SGD': r'S$',
  };
  return NumberFormatter(
    locale: locale,
    currencySymbol: symbols[currency] ?? '$currency ',
  );
});
