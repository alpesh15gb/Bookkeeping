/// App-wide constants — pagination defaults, debounce intervals, cache TTLs,
/// storage keys and numeric limits. Centralized so every module stays
/// consistent and tunable in one place.
library;

class AppConstants {
  AppConstants._();

  /// Default page size for server-side paginated lists.
  static const int defaultPageSize = 20;

  /// Page size options offered in the table footer.
  static const List<int> pageSizeOptions = [10, 20, 50, 100];

  /// Debounce delay (ms) applied to search-as-you-type inputs.
  static const int searchDebounceMs = 350;

  /// Default request dedup window (ms) for [CacheService].
  static const int dedupWindowMs = 500;

  /// Default in-memory cache TTL for list responses.
  static const Duration listCacheTtl = Duration(minutes: 2);

  /// Default in-memory cache TTL for single-record detail responses.
  static const Duration detailCacheTtl = Duration(minutes: 5);

  /// Max upload size in bytes (5 MB) — matches the backend logo limit.
  static const int maxUploadBytes = 5 * 1024 * 1024;

  /// Allowed upload MIME types.
  static const List<String> allowedImageTypes = [
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif',
    'image/webp',
  ];

  static const List<String> allowedDocumentTypes = [
    'application/pdf',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'application/json',
    'application/xml',
    'text/xml',
  ];

  /// Currency symbol used across the app.
  static const String currencySymbol = '₹';

  /// Indian state codes (first 2 digits of GSTIN) used by filters/POS fields.
  static const Map<String, String> indianStateCodes = {
    '01': 'Jammu & Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '25': 'Daman & Diu',
    '26': 'Dadra & Nagar Haveli & Daman & Diu',
    '27': 'Maharashtra',
    '28': 'Andhra Pradesh (Old)',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman & Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
  };
}

/// Storage key namespaces (avoids magic strings across services).
class StorageKeys {
  StorageKeys._();
  static const themeMode = 'apex_theme_mode';
  static const recentItems = 'apex_recent_items';
  static const favorites = 'apex_favorites';
  static const tablePrefs = 'apex_table_prefs';
}
