import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Color Tokens ───────────────────────────────────────────────
class AppColors {
  static bool isDark = false;

  // Brand
  static Color get brandNavy => isDark ? const Color(0xFF6B8CC7) : const Color(0xFF0F234A);
  static const Color brandNavyLight = Color(0xFF1A335C);
  static const Color brandNavyDark = Color(0xFF0A1A3A);

  // Primary action accent (Electric Indigo) — used for CTAs, active states on light bg
  static Color get brandIndigo => isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
  static Color get brandIndigoBg => isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF);
  static Color get brandIndigoBorder => isDark ? const Color(0xFF3730A3) : const Color(0xFFC7D2FE);

  // Accent (Gold — sidebar active state, FAB, highlights)
  static const Color goldAccent = Color(0xFFDCA035);
  static const Color goldAccentLight = Color(0xFFE8B94C);
  static const Color goldAccentDark = Color(0xFFB88728);
  static const Color accentBlue = Color(0xFF3B82F6);

  // Semantic amount colors (aliases for consistent financial display)
  static Color get amountPositive => isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  static Color get amountNegative => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get amountReceivable => isDark ? const Color(0xFFE8B94C) : const Color(0xFFD97706); // amber — money owed to you
  static Color get amountPayable => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);   // red — money you owe

  // Theme-aware backgrounds (getters return new instances so Flutter detects changes)
  static Color get bgLight => isDark ? const Color(0xFF0F1117) : const Color(0xFFF8FAFC);
  static Color get bgSurface => isDark ? const Color(0xFF1A1D26) : const Color(0xFFFFFFFF);
  static Color get bgSidebar => isDark ? const Color(0xFF0F1117) : const Color(0xFF0F234A);
  static Color get bgSidebarHover => isDark ? const Color(0xFF1E293B) : const Color(0xFF1A335C);
  static const Color bgSidebarActive = Color(0xFFD4A036);
  static Color get bgSidebarSection => isDark ? const Color(0xFF1E293B) : const Color(0xFF162A54);
  static const Color cardGradientTop = Color(0xFFDCA035);

  // Overlays
  static const Color overlayLight = Color(0x33000000);
  static const Color overlayDark = Color(0x99000000);

  // Theme-aware borders
  static Color get border => isDark ? const Color(0xFF2D3139) : const Color(0xFFE5E7EB);
  static Color get borderLight => isDark ? const Color(0xFF242831) : const Color(0xFFF0F2F7);
  static Color get borderInput => isDark ? const Color(0xFF3B404D) : const Color(0xFFD1D5DC);

  // Theme-aware text
  static Color get textPrimary => isDark ? const Color(0xFFECEFF4) : const Color(0xFF131620);
  static Color get textSecondary => isDark ? const Color(0xFFB2B9C8) : const Color(0xFF5F6572);
  static Color get textMuted => isDark ? const Color(0xFF818896) : const Color(0xFF9CA1AB);
  static const Color textWhite = Color(0xFFFFFFFF);
  static Color get textWhiteMuted => isDark ? const Color(0xFF818896) : const Color(0xFFB0B8CC);

  // Status
  static Color get success => isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  static Color get successBg => isDark ? const Color(0xFF14291D) : const Color(0xFFF0FDF4);
  static Color get error => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get errorBg => isDark ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2);
  static Color get warning => isDark ? const Color(0xFFE8B94C) : const Color(0xFFD97706);
  static Color get warningBg => isDark ? const Color(0xFF2D2418) : const Color(0xFFFFFBEB);
  static Color get info => isDark ? const Color(0xFF6B9FE8) : const Color(0xFF175CD3);
  static Color get infoBg => isDark ? const Color(0xFF1A2744) : const Color(0xFFEFF6FF);

  // Type
  static Color get typeGoods => isDark ? const Color(0xFFFFB74D) : const Color(0xFFE57C00);
  static Color get typeGoodsBg => isDark ? const Color(0xFF2D2418) : const Color(0xFFFFF3E0);
  static Color get typeService => isDark ? const Color(0xFF4DB6AC) : const Color(0xFF00897B);
  static Color get typeServiceBg => isDark ? const Color(0xFF14292D) : const Color(0xFFE0F2F1);
  static Color get typeCustomer => isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
  static Color get typeCustomerBg => isDark ? const Color(0xFF1A2744) : const Color(0xFFE3F2FD);
  static Color get typeVendor => isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
  static Color get typeVendorBg => isDark ? const Color(0xFF14291D) : const Color(0xFFE8F5E9);
  static Color get typeBoth => isDark ? const Color(0xFFCE93D8) : const Color(0xFF7B1FA2);
  static Color get typeBothBg => isDark ? const Color(0xFF2D1A33) : const Color(0xFFF3E5F5);
  static Color get typeDraft => isDark ? const Color(0xFF818896) : const Color(0xFF9CA1AB);
  static Color get typeDraftBg => isDark ? const Color(0xFF1E2130) : const Color(0xFFF2F2F4);
  static Color get typePaid => isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  static Color get typePaidBg => isDark ? const Color(0xFF14291D) : const Color(0xFFF0FDF4);
  static Color get typePending => isDark ? const Color(0xFFE8B94C) : const Color(0xFFD97706);
  static Color get typePendingBg => isDark ? const Color(0xFF2D2418) : const Color(0xFFFFFBEB);

  // Document status colors (accessibility-safe — no red/green dominance)
  // Kept as static const for backwards compatibility; prefer the theme-aware getters above
  static const Color statusDraftConst = Color(0xFF9CA1AB);
  static const Color statusDraftBgConst = Color(0xFFF2F2F4);
  static const Color statusPostedConst = Color(0xFF175CD3);
  static const Color statusPostedBgConst = Color(0xFFEFF6FF);
  static const Color statusPartiallyPaidConst = Color(0xFFD97706);
  static const Color statusPartiallyPaidBgConst = Color(0xFFFFFBEB);
  static const Color statusPaidConst = Color(0xFF16A34A);
  static const Color statusPaidBgConst = Color(0xFFF0FDF4);
  static const Color statusCancelledConst = Color(0xFFDC2626);
  static const Color statusCancelledBgConst = Color(0xFFFEF2F2);
  static const Color statusOverdueConst = Color(0xFFDC2626);
  static const Color statusOverdueBgConst = Color(0xFFFEF2F2);

  // Action tier colors
  static Color get actionSafe => isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  static Color get actionSafeBg => isDark ? const Color(0xFF14291D) : const Color(0xFFF0FDF4);
  static Color get actionWarning => isDark ? const Color(0xFFE8B94C) : const Color(0xFFD97706);
  static Color get actionWarningBg => isDark ? const Color(0xFF2D2418) : const Color(0xFFFFFBEB);
  static Color get actionDangerous => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get actionDangerousBg => isDark ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2);

  // Immutable / locked
  static Color get immutableBg => isDark ? const Color(0xFF1A1D26) : const Color(0xFFF9F9FB);
  static Color get immutableBorder => isDark ? const Color(0xFF2D3139) : const Color(0xFFE8E8EE);
  static Color get immutableText => isDark ? const Color(0xFF818896) : const Color(0xFF8B8F9B);

  // Stale / conflict
  static Color get staleBg => isDark ? const Color(0xFF2D2418) : const Color(0xFFFFF8E7);
  static Color get staleBorder => isDark ? const Color(0xFF5C3D0A) : const Color(0xFFFDE3B0);
  static Color get staleText => isDark ? const Color(0xFFE8B94C) : const Color(0xFFB76E00);

  // Dark-mode aware status colors
  static Color get statusDraft => isDark ? const Color(0xFF818896) : const Color(0xFF9CA1AB);
  static Color get statusDraftBg => isDark ? const Color(0xFF1E2130) : const Color(0xFFF2F2F4);
  static Color get statusPosted => isDark ? const Color(0xFF6B9FE8) : const Color(0xFF175CD3);
  static Color get statusPostedBg => isDark ? const Color(0xFF1A2744) : const Color(0xFFEFF6FF);
  static Color get statusPartiallyPaid => isDark ? const Color(0xFFE8B94C) : const Color(0xFFD97706);
  static Color get statusPartiallyPaidBg => isDark ? const Color(0xFF2D2418) : const Color(0xFFFFFBEB);
  static Color get statusPaid => isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
  static Color get statusPaidBg => isDark ? const Color(0xFF14291D) : const Color(0xFFF0FDF4);
  static Color get statusCancelled => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get statusCancelledBg => isDark ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2);
  static Color get statusOverdue => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get statusOverdueBg => isDark ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2);
}

