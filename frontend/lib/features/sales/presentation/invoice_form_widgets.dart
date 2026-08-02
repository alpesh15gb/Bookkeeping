/// Extracted sub-widgets for the invoice form screen.
///
/// All widgets preserve the same behavior as the original inline definitions
/// in [InvoiceFormScreen] — no business logic changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/features/masters/contacts/data/models/contact.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_controller.dart';
import 'package:apexbooks/features/masters/contacts/presentation/contact_search.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/features/settings/data/models/gst_config.dart';
import '../models/invoice_line.dart';

// ── Label helper ─────────────────────────────────────────────────────────────

Widget labeledField(
  String label,
  Widget field,
  ApexColors colors, {
  bool required = false,
}) {
  return Column(
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
}

// ── Customer selector ────────────────────────────────────────────────────────

class CustomerFieldWidget extends ConsumerWidget {
  const CustomerFieldWidget({
    super.key,
    required this.focusNode,
    required this.contacts,
    required this.selectedName,
    required this.colors,
    required this.onSelected,
  });

  final FocusNode focusNode;
  final List<Contact> contacts;
  final String selectedName;
  final ApexColors colors;
  final void Function(Contact) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Autocomplete<Contact>(
      displayStringForOption: (c) => c.name,
      optionsBuilder: (v) async {
        final result = await searchContactOptions(
          repository: ref.read(contactRepositoryProvider),
          localContacts: contacts,
          type: ContactType.customer,
          query: v.text,
        );
        return result;
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (selectedName.isNotEmpty && ctrl.text.isEmpty) {
          ctrl.text = selectedName;
        }
        final canCreate = ref.watch(
          permissionProvider(Permissions.contactCreate),
        );
        return Row(
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  if (canCreate)
                    const SingleActivator(LogicalKeyboardKey.keyC, alt: true):
                        _createParty,
                },
                child: TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  style: TextStyle(fontSize: isMobile ? 15 : 14),
                  decoration: _decoration(
                    colors,
                    hint: 'Search customer or GSTIN…',
                    icon: Icons.person_search_rounded,
                    isMobile: isMobile,
                  ),
                ),
              ),
            ),
            if (canCreate)
              IconButton(
                tooltip: 'New customer (Alt+C)',
                onPressed: _createParty,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
          ],
        );
      },
      optionsViewBuilder: (context, onSelected, options) => _optionsPanel(
        context,
        colors,
        options,
        onSelected,
        (Contact c) => c.name,
        (Contact c) => c.gstin ?? c.email ?? '',
      ),
    );
  }

  void _createParty() {}
}

// ── Date field ───────────────────────────────────────────────────────────────

class DateFieldWidget extends StatelessWidget {
  const DateFieldWidget({
    super.key,
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
        decoration: _decoration(
          colors,
          icon: Icons.calendar_today_rounded,
          isDense: true,
        ),
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

// ── Place of supply field ────────────────────────────────────────────────────

class PlaceOfSupplyFieldWidget extends StatelessWidget {
  const PlaceOfSupplyFieldWidget({
    super.key,
    required this.value,
    required this.colors,
    required this.onSelected,
  });

  final String value;
  final ApexColors colors;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<MapEntry<String, String>>(
      initialValue: TextEditingValue(
        text: IndianStates.codes[value] != null
            ? '$value - ${IndianStates.codes[value]}'
            : '',
      ),
      displayStringForOption: (state) => '${state.key} - ${state.value}',
      optionsBuilder: (v) {
        final query = v.text.trim().toLowerCase();
        if (query.isEmpty) return IndianStates.codes.entries.toList();
        return IndianStates.codes.entries
            .where(
              (state) =>
                  state.key.contains(query) ||
                  state.value.toLowerCase().contains(query),
            )
            .toList();
      },
      onSelected: (state) => onSelected(state.key),
      fieldViewBuilder: (context, ctrl, fn, onSubmit) => TextField(
        controller: ctrl,
        focusNode: fn,
        onSubmitted: (_) => onSubmit(),
        decoration: _decoration(
          colors,
          hint: 'Type state name or code…',
          icon: Icons.location_on_outlined,
        ),
      ),
      optionsViewBuilder: (context, select, options) =>
          _optionsPanel<MapEntry<String, String>>(
            context,
            colors,
            options,
            select,
            (state) => state.value,
            (state) => 'GST state code ${state.key}',
          ),
    );
  }
}

// ── Line item row (desktop + mobile variants) ────────────────────────────────

class LineRowWidget extends StatefulWidget {
  const LineRowWidget({
    super.key,
    required this.index,
    required this.line,
    required this.products,
    required this.colors,
    required this.fmt,
    required this.gstEnabled,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
    required this.onProduct,
  });

  final int index;
  final InvoiceLine line;
  final List<Product> products;
  final ApexColors colors;
  final NumberFormatter fmt;
  final bool gstEnabled;
  final bool canRemove;
  final void Function(InvoiceLine) onChanged;
  final VoidCallback onRemove;
  final void Function(Product) onProduct;

  @override
  State<LineRowWidget> createState() => _LineRowWidgetState();
}

class _LineRowWidgetState extends State<LineRowWidget> {
  late TextEditingController _qty;
  late TextEditingController _rate;
  late TextEditingController _disc;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: _num(widget.line.quantity));
    _rate = TextEditingController(text: _num(widget.line.rate));
    _disc = TextEditingController(text: _num(widget.line.discount));
  }

