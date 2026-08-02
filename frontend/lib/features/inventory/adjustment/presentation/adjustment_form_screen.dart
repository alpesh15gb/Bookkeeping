import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import '../services/adjustment_service.dart';
import 'adjustment_form_notifier.dart';
import 'adjustment_form_state.dart';

class AdjustmentFormScreen extends ConsumerStatefulWidget {
  const AdjustmentFormScreen({super.key});
  @override
  ConsumerState<AdjustmentFormScreen> createState() =>
      _AdjustmentFormScreenState();
}

class _AdjustmentFormScreenState extends ConsumerState<AdjustmentFormScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(productControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      ref
          .read(adjustmentFormProvider.notifier)
          .setDate(_fmtDate(DateTime.now()));
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime? _parseDate(String s) => DateTime.tryParse(s);

  bool get _hasUnsavedChanges {
    final s = ref.read(adjustmentFormProvider);
    return s.adjustmentNumber.isNotEmpty ||
        (s.reason?.isNotEmpty ?? false) ||
        s.lines.any((l) => l.productId.isNotEmpty || l.quantityChange != 0);
  }

  Future<void> _save() async {
    final notifier = ref.read(adjustmentFormProvider.notifier);
    if (ref.read(adjustmentFormProvider).saving) return;
    if (await notifier.create() != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adjustmentFormProvider);
    final notifier = ref.read(adjustmentFormProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final productsState = ref.watch(productControllerProvider);
    final products = productsState is ListData<Product>
        ? productsState.paged.items
        : <Product>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true):
            notifier.addLine,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_hasUnsavedChanges) {
              final result = await const DialogService().unsavedChanges(
                context,
              );
              if (result == DialogResult.discard && context.mounted) {
                Navigator.of(context).pop();
              }
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: colors.surfaceMuted,
            appBar: AppBar(
              backgroundColor: colors.surfaceRaised,
              elevation: 0,
              titleSpacing: 20,
              title: Text(
                'New Stock Adjustment',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: colors.border),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 16,
                  ),
                  child: FilledButton.icon(
                    onPressed: state.saving ? null : _save,
                    icon: state.saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: LoadingSpinner(size: 16),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save adjustment'),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                if (state.error != null)
                  Container(
                    width: double.infinity,
                    color: colors.danger.withValues(alpha: 0.1),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: colors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: TextStyle(
                              color: colors.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _headerCard(state, notifier, colors),
                          const SizedBox(height: 16),
                          _linesCard(state, notifier, colors, fmt, products),
                        ],
                      ),
                    ),
                  ),
                ),
                _summaryBar(state, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    AdjustmentFormState state,
    AdjustmentFormNotifier notifier,
    ApexColors colors,
  ) {
    return _Card(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 640;
          final number = _labeled(
            'Adjustment No.',
            TextField(
              decoration: _dec(
                colors,
                hint: 'e.g. ADJ-0001',
                icon: Icons.tag_rounded,
              ),
              onChanged: notifier.setNumber,
            ),
            colors,
            required: true,
          );
          final date = _labeled(
            'Date',
            _DateField(
              value: state.adjustmentDate,
              colors: colors,
              onPick: (d) => notifier.setDate(_fmtDate(d)),
              parse: _parseDate,
            ),
            colors,
          );
          final reason = _labeled(
            'Reason',
            TextField(
              decoration: _dec(
                colors,
                hint: 'e.g. Physical count, damage…',
                icon: Icons.notes_rounded,
              ),
              onChanged: notifier.setReason,
            ),
            colors,
          );
          if (narrow) {
            return Column(
              children: [
                number,
                const SizedBox(height: 12),
                date,
                const SizedBox(height: 12),
                reason,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: number),
              const SizedBox(width: 16),
              Expanded(child: date),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: reason),
            ],
          );
        },
      ),
    );
  }

  Widget _linesCard(
    AdjustmentFormState state,
    AdjustmentFormNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
    List<Product> products,
  ) {
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ApexRadius_lg),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 44, child: Text('PRODUCT', style: _th(colors))),
              Expanded(
                flex: 22,
                child: Text(
                  'QTY CHANGE (+/-)',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 22,
                child: Text(
                  'UNIT COST',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              const SizedBox(width: 36),
            ],
          ),
        ),
        ...state.lines.asMap().entries.map(
          (e) => _AdjLineRow(
            key: ValueKey('adj_line_${e.key}'),
            line: e.value,
            products: products,
            colors: colors,
            canRemove: state.lines.length > 1,
            onChanged: (l) => notifier.updateLine(e.key, l),
            onRemove: () => notifier.removeLine(e.key),
            onProduct: (p) => notifier.updateLine(
              e.key,
              e.value.copyWith(
                productId: p.id,
                productName: p.name,
                unitCost: p.purchasePrice,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton.icon(
              onPressed: notifier.addLine,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add line  (Alt+N)'),
            ),
          ),
        ),
      ],
    );

    return _Card(
      colors: colors,
      padding: EdgeInsets.zero,
      child: ResponsiveLayout.isMobile(context)
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            )
          : table,
    );
  }

  Widget _summaryBar(AdjustmentFormState state, ApexColors colors) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 28,
        vertical: 14,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: colors.success,
                    ),
                    Text(
                      '${state.increaseCount} increase',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: colors.danger,
                    ),
                    Text(
                      '${state.decreaseCount} decrease',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: state.saving ? null : _save,
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: LoadingSpinner(size: 16),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save  (Ctrl+S)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: colors.success,
                    ),
                    Text(
                      ' ${state.increaseCount} increase',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: colors.danger,
                    ),
                    Text(
                      ' ${state.decreaseCount} decrease',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: state.saving ? null : _save,
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: LoadingSpinner(size: 16),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save  (Ctrl+S)'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _labeled(
    String label,
    Widget field,
    ApexColors colors, {
    bool required = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          if (required)
            Text(
              ' *',
              style: TextStyle(
                color: colors.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      field,
    ],
  );

  TextStyle _th(ApexColors colors) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: colors.textMuted,
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.colors, required this.child, this.padding});
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(20), child: child);
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.colors,
    required this.onPick,
    required this.parse,
  });
  final String value;
  final ApexColors colors;
  final void Function(DateTime) onPick;
  final DateTime? Function(String) parse;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ApexRadius_sm),
      onTap: () async {
        final init = parse(value) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _dec(colors, icon: Icons.calendar_today_rounded),
        child: Text(
          value.isEmpty ? 'Select…' : value,
          style: TextStyle(
            color: value.isEmpty ? colors.textMuted : colors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _AdjLineRow extends StatefulWidget {
  const _AdjLineRow({
    super.key,
    required this.line,
    required this.products,
    required this.colors,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onProduct,
  });
  final AdjustmentLine line;
  final List<Product> products;
  final ApexColors colors;
  final bool canRemove;
  final void Function(AdjustmentLine) onChanged;
  final VoidCallback onRemove;
  final void Function(Product) onProduct;
  @override
  State<_AdjLineRow> createState() => _AdjLineRowState();
}

class _AdjLineRowState extends State<_AdjLineRow> {
  late final TextEditingController _qty;
  late final TextEditingController _cost;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: widget.line.quantityChange != 0
          ? _num(widget.line.quantityChange)
          : '',
    );
    _cost = TextEditingController(
      text: widget.line.unitCost != null ? _num(widget.line.unitCost!) : '',
    );
  }

  @override
  void didUpdateWidget(_AdjLineRow old) {
    super.didUpdateWidget(old);
    final c = widget.line.unitCost ?? 0;
    if (c != (old.line.unitCost ?? 0) &&
        (double.tryParse(_cost.text) ?? 0) != c) {
      _cost.text = c != 0 ? _num(c) : '';
    }
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final qc = widget.line.quantityChange;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 44,
            child: _ProductField(
              products: widget.products,
              current: widget.line.productName,
              colors: c,
              onSelected: widget.onProduct,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 22,
            child: TextField(
              controller: _qty,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')),
              ],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: qc > 0
                    ? c.success
                    : qc < 0
                    ? c.danger
                    : c.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: '± qty',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius_sm),
                ),
              ),
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(quantityChange: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 22,
            child: TextField(
              controller: _cost,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '0.00',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius_sm),
                ),
              ),
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(unitCost: double.tryParse(v)),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: widget.canRemove ? c.textMuted : c.border,
              ),
              onPressed: widget.canRemove ? widget.onRemove : null,
              tooltip: 'Remove line',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductField extends StatelessWidget {
  const _ProductField({
    required this.products,
    required this.current,
    required this.colors,
    required this.onSelected,
  });
  final List<Product> products;
  final String current;
  final ApexColors colors;
  final void Function(Product) onSelected;
  @override
  Widget build(BuildContext context) {
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.name,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return products.take(8);
        return products
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  (p.sku ?? '').toLowerCase().contains(q),
            )
            .take(12);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (current.isNotEmpty && ctrl.text.isEmpty) ctrl.text = current;
        return TextField(
          controller: ctrl,
          focusNode: fn,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search product…',
            prefixIcon: Icon(
              Icons.inventory_2_outlined,
              size: 16,
              color: colors.textMuted,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ApexRadius_sm),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSel, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(ApexRadius_md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 380),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(ApexRadius_md),
                  border: Border.all(color: colors.border),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return InkWell(
                      onTap: () => onSel(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            if ((p.sku ?? '').isNotEmpty)
                              Text(
                                p.sku!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

InputDecoration _dec(ApexColors colors, {String? hint, IconData? icon}) =>
    InputDecoration(
      isDense: true,
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 18, color: colors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ApexRadius_sm),
      ),
    );
