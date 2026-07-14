/// User preferences model for currency, date/number format and theme.
library;

import 'package:flutter/foundation.dart';

/// Application-level user preferences.
@immutable
class UserPreferences {
  const UserPreferences({
    this.currency = 'INR',
    this.dateFormat = 'dd MMM yyyy',
    this.numberFormat = 'en_IN',
    this.themeMode = 'system',
    this.timezone = 'Asia/Kolkata',
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    final display = json['display_settings'] is Map
        ? Map<String, dynamic>.from(json['display_settings'] as Map)
        : const <String, dynamic>{};
    return UserPreferences(
      currency: (json['currency'] as String?) ?? 'INR',
      dateFormat:
          (display['date_format'] as String?) ??
          (json['date_format'] as String?) ??
          'dd MMM yyyy',
      numberFormat:
          (display['number_format'] as String?) ??
          (json['number_format'] as String?) ??
          'en_IN',
      themeMode:
          (display['theme_mode'] as String?) ??
          (json['theme_mode'] as String?) ??
          'system',
      timezone:
          (display['timezone'] as String?) ??
          (json['timezone'] as String?) ??
          'Asia/Kolkata',
    );
  }

  final String currency;
  final String dateFormat;
  final String numberFormat;
  final String themeMode;
  final String timezone;

  Map<String, dynamic> toJson() => {
    'currency': currency,
    'display_settings': {
      'date_format': dateFormat,
      'number_format': numberFormat,
      'theme_mode': themeMode,
      'timezone': timezone,
    },
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserPreferences && runtimeType == other.runtimeType;

  @override
  int get hashCode =>
      Object.hash(currency, dateFormat, numberFormat, themeMode);
}

/// Supported currencies.
class CurrencyCodes {
  CurrencyCodes._();
  static const Map<String, String> labels = {'INR': 'Indian Rupee (₹)'};
}

/// Date format presets.
class DateFormatPresets {
  DateFormatPresets._();
  static const Map<String, String> labels = {
    'dd MMM yyyy': '15 Jul 2026',
    'dd/MM/yyyy': '15/07/2026',
    'MM/dd/yyyy': '07/15/2026',
    'yyyy-MM-dd': '2026-07-15',
    'dd-MM-yyyy': '15-07-2026',
    'MMMM dd, yyyy': 'July 15, 2026',
  };
}

/// Number format locales.
class NumberFormatPresets {
  NumberFormatPresets._();
  static const Map<String, String> labels = {
    'en_IN': '1,23,456.78 (Indian)',
    'en_US': '123,456.78 (US)',
    'en_EU': '123.456,78 (European)',
  };
}
