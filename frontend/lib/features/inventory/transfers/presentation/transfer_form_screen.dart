/// Stock transfer form — create inter-warehouse transfers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/features/inventory/warehouse/services/warehouse_service.dart';
import 'package:apexbooks/features/inventory/transfers/services/transfer_service.dart';
import 'package:apexbooks/features/masters/products/presentation/product_controller.dart';
import 'package:apexbooks/features/masters/products/data/models/product.dart';
import 'transfer_form_notifier.dart';
import 'transfer_form_state.dart';

class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});
  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(transferFormProvider.notifier).loadWarehouses();
      ref
          .read(productControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      ref.read(transferFormProvider.notifier).setDate(_fmtDate(DateTime.now()));
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final notifier = ref.read(transferFormProvider.notifier);
    if (ref.read(transferFormProvider).saving) return;
    if (await notifier.create() != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transferFormProvider);
    final notifier = ref.read(transferFormProvider.notifier);
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
              'New Stock Transfer',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(state.saving ? 'Saving…' : 'Save Transfer'),
                  onPressed: state.saving ? null : _save,
                ),
              ),
            ],
          ),
          body: _buildBody(state, notifier, products, colors, fmt),
        ),
      ),
    );
  }

  Widget _buildBody(
    TransferFormState state,
    TransferFormNotifier notifier,
    List<Product> products,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (state.error != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(ApexRadius.md),
            ),
            child: Text(
              state.error!,
              style: TextStyle(color: colors.danger, fontSize: 13),
            ),
          ),
        _headerRows(state, notifier, colors),
        const SizedBox(height: 24),
        _linesSection(state, notifier, products, colors, fmt),
      ],
    );
  }

  Widget _headerRows(
    TransferFormState state,
    TransferFormNotifier notifier,
    ApexColors colors,
  ) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return Column(
      children: [
        if (isMobile)
          Column(
            children: [
              _textField(
                'Transfer Number',
                state.transferNumber,
                notifier.setNumber,
                'Auto-generated',
                colors,
              ),
              const SizedBox(height: 12),
              _textField(
                'Transfer Date',
                state.transferDate,
                notifier.setDate,
                'YYYY-MM-DD',
                colors,
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _textField(
                  'Transfer Number',
                  state.transferNumber,
                  notifier.setNumber,
                  'Auto-generated',
                  colors,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _textField(
                  'Transfer Date',
                  state.transferDate,
                  notifier.setDate,
                  'YYYY-MM-DD',
                  colors,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        if (isMobile)
          Column(
            children: [
              _warehouseSelect(
                'Source Warehouse',
                state.fromWarehouseId,
                state.warehouses,
                notifier.setFromWarehouse,
                colors,
              ),
              const SizedBox(height: 12),
              _warehouseSelect(
                'Destination Warehouse',
                state.toWarehouseId,
                state.warehouses,
                notifier.setToWarehouse,
                colors,
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _warehouseSelect(
                  'Source Warehouse',
                  state.fromWarehouseId,
                  state.warehouses,
                  notifier.setFromWarehouse,
                  colors,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _warehouseSelect(
                  'Destination Warehouse',
                  state.toWarehouseId,
                  state.warehouses,
                  notifier.setToWarehouse,
                  colors,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _linesSection(
    TransferFormState state,
    TransferFormNotifier notifier,
    List<Product> products,
    ApexColors colors,
    NumberFormatter fmt,
  ) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'TRANSFER LINES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colors.textMuted,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Line'),
              onPressed: notifier.addLine,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...state.lines.asMap().entries.map(
          (e) => _lineRow(
            e.key,
            e.value,
            products,
            colors,
            fmt,
            notifier,
            state.lines.length > 1,
          ),
        ),
      ],
    );

    return ResponsiveLayout.isMobile(context)
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: body,
          )
        : body;
  }

  Widget _textField(
    String label,
    String value,
    ValueChanged<String> onChanged,
    String hint,
    ApexColors colors,
  ) {
    return TextField(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: colors.textMuted),
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.sm),
        ),
      ),
      style: const TextStyle(fontSize: 13),
      controller: TextEditingController.fromValue(
        TextEditingValue(text: value),
      ),
      onChanged: onChanged,
    );
  }

  Widget _warehouseSelect(
    String label,
    String current,
    List<Warehouse> warehouses,
    ValueChanged<String?> onChanged,
    ApexColors colors,
  ) {
    return DropdownButtonFormField<String>(
      value: current.isNotEmpty ? current : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: colors.textMuted),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.sm),
        ),
      ),
      items: warehouses
          .map(
            (w) => DropdownMenuItem(
              value: w.id,
              child: Text(w.name, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _lineRow(
    int idx,
    TransferLine line,
    List<Product> products,
    ApexColors colors,
    NumberFormatter fmt,
    TransferFormNotifier notifier,
    bool canRemove,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 35,
            child: _productAutoComplete(
              line,
              products,
              colors,
              (p) => notifier.updateLine(
                idx,
                line.copyWith(
                  productId: p.id,
                  productName: p.name,
                  rate: p.purchasePrice,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 20,
            child: _qtyField(
              line,
              colors,
              (v) => notifier.updateLine(idx, line.copyWith(quantity: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 22,
            child: Text(
              fmt.currency(line.rate),
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
          ),
          SizedBox(
            width: 36,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: canRemove ? colors.textMuted : colors.border,
              ),
              onPressed: canRemove ? () => notifier.removeLine(idx) : null,
              tooltip: 'Remove',
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyField(
    TransferLine line,
    ApexColors colors,
    ValueChanged<double> onChanged,
  ) {
    return TextField(
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Qty',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ApexRadius.sm),
        ),
      ),
      onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
    );
  }

  Widget _productAutoComplete(
    TransferLine line,
    List<Product> products,
    ApexColors colors,
    ValueChanged<Product> onSelected,
  ) {
    final product = products.where((p) => p.id == line.productId).firstOrNull;
    return Autocomplete<Product>(
      optionsBuilder: (text) {
        if (text.text.isEmpty) return products;
        final q = text.text.toLowerCase();
        return products.where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              (p.sku ?? '').toLowerCase().contains(q),
        );
      },
      displayStringForOption: (p) => p.name,
      initialValue: product != null
          ? TextEditingValue(text: product.name)
          : null,
      onSelected: onSelected,
      fieldViewBuilder: (ctx, controller, fn, _) => TextField(
        controller: controller,
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
            borderRadius: BorderRadius.circular(ApexRadius.sm),
          ),
        ),
      ),
      optionsViewBuilder: (ctx, onSel, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(ApexRadius.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300, maxWidth: 380),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(ApexRadius.md),
                  border: Border.all(color: colors.border),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
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
