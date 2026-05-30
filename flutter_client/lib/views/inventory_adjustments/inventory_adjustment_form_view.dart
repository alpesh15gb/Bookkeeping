import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class InventoryAdjustmentFormView extends StatefulWidget {
  final Map<String, dynamic>? adjustment;

  const InventoryAdjustmentFormView({super.key, this.adjustment});

  @override
  State<InventoryAdjustmentFormView> createState() => _InventoryAdjustmentFormViewState();
}

class _InventoryAdjustmentFormViewState extends State<InventoryAdjustmentFormView> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  late final TextEditingController _dateCtrl;
  late final TextEditingController _reasonCtrl;
  final List<_AdjLineItem> _lines = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    _reasonCtrl = TextEditingController();

    if (widget.adjustment != null) {
      _dateCtrl.text = widget.adjustment!['adjustment_date'] ?? _dateCtrl.text;
      _reasonCtrl.text = widget.adjustment!['reason'] ?? '';
      for (final item in (widget.adjustment!['lines'] as List? ?? widget.adjustment!['line_items'] as List? ?? [])) {
        _lines.add(_AdjLineItem(
          productId: item['product_id'],
          productName: item['product_name'] ?? '',
          quantityChange: double.tryParse((item['quantity'] ?? item['quantity_change'] ?? 0).toString()) ?? 0,
          unitCost: double.tryParse((item['unit_cost'] ?? 0).toString()) ?? 0,
        ));
      }
    }

    Future.microtask(() => context.read<ProductProvider>().fetchProducts());
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _reasonCtrl.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  void _addLine(ProductModel p) {
    setState(() => _lines.add(_AdjLineItem(
      productId: p.id,
      productName: p.name,
      unitCost: p.purchasePrice,
    )));
  }

  void _removeLine(int i) {
    setState(() { _lines[i].dispose(); _lines.removeAt(i); });
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one product'), backgroundColor: AppColors.error)); return; }
    if (_lines.any((l) => l.quantityChange == 0)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity change cannot be 0 for any item'), backgroundColor: AppColors.error)); return; }

    setState(() => _isSaving = true);
    final payload = {
      'adjustment_number': widget.adjustment != null ? widget.adjustment!['adjustment_number'] : 'ADJ-${DateTime.now().millisecondsSinceEpoch}',
      'adjustment_date': _dateCtrl.text,
      'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      'line_items': _lines.map((l) => {
        'product_id': l.productId,
        'quantity_change': l.quantityChange,
        if (l.unitCost > 0) 'unit_cost': l.unitCost,
      }).toList(),
    };

    final provider = context.read<InventoryAdjustmentProvider>();
    final success = widget.adjustment != null
        ? await provider.updateAdjustment(widget.adjustment!['id'], payload)
        : await provider.createAdjustment(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.errorMessage ?? 'Failed'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final products = context.watch<ProductProvider>().products;
    final title = widget.adjustment != null ? 'Edit Adjustment' : 'New Adjustment';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('SAVE'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
          children: [
            _FormCard(
              title: 'ADJUSTMENT DETAILS',
              child: Column(
                children: [
                  TextFormField(
                    controller: _dateCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Adjustment Date *', prefixIcon: Icon(Icons.calendar_today, size: 16)),
                    onTap: _pickDate,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Physical count correction', prefixIcon: Icon(Icons.edit_note, size: 18)),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormCard(
              title: 'PRODUCTS',
              trailing: PopupMenuButton<ProductModel>(
                onSelected: _addLine,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.brandNavy, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, color: Colors.white, size: 14), SizedBox(width: 4), Text('Add', style: TextStyle(color: Colors.white, fontSize: 12))]),
                ),
                itemBuilder: (_) => products.map((p) => PopupMenuItem(value: p, child: Text(p.name))).toList(),
              ),
              child: _lines.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('Add products to adjust', style: AppTextStyles.bodySmall)))
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(AppRadius.sm)),
                          child: const Row(children: [
                            Expanded(flex: 3, child: Text('PRODUCT', style: AppTextStyles.labelSmall)),
                            Expanded(flex: 1, child: Text('QTY', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                            Expanded(flex: 2, child: Text('COST/UNIT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                            SizedBox(width: 28),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        ..._lines.asMap().entries.map((e) {
                          final l = e.value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              Expanded(flex: 3, child: Text(l.productName, style: AppTextStyles.bodySmall)),
                              Expanded(
                                flex: 1,
                                child: SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: l.qtyCtrl,
                                    textAlign: TextAlign.center,
                                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder()),
                                    onChanged: (v) => setState(() => l.quantityChange = double.tryParse(v) ?? 0),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 32,
                                  child: TextField(
                                    controller: l.costCtrl,
                                    textAlign: TextAlign.right,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder()),
                                    onChanged: (v) => setState(() => l.unitCost = double.tryParse(v) ?? 0),
                                  ),
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.close, size: 14, color: AppColors.error), onPressed: () => _removeLine(e.key), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                            ]),
                          );
                        }),
                      ],
                    ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (date != null) _dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _AdjLineItem {
  String productId;
  String productName;
  double quantityChange;
  double unitCost;
  late final TextEditingController qtyCtrl;
  late final TextEditingController costCtrl;

  _AdjLineItem({required this.productId, required this.productName, this.quantityChange = 1, this.unitCost = 0}) {
    qtyCtrl = TextEditingController(text: quantityChange % 1 == 0 ? quantityChange.toInt().toString() : quantityChange.toString());
    costCtrl = TextEditingController(text: unitCost == 0 ? '' : unitCost.toStringAsFixed(2));
  }

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _FormCard({required this.title, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(color: AppColors.bgSurface, borderRadius: AppRadius.card, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text(title, style: AppTextStyles.labelSmall), const Spacer(), if (trailing != null) trailing!]),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
