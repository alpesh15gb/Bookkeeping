import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/inventory_adjustment_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/shared/app_components.dart';
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
  String _adjustmentType = 'STOCK_IN';
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
      _adjustmentType = widget.adjustment!['adjustment_type'] ?? 'STOCK_IN';
      for (final item in (widget.adjustment!['lines'] as List? ?? [])) {
        _lines.add(_AdjLineItem(
          productId: item['product_id'],
          productName: item['product_name'] ?? '',
          quantity: double.tryParse((item['quantity'] ?? 1).toString()) ?? 1,
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
    setState(() => _lines.add(_AdjLineItem(productId: p.id, productName: p.name)));
  }

  void _removeLine(int i) {
    setState(() { _lines[i].dispose(); _lines.removeAt(i); });
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one product'), backgroundColor: AppColors.error)); return; }

    setState(() => _isSaving = true);
    final payload = {
      'adjustment_date': _dateCtrl.text,
      'adjustment_type': _adjustmentType,
      'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      'lines': _lines.map((l) => {'product_id': l.productId, 'quantity': l.quantity}).toList(),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: Row(
                      children: [
                        Expanded(child: _TypeBtn(label: 'Stock In', value: 'STOCK_IN', selected: _adjustmentType == 'STOCK_IN', onTap: () => setState(() => _adjustmentType = 'STOCK_IN'))),
                        const SizedBox(width: 8),
                        Expanded(child: _TypeBtn(label: 'Stock Out', value: 'STOCK_OUT', selected: _adjustmentType == 'STOCK_OUT', onTap: () => setState(() => _adjustmentType = 'STOCK_OUT'))),
                        const SizedBox(width: 8),
                        Expanded(child: _TypeBtn(label: 'Write Off', value: 'WRITE_OFF', selected: _adjustmentType == 'WRITE_OFF', onTap: () => setState(() => _adjustmentType = 'WRITE_OFF'))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder()),
                                    onChanged: (v) => setState(() => l.quantity = double.tryParse(v) ?? 0),
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
  double quantity;
  late final TextEditingController qtyCtrl;

  _AdjLineItem({required this.productId, required this.productName, this.quantity = 1}) {
    qtyCtrl = TextEditingController(text: quantity.toString());
  }

  void dispose() { qtyCtrl.dispose(); }
}

class _TypeBtn extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _TypeBtn({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
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