// ─── Amount Formatting ──────────────────────────────────────────
class AmountFormat {
  /// Formats a monetary value consistently across the app.
  /// [amount] in the given currency, returns formatted string with symbol.
  /// Handles string inputs gracefully (common with JSON API responses).
  static String format(num amount, {String currency = 'INR'}) {
    final info = CurrencyInfo.fromCode(currency);
    final value = amount;
    final abs = value.abs();
    final formatted = '${info.symbol}${abs.toStringAsFixed(2)}';
    // Use minified digit grouping for INR, standard for others
    if (currency == 'INR') {
      final parts = formatted.split('.');
      final intPart = parts[0].substring(info.symbol.length);
      final grouped = _indianGroup(intPart);
      return value < 0 ? '-${info.symbol}$grouped.${parts[1]}' : '${info.symbol}$grouped.${parts[1]}';
    }
    final parts = formatted.split('.');
    final intPart = parts[0].substring(info.symbol.length);
    final grouped = _standardGroup(intPart);
    return value < 0 ? '-${info.symbol}$grouped.${parts[1]}' : '${info.symbol}$grouped.${parts[1]}';
  }

  /// Formats amount with currency code: "₹1,234.00 INR"
  static String formatWithCode(num amount, {String currency = 'INR'}) {
    return '${format(amount, currency: currency)} $currency';
  }

  /// Short format for compact displays: "₹1.2K", "-₹5Cr"
  static String short(num amount, {String currency = 'INR'}) {
    final info = CurrencyInfo.fromCode(currency);
    final abs = amount.abs();
    final prefix = amount < 0 ? '-${info.symbol}' : info.symbol;
    if (abs >= 10000000) return '$prefix${(abs / 10000000).toStringAsFixed(1)}Cr';
    if (abs >= 100000) return '$prefix${(abs / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000) return '$prefix${(abs / 1000).toStringAsFixed(1)}K';
    return '$prefix${abs.toStringAsFixed(0)}';
  }

  static String _indianGroup(String digits) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    final rest = digits.substring(0, digits.length - 3);
    final grouped = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && i % 2 == 0) {
        grouped.write(',');
      }
      grouped.write(rest[rest.length - 1 - i]);
    }
    final restGrouped = grouped.toString().split('').reversed.join();
    return '$restGrouped,$last3';
  }

  static String _standardGroup(String digits) {
    if (digits.length <= 3) return digits;
    final grouped = StringBuffer();
    for (var i = digits.length - 1; i >= 0; i--) {
      final pos = digits.length - 1 - i;
      if (pos > 0 && pos % 3 == 0) {
        grouped.write(',');
      }
      grouped.write(digits[i]);
    }
    return grouped.toString().split('').reversed.join();
  }

  }

/// Multi-currency support with 22+ countries
class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final String taxLabel; // GST, VAT, SST, etc.

  const CurrencyInfo(this.code, this.symbol, this.name, this.taxLabel);

  static const Map<String, CurrencyInfo> _currencies = {
    'INR': CurrencyInfo('INR', '₹', 'Indian Rupee', 'GST'),
    'USD': CurrencyInfo('USD', '\$', 'US Dollar', 'Sales Tax'),
    'EUR': CurrencyInfo('EUR', '€', 'Euro', 'VAT'),
    'GBP': CurrencyInfo('GBP', '£', 'British Pound', 'VAT'),
    'AED': CurrencyInfo('AED', 'د.إ', 'UAE Dirham', 'VAT'),
    'SAR': CurrencyInfo('SAR', '﷼', 'Saudi Riyal', 'VAT'),
    'SGD': CurrencyInfo('SGD', 'S\$', 'Singapore Dollar', 'GST'),
    'AUD': CurrencyInfo('AUD', 'A\$', 'Australian Dollar', 'GST'),
    'CAD': CurrencyInfo('CAD', 'C\$', 'Canadian Dollar', 'GST'),
    'MYR': CurrencyInfo('MYR', 'RM', 'Malaysian Ringgit', 'SST'),
    'THB': CurrencyInfo('THB', '฿', 'Thai Baht', 'VAT'),
    'IDR': CurrencyInfo('IDR', 'Rp', 'Indonesian Rupiah', 'VAT'),
    'PHP': CurrencyInfo('PHP', '₱', 'Philippine Peso', 'VAT'),
    'VND': CurrencyInfo('VND', '₫', 'Vietnamese Dong', 'VAT'),
    'ZAR': CurrencyInfo('ZAR', 'R', 'South African Rand', 'VAT'),
    'NZD': CurrencyInfo('NZD', 'NZ\$', 'New Zealand Dollar', 'GST'),
    'JPY': CurrencyInfo('JPY', '¥', 'Japanese Yen', 'Consumption Tax'),
    'CNY': CurrencyInfo('CNY', '¥', 'Chinese Yuan', 'VAT'),
    'KWD': CurrencyInfo('KWD', 'د.ك', 'Kuwaiti Dinar', 'VAT'),
    'QAR': CurrencyInfo('QAR', '﷼', 'Qatari Riyal', 'VAT'),
    'BHD': CurrencyInfo('BHD', 'ب.د', 'Bahraini Dinar', 'VAT'),
    'OMR': CurrencyInfo('OMR', '﷼', 'Omani Rial', 'VAT'),
  };

  static CurrencyInfo fromCode(String code) {
    return _currencies[code.toUpperCase()] ?? CurrencyInfo(code, code, code, 'Tax');
  }

  static List<CurrencyInfo> get all => _currencies.values.toList();

  static List<String> get codes => _currencies.keys.toList();
}

// ─── Spacing Tokens

// ─── Spacing Tokens ─────────────────────────────────────────────
class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 6;
  static const double sm = 8;
  static const double n = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 40;
  static const double section = 48;

  static const EdgeInsets pagePadding = EdgeInsets.all(24);
  static const EdgeInsets pagePaddingMobile = EdgeInsets.all(16);
  static const EdgeInsets cardPadding = EdgeInsets.all(16);
  static const EdgeInsets cardPaddingMobile = EdgeInsets.all(12);
  static const EdgeInsets inputPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 13);
  static const EdgeInsets inputPaddingCompact =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);
}

// ─── Radius Tokens ──────────────────────────────────────────────
class AppRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 20;
  static const double pill = 24;

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get input => BorderRadius.circular(sm);
  static BorderRadius get button => BorderRadius.circular(sm);
  static BorderRadius get badge => BorderRadius.circular(xs);
  static BorderRadius get dialog => BorderRadius.circular(xl);
  static BorderRadius get sidebar => BorderRadius.circular(md);
  static BorderRadius get pillBorder => BorderRadius.circular(pill);
}

// ─── Shadow Tokens ──────────────────────────────────────────────
class AppShadows {
  static const List<BoxShadow> glow = [
    BoxShadow(
      color: Color(0x1A0F234A),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x04000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Used for KPI/financial cards — subtle 2dp lift to signal importance
  static const List<BoxShadow> financialCard = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x05000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x0C000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x06000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> dialog = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> sidebar = [
    BoxShadow(
      color: Color(0x08000000),
      blurRadius: 12,
      offset: Offset(2, 0),
    ),
  ];
}

// ─── Typography Tokens ──────────────────────────────────────────
class AppTextStyles {
  // Display
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.2,
  );

  // Headings
  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  // Body
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
  );

  // Theme-aware text styles (getters so colors update when isDark changes)
  static TextStyle get bodySmall => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  static TextStyle get partyName => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle get dateText => TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.3,
  );

  static TextStyle get label => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.3,
    height: 1.4,
  );

  static TextStyle get labelSmall => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 0.5,
    height: 1.4,
  );

  // Numeric / tabular (no dynamic colors, keep const)
  static const TextStyle numeric = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle numericLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ─── Financial Amounts ────────────────────────────────────
  static const TextStyle amount = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.2,
  );

  static const TextStyle amountLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.3,
  );

  static const TextStyle amountNegative = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.2,
  );

  static const TextStyle amountSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.1,
  );

  static TextStyle get amountLabel => TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.5,
  );

  static TextStyle get caption => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.4,
  );

  // Button (no dynamic colors, keep const)
  static const TextStyle button = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.2,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    height: 1.2,
  );

  static TextStyle get overline => TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: AppColors.textMuted,
  );

  static const TextStyle tabLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
}

// ─── App Theme ──────────────────────────────────────────────────
class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bgLight,
      colorScheme: ColorScheme.light(
        primary: AppColors.brandNavy,
        secondary: AppColors.goldAccent,
        surface: AppColors.bgSurface,
        error: AppColors.error,
      ),
      fontFamily: GoogleFonts.inter().fontFamily,
      dividerTheme: DividerThemeData(
        color: AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bgSurface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goldAccent,
          foregroundColor: AppColors.textWhite,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
          ),
          textStyle: AppTextStyles.button,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.borderInput),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brandNavy,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.button,
          ),
          textStyle: AppTextStyles.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSurface,
        contentPadding: AppSpacing.inputPadding,
        border: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.brandNavy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: BorderSide(color: AppColors.borderLight),
        ),
        labelStyle: AppTextStyles.bodySmall,
        hintStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textMuted,
        ),
        errorStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.error,
          height: 1.3,
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.error)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.brandNavy,
          );
        }),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.bgSurface,
          contentPadding: AppSpacing.inputPadding,
          border: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: AppColors.borderInput),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: AppColors.borderInput),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: BorderSide(color: AppColors.brandNavy, width: 1.5),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.dialog,
        ),
        titleTextStyle: AppTextStyles.h2,
        contentTextStyle: AppTextStyles.body,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.goldAccent,
        foregroundColor: AppColors.textWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: AppColors.goldAccent,
        labelColor: AppColors.brandNavy,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: AppTextStyles.button,
        unselectedLabelStyle: AppTextStyles.button,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgSurface,
        selectedItemColor: AppColors.goldAccentDark,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: AppTextStyles.labelSmall,
        unselectedLabelStyle: AppTextStyles.labelSmall,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.goldAccent,
        linearTrackColor: AppColors.borderLight,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
    );
  }
}
