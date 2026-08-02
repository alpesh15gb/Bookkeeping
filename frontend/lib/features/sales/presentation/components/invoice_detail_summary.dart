/// Invoice Detail Summary — Totals, GST breakdown, and outstanding amounts.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/invoice.dart';

class InvoiceDetailSummary extends StatelessWidget {
  const InvoiceDetailSummary({super.key, required this.invoice, required this.fmt});

  final Invoice invoice;
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
                    fmt.currency(invoice.total),
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

              // Outstanding
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Outstanding', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  Text(
                    fmt.currency(invoice.outstandingAmount),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: invoice.outstandingAmount > 0 ? colors.error : colors.success,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              if (invoice.outstandingAmount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  invoice.outstandingAmount == invoice.total
                      ? 'No payments received'
                      : 'Partially paid',
                  style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],

              const SizedBox(height: 20),

              Divider(color: colors.border, height: 1),
              const SizedBox(height: 16),

              // Detailed Breakdown
              _DetailRow(label: 'Subtotal', value: fmt.currency(_calcSubtotal())),
              if (_calcDiscountTotal() > 0)
                _DetailRow(label: 'Discount', value: '-${fmt.currency(_calcDiscountTotal())}', valueColor: colors.error),
              if (invoice.shippingCharges > 0)
                _DetailRow(label: 'Shipping', value: fmt.currency(invoice.shippingCharges)),

              const SizedBox(height: 12),
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 12),

              _DetailRow(
                label: 'Taxable Value',
                value: fmt.currency(_calcTaxableValue()),
                isBold: true,
              ),

              // Tax Breakdown
              if (invoice.lines.isNotEmpty) ...[
                const SizedBox(height: 12),
                ..._buildTaxBreakdown(context),
              ],

              if (invoice.roundOff != 0) ...[
                const SizedBox(height: 12),
                Divider(color: colors.border, height: 1),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Round Off',
                  value: invoice.roundOff > 0 ? '+${fmt.currency(invoice.roundOff)}' : fmt.currency(invoice.roundOff),
                  valueColor: invoice.roundOff > 0 ? colors.success : colors.error,
                ),
              ],

              const SizedBox(height: 12),
              Divider(color: colors.border, height: 1, thickness: 2),
              const SizedBox(height: 12),

              _DetailRow(
                label: 'Total',
                value: fmt.currency(invoice.total),
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
        if (invoice.total > 0) ...[
          const SizedBox(height: 16),
          _AmountInWords(amount: invoice.total),
        ],
      ],
    );
  }

  double _calcSubtotal() {
    return invoice.lines.fold(0, (sum, line) => sum + (line.quantity * line.rate));
  }

  double _calcDiscountTotal() {
    return invoice.lines.fold(0, (sum, line) => sum + (line.quantity * line.rate * (line.discount / 100)));
  }

  double _calcTaxableValue() {
    return _calcSubtotal() - _calcDiscountTotal() + invoice.shippingCharges;
  }

  List<Widget> _buildTaxBreakdown(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    // Calculate tax totals by type
    final Map<String, double> taxTotals = {};
    final Map<String, double> taxRates = {};

    for (final line in invoice.lines) {
        final taxable = (line.quantity * line.rate) - (line.quantity * line.rate * (line.discount / 100));
        final taxAmount = taxable * (line.gstRate / 100);

        if (taxAmount > 0) {
          String taxType;
          if (invoice.supplyType == 'EXPORT' || invoice.supplyType == 'SEZ') {
            taxType = 'Zero Rated';
          } else if (invoice.isRcm) {
            taxType = 'RCM GST';
          } else if (invoice.originStateCode?.isNotEmpty == true &&
              invoice.posStateCode.isNotEmpty &&
              invoice.originStateCode != invoice.posStateCode) {
            taxType = 'IGST';
          } else {
            taxType = 'CGST + SGST';
          }

          taxTotals[taxType] = (taxTotals[taxType] ?? 0) + taxAmount;
          taxRates[taxType] = line.gstRate;
        }
    }

    if (taxTotals.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text('Tax Breakdown', style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textSecondary)),
      ),
      ...taxTotals.entries.map((entry) {
        final rate = taxRates[entry.key] ?? 0;
        return _DetailRow(
          label: '${entry.key} (${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}%)',
          value: fmt.currency(entry.value),
          valueStyle: textTheme.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
            fontFamily: 'JetBrains Mono',
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
      }),
    ];
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