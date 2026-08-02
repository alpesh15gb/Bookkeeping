/// Purchase Order Detail Lines — Read-only table with receipt status per line.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/purchase_order.dart';
import '../../models/purchase_order_line.dart';

class PODetailLines extends StatelessWidget {
  const PODetailLines({super.key, required this.po, required this.fmt});

  final PurchaseOrder po;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final lines = po.lines;

    if (lines.isEmpty) {
      return ApexCard(
        elevation: CardElevation.low,
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.table_rows_outlined, size: 48, color: colors.textMuted),
              const SizedBox(height: 12),
              Text('No line items', style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (isMobile) {
      return _buildMobileCards(context, lines);
    }

    return ApexCard(
      elevation: CardElevation.low,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Line Items (${lines.length})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          // Table
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(colors.surfaceMuted),
                headingRowHeight: 48,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 52,
                columnSpacing: 12,
                horizontalMargin: 16,
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: _headerCell(context, '#', width: 50)),
                  DataColumn(label: _headerCell(context, 'Description', width: 280)),
                  DataColumn(label: _headerCell(context, 'HSN/SAC', width: 100)),
                  DataColumn(label: _headerCell(context, 'Qty', width: 80), numeric: true),
                  DataColumn(label: _headerCell(context, 'Unit', width: 80)),
                  DataColumn(label: _headerCell(context, 'Rate', width: 120), numeric: true),
                  DataColumn(label: _headerCell(context, 'Disc %', width: 100), numeric: true),
                  DataColumn(label: _headerCell(context, 'GST %', width: 90), numeric: true),
                  DataColumn(label: _headerCell(context, 'Received', width: 100), numeric: true),
                  DataColumn(label: _headerCell(context, 'Pending', width: 100), numeric: true),
                  DataColumn(label: _headerCell(context, 'Amount', width: 140), numeric: true),
                ],
                rows: List.generate(lines.length, (index) {
                  final line = lines[index];
                  final amount = line.quantity * line.rate * (1 - line.discount / 100);
                  final pending = line.quantity - line.quantityReceived;

                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (index.isEven) return colors.surfaceMuted.withValues(alpha: 0.3);
                      return colors.surface;
                    }),
                    cells: [
                      DataCell(Center(child: Text('${index + 1}', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w500)))),
                      DataCell(_buildDescriptionCell(line, textTheme, colors)),
                      DataCell(Text(line.hsnSac.isNotEmpty ? line.hsnSac : '—', style: textTheme.bodyMedium?.copyWith(color: line.hsnSac.isNotEmpty ? colors.textPrimary : colors.textMuted, fontFamily: 'JetBrains Mono'))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.decimal(line.quantity), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Text(line.unit.isNotEmpty ? line.unit : 'PCS', style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.currency(line.rate), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text('${line.discount.toStringAsFixed(2)}%', style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text('${line.gstRate.toStringAsFixed(line.gstRate == line.gstRate.roundToDouble() ? 0 : 2)}%', style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.decimal(line.quantityReceived), style: textTheme.bodyMedium?.copyWith(color: line.quantityReceived > 0 ? colors.success : colors.textSecondary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.decimal(pending), style: textTheme.bodyMedium?.copyWith(color: pending > 0 ? colors.error : colors.success, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.currency(amount), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                    ],
                  );
                }),
              ),
            ),
          ),

          // Tax Summary Footer
          _TaxSummaryFooter(po: po, fmt: fmt),
        ],
      ),
    );
  }

  Widget _buildMobileCards(BuildContext context, List<PurchaseOrderLine> lines) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: lines.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final line = lines[index];
            final amount = line.quantity * line.rate * (1 - line.discount / 100);
            final taxable = amount;
            final taxAmount = taxable * (line.gstRate / 100);
            final pending = line.quantity - line.quantityReceived;
            final receivedPercent = line.quantity > 0 ? (line.quantityReceived / line.quantity * 100).round() : 0;

            return ApexCard(
              elevation: CardElevation.low,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row with # and description
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: textTheme.labelSmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.productName?.isNotEmpty == true ? line.productName! : (line.description?.isNotEmpty == true ? line.description! : 'Item'),
                              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
                            ),
                            if (line.description?.isNotEmpty == true && line.productName != line.description)
                              Text(line.description!, style: textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Details grid
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _DetailItem(label: 'HSN/SAC', value: line.hsnSac.isNotEmpty ? line.hsnSac : '—', colors: colors, textTheme: textTheme),
                      _DetailItem(label: 'Qty Ordered', value: fmt.decimal(line.quantity), colors: colors, textTheme: textTheme),
                      _DetailItem(label: 'Received', value: fmt.decimal(line.quantityReceived), colors: colors, textTheme: textTheme, isAmount: true, valueColor: line.quantityReceived > 0 ? colors.success : colors.textMuted),
                      _DetailItem(label: 'Pending', value: fmt.decimal(pending), colors: colors, textTheme: textTheme, isAmount: true, valueColor: pending > 0 ? colors.error : colors.success),
                      _DetailItem(label: 'Received %', value: '$receivedPercent%', colors: colors, textTheme: textTheme, valueColor: receivedPercent == 100 ? colors.success : (receivedPercent > 0 ? colors.warning : colors.textMuted)),
                      _DetailItem(label: 'Unit', value: line.unit.isNotEmpty ? line.unit : 'PCS', colors: colors, textTheme: textTheme),
                      _DetailItem(label: 'Rate', value: fmt.currency(line.rate), colors: colors, textTheme: textTheme, isAmount: true),
                      _DetailItem(label: 'Disc %', value: '${line.discount.toStringAsFixed(2)}%', colors: colors, textTheme: textTheme),
                      _DetailItem(label: 'GST %', value: '${line.gstRate.toStringAsFixed(line.gstRate == line.gstRate.roundToDouble() ? 0 : 2)}%', colors: colors, textTheme: textTheme),
                      _DetailItem(label: 'Amount', value: fmt.currency(amount), colors: colors, textTheme: textTheme, isAmount: true, isBold: true),
                    ],
                  ),
                  if (taxAmount > 0) ...[
                    const SizedBox(height: 12),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: 8),
                    _TaxDetailRow(
                      label: _getTaxLabel(po, line),
                      rate: line.gstRate,
                      taxable: taxable,
                      amount: taxAmount,
                      fmt: fmt,
                      colors: colors,
                      textTheme: textTheme,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        _TaxSummaryFooter(po: po, fmt: fmt),
      ],
    );
  }

  Widget _buildDescriptionCell(PurchaseOrderLine line, TextTheme textTheme, ApexColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.productName?.isNotEmpty == true ? line.productName! : (line.description?.isNotEmpty == true ? line.description! : 'Item'),
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: colors.textPrimary),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        if (line.description?.isNotEmpty == true && line.productName != line.description)
          Text(
            line.description!,
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
      ],
    );
  }

  Widget _headerCell(BuildContext context, String label, {required double width}) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(label, style: textTheme.labelMedium?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600)),
    );
  }

  String _getTaxLabel(PurchaseOrder po, PurchaseOrderLine line) {
    if (po.igstAmount > 0 && po.cgstAmount == 0 && po.sgstAmount == 0) {
      return 'IGST';
    } else if (po.cgstAmount > 0 || po.sgstAmount > 0) {
      return 'CGST + SGST';
    } else if (po.utgstAmount > 0) {
      return 'UTGST';
    } else {
      return 'GST';
    }
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.label,
    required this.value,
    required this.colors,
    required this.textTheme,
    this.isAmount = false,
    this.isBold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final ApexColors colors;
  final TextTheme textTheme;
  final bool isAmount;
  final bool isBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: textTheme.labelSmall?.copyWith(color: colors.textMuted)),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: valueColor ?? colors.textPrimary,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            fontFamily: isAmount ? 'JetBrains Mono' : null,
            fontFeatures: isAmount ? const [FontFeature.tabularFigures()] : null,
          ),
        ),
      ],
    );
  }
}

class _TaxDetailRow extends StatelessWidget {
  const _TaxDetailRow({
    required this.label,
    required this.rate,
    required this.taxable,
    required this.amount,
    required this.fmt,
    required this.colors,
    required this.textTheme,
  });

  final String label;
  final double rate;
  final double taxable;
  final double amount;
  final NumberFormatter fmt;
  final ApexColors colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    Color taxColor;
    switch (label) {
      case 'IGST':
        taxColor = Colors.purple;
        break;
      case 'CGST + SGST':
        taxColor = Colors.blue;
        break;
      case 'UTGST':
        taxColor = Colors.teal;
        break;
      default:
        taxColor = colors.textSecondary;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: taxColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$label (${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}%)',
            style: textTheme.labelSmall?.copyWith(color: taxColor, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('On ${fmt.currency(taxable)}', style: textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
        ),
        Text(fmt.currency(amount), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}

class _TaxSummaryFooter extends StatelessWidget {
  const _TaxSummaryFooter({required this.po, required this.fmt});

  final PurchaseOrder po;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final hasTax = po.totalTax > 0;

    if (!hasTax) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tax Summary', style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textSecondary)),
          const SizedBox(height: 12),
          if (po.igstAmount > 0)
            _TaxSummaryRow(
              label: 'IGST',
              value: fmt.currency(po.igstAmount),
              color: Colors.purple,
              textTheme: textTheme,
              colors: colors,
              fmt: fmt,
            ),
          if (po.cgstAmount > 0)
            _TaxSummaryRow(
              label: 'CGST',
              value: fmt.currency(po.cgstAmount),
              color: Colors.blue,
              textTheme: textTheme,
              colors: colors,
              fmt: fmt,
            ),
          if (po.sgstAmount > 0)
            _TaxSummaryRow(
              label: 'SGST',
              value: fmt.currency(po.sgstAmount),
              color: Colors.blue,
              textTheme: textTheme,
              colors: colors,
              fmt: fmt,
            ),
          if (po.utgstAmount > 0)
            _TaxSummaryRow(
              label: 'UTGST',
              value: fmt.currency(po.utgstAmount),
              color: Colors.teal,
              textTheme: textTheme,
              colors: colors,
              fmt: fmt,
            ),
          if (po.cessAmount > 0)
            _TaxSummaryRow(
              label: 'Cess',
              value: fmt.currency(po.cessAmount),
              color: Colors.amber.shade800,
              textTheme: textTheme,
              colors: colors,
              fmt: fmt,
            ),
          const SizedBox(height: 8),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Total Tax', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
              const Spacer(),
              Text(
                fmt.currency(po.totalTax),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  fontFamily: 'JetBrains Mono',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaxSummaryRow extends StatelessWidget {
  const _TaxSummaryRow({
    required this.label,
    required this.value,
    required this.color,
    required this.textTheme,
    required this.colors,
    required this.fmt,
  });

  final String label;
  final String value;
  final Color color;
  final TextTheme textTheme;
  final ApexColors colors;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          const Spacer(),
          Text(
            value,
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