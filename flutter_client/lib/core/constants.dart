import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Color Tokens ───────────────────────────────────────────────
class AppColors {
  // Brand
  static const Color brandNavy = Color(0xFF0F1B3D);
  static const Color brandNavyLight = Color(0xFF16244D);
  static const Color brandNavyDark = Color(0xFF0A1330);

  // Accent
  static const Color goldAccent = Color(0xFFD4A036);
  static const Color goldAccentLight = Color(0xFFE8B94C);
  static const Color goldAccentDark = Color(0xFFB88728);

  // Backgrounds
  static const Color bgLight = Color(0xFFF8F9FC);
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgSidebar = Color(0xFF0F1B3D);
  static const Color bgSidebarHover = Color(0xFF1A2D54);
  static const Color bgSidebarActive = Color(0xFFD4A036);

  // Borders
  static const Color border = Color(0xFFE2E5ED);
  static const Color borderLight = Color(0xFFF0F2F7);
  static const Color borderInput = Color(0xFFD1D5DC);

  // Text
  static const Color textPrimary = Color(0xFF131620);
  static const Color textSecondary = Color(0xFF5F6572);
  static const Color textMuted = Color(0xFF9CA1AB);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textWhiteMuted = Color(0xFFB0B8CC);

  // Status
  static const Color success = Color(0xFF0F973D);
  static const Color successBg = Color(0xFFE9F7EE);
  static const Color error = Color(0xFFD92D20);
  static const Color errorBg = Color(0xFFFDF2F2);
  static const Color warning = Color(0xFFDC6803);
  static const Color warningBg = Color(0xFFFFFAEB);
  static const Color info = Color(0xFF175CD3);
  static const Color infoBg = Color(0xFFEFF6FF);

  // Type
  static const Color typeGoods = Color(0xFFE57C00);
  static const Color typeGoodsBg = Color(0xFFFFF3E0);
  static const Color typeService = Color(0xFF00897B);
  static const Color typeServiceBg = Color(0xFFE0F2F1);
  static const Color typeCustomer = Color(0xFF1565C0);
  static const Color typeCustomerBg = Color(0xFFE3F2FD);
  static const Color typeVendor = Color(0xFF2E7D32);
  static const Color typeVendorBg = Color(0xFFE8F5E9);
  static const Color typeBoth = Color(0xFF7B1FA2);
  static const Color typeBothBg = Color(0xFFF3E5F5);
  static const Color typeDraft = Color(0xFF9CA1AB);
  static const Color typeDraftBg = Color(0xFFF2F2F4);
  static const Color typePaid = Color(0xFF0F973D);
  static const Color typePaidBg = Color(0xFFE9F7EE);
  static const Color typePending = Color(0xFFDC6803);
  static const Color typePendingBg = Color(0xFFFFFAEB);

  // Document status colors (accessibility-safe — no red/green dominance)
  static const Color statusDraft = Color(0xFF9CA1AB);
  static const Color statusDraftBg = Color(0xFFF2F2F4);
  static const Color statusPosted = Color(0xFF175CD3);
  static const Color statusPostedBg = Color(0xFFEFF6FF);
  static const Color statusPartiallyPaid = Color(0xFFDC6803);
  static const Color statusPartiallyPaidBg = Color(0xFFFFFAEB);
  static const Color statusPaid = Color(0xFF067647);
  static const Color statusPaidBg = Color(0xFFECFDF3);
  static const Color statusCancelled = Color(0xFFD92D20);
  static const Color statusCancelledBg = Color(0xFFFEF3F2);
  static const Color statusOverdue = Color(0xFFB42318);
  static const Color statusOverdueBg = Color(0xFFFFF0EE);

  // Action tier colors
  static const Color actionSafe = Color(0xFF067647);
  static const Color actionSafeBg = Color(0xFFECFDF3);
  static const Color actionWarning = Color(0xFFDC6803);
  static const Color actionWarningBg = Color(0xFFFFFAEB);
  static const Color actionDangerous = Color(0xFFD92D20);
  static const Color actionDangerousBg = Color(0xFFFEF3F2);

  // Immutable / locked
  static const Color immutableBg = Color(0xFFF9F9FB);
  static const Color immutableBorder = Color(0xFFE8E8EE);
  static const Color immutableText = Color(0xFF8B8F9B);

  // Stale / conflict
  static const Color staleBg = Color(0xFFFFF8E7);
  static const Color staleBorder = Color(0xFFFDE3B0);
  static const Color staleText = Color(0xFFB76E00);
}

