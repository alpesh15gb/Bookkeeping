/// ApexBooks Design Tokens — Colors
///
/// Bridges the existing [ApexColors] theme extension with a unified token
/// system. All feature screens import from here — never hardcode a hex value
/// or import [ApexColors] directly outside the theme layer.
library;

export '../../theme/app_colors.dart'
    show apexColors, ApexColors, ApexSpacing, ApexRadius;
