import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import '../models/purchase_return_line.dart';
import 'purchase_return_form_notifier.dart';
import 'purchase_return_form_state.dart';
import 'purchase_return_list_provider.dart';

class PurchaseReturnFormScreen extends ConsumerStatefulWidget {
  const PurchaseReturnFormScreen({super.key});
  @override
  ConsumerState<PurchaseReturnFormScreen> createState() =>
      _PurchaseReturnFormScreenState();
}

class _PurchaseReturnFormScreenState
    extends ConsumerState<PurchaseReturnFormScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(purchaseReturnFormProvider.notifier)
          .setReturnDate(_fmtDate(DateTime.now())),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime? _parseDate(String s) => DateTime.tryParse(s);

  bool get _hasUnsavedChanges {
    final s = ref.read(purchaseReturnFormProvider);
    return s.hasBill || s.lines.any((l) => l.quantityReturned > 0);
  }

  Future<void> _save() async {
    final notifier = ref.read(purchaseReturnFormProvider.notifier);
    if (ref.read(purchaseReturnFormProvider).saving) return;
    if (await notifier.create() != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseReturnFormProvider);
    final notifier = ref.read(purchaseReturnFormProvider.notifier);
    final colors = apexColors(context);
    final fmt = ref.watch(numberFormatterProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
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
                'New Purchase Return',
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
                    onPressed: (state.saving || !state.hasBill) ? null : _save,
                    icon: state.saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: LoadingSpinner(size: 16),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save return'),
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
                          if (state.loadingBill)
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(child: LoadingSpinner(size: 30)),
                            )
                          else if (state.hasBill)
                            _linesCard(state, notifier, colors, fmt)
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
                                      'Select a posted bill to return items against.',
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
                if (state.hasBill) _summaryBar(state, colors, fmt),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    PurchaseReturnFormState state,
    PurchaseReturnFormNotifier notifier,
    ApexColors colors,
  ) {
    return _Card(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 640;
          final bill = _labeled(
            'Source Bill',
            _BillSelectorField(
              selectedLabel: state.hasBill
                  ? '${state.billNumber} · ${state.contactName}'
                  : '',
              colors: colors,
              onSelected: (id) => notifier.selectBill(id),
            ),
            colors,
            required: true,
          );
          final date = _labeled(
            'Return date',
            _DateField(
              value: state.returnDate,
              colors: colors,
              onPick: (d) => notifier.setReturnDate(_fmtDate(d)),
              parse: _parseDate,
            ),
            colors,
          );
          if (narrow) {
            return Column(children: [bill, const SizedBox(height: 12), date]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: bill),
              const SizedBox(width: 16),
              Expanded(child: date),
            ],
          );
        },
      ),
    );
  }

  Widget _linesCard(
    PurchaseReturnFormState state,
    PurchaseReturnFormNotifier notifier,
    ApexColors colors,
    NumberFormatter fmt,
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
                  'RATE',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(
                flex: 16,
                child: Text(
                  'RETURN QTY',
                  textAlign: TextAlign.right,
                  style: _th(colors),
                ),
              ),
              Expanded(flex: 34, child: Text('REASON', style: _th(colors))),
            ],
          ),
        ),
        ...state.lines.asMap().entries.map(
          (e) => _ReturnLineRow(
            key: ValueKey('ret_line_${e.key}_${state.billId}'),
            line: e.value,
            colors: colors,
            fmt: fmt,
            onQty: (q) => notifier.setLineQuantity(e.key, q),
            onReason: (r) => notifier.setLineReason(e.key, r),
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

  Widget _summaryBar(
    PurchaseReturnFormState state,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
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
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      child: Row(
        children: [
          Text(
            '${state.lines.where((l) => l.quantityReturned > 0).length} line(s) · ${fmt.quantity(state.totalReturnedQty)} qty',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RETURN TOTAL (PREVIEW)',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                fmt.currency(state.previewTotal),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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

class _BillSelectorField extends ConsumerWidget {
  const _BillSelectorField({
    required this.selectedLabel,
    required this.colors,
    required this.onSelected,
  });
  final String selectedLabel;
  final ApexColors colors;
  final void Function(String billId) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(returnableBillsProvider);
    return async.when(
      loading: () => _box(colors, const Text('Loading…')),
      error: (e, _) => _box(
        colors,
        Text('Failed to load bills', style: TextStyle(color: colors.danger)),
      ),
      data: (bills) {
        if (bills.isEmpty) {
          return _box(
            colors,
            Text(
              'No posted bills available',
              style: TextStyle(color: colors.textMuted),
            ),
          );
        }
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
                        'Select a bill to return against',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    for (final b in bills)
                      ListTile(
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        title: Text(b.billNumber.isEmpty ? b.id : b.billNumber),
                        subtitle: Text(b.contactName),
                        onTap: () => Navigator.of(context).pop(b.id),
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
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: colors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selectedLabel.isEmpty ? 'Choose a bill…' : selectedLabel,
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

class _ReturnLineRow extends StatefulWidget {
  const _ReturnLineRow({
    super.key,
    required this.line,
    required this.colors,
    required this.fmt,
    required this.onQty,
    required this.onReason,
  });
  final PurchaseReturnLine line;
  final ApexColors colors;
  final NumberFormatter fmt;
  final void Function(double) onQty;
  final void Function(String) onReason;
  @override
  State<_ReturnLineRow> createState() => _ReturnLineRowState();
}

class _ReturnLineRowState extends State<_ReturnLineRow> {
  late final TextEditingController _qty;
  late final TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: widget.line.quantityReturned > 0
          ? _num(widget.line.quantityReturned)
          : '',
    );
    _reason = TextEditingController(text: widget.line.reason ?? '');
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final isMobile = ResponsiveLayout.isMobile(context);
    if (isMobile) return _buildMobileLine(c);
    return _buildDesktopLine(c);
  }

  Widget _buildDesktopLine(ApexColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.line.productName ?? 'Item',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'Billed: ${widget.fmt.quantity(widget.line.maximumQuantity)}',
                  style: TextStyle(fontSize: 10.5, color: c.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 16,
            child: Text(
              widget.fmt.currency(widget.line.rate),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          Expanded(
            flex: 16,
            child: TextField(
              controller: _qty,
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
                hintText: '0',
                suffixText:
                    '/ ${widget.fmt.quantity(widget.line.maximumQuantity)}',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
              ),
              onChanged: (v) => widget.onQty(double.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 34,
            child: TextField(
              controller: _reason,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'e.g. Damaged',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ApexRadius.sm),
                ),
              ),
              onChanged: widget.onReason,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLine(ApexColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(ApexRadius.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.line.productName ?? 'Item',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'Billed: ${widget.fmt.quantity(widget.line.maximumQuantity)}',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              children: [
                Text(
                  'Rate: ${widget.fmt.currency(widget.line.rate)}',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _rMobileField(
                        c,
                        'RETURN QTY (MAX ${widget.fmt.quantity(widget.line.maximumQuantity)})',
                        _qty,
                        onChanged: (v) => widget.onQty(double.tryParse(v) ?? 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _rMobileField(c, 'REASON', _reason, onChanged: widget.onReason),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rMobileField(
    ApexColors c,
    String label,
    TextEditingController ctrl, {
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: label == 'REASON'
              ? TextInputType.text
              : const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: label == 'REASON'
              ? []
              : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: label == 'REASON' ? 'e.g. Damaged' : '0',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ApexRadius.sm),
              borderSide: BorderSide(color: c.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ApexRadius.sm),
              borderSide: BorderSide(color: c.primary, width: 1.5),
            ),
            filled: true,
            fillColor: c.surfaceMuted,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