  @override
  void didUpdateWidget(LineRowWidget old) {
    super.didUpdateWidget(old);
    _syncIfChanged(_rate, widget.line.rate, old.line.rate);
    _syncIfChanged(_qty, widget.line.quantity, old.line.quantity);
    _syncIfChanged(_disc, widget.line.discount, old.line.discount);
  }

  void _syncIfChanged(TextEditingController c, double now, double before) {
    if (now != before && (double.tryParse(c.text) ?? 0) != now) {
      c.text = _num(now);
    }
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _qty.dispose();
    _rate.dispose();
    _disc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return isMobile ? _buildMobile() : _buildDesktop();
  }

  Widget _buildMobile() {
    final c = widget.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius_lg),
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
                top: Radius.circular(ApexRadius_lg),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(ApexRadius_sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.line.productName ??
                        widget.line.description ??
                        'Item #${widget.index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: widget.line.productId.isNotEmpty
                          ? c.textPrimary
                          : c.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.danger),
                    onPressed: widget.onRemove,
                    tooltip: 'Remove',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: _ProductFieldWidget(
              products: widget.products,
              current: widget.line.productName ?? widget.line.description ?? '',
              colors: c,
              onSelected: widget.onProduct,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: _mobileField(
                    c,
                    'QTY',
                    _qty,
                    onChanged: (v) => widget.onChanged(
                      widget.line.copyWith(quantity: double.tryParse(v) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _mobileField(
                    c,
                    'RATE',
                    _rate,
                    onChanged: (v) => widget.onChanged(
                      widget.line.copyWith(rate: double.tryParse(v) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _mobileField(
                    c,
                    'DISC ₹',
                    _disc,
                    onChanged: (v) => widget.onChanged(
                      widget.line.copyWith(discount: double.tryParse(v) ?? 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                _chip(
                  c,
                  'HSN',
                  widget.line.hsnSac.isEmpty ? '—' : widget.line.hsnSac,
                ),
                if (widget.gstEnabled) ...[
                  const SizedBox(width: 8),
                  _chip(c, 'GST', '${widget.line.gstRate.toInt()}%'),
                ],
                const Spacer(),
                Text(
                  widget.fmt.currency(widget.line.total),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop() {
    final c = widget.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: widget.gstEnabled ? 34 : 44,
            child: _ProductFieldWidget(
              products: widget.products,
              current: widget.line.productName ?? widget.line.description ?? '',
              colors: c,
              onSelected: widget.onProduct,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 12,
            child: Text(
              widget.line.hsnSac.isEmpty ? '—' : widget.line.hsnSac,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: _numField(
              _qty,
              right: true,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(quantity: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 14,
            child: _numField(
              _rate,
              right: true,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(rate: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: _numField(
              _disc,
              right: true,
              onChanged: (v) => widget.onChanged(
                widget.line.copyWith(discount: double.tryParse(v) ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.gstEnabled)
            Expanded(
              flex: 10,
              child: Text(
                '${_num(widget.line.gstRate)}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ),
          if (widget.gstEnabled) const SizedBox(width: 8),
          Expanded(
            flex: 14,
            child: Text(
              widget.fmt.currency(widget.line.total),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
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

  Widget _numField(
    TextEditingController ctrl, {
    required bool right,
    required ValueChanged<String> onChanged,
  }) => TextField(
    controller: ctrl,
    textAlign: right ? TextAlign.right : TextAlign.left,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ApexRadius_sm),
      ),
    ),
    onChanged: onChanged,
  );

  Widget _mobileField(
    ApexColors c,
    String label,
    TextEditingController ctrl, {
    required ValueChanged<String> onChanged,
  }) => Column(
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
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ApexRadius_sm),
            borderSide: BorderSide(color: c.border),
          ),
          filled: true,
          fillColor: c.surfaceMuted,
        ),
        onChanged: onChanged,
      ),
    ],
  );

  Widget _chip(ApexColors c, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: c.surfaceMuted,
      borderRadius: BorderRadius.circular(ApexRadius_sm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textSecondary,
          ),
        ),
      ],
    ),
  );
}

// ── Product field ────────────────────────────────────────────────────────────

class _ProductFieldWidget extends ConsumerWidget {
  const _ProductFieldWidget({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.name,
      optionsBuilder: (v) async {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return products.take(8);
        final result = await ref
            .read(productRepositoryProvider)
            .list(ListQuery(search: q, limit: 12));
        return result.dataOrNull?.items ?? <Product>[];
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, ctrl, fn, onSubmit) {
        if (current.isNotEmpty && ctrl.text.isEmpty) ctrl.text = current;
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                focusNode: fn,
                style: TextStyle(fontSize: isMobile ? 15 : 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search item…',
                  prefixIcon: Icon(
                    Icons.inventory_2_outlined,
                    size: isMobile ? 20 : 16,
                    color: colors.textMuted,
                  ),
                  prefixIconConstraints: BoxConstraints(
                    minWidth: isMobile ? 40 : 32,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 8,
                    vertical: isMobile ? 14 : 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(ApexRadius_sm),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      optionsViewBuilder: (context, onSel, options) => _optionsPanel<Product>(
        context,
        colors,
        options,
        onSel,
        (p) => p.name,
        (p) =>
            '${p.sku ?? ''}${p.barcode == null ? '' : '  ·  ${p.barcode}'}  ·  ${p.hsnSac}  ·  GST ${p.gstRate.toInt()}%',
      ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

InputDecoration _decoration(
  ApexColors colors, {
  String? hint,
  IconData? icon,
  bool isMobile = false,
  bool isDense = false,
}) => InputDecoration(
  isDense: isDense,
  hintText: hint,
  prefixIcon: icon == null
      ? null
      : Icon(icon, size: isMobile ? 22 : 18, color: colors.textMuted),
  contentPadding: EdgeInsets.symmetric(
    horizontal: 12,
    vertical: isMobile ? 16 : 14,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(ApexRadius_sm),
  ),
);

Widget _optionsPanel<T extends Object>(
  BuildContext context,
  ApexColors colors,
  Iterable<T> options,
  void Function(T) onSelected,
  String Function(T) title,
  String Function(T) subtitle,
) {
  final list = options.toList();
  final isMobile = ResponsiveLayout.isMobile(context);
  return Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(ApexRadius_md),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: isMobile ? 350 : 300,
          maxWidth: isMobile ? double.infinity : 420,
        ),
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
              final o = list[i];
              return InkWell(
                onTap: () => onSelected(o),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: isMobile ? 12 : 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title(o),
                        style: TextStyle(
                          fontSize: isMobile ? 15 : 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle(o).trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle(o),
                            style: TextStyle(
                              fontSize: isMobile ? 12 : 11,
                              color: colors.textMuted,
                            ),
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
}
