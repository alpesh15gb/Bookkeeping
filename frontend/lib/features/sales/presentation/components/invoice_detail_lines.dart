/// Invoice Detail Lines — Read-only table with expandable tax details.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/invoice.dart';
import '../../models/invoice_line.dart';

class InvoiceDetailLines extends StatelessWidget {
  const InvoiceDetailLines({super.key, required this.invoice, required this.fmt});

  final Invoice invoice;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final lines = invoice.lines;

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
                  DataColumn(label: _headerCell(context, 'Amount', width: 140), numeric: true),
                ],
                rows: List.generate(lines.length, (index) {
                  final line = lines[index];
                  final amount = line.quantity * line.rate * (1 - line.discount / 100);

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
                      DataCell(Text((line.unit?.isNotEmpty ?? false) ? line.unit! : 'PCS', style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.currency(line.rate), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text('${line.discount.toStringAsFixed(2)}%', style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text('${line.gstRate.toStringAsFixed(line.gstRate == line.gstRate.roundToDouble() ? 0 : 2)}%', style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.currency(amount), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                    ],
                  );
                }),
              ),
            ),
          ),

          // Tax Summary Footer
          _TaxSummaryFooter(invoice: invoice, fmt: fmt),
        ],
      ),
    );
  }

  Widget _buildMobileCards(BuildContext context, List<InvoiceLine> lines) {
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
                      _DetailItem(label: 'Qty', value: fmt.decimal(line.quantity), colors: colors, textTheme: textTheme),
                      _DetailItem(label: 'Unit', value: (line.unit?.isNotEmpty ?? false) ? line.unit! : 'PCS', colors: colors, textTheme: textTheme),
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
                      label: _getTaxLabel(invoice, line),
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
        _TaxSummaryFooter(invoice: invoice, fmt: fmt),
      ],
    );
  }

  Widget _buildDescriptionCell(InvoiceLine line, TextTheme textTheme, ApexColors colors) {
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

  String _getTaxLabel(Invoice invoice, InvoiceLine line) {
    if (invoice.supplyType == 'EXPORT' || invoice.supplyType == 'SEZ') {
      return 'Zero Rated GST';
    } else if (invoice.isRcm) {
      return 'RCM GST';
    } else if (invoice.originStateCode?.isNotEmpty == true &&
        invoice.posStateCode.isNotEmpty &&
        invoice.originStateCode != invoice.posStateCode) {
      return 'IGST';
    } else {
      return 'CGST + SGST';
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
  });

  final String label;
  final String value;
  final ApexColors colors;
  final TextTheme textTheme;
  final bool isAmount;
  final bool isBold;

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
            color: colors.textPrimary,
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
      case 'RCM GST':
        taxColor = colors.warning;
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
  const _TaxSummaryFooter({required this.invoice, required this.fmt});

  final Invoice invoice;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    // Calculate tax totals
    final Map<String, double> taxTotals = {};
    final Map<String, double> taxRates = {};

    if (invoice.lines.isNotEmpty) {
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
    }

    if (taxTotals.isEmpty) return const SizedBox.shrink();

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
          ...taxTotals.entries.map((entry) {
            final rate = taxRates[entry.key] ?? 0;
            Color taxColor;
            switch (entry.key) {
              case 'IGST':
                taxColor = Colors.purple;
                break;
              case 'CGST + SGST':
                taxColor = Colors.blue;
                break;
              case 'RCM GST':
                taxColor = colors.warning;
                break;
              default:
                taxColor = colors.textSecondary;
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: taxColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${entry.key} (${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}%)',
                      style: textTheme.labelSmall?.copyWith(color: taxColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Spacer(),
                  Text(
                    fmt.currency(entry.value),
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
          }),
          const SizedBox(height: 8),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Total Tax', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
              const Spacer(),
              Text(
                fmt.currency(taxTotals.values.fold<double>(0, (a, b) => a + b)),
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