// ─── Amount Formatting ──────────────────────────────────────────
class AmountFormat {
  /// Formats a monetary value consistently across the app.
  /// [amount] in rupees, returns "₹1,234.00" or "-₹1,234.00".
  static String format(num amount) {
    final abs = amount.abs();
    final formatted = '₹${abs.toStringAsFixed(2)}';
    // Use minified digit grouping: insert commas in Indian format
    // e.g. 1234567 → ₹12,34,567.00
    final parts = formatted.split('.');
    final intPart = parts[0].substring(1); // remove ₹
    final grouped = _indianGroup(intPart);
    return amount < 0 ? '-₹$grouped.${parts[1]}' : '₹$grouped.${parts[1]}';
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

  /// Short format for compact displays: "₹1.2K", "-₹5Cr"
  static String short(num amount) {
    final abs = amount.abs();
    final prefix = amount < 0 ? '-₹' : '₹';
    if (abs >= 10000000) return '${prefix}${(abs / 10000000).toStringAsFixed(1)}Cr';
    if (abs >= 100000) return '${prefix}${(abs / 100000).toStringAsFixed(1)}L';
    if (abs >= 1000) return '${prefix}${(abs / 1000).toStringAsFixed(1)}K';
    return '${prefix}${abs.toStringAsFixed(0)}';
  }
}

// ─── Spacing Tokens

// ─── Spacing Tokens ─────────────────────────────────────────────
class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 40;
  static const double section = 48;

  static const EdgeInsets pagePadding = EdgeInsets.all(24);
  static const EdgeInsets pagePaddingMobile = EdgeInsets.all(16);
  static const EdgeInsets cardPadding = EdgeInsets.all(20);
  static const EdgeInsets cardPaddingMobile = EdgeInsets.all(16);
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

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get input => BorderRadius.circular(sm);
  static BorderRadius get button => BorderRadius.circular(sm);
  static BorderRadius get badge => BorderRadius.circular(xs);
  static BorderRadius get dialog => BorderRadius.circular(xl);
  static BorderRadius get sidebar => BorderRadius.circular(md);
}

// ─── Shadow Tokens ──────────────────────────────────────────────
class AppShadows {
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
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.2,
  );

  // Headings
  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  // Body
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.45,
  );

  // Labels
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.3,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 0.5,
    height: 1.4,
  );

  // Numeric / tabular
  static const TextStyle numeric = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle numericLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ─── Financial Amounts ────────────────────────────────────
  // Neutral toned — never red/green for accessibility.
  // Sign is conveyed via prefix (-) not via color.

  /// Standard amount in ledgers, tables, line items.
  /// Right-aligned by default — use [TextAlign.right] in parent.
  static const TextStyle amount = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.2,
  );

  /// Large totals, dashboard metrics, invoice grand totals.
  static const TextStyle amountLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.3,
  );

  /// Negative/debit amounts. Uses the same neutral color as positive;
  /// the sign is always shown with a leading minus sign.
  static const TextStyle amountNegative = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.2,
  );

  /// Small amount for compact table cells, sub-ledgers.
  static const TextStyle amountSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.1,
  );

  /// Unit-only style for headers, column labels in ledgers.
  static const TextStyle amountLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    fontFeatures: [FontFeature.tabularFigures()],
    letterSpacing: 0.5,
  );

  // Caption / metadata
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
    height: 1.4,
  );

  // Button
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
      dividerTheme: const DividerThemeData(
        color: AppColors.borderLight,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
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
          side: const BorderSide(color: AppColors.border),
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
          side: const BorderSide(color: AppColors.borderInput),
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
          borderSide: const BorderSide(color: AppColors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        labelStyle: AppTextStyles.bodySmall,
        hintStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textMuted,
        ),
        errorStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.error,
          height: 1.3,
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
          if (states.contains(WidgetState.error)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            );
          }
          return const TextStyle(
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
            borderSide: const BorderSide(color: AppColors.borderInput),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: const BorderSide(color: AppColors.borderInput),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.input,
            borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.5),
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
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.goldAccent,
        labelColor: AppColors.brandNavy,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: AppTextStyles.button,
        unselectedLabelStyle: AppTextStyles.button,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgSurface,
        selectedItemColor: AppColors.goldAccentDark,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: AppTextStyles.labelSmall,
        unselectedLabelStyle: AppTextStyles.labelSmall,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
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
