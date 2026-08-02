/// Invoice Totals Panel — GST-compliant breakdown with sticky positioning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../invoice_form_notifier.dart';
import '../invoice_form_state.dart';

class InvoiceTotalsPanel extends ConsumerWidget {
  const InvoiceTotalsPanel({
    super.key,
    required this.state,
    required this.notifier,
    required this.fmt,
    this.isSticky = false,
  });

  final InvoiceFormState state;
  final InvoiceFormNotifier notifier;
  final NumberFormatter fmt;
  final bool isSticky;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final panel = ApexCard(
      elevation: CardElevation.low,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Icon(Icons.receipt_long, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Totals',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              // GST Status badge
              _GstStatusBadge(
                isGstInclusive: state.isGstInclusive,
                isRcm: state.isRcm,
                supplyType: state.supplyType,
                originStateCode: '', // Would come from company settings
                posStateCode: state.posStateCode,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Subtotal section
          _TotalRow(
            label: 'Subtotal',
            value: fmt.currency(state.calculatedSubtotal),
            style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            valueStyle: textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontFamily: 'JetBrains Mono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),

          if (state.calculatedDiscountTotal > 0) ...[
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Discount',
              value: '-${fmt.currency(state.calculatedDiscountTotal)}',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              valueStyle: textTheme.bodyMedium?.copyWith(
                color: colors.error,
                fontFamily: 'JetBrains Mono',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],

          if (state.calculatedShippingCharges > 0) ...[
            const SizedBox(height: 8),
            _TotalRow(
              label: 'Shipping Charges',
              value: fmt.currency(state.calculatedShippingCharges),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              valueStyle: textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontFamily: 'JetBrains Mono',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],

          // Taxable Value
          const SizedBox(height: 16),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 16),

          _TotalRow(
            label: 'Taxable Value',
            value: fmt.currency(state.calculatedTaxableValue),
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
            valueStyle: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              fontFamily: 'JetBrains Mono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),

          // Tax Breakdown
          if (state.calculatedTaxBreakdown.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 16),
            Text(
              'Tax Breakdown',
              style: textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...state.calculatedTaxBreakdown.map(
              (tax) => _TaxBreakdownRow(tax: tax, fmt: fmt),
            ),
          ],

          // Round Off
          if (state.calculatedRoundOff != 0) ...[
            const SizedBox(height: 16),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 16),
            _TotalRow(
              label: 'Round Off',
              value: state.calculatedRoundOff > 0
                  ? '+${fmt.currency(state.calculatedRoundOff)}'
                  : fmt.currency(state.calculatedRoundOff),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              valueStyle: textTheme.bodyMedium?.copyWith(
                color: state.calculatedRoundOff > 0
                    ? colors.success
                    : colors.error,
                fontFamily: 'JetBrains Mono',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],

          // Grand Total
          const SizedBox(height: 16),
          Divider(color: colors.border, height: 1, thickness: 2),
          const SizedBox(height: 16),

          _TotalRow(
            label: 'Grand Total',
            value: fmt.currency(state.calculatedTotal),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
            valueStyle: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
              fontFamily: 'JetBrains Mono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),

          // Amount in words
          if (state.calculatedTotal > 0) ...[
            const SizedBox(height: 16),
            Divider(color: colors.border, height: 1),
            const SizedBox(height: 12),
            _AmountInWords(amount: state.calculatedTotal),
          ],
        ],
      ),
    );

    if (isSticky) {
      return Sticky(bottomOffset: 24, child: panel);
    }

    return panel;
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.style,
    required this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? style;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _TaxBreakdownRow extends StatelessWidget {
  const _TaxBreakdownRow({required this.tax, required this.fmt});

  final TaxBreakdownItem tax;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    // Determine tax type color
    Color taxColor;
    switch (tax.label) {
      case 'CGST':
        taxColor = Colors.blue;
        break;
      case 'SGST':
        taxColor = Colors.green;
        break;
      case 'IGST':
        taxColor = Colors.purple;
        break;
      case 'UTGST':
        taxColor = Colors.orange;
        break;
      case 'Cess':
        taxColor = Colors.red;
        break;
      default:
        taxColor = colors.textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: taxColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${tax.label} (${tax.rate.toStringAsFixed(tax.rate == tax.rate.roundToDouble() ? 0 : 2)}%)',
              style: textTheme.labelSmall?.copyWith(
                color: taxColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'On ${fmt.currency(tax.taxableValue)}',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            fmt.currency(tax.amount),
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _GstStatusBadge extends StatelessWidget {
  const _GstStatusBadge({
    required this.isGstInclusive,
    required this.isRcm,
    required this.supplyType,
    required this.originStateCode,
    required this.posStateCode,
  });

  final bool isGstInclusive;
  final bool isRcm;
  final String supplyType;
  final String originStateCode;
  final String posStateCode;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);

    String gstType = 'INTRA-STATE';
    if (supplyType == 'EXPORT') {
      gstType = 'EXPORT (Zero Rated)';
    } else if (supplyType == 'SEZ') {
      gstType = 'SEZ (Zero Rated)';
    } else if (originStateCode.isNotEmpty &&
        posStateCode.isNotEmpty &&
        originStateCode != posStateCode) {
      gstType = 'INTER-STATE';
    }

    final badges = <Widget>[
      if (isGstInclusive) _Badge(label: 'GST Inclusive', color: colors.primary),
      if (isRcm) _Badge(label: 'RCM', color: colors.warning),
      _Badge(label: gstType, color: colors.info),
    ];

    return Wrap(spacing: 6, children: badges);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        'Amount in words: $words Only',
        style: textTheme.bodySmall?.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _convertToWords(double amount) {
    // Simplified Indian numbering system conversion
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
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];

    final tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
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

/// Sticky widget that keeps child at bottom of viewport when scrolling
class Sticky extends StatefulWidget {
  const Sticky({super.key, required this.child, this.bottomOffset = 0});

  final Widget child;
  final double bottomOffset;

  @override
  State<Sticky> createState() => _StickyState();
}

class _StickyState extends State<Sticky> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        return false;
      },
      child: widget.child,
    );
  }
}
