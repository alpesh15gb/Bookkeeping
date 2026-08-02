/// Purchase Order Detail Summary — Totals, tax breakdown, and outstanding amounts.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/purchase_order.dart';

class PODetailSummary extends StatelessWidget {
  const PODetailSummary({super.key, required this.po, required this.fmt});

  final PurchaseOrder po;
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
                    fmt.currency(po.total),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Amount Received
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Amount Received', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  Text(
                    fmt.currency(po.amountReceived),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.success,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Outstanding
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Outstanding', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  Text(
                    fmt.currency(po.total - po.amountReceived),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: (po.total - po.amountReceived) > 0 ? colors.error : colors.success,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Divider(color: colors.border, height: 1),
              const SizedBox(height: 16),

              // Detailed Breakdown
              _DetailRow(label: 'Subtotal', value: fmt.currency(po.subtotal)),
              if (po.discountTotal > 0)
                _DetailRow(label: 'Discount', value: '-${fmt.currency(po.discountTotal)}', valueColor: colors.error),

              const SizedBox(height: 12),
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 12),

              _DetailRow(
                label: 'Taxable Value',
                value: fmt.currency(po.subtotal - po.discountTotal),
                isBold: true,
              ),

              // Tax Breakdown
              if (po.totalTax > 0) ...[
                const SizedBox(height: 12),
                ..._buildTaxBreakdown(context),
              ],

              const SizedBox(height: 12),
              Divider(color: colors.border, height: 1, thickness: 2),
              const SizedBox(height: 12),

              _DetailRow(
                label: 'Total',
                value: fmt.currency(po.total),
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
        if (po.total > 0) ...[
          const SizedBox(height: 16),
          _AmountInWords(amount: po.total),
        ],
      ],
    );
  }

  List<Widget> _buildTaxBreakdown(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    final breakdown = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('Tax Breakdown', style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textSecondary)),
      ),
    ];

    if (po.igstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'IGST',
        value: fmt.currency(po.igstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.purple,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (po.cgstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'CGST',
        value: fmt.currency(po.cgstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (po.sgstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'SGST',
        value: fmt.currency(po.sgstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (po.utgstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'UTGST',
        value: fmt.currency(po.utgstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.teal,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (po.cessAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'Cess',
        value: fmt.currency(po.cessAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.amber.shade800,
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
    this.valueColor,
    this.valueStyle,
  });

  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
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
                  color: valueColor ?? colors.textPrimary,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
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

    final words = _convertToWords(amount);

    return ApexCard(
      elevation: CardElevation.low,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Amount in words: $words Only',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _convertToWords(double amount) {
    final rupees = amount.floor();
    final paise = ((amount - rupees) * 100).round();

    final rupeeWords = _numberToWordsIndian(rupees);
    String result = 'Rupees $rupeeWords';

    if (paise > 0) {
      final paiseWords = _numberToWordsIndian(paise);
      result += ' and $paiseWords Paise';
    }

    return result;
  }

  String _numberToWordsIndian(int number) {
    if (number == 0) return 'Zero';

    final ones = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
      'Seventeen', 'Eighteen', 'Nineteen',
    ];

    final tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety',
    ];

    String convertHundreds(int n) {
      String result = '';
      if (n >= 100) {
        result += '${ones[n ~/ 100]} Hundred ';
        n %= 100;
      }
      if (n >= 20) {
        result += '${tens[n ~/ 10]} ';
        n %= 10;
      }
      if (n > 0) {
        result += '${ones[n]} ';
      }
      return result.trim();
    }

    String result = '';
    if (number >= 10000000) {
      result += '${convertHundreds(number ~/ 10000000)} Crore ';
      number %= 10000000;
    }
    if (number >= 100000) {
      result += '${convertHundreds(number ~/ 100000)} Lakh ';
      number %= 100000;
    }
    if (number >= 1000) {
      result += '${convertHundreds(number ~/ 1000)} Thousand ';
      number %= 1000;
    }
    if (number > 0) {
      result += convertHundreds(number);
    }
    return result.trim();
  }
}