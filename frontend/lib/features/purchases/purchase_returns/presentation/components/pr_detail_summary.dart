/// Purchase Return Detail Summary — Totals and tax breakdown.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/purchase_return.dart';

class PRDetailSummary extends StatelessWidget {
  const PRDetailSummary({super.key, required this.pr, required this.fmt});

  final PurchaseReturn pr;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Text('Summary', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
        const SizedBox(height: 16),

        // Main Totals Card
        ApexCard(
          elevation: CardElevation.medium,
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            children: [
              // Grand Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  Text(
                    fmt.currency(pr.total),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Divider(color: colors.border, height: 1),

              const SizedBox(height: 16),

              // Subtotal
              _DetailRow(
                label: 'Subtotal',
                value: fmt.currency(pr.subtotal),
                valueStyle: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                  fontFamily: 'JetBrains Mono',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),

              const SizedBox(height: 12),

              // Tax Breakdown
              ..._buildTaxBreakdown(context, colors, textTheme),

              const SizedBox(height: 12),

              // Total
              _DetailRow(
                label: 'Total',
                value: fmt.currency(pr.total),
                isBold: true,
                valueStyle: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  fontFamily: 'JetBrains Mono',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        // Amount in Words
        if (pr.total > 0) ...[
          const SizedBox(height: 16),
          _AmountInWords(amount: pr.total),
        ],
      ],
    );
  }

  List<Widget> _buildTaxBreakdown(BuildContext context, ApexColors colors, TextTheme textTheme) {
    final breakdown = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('Tax Breakdown', style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textSecondary)),
      ),
    ];

    // Note: PurchaseReturn doesn't have detailed tax breakdown in the model
    // This would need to be added from the backend
    if (pr.totalTax > 0) {
      breakdown.add(_DetailRow(
        label: 'Total Tax',
        value: fmt.currency(pr.totalTax),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }

    return breakdown;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueStyle,
  });

  final String label;
  final String value;
  final bool isBold;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: valueStyle ??
                textTheme.bodyMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
                  fontFamily: 'JetBrains Mono',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

class _AmountInWords extends StatelessWidget {
  const _AmountInWords({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Amount in Words', style: textTheme.labelSmall?.copyWith(color: colors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            _numberToWords(amount),
            style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }

  String _numberToWords(double number) {
    if (number == 0) return 'Zero Only';

    final int integerPart = number.floor();
    final int decimalPart = ((number - integerPart) * 100).round();

    final words = _integerToWords(integerPart);

    if (decimalPart > 0) {
      return '$words and ${_integerToWords(decimalPart)} Paise Only';
    }
    return '$words Only';
  }

  String _integerToWords(int number) {
    if (number == 0) return 'Zero';

    final List<String> units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    final List<String> tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

    String convertHundreds(int num) {
      if (num < 20) return units[num];
      if (num < 100) return '${tens[num ~/ 10]}${num % 10 != 0 ? ' ${units[num % 10]}' : ''}';
      return '${units[num ~/ 100]} Hundred${num % 100 != 0 ? ' and ${convertHundreds(num % 100)}' : ''}';
    }

    if (number < 1000) return convertHundreds(number);
    if (number < 100000) return '${convertHundreds(number ~/ 1000)} Thousand${number % 1000 != 0 ? ' ${convertHundreds(number % 1000)}' : ''}';
    if (number < 10000000) return '${convertHundreds(number ~/ 100000)} Lakh${number % 100000 != 0 ? ' ${_integerToWords(number % 100000)}' : ''}';
    return '${convertHundreds(number ~/ 10000000)} Crore${number % 10000000 != 0 ? ' ${_integerToWords(number % 10000000)}' : ''}';
  }
}