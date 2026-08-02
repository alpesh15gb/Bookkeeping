/// ApexBooks Design Language — spacing and radius tokens.
library;

/// Semantic spacing scale (8px base unit).
class ApexSpacing {
  const ApexSpacing._();

  static const double xs = 4.0;   // 0.5×
  static const double sm = 8.0;   // 1×
  static const double md = 16.0;  // 2×
  static const double lg = 24.0;  // 3×
  static const double xl = 32.0;  // 4×
  static const double xxl = 48.0; // 6×
}

/// Semantic border-radius scale.
class ApexRadius {
  const ApexRadius._();

  static const double sm = 4.0;
  static const double md = 8.0;
  static const double lg = 12.0;
  static const double xl = 16.0;
  static const double pill = 9999.0; // fully rounded
}