/// Invoice Lines Table — Spreadsheet-like editable table with keyboard navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/permissions/permissions.dart';
import '../invoice_form_notifier.dart';
import '../invoice_form_state.dart';
import '../../models/invoice_line.dart';

class InvoiceLinesTable extends ConsumerStatefulWidget {
  const InvoiceLinesTable({
    super.key,
    required this.state,
    required this.notifier,
    required this.fmt,
  });

  final InvoiceFormState state;
  final InvoiceFormNotifier notifier;
  final NumberFormatter fmt;

  @override
  ConsumerState<InvoiceLinesTable> createState() => _InvoiceLinesTableState();
}

class _InvoiceLinesTableState extends ConsumerState<InvoiceLinesTable> {
  late final List<TextEditingController> _qtyControllers;
  late final List<TextEditingController> _rateControllers;
  late final List<TextEditingController> _discountControllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  @override
  void didUpdateWidget(covariant InvoiceLinesTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.lines.length != oldWidget.state.lines.length) {
      _initControllers();
    }
  }

  void _initControllers() {
    // Dispose old controllers
    for (final c in _qtyControllers) {
      c.dispose();
    }
    for (final c in _rateControllers) {
      c.dispose();
    }
    for (final c in _discountControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }

    _qtyControllers = List.generate(
      widget.state.lines.length,
      (i) => TextEditingController(text: widget.state.lines[i].quantity.toString()),
    );
    _rateControllers = List.generate(
      widget.state.lines.length,
      (i) => TextEditingController(text: widget.state.lines[i].rate.toString()),
    );
    _discountControllers = List.generate(
      widget.state.lines.length,
      (i) => TextEditingController(text: widget.state.lines[i].discount.toString()),
    );
    _focusNodes = List.generate(widget.state.lines.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _qtyControllers) {
      c.dispose();
    }
    for (final c in _rateControllers) {
      c.dispose();
    }
    for (final c in _discountControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;
    final state = widget.state;
    final notifier = widget.notifier;
    final fmt = widget.fmt;

    if (isMobile) {
      return _buildMobileCards(context, state, notifier, fmt, colors, textTheme);
    }

    return ApexCard(
      elevation: CardElevation.low,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Table Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Invoice Lines', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary)),
                const Spacer(),
                PermissionGate(
                  permission: Permissions.productCreate,
                  child: ApexTertiaryButton(
                    icon: Icons.add,
                    label: 'Add Line',
                    onPressed: () => notifier.addLine(),
                    tooltip: 'Add new line (Ctrl+Enter)',
                  ),
                ),
              ],
            ),
          ),

          // Table
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStatePropertyAll(colors.surfaceMuted),
                      headingRowHeight: 48,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 52,
                      columnSpacing: 12,
                      horizontalMargin: 16,
                      showCheckboxColumn: false,
                      columns: [
                        DataColumn(label: _headerCell('#', width: 50)),
                        DataColumn(label: _headerCell('Product / Description', width: 280)),
                        DataColumn(label: _headerCell('HSN/SAC', width: 100), numeric: false),
                        DataColumn(label: _headerCell('Qty', width: 80), numeric: true),
                        DataColumn(label: _headerCell('Unit', width: 80)),
                        DataColumn(label: _headerCell('Rate', width: 120), numeric: true),
                        DataColumn(label: _headerCell('Disc %', width: 100), numeric: true),
                        DataColumn(label: _headerCell('GST %', width: 90), numeric: true),
                        DataColumn(label: _headerCell('Amount', width: 140), numeric: true),
                        DataColumn(label: _headerCell('Actions', width: 100)),
                      ],
                      rows: List.generate(state.lines.length, (index) {
                        final line = state.lines[index];
                        final lineCalc = index < state.lineCalculations.length ? state.lineCalculations[index] : null;
                        final isEditing = state.editingLineIndex == index;

                        return DataRow(
                          color: WidgetStateProperty.resolveWith((states) {
                            if (isEditing) return colors.primaryContainer.withValues(alpha: 0.2);
                            if (index.isEven) return colors.surfaceMuted.withValues(alpha: 0.3);
                            return colors.surface;
                          }),
                          cells: [
                            // Row Number
                            DataCell(
                              Center(
                                child: Text(
                                  '${index + 1}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            // Product / Description
                            DataCell(
                              _ProductCell(
                                line: line,
                                index: index,
                                isEditing: isEditing,
                                notifier: notifier,
                                fmt: fmt,
                                onTap: () => notifier.startLineEdit(index),
                              ),
                            ),
                            // HSN/SAC
                            DataCell(
                              _HsnCell(
                                line: line,
                                index: index,
                                isEditing: isEditing,
                                notifier: notifier,
                              ),
                            ),
                            // Quantity
                            DataCell(
                              _NumericCell(
                                controller: _qtyControllers[index],
                                focusNode: _focusNodes[index],
                                value: line.quantity,
                                onChanged: (v) => notifier.updateLineField(index, 'quantity', v),
                                onSubmitted: (_) => _moveFocus(index, 1),
                                format: (v) => fmt.decimal(v),
                              ),
                            ),
                            // Unit
                            DataCell(
                              _UnitCell(
                                line: line,
                                index: index,
                                isEditing: isEditing,
                                notifier: notifier,
                              ),
                            ),
                            // Rate
                            DataCell(
                              _NumericCell(
                                controller: _rateControllers[index],
                                focusNode: _focusNodes[index],
                                value: line.rate,
                                onChanged: (v) => notifier.updateLineField(index, 'rate', v),
                                onSubmitted: (_) => _moveFocus(index, 2),
                                format: (v) => fmt.currency(v),
                              ),
                            ),
                            // Discount %
                            DataCell(
                              _NumericCell(
                                controller: _discountControllers[index],
                                focusNode: _focusNodes[index],
                                value: line.discount,
                                onChanged: (v) => notifier.updateLineField(index, 'discount', v),
                                onSubmitted: (_) => _moveFocus(index, 3),
                                format: (v) => '${v.toStringAsFixed(2)}%',
                              ),
                            ),
                            // GST %
                            DataCell(
                              _GstRateCell(
                                line: line,
                                index: index,
                                isEditing: isEditing,
                                notifier: notifier,
                              ),
                            ),
                            // Amount
                            DataCell(
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  lineCalc != null
                                      ? fmt.currency(lineCalc.total)
                                      : fmt.currency(line.quantity * line.rate * (1 - line.discount / 100)),
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'JetBrains Mono',
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                            // Actions
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isEditing)
                                    ApexIconButton(
                                      icon: Icons.check,
                                      onPressed: () => notifier.cancelLineEdit(),
                                      tooltip: 'Done editing',
                                      size: 36,
                                    )
                                  else
                                    ApexIconButton(
                                      icon: Icons.edit,
                                      onPressed: () => notifier.startLineEdit(index),
                                      tooltip: 'Edit line',
                                      size: 36,
                                    ),
                                  ApexIconButton(
                                    icon: Icons.copy,
                                    onPressed: () => notifier.duplicateLine(index),
                                    tooltip: 'Duplicate line',
                                    size: 36,
                                  ),
                                  ApexIconButton(
                                    icon: Icons.delete_outline,
                                    onPressed: state.lines.length > 1
                                        ? () => notifier.removeLine(index)
                                        : null,
                                    tooltip: 'Remove line',
                                    size: 36,
                                    isDestructive: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                );
              },
            ),
          ),

          // Empty state message
          if (state.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.table_rows_outlined, size: 48, color: colors.textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No lines added yet',
                      style: textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    PermissionGate(
                      permission: Permissions.productCreate,
                      child: ApexPrimaryButton(
                        icon: Icons.add,
                        label: 'Add First Line',
                        onPressed: () => notifier.addLine(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(
    BuildContext context,
    InvoiceFormState state,
    InvoiceFormNotifier notifier,
    NumberFormatter fmt,
    ApexColors colors,
    TextTheme textTheme,
  ) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('Invoice Lines', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              PermissionGate(
                permission: Permissions.productCreate,
                child: ApexTertiaryButton(
                  icon: Icons.add,
                  label: 'Add Line',
                  onPressed: () => notifier.addLine(),
                ),
              ),
            ],
          ),
        ),
        // Cards
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: state.lines.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final line = state.lines[index];
            final lineCalc = index < state.lineCalculations.length ? state.lineCalculations[index] : null;
            final isEditing = state.editingLineIndex == index;

            return ApexCard(
              elevation: CardElevation.low,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product selector
                  _ProductCell(
                    line: line,
                    index: index,
                    isEditing: isEditing,
                    notifier: notifier,
                    fmt: fmt,
                    onTap: () => notifier.startLineEdit(index),
                  ),
                  const SizedBox(height: 12),
                  // Quantity, Rate, Discount in row
                  Row(
                    children: [
                      Expanded(
                        child: _buildMobileField(
                          label: 'Qty',
                          controller: _qtyControllers[index],
                          focusNode: _focusNodes[index],
                          value: line.quantity,
                          onChanged: (v) => notifier.updateLineField(index, 'quantity', v),
                          format: (v) => fmt.decimal(v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMobileField(
                          label: 'Rate',
                          controller: _rateControllers[index],
                          focusNode: _focusNodes[index],
                          value: line.rate,
                          onChanged: (v) => notifier.updateLineField(index, 'rate', v),
                          format: (v) => fmt.currency(v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMobileField(
                          label: 'Disc %',
                          controller: _discountControllers[index],
                          focusNode: _focusNodes[index],
                          value: line.discount,
                          onChanged: (v) => notifier.updateLineField(index, 'discount', v),
                          format: (v) => '${v.toStringAsFixed(2)}%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // HSN, Unit, GST
                  Row(
                    children: [
                      Expanded(child: _HsnCell(line: line, index: index, isEditing: isEditing, notifier: notifier)),
                      const SizedBox(width: 12),
                      Expanded(child: _UnitCell(line: line, index: index, isEditing: isEditing, notifier: notifier)),
                      const SizedBox(width: 12),
                      Expanded(child: _GstRateCell(line: line, index: index, isEditing: isEditing, notifier: notifier)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Amount and actions
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Amount: ${fmt.currency(lineCalc?.total ?? (line.quantity * line.rate * (1 - line.discount / 100)))}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isEditing)
                            ApexIconButton(icon: Icons.check, onPressed: () => notifier.cancelLineEdit(), size: 36)
                          else
                            ApexIconButton(icon: Icons.edit, onPressed: () => notifier.startLineEdit(index), size: 36),
                          ApexIconButton(icon: Icons.copy, onPressed: () => notifier.duplicateLine(index), size: 36),
                          ApexIconButton(
                            icon: Icons.delete_outline,
                            onPressed: state.lines.length > 1 ? () => notifier.removeLine(index) : null,
                            isDestructive: true,
                            size: 36,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMobileField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required double value,
    required ValueChanged<double> onChanged,
    required String Function(double) format,
  }) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelSmall?.copyWith(color: colors.textSecondary)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
          style: textTheme.bodyMedium?.copyWith(fontFamily: 'JetBrains Mono'),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary, width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String label, {required double width}) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: textTheme.labelMedium?.copyWith(color: colors.textSecondary, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _moveFocus(int currentIndex, int fieldOffset) {
    // fieldOffset: 0=qty, 1=rate, 2=discount, 3=next line qty
    const fieldsPerLine = 3;
    final targetField = (currentIndex * fieldsPerLine) + fieldOffset;
    if (targetField < _focusNodes.length) {
      _focusNodes[targetField].requestFocus();
    } else if (currentIndex + 1 < _focusNodes.length) {
      _focusNodes[(currentIndex + 1) * fieldsPerLine].requestFocus();
    }
  }
}

/// Product cell with search and selection
class _ProductCell extends ConsumerWidget {
  const _ProductCell({
    required this.line,
    required this.index,
    required this.isEditing,
    required this.notifier,
    required this.fmt,
    this.onTap,
  });

  final InvoiceLine line;
  final int index;
  final bool isEditing;
  final InvoiceFormNotifier notifier;
  final NumberFormatter fmt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    final productState = ref.watch(productControllerProvider);
    final products = switch (productState) {
      ListData<Product>(:final paged) => paged.items,
      _ => const <Product>[],
    };

    if (isEditing) {
      return _ProductSearchField(
        line: line,
        index: index,
        notifier: notifier,
        products: products,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              line.productName?.isNotEmpty == true ? line.productName! : (line.description?.isNotEmpty == true ? line.description! : 'No product selected'),
              style: textTheme.bodyMedium?.copyWith(
                color: line.productName?.isNotEmpty == true ? colors.textPrimary : colors.textMuted,
                fontWeight: FontWeight.w500,
              ),
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
        ),
      ),
    );
  }
}

class _ProductSearchField extends ConsumerWidget {
  const _ProductSearchField({
    required this.line,
    required this.index,
    required this.notifier,
    required this.products,
  });

  final InvoiceLine line;
  final int index;
  final InvoiceFormNotifier notifier;
  final List<Product> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ApexSearchField<Product>(
      label: '',
      suggestions: products,
      value: line.productId.isNotEmpty
          ? products.firstWhere((p) => p.id == line.productId, orElse: () => products.first)
          : null,
      hint: 'Search product...',
      prefixIcon: Icons.search,
      getLabel: (p) => p.name,
      getSubtitle: (p) => '${p.hsnSac} • ${p.salesPrice > 0 ? '₹${p.salesPrice.toStringAsFixed(2)}' : ''}',
      onSelected: (product) {
        if (product != null) {
          notifier.applyProductToLine(index, product);
        }
      },
    );
  }
}

/// HSN/SAC cell
class _HsnCell extends StatelessWidget {
  const _HsnCell({
    required this.line,
    required this.index,
    required this.isEditing,
    required this.notifier,
  });

  final InvoiceLine line;
  final int index;
  final bool isEditing;
  final InvoiceFormNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    if (isEditing) {
      return SizedBox(
        width: 100,
        child: TextFormField(
          initialValue: line.hsnSac,
          style: textTheme.bodyMedium?.copyWith(fontFamily: 'JetBrains Mono'),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.primary, width: 2)),
          ),
          onChanged: (v) => notifier.updateLineField(index, 'hsnSac', v),
        ),
      );
    }

    return Text(
      line.hsnSac.isNotEmpty ? line.hsnSac : '—',
      style: textTheme.bodyMedium?.copyWith(
        color: line.hsnSac.isNotEmpty ? colors.textPrimary : colors.textMuted,
        fontFamily: 'JetBrains Mono',
      ),
    );
  }
}

/// Unit cell
class _UnitCell extends StatelessWidget {
  const _UnitCell({
    required this.line,
    required this.index,
    required this.isEditing,
    required this.notifier,
  });

  final InvoiceLine line;
  final int index;
  final bool isEditing;
  final InvoiceFormNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    const units = ['PCS', 'KG', 'MTR', 'LTR', 'BOX', 'SET', 'ROLL', 'SQFT', 'CFT', 'NOS'];

    if (isEditing) {
      return SizedBox(
        width: 80,
        child: DropdownButtonFormField<String>(
          initialValue: line.unit?.isNotEmpty == true ? line.unit : 'PCS',
          items: units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
          onChanged: (v) => v != null ? notifier.updateLineField(index, 'unit', v) : null,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.primary, width: 2)),
          ),
          style: textTheme.bodyMedium,
          isExpanded: true,
        ),
      );
    }

    return Text(
      line.unit?.isNotEmpty == true ? line.unit! : 'PCS',
      style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
    );
  }
}

/// GST Rate cell
class _GstRateCell extends StatelessWidget {
  const _GstRateCell({
    required this.line,
    required this.index,
    required this.isEditing,
    required this.notifier,
  });

  final InvoiceLine line;
  final int index;
  final bool isEditing;
  final InvoiceFormNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;
    const gstRates = [0, 0.25, 3, 5, 12, 18, 28];

    if (isEditing) {
      return SizedBox(
        width: 90,
        child: DropdownButtonFormField<double>(
          initialValue: line.gstRate,
          items: gstRates.map((r) => DropdownMenuItem(value: r.toDouble(), child: Text('$r%'))).toList(),
          onChanged: (v) => v != null ? notifier.updateLineField(index, 'gstRate', v) : null,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.primary, width: 2)),
          ),
          style: textTheme.bodyMedium?.copyWith(fontFamily: 'JetBrains Mono'),
          isExpanded: true,
        ),
      );
    }

    return Text(
      '${line.gstRate.toStringAsFixed(line.gstRate == line.gstRate.roundToDouble() ? 0 : 2)}%',
      style: textTheme.bodyMedium?.copyWith(
        color: colors.textPrimary,
        fontFamily: 'JetBrains Mono',
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Numeric input cell
class _NumericCell extends StatelessWidget {
  const _NumericCell({
    required this.controller,
    required this.focusNode,
    required this.value,
    required this.onChanged,
    required this.onSubmitted,
    required this.format,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<String> onSubmitted;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 100,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
        onFieldSubmitted: onSubmitted,
        style: textTheme.bodyMedium?.copyWith(fontFamily: 'JetBrains Mono', fontFeatures: const [FontFeature.tabularFigures()]),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: colors.primary, width: 2)),
        ),
      ),
    );
  }
}