/// Vendor Bill Detail Summary — Totals, tax breakdown, and outstanding amounts.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/vendor_bill.dart';

class BillDetailSummary extends StatelessWidget {
  const BillDetailSummary({super.key, required this.bill, required this.fmt});

  final VendorBill bill;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);
    final outstanding = bill.total - bill.amountPaid;

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
                    fmt.currency(bill.total),
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

              // Amount Paid
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Amount Paid', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                  Text(
                    fmt.currency(bill.amountPaid),
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
                    fmt.currency(outstanding),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: outstanding > 0 ? colors.error : colors.success,
                      fontFamily: 'JetBrains Mono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              if (outstanding > 0) ...[
                const SizedBox(height: 8),
                Text(
                  bill.amountPaid == 0
                      ? 'No payments recorded'
                      : 'Partially paid',
                  style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],

              const SizedBox(height: 20),

              Divider(color: colors.border, height: 1),
              const SizedBox(height: 16),

              // Detailed Breakdown
              _DetailRow(label: 'Subtotal', value: fmt.currency(bill.subtotal)),
              if (bill.discountTotal > 0)
                _DetailRow(label: 'Discount', value: '-${fmt.currency(bill.discountTotal)}', valueColor: colors.error),

              const SizedBox(height: 12),
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 12),

              _DetailRow(
                label: 'Taxable Value',
                value: fmt.currency(bill.subtotal - bill.discountTotal),
                isBold: true,
              ),

              // Tax Breakdown
              if (bill.totalTax > 0) ...[
                const SizedBox(height: 12),
                ..._buildTaxBreakdown(context),
              ],

              if (bill.roundOff != 0) ...[
                const SizedBox(height: 12),
                Divider(color: colors.border, height: 1),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'Round Off',
                  value: bill.roundOff > 0 ? '+${fmt.currency(bill.roundOff)}' : fmt.currency(bill.roundOff),
                  valueColor: bill.roundOff > 0 ? colors.success : colors.error,
                ),
              ],

              if (bill.tdsAmount > 0) ...[
                const SizedBox(height: 12),
                Divider(color: colors.border, height: 1),
                const SizedBox(height: 12),
                _DetailRow(
                  label: 'TDS Deducted',
                  value: '-${fmt.currency(bill.tdsAmount)}',
                  valueColor: colors.warning,
                ),
              ],

              const SizedBox(height: 12),
              Divider(color: colors.border, height: 1, thickness: 2),
              const SizedBox(height: 12),

              _DetailRow(
                label: 'Total',
                value: fmt.currency(bill.total),
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
        if (bill.total > 0) ...[
          const SizedBox(height: 16),
          _AmountInWords(amount: bill.total),
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

    if (bill.igstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'IGST',
        value: fmt.currency(bill.igstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.purple,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (bill.cgstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'CGST',
        value: fmt.currency(bill.cgstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (bill.sgstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'SGST',
        value: fmt.currency(bill.sgstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.blue,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (bill.utgstAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'UTGST',
        value: fmt.currency(bill.utgstAmount),
        valueStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.teal,
          fontWeight: FontWeight.w600,
          fontFamily: 'JetBrains Mono',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
    }
    if (bill.cessAmount > 0) {
      breakdown.add(_DetailRow(
        label: 'Cess',
        value: fmt.currency(bill.cessAmount),
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