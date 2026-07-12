/// Typography for financial data — JetBrains Mono with tabular-nums.
/// DESIGN.md mandates JetBrains Mono for "invoice amounts, ledger entries,
/// GST calculations, account balances" to prevent alignment jitter.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Returns a TextStyle using JetBrains Mono with tabular figures.
/// Use this for any financial number display to prevent digit-width jitter.
TextStyle financialTextStyle(
  BuildContext context, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// A convenience widget that renders a financial amount in JetBrains Mono.
class MonetaryText extends StatelessWidget {
  const MonetaryText({
    super.key,
    required this.value,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w500,
    this.color,
    this.textAlign,
  });

  final String value;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      textAlign: textAlign,
      style: financialTextStyle(
        context,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }
}
