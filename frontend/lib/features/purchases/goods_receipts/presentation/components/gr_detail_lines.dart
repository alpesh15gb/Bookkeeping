/// Goods Receipt Detail Lines — Read-only table with received quantities.
library;

import 'package:flutter/material.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import '../../models/goods_receipt.dart';
import '../../models/goods_receipt_line.dart';

class GRDetailLines extends StatelessWidget {
  const GRDetailLines({super.key, required this.gr, required this.fmt});

  final GoodsReceipt gr;
  final NumberFormatter fmt;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final isMobile = ResponsiveLayout.isMobile(context);

    final lines = gr.lines;

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
                  DataColumn(label: _headerCell(context, 'Qty Ordered', width: 100), numeric: true),
                  DataColumn(label: _headerCell(context, 'Qty Received', width: 120), numeric: true),
                  DataColumn(label: _headerCell(context, 'Pending', width: 100), numeric: true),
                  DataColumn(label: _headerCell(context, 'Warehouse', width: 140)),
                ],
                rows: List.generate(lines.length, (index) {
                  final line = lines[index];
                  final pending = line.quantityOrdered - line.quantityReceived;

                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (index.isEven) return colors.surfaceMuted.withValues(alpha: 0.3);
                      return colors.surface;
                    }),
                    cells: [
                      DataCell(Center(child: Text('${index + 1}', style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w500)))),
                      DataCell(_buildDescriptionCell(line, textTheme, colors)),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.quantity(line.quantityOrdered), style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.quantity(line.quantityReceived), style: textTheme.bodyMedium?.copyWith(color: colors.success, fontWeight: FontWeight.w500, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Align(alignment: Alignment.centerRight, child: Text(fmt.quantity(pending), style: textTheme.bodyMedium?.copyWith(color: pending > 0 ? colors.danger : colors.success, fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()])))),
                      DataCell(Text(line.warehouseName?.isNotEmpty == true ? line.warehouseName! : '—', style: textTheme.bodyMedium?.copyWith(color: line.warehouseName?.isNotEmpty == true ? colors.textPrimary : colors.textMuted))),
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

  Widget _buildMobileCards(BuildContext context, List<GoodsReceiptLine> lines) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final line = lines[index];
        final pending = line.quantityOrdered - line.quantityReceived;

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
                  _DetailItem(label: 'Ordered', value: fmt.quantity(line.quantityOrdered), colors: colors, textTheme: textTheme),
                  _DetailItem(label: 'Received', value: fmt.quantity(line.quantityReceived), colors: colors, textTheme: textTheme, valueColor: colors.success),
                  _DetailItem(label: 'Pending', value: fmt.quantity(pending), colors: colors, textTheme: textTheme, valueColor: pending > 0 ? colors.danger : colors.success),
                  if (line.warehouseName?.isNotEmpty == true)
                    _DetailItem(label: 'Warehouse', value: line.warehouseName!, colors: colors, textTheme: textTheme),
                  if (line.lotNumber?.isNotEmpty == true)
                    _DetailItem(label: 'Lot', value: line.lotNumber!, colors: colors, textTheme: textTheme),
                  if (line.batchNumber?.isNotEmpty == true)
                    _DetailItem(label: 'Batch', value: line.batchNumber!, colors: colors, textTheme: textTheme),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDescriptionCell(GoodsReceiptLine line, TextTheme textTheme, ApexColors colors) {
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
    this.valueColor,
  });

  final String label;
  final String value;
  final ApexColors colors;
  final TextTheme textTheme;
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
          ),
        ),
      ],
    );
  }
}