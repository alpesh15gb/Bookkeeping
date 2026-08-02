/// Purchase Return Detail Lines — Read-only table with return quantities and amounts.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/purchase_return.dart';
import '../../models/purchase_return_line.dart';

class PRDetailLines extends StatelessWidget {
  const PRDetailLines({super.key, required this.pr, required this.fmt});

  final PurchaseReturn pr;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final lines = pr.lines;

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
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 44,
                columnSpacing: 12,
                horizontalMargin: 16,
                showCheckboxColumn: false,
                columns: [
                  DataColumn(label: _headerCell(context, '#', width: 50)),
                  DataColumn(label: _headerCell(context, 'Description', width: 280)),
                  DataColumn(label: _headerCell(context, 'HSN/SAC', width: 100)),
                  DataColumn(label: _headerCell(context, 'Qty Returned', width: 120), numeric: true),
                  DataColumn(label: _headerCell(context, 'Rate', width: 120), numeric: true),
                  DataColumn(label: _headerCell(context, 'Amount', width: 140), numeric: true),
                ],
                rows: List.generate(lines.length, (index) {
                  final line = lines[index];
                  final amount = line.quantityReturned * line.rate;

                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (index.isEven) return colors.surfaceMuted.withValues(alpha: 0.3);
                      return colors.surface;
                    }),
                    cells: [
                      DataCell(Center(child: Text('${index + 1}', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w500)))),
                      DataCell(_buildDescriptionCell(line, textTheme, colors)),
                      DataCell(Text(line.hsnSac.isNotEmpty ? line.hsnSac : '—', style: textTheme.bodyMedium?.copyWith(color: line.hsnSac.isNotEmpty ? colors.textPrimary : colors.textMuted, fontFamily: 'JetBrains Mono'))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.quantity(line.quantityReturned), style: textTheme.bodyMedium?.copyWith(color: colors.success, fontWeight: FontWeight.w500, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.currency(line.rate), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.currency(amount), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(BuildContext context, List<PurchaseReturnLine> lines) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final line = lines[index];
        final amount = line.quantityReturned * line.rate;

        return ApexCard(
          elevation: CardElevation.none,
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          line.productName?.isNotEmpty == true ? line.productName! : 'Item',
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _DetailItem(label: 'HSN/SAC', value: line.hsnSac.isNotEmpty ? line.hsnSac : '—', colors: colors, textTheme: textTheme),
                  _DetailItem(label: 'Returned', value: fmt.quantity(line.quantityReturned), colors: colors, textTheme: textTheme, valueColor: colors.success),
                  _DetailItem(label: 'Rate', value: fmt.currency(line.rate), colors: colors, textTheme: textTheme, isAmount: true),
                  _DetailItem(label: 'Amount', value: fmt.currency(amount), colors: colors, textTheme: textTheme, isAmount: true, isBold: true),
                  if (line.reason?.isNotEmpty == true)
                    _DetailItem(label: 'Reason', value: line.reason!, colors: colors, textTheme: textTheme),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDescriptionCell(PurchaseReturnLine line, TextTheme textTheme, ApexColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.productName?.isNotEmpty == true ? line.productName! : 'Item',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: colors.textPrimary),
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
            fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            fontFamily: isAmount ? 'JetBrains Mono' : null,
          ),
        ),
      ],
    );
  }
}