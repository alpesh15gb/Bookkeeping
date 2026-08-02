/// ApexBooks Design Tokens — Spacing Scale
///
/// Consistent spacing scale based on 4px base unit.
/// All components should use these tokens instead of hardcoded values.
// ignore_for_file: constant_identifier_names
library;

/// Re-export the semantic spacing/radius classes so both the legacy
/// `core/theme` and the design-system import paths resolve to the same
/// declarations (avoids ambiguous-import errors when a file imports both).
export '../../theme/spacing.dart' show ApexSpacing, ApexRadius;

/// Base spacing unit: 4px
const double _base = 4.0;

/// Spacing scale for consistent layout.
/// All values are compile-time constants.
const double ApexSpacing_xs = _base; // 4px
const double ApexSpacing_sm = _base * 2; // 8px
const double ApexSpacing_md = _base * 3; // 12px
const double ApexSpacing_lg = _base * 4; // 16px
const double ApexSpacing_xl = _base * 5; // 20px
const double ApexSpacing_xxl = _base * 6; // 24px
const double ApexSpacing_xxxl = _base * 8; // 32px

// ───── Component-specific ─────
const double ApexSpacing_cardPadding = ApexSpacing_lg; // 16px
const double ApexSpacing_cardPaddingLarge = ApexSpacing_xxl; // 24px
const double ApexSpacing_sectionGap = ApexSpacing_xxl; // 24px
const double ApexSpacing_fieldGap = ApexSpacing_md; // 12px
const double ApexSpacing_fieldLabelGap = 6; // 6px
const double ApexSpacing_buttonGap = ApexSpacing_sm; // 8px
const double ApexSpacing_iconGap = ApexSpacing_sm; // 8px
const double ApexSpacing_listItemGap = ApexSpacing_lg; // 16px
const double ApexSpacing_pagePadding = ApexSpacing_lg; // 16px
const double ApexSpacing_pagePaddingLarge = ApexSpacing_xxl; // 24px
const double ApexSpacing_modalPadding = ApexSpacing_xxl; // 24px
const double ApexSpacing_tableCellPadding = ApexSpacing_md; // 12px
const double ApexSpacing_tableHeaderHeight = 48.0;
const double ApexSpacing_tableRowHeight = 52.0;

// ───── Responsive breakpoints ─────
const double ApexSpacing_mobileBreakpoint = 600;
const double ApexSpacing_tabletBreakpoint = 1024;
const double ApexSpacing_desktopBreakpoint = 1440;

/// Radius scale for consistent rounded corners.
/// All values are compile-time constants.
const double ApexRadius_none = 0;
const double ApexRadius_xs = 4;
const double ApexRadius_sm = 6;
const double ApexRadius_md = 8;
const double ApexRadius_lg = 10;
const double ApexRadius_xl = 12;
const double ApexRadius_xxl = 16;
const double ApexRadius_full = 9999;
const double ApexRadius_pill = 9999;