import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/features/inventory/warehouse/presentation/warehouse_providers.dart';
import 'package:apexbooks/features/inventory/warehouse/services/warehouse_service.dart';
import '../models/goods_receipt_line.dart';
import 'goods_receipt_form_notifier.dart';
import 'goods_receipt_form_state.dart';
import 'goods_receipt_list_provider.dart';

class GoodsReceiptFormScreen extends ConsumerStatefulWidget {
  const GoodsReceiptFormScreen({super.key});
  @override
  ConsumerState<GoodsReceiptFormScreen> createState() =>
      _GoodsReceiptFormScreenState();
}

class _GoodsReceiptFormScreenState
    extends ConsumerState<GoodsReceiptFormScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final now = DateTime.now();
      ref.read(goodsReceiptFormProvider.notifier).setReceiptDate(_fmtDate(now));
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime? _parseDate(String s) => DateTime.tryParse(s);

  Future<void> _save() async {
    final notifier = ref.read(goodsReceiptFormProvider.notifier);
    if (ref.read(goodsReceiptFormProvider).saving) return;
    if (await notifier.create() != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goodsReceiptFormProvider);
    final notifier = ref.read(goodsReceiptFormProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);
    final warehouses =
        ref.watch(warehouseListProvider).valueOrNull ?? const <Warehouse>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surfaceMuted,
          appBar: AppBar(
            backgroundColor: colors.surfaceRaised,
            elevation: 0,
            titleSpacing: 20,
            title: Text(
              'New Goods Receipt',
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
                  onPressed: (state.saving || !state.hasPo) ? null : _save,
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: LoadingSpinner(size: 16),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save GRN'),
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
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _headerCard(state, notifier, colors),
                        const SizedBox(height: 16),
                        if (state.loadingPo)
                          const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: LoadingSpinner(size: 30)),
                          )
                        else if (state.hasPo)
                          _linesCard(state, notifier, colors, fmt, warehouses)
                        else
                          _Card(
                            colors: colors,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                  color: colors.textMuted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Select a confirmed purchase order to receive goods against.',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    GoodsReceiptFormState state,
    GoodsReceiptFormNotifier notifier,
    ApexColors colors,
  ) {
    return _Card(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 640;
          final po = _labeled(
            'Purchase Order',
            _PoSelectorField(
              selectedLabel: state.hasPo
                  ? '${state.poNumber} · ${state.contactName}'
                  : '',
              colors: colors,
              onSelected: (id) => notifier.selectPurchaseOrder(id),
            ),
            colors,
            required: true,
          );
          final date = _labeled(
            'Receipt date',
            _DateField(
              value: state.receiptDate,
              colors: colors,
              onPick: (d) => notifier.setReceiptDate(_fmtDate(d)),
              parse: _parseDate,
            ),
            colors,
          );
          if (narrow)
            return Column(children: [po, const SizedBox(height: 12), date]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: po),
              const SizedBox(width: 16),
              Expanded(child: date),
            ],
          );
        },
      ),
    );
  }

  Widget _linesCard(
    GoodsReceiptFormState state,
    GoodsReceiptFormNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
    List<Warehouse> warehouses,
  ) {
    final lineTable = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ApexRadius.lg),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 34, child: Text('ITEM', style: _th(colors))),
              Expanded(
                flex: 16,
                child: Text(
                  'ORDERED',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 16,
                child: Text(
                  'OUTSTANDING',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 16,
                child: Text(
                  'RECEIVE',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 18,
                child: Text('WAREHOUSE', style: _th(colors)),
              ),
            ],
          ),
        ),
        ...state.lines.asMap().entries.map(
          (e) => _ReceiptLineRow(
            key: ValueKey('gr_line_${e.key}_${state.purchaseOrderId}'),
            line: e.value,
            colors: colors,
            fmt: fmt,
            warehouses: warehouses,
            onQty: (q) => notifier.setLineQuantity(e.key, q),
            onWarehouse: (w) =>
                notifier.setLineWarehouse(e.key, w?.id, w?.name),
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
              child: lineTable,
            )
          : lineTable,
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
  const _Card({
    required this.colors,
    required this.child,
    this.padding,
  });
  final ApexColors colors;
  final Widget child;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) =>
      ApexCard(padding: padding ?? const EdgeInsets.all(20), child: child);
}

/// PO selector — lists confirmed POs available to receive against.
class _PoSelectorField extends ConsumerWidget {
  const _PoSelectorField({
    required this.selectedLabel,
    required this.colors,
    required this.onSelected,
  });
  final String selectedLabel;
  final ApexColors colors;
  final void Function(String poId) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(confirmedPurchaseOrdersProvider);
    return async.when(
      loading: () => _box(colors, const Text('Loading…')),
      error: (e, _) => _box(
        colors,
        Text('Failed to load POs', style: TextStyle(color: colors.danger)),
      ),
      data: (pos) {
        if (pos.isEmpty)
          return _box(
            colors,
            Text(
              'No confirmed POs available',
              style: TextStyle(color: colors.textMuted),
            ),
          );
        return InkWell(
          borderRadius: BorderRadius.circular(ApexRadius.sm),
          onTap: () async {
            final chosen = await showModalBottomSheet<String>(
              context: context,
              builder: (_) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Select a confirmed PO',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    for (final po in pos)
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(po.poNumber.isEmpty ? po.id : po.poNumber),
                        subtitle: Text(po.contactName),
                        onTap: () => Navigator.of(context).pop(po.id),
                      ),
                  ],
                ),
              ),
            );
            if (chosen != null) onSelected(chosen);
          },
          child: _box(
            colors,
            Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selectedLabel.isEmpty
                        ? 'Choose a purchase order…'
                        : selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selectedLabel.isEmpty
                          ? colors.textMuted
                          : colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _box(ApexColors colors, Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(ApexRadius.sm),
      border: Border.all(color: colors.border),
    ),
    child: child,
  );
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
      borderRadius: BorderRadius.circular(ApexRadius.sm),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ApexRadius.sm),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: colors.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              value.isEmpty ? 'Select…' : value,
              style: TextStyle(
                color: value.isEmpty ? colors.textMuted : colors.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptLineRow extends StatefulWidget {
  const _ReceiptLineRow({
    super.key,
    required this.line,
    required this.colors,
    required this.fmt,
    required this.warehouses,
    required this.onQty,
    required this.onWarehouse,
  });
  final GoodsReceiptLine line;
  final ApexColors colors;
  final NumberFormatter fmt;
  final List<Warehouse> warehouses;
  final void Function(double) onQty;
  final void Function(Warehouse?) onWarehouse;
  @override
  State<_ReceiptLineRow> createState() => _ReceiptLineRowState();
}

class _ReceiptLineRowState extends State<_ReceiptLineRow> {
  late final TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: _num(widget.line.quantityReceived));
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final over = widget.line.isOverReceipt;
    final isMobile = ResponsiveLayout.isMobile(context);
    if (isMobile) return _buildMobileLine(c, over);
    return _buildDesktopLine(c, over);
  }

  Widget _buildDesktopLine(ApexColors c, bool over) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(flex: 34, child: Text(widget.line.productName ?? 'Item',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textPrimary))),
        Expanded(flex: 16, child: Text(widget.fmt.quantity(widget.line.quantityOrdered),
          textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: c.textSecondary))),
        Expanded(flex: 16, child: Text(widget.fmt.quantity(widget.line.outstandingQuantity),
          textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: c.textMuted))),
        Expanded(flex: 16, child: TextField(controller: _qty, textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: TextStyle(fontSize: 13, color: over ? c.danger : c.textPrimary),
          decoration: InputDecoration(isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(ApexRadius.sm)),
            enabledBorder: over ? OutlineInputBorder(borderRadius: BorderRadius.circular(ApexRadius.sm),
              borderSide: BorderSide(color: c.danger)) : null),
          onChanged: (v) => widget.onQty(double.tryParse(v) ?? 0))),
        const SizedBox(width: 8),
        Expanded(flex: 18, child: _warehouseDropdown(c)),
      ]),
    );
  }

  Widget _buildMobileLine(ApexColors c, bool over) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.surfaceMuted,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(ApexRadius.lg))),
          child: Text(widget.line.productName ?? 'Item', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary)),
        ),
        Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          Row(children: [
            _infoChip(c, 'Ordered', widget.fmt.quantity(widget.line.quantityOrdered)),
            const SizedBox(width: 8),
            _infoChip(c, 'Pending', widget.fmt.quantity(widget.line.outstandingQuantity)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: _mobileField(c, 'QTY', _qty, over,
              onChanged: (v) => widget.onQty(double.tryParse(v) ?? 0))),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('WAREHOUSE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              _warehouseDropdown(c),
            ])),
          ]),
        ])),
      ]),
    );
  }

  Widget _mobileField(ApexColors c, String label, TextEditingController ctrl, bool over, {required ValueChanged<String> onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.textMuted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(controller: ctrl, textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: over ? c.danger : c.textPrimary),
        decoration: InputDecoration(isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(ApexRadius.sm), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(ApexRadius.sm), borderSide: BorderSide(color: c.primary, width: 1.5)),
          filled: true, fillColor: c.surfaceMuted),
        onChanged: onChanged),
    ]);
  }

  Widget _warehouseDropdown(ApexColors c) {
    return DropdownButtonFormField<String>(
      initialValue: widget.line.warehouseId,
      isDense: true, isExpanded: true,
      decoration: InputDecoration(isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(ApexRadius.sm))),
      hint: Text('Warehouse', style: TextStyle(fontSize: 12, color: c.textMuted)),
      items: widget.warehouses.map((w) => DropdownMenuItem(value: w.id,
        child: Text(w.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (id) => widget.onWarehouse(
        id == null ? null : widget.warehouses.firstWhere((w) => w.id == id)),
    );
  }

  Widget _infoChip(ApexColors c, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(ApexRadius.sm)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.textMuted)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary)),
      ]),
    );
  }
}
