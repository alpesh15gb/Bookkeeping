/// Locale-aware formatters and validators shared across the app.
library;

import 'package:intl/intl.dart';

/// Formats an amount as Indian Rupees with grouping (e.g. ₹1,23,456.78).
String formatCurrency(num amount, {String symbol = '₹', int decimals = 2}) {
  final fmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: symbol,
    decimalDigits: decimals,
  );
  return fmt.format(amount);
}

/// Formats a bare number with Indian grouping and no currency symbol.
String formatNumber(num value, {int decimals = 2}) {
  final fmt = NumberFormat.decimalPatternDigits(
    locale: 'en_IN',
    decimalDigits: decimals,
  );
  return fmt.format(value);
}

/// Formats an ISO date as `dd MMM yyyy` (e.g. 04 Apr 2026).
String formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

/// Formats an ISO date-time as `dd MMM yyyy, hh:mm a`.
String formatDateTime(DateTime dt) =>
    DateFormat('dd MMM yyyy, hh:mm a').format(dt);

/// Parses a decimal string from the backend into a [double], tolerating null.
double parseDecimal(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

/// Validates an email address.
String? emailValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'Email is required';
  final regex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
  if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
  return null;
}

/// Validates the ApexBooks password policy: min 8, max 128, with upper, lower,
/// digit and special char — mirrors the backend rules.
String? passwordValidator(String? value) {
  if (value == null || value.isEmpty) return 'Password is required';
  if (value.length < 8) return 'At least 8 characters';
  if (value.length > 128) return 'At most 128 characters';
  if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Add an uppercase letter';
  if (!RegExp(r'[a-z]').hasMatch(value)) return 'Add a lowercase letter';
  if (!RegExp(r'[0-9]').hasMatch(value)) return 'Add a number';
  if (!RegExp(r'[!@#$%^&*(),.?":{}<>_=\+\-\[\]\\\/]').hasMatch(value)) {
    return 'Add a special character';
  }
  return null;
}

/// A 0-100 password strength score used by the register screen meter.
int passwordStrength(String password) {
  if (password.isEmpty) return 0;
  var score = 0;
  if (password.length >= 8) score += 25;
  if (password.length >= 12) score += 10;
  if (RegExp(r'[A-Z]').hasMatch(password)) score += 15;
  if (RegExp(r'[a-z]').hasMatch(password)) score += 15;
  if (RegExp(r'[0-9]').hasMatch(password)) score += 15;
  if (RegExp(r'[!@#$%^&*(),.?":{}<>_=\+\-\[\]\\\/]').hasMatch(password)) {
    score += 20;
  }
  return score.clamp(0, 100);
}

/// Validates a 15-char GSTIN.
String? gstinValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null; // optional
  final regex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
  if (!regex.hasMatch(value.trim().toUpperCase())) {
    return 'Enter a valid 15-character GSTIN';
  }
  return null;
}

/// Validates a 10-char PAN.
String? panValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null; // optional
  final regex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  if (!regex.hasMatch(value.trim().toUpperCase())) {
    return 'Enter a valid 10-character PAN';
  }
  return null;
}

/// Required-field validator.
String? requiredValidator(String? value, {String label = 'This field'}) {
  if (value == null || value.trim().isEmpty) return '$label is required';
  return null;
}

/// Indian phone number validator (tolerates +91 prefix).
String? phoneValidator(String? value) {
  if (value == null || value.trim().isEmpty) return null; // optional
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10) return null;
  if (digits.length == 12 && digits.startsWith('91')) return null;
  return 'Enter a valid 10-digit phone number';
}
