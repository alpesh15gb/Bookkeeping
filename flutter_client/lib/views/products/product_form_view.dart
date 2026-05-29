import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';

class ProductFormView extends StatefulWidget {
  final ProductModel? product;

  const ProductFormView({super.key, this.product});

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<ProductFormView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _hsnController;
  late final TextEditingController _uomController;
  late final TextEditingController _salesPriceController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _gstRateController;
  late final TextEditingController _stockController;
  late final TextEditingController _reorderController;

  String _productType = 'GOODS';

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _skuController = TextEditingController(text: p?.sku ?? '');
    _hsnController = TextEditingController(text: p?.hsnSac ?? '');
    _uomController = TextEditingController(text: p?.uom ?? 'PCS');
    _salesPriceController = TextEditingController(text: p?.salesPrice.toString() ?? '0.00');
    _purchasePriceController = TextEditingController(text: p?.purchasePrice.toString() ?? '0.00');
    _gstRateController = TextEditingController(text: p?.gstRate.toString() ?? '18.00');
    _stockController = TextEditingController(text: p?.openingStock.toString() ?? '0.0');
    _reorderController = TextEditingController(text: p?.reorderLevel.toString() ?? '0.0');
    _productType = p?.productType ?? 'GOODS';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _hsnController.dispose();
    _uomController.dispose();
    _salesPriceController.dispose();
    _purchasePriceController.dispose();
    _gstRateController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      final product = ProductModel(
        id: widget.product?.id ?? '',
        name: _nameController.text.trim(),
        sku: _skuController.text.trim().isEmpty ? null : _skuController.text.trim(),
        hsnSac: _hsnController.text.trim(),
        productType: _productType,
        uom: _uomController.text.trim(),
        salesPrice: double.parse(_salesPriceController.text.trim()),
        purchasePrice: double.parse(_purchasePriceController.text.trim()),
        gstRate: double.parse(_gstRateController.text.trim()),
        openingStock: double.parse(_stockController.text.trim()),
        currentStock: widget.product?.currentStock ?? double.parse(_stockController.text.trim()),
        reorderLevel: double.parse(_reorderController.text.trim()),
        isActive: widget.product?.isActive ?? true,
      );

      final provider = context.read<ProductProvider>();
      bool success;
      if (widget.product == null) {
        success = await provider.addProduct(product);
      } else {
        success = await provider.updateProduct(widget.product!.id, product);
      }

      if (success && mounted) {
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Operation failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandNavy,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, size: 18, color: AppColors.goldAccent),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.product == null ? 'Add Product / Service' : 'Edit Product / Service',
                    style: AppTextStyles.h2,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Type Selection
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.borderLight,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _TypeOption(
                                label: 'Goods',
                                value: 'GOODS',
                                selected: _productType == 'GOODS',
                                onTap: () => setState(() => _productType = 'GOODS'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _TypeOption(
                                label: 'Service',
                                value: 'SERVICE',
                                selected: _productType == 'SERVICE',
                                onTap: () => setState(() => _productType = 'SERVICE'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Product / Service Name *'),
                        validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),

                      // SKU + HSN
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _skuController,
                              decoration: const InputDecoration(labelText: 'SKU'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _hsnController,
                              decoration: const InputDecoration(labelText: 'HSN/SAC *'),
                              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // UOM + GST
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _uomController,
                              decoration: const InputDecoration(labelText: 'Unit (UOM) *', hintText: 'e.g. PCS, BOX'),
                              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _gstRateController,
                              decoration: const InputDecoration(labelText: 'GST Rate (%) *'),
                              keyboardType: TextInputType.number,
                              validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Prices
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _salesPriceController,
                              decoration: const InputDecoration(labelText: 'Sales Price *', prefixText: '₹ '),
                              keyboardType: TextInputType.number,
                              validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _purchasePriceController,
                              decoration: const InputDecoration(labelText: 'Purchase Price *', prefixText: '₹ '),
                              keyboardType: TextInputType.number,
                              validator: (v) => (v == null || double.tryParse(v) == null) ? 'Invalid' : null,
                            ),
                          ),
                        ],
                      ),

                      // Stock fields for new products
                      if (widget.product == null) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _stockController,
                                decoration: const InputDecoration(labelText: 'Opening Stock'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _reorderController,
                                decoration: const InputDecoration(labelText: 'Reorder Level'),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _save,
                    child: Text(widget.product == null ? 'Create' : 'Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.bgSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.brandNavy : AppColors.borderInput,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? AppShadows.card : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              value == 'GOODS' ? Icons.inventory_2_rounded : Icons.build_rounded,
              size: 16,
              color: selected ? AppColors.brandNavy : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
