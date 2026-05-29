import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/providers/product_provider.dart';

/// Shows a bottom sheet to quickly create a product/service.
/// Returns the created [ProductModel] on success, or null if cancelled.
Future<ProductModel?> showQuickCreateProduct(
  BuildContext context, {
  String? initialName,
}) {
  return showModalBottomSheet<ProductModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickCreateProductSheet(initialName: initialName),
  );
}

class _QuickCreateProductSheet extends StatefulWidget {
  final String? initialName;
  const _QuickCreateProductSheet({this.initialName});

  @override
  State<_QuickCreateProductSheet> createState() => _QuickCreateProductSheetState();
}

class _QuickCreateProductSheetState extends State<_QuickCreateProductSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _hsnCtrl = TextEditingController();
  String _productType = 'GOODS';
  double _gstRate = 18.0;
  bool _isSaving = false;

  static const List<double> _gstOptions = [0, 5, 12, 18, 28];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _hsnCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final product = ProductModel(
      id: '',
      name: _nameCtrl.text.trim(),
      hsnSac: _hsnCtrl.text.trim(),
      productType: _productType,
      uom: 'PCS',
      salesPrice: double.tryParse(_priceCtrl.text.trim()) ?? 0,
      purchasePrice: double.tryParse(_priceCtrl.text.trim()) ?? 0,
      gstRate: _gstRate,
      openingStock: 0,
      currentStock: 0,
      reorderLevel: 0,
      isActive: true,
    );

    final provider = context.read<ProductProvider>();
    final success = await provider.addProduct(product);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        final created = provider.products
            .where((p) => p.name.toLowerCase() == _nameCtrl.text.trim().toLowerCase())
            .lastOrNull;
        if (mounted) Navigator.pop(context, created);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(provider.errorMessage ?? 'Failed to create product'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add_box_rounded, color: Color(0xFF2E7D32), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('New Product / Service', style: AppTextStyles.h3)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Type toggle: GOODS / SERVICE
              Row(
                children: ['GOODS', 'SERVICE'].map((type) {
                  final isSelected = _productType == type;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: type == 'GOODS' ? 6 : 0, left: type == 'SERVICE' ? 6 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _productType = type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.brandNavy : AppColors.borderLight,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: isSelected ? AppColors.brandNavy : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                type == 'GOODS' ? Icons.inventory_2_rounded : Icons.miscellaneous_services_rounded,
                                size: 14,
                                color: isSelected ? Colors.white : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                type,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Name
              TextFormField(
                controller: _nameCtrl,
                autofocus: widget.initialName == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  prefixIcon: Icon(Icons.label_outline_rounded, size: 18),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),

              // Price + GST
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Sales Price *',
                        prefixIcon: Icon(Icons.currency_rupee_rounded, size: 16),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<double>(
                      value: _gstRate,
                      decoration: const InputDecoration(labelText: 'GST Rate'),
                      items: _gstOptions.map((r) => DropdownMenuItem(
                        value: r,
                        child: Text('${r.toStringAsFixed(0)}%'),
                      )).toList(),
                      onChanged: (v) { if (v != null) setState(() => _gstRate = v); },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // HSN/SAC
              TextFormField(
                controller: _hsnCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'HSN / SAC Code *',
                  prefixIcon: Icon(Icons.tag_rounded, size: 16),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'HSN/SAC is required';
                  }
                  if (!RegExp(r'^[0-9]{4,8}$').hasMatch(v.trim())) {
                    return 'Must be 4 to 8 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded, size: 18),
                            SizedBox(width: 6),
                            Text('Create & Add to Invoice', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
