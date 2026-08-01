/// Product form screen — uses ApexForm + reusable field widgets.
library;

import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/forms/apex_form.dart';
import 'package:apexbooks/core/forms/dropdown_date_fields.dart';
import 'package:apexbooks/core/forms/gst_percentage_fields.dart';
import 'package:apexbooks/core/forms/money_field.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/features/auth/presentation/auth_controller.dart';
import '../data/models/product.dart';
import 'product_controller.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product});
  final Product? product;
  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = ApexFormController<Map<String, dynamic>>(_serialize);

  late TextEditingController _nameCtrl,
      _skuCtrl,
      _barcodeCtrl,
      _hsnCtrl,
      _uomCtrl;
  ProductType _type = ProductType.goods;
  double _salesPrice = 0;
  double _purchasePrice = 0;
  double _gstRate = 0;
  double _openingStock = 0;
  double _reorderLevel = 0;
  bool _isActive = true;
  bool _saving = false;

  bool get _isEditing => widget.product != null;
  bool get _isGoods => _type == ProductType.goods;

  bool get _hasUnsavedChanges =>
      _nameCtrl.text.isNotEmpty ||
      _skuCtrl.text.isNotEmpty ||
      _barcodeCtrl.text.isNotEmpty ||
      _hsnCtrl.text.isNotEmpty;

  static Map<String, dynamic> _serialize(
    Map<String, ApexFormField<dynamic>> fields,
  ) {
    return {'fields': fields};
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _skuCtrl = TextEditingController(text: p?.sku ?? '');
    _barcodeCtrl = TextEditingController(text: p?.barcode ?? '');
    _hsnCtrl = TextEditingController(text: p?.hsnSac ?? '');
    _uomCtrl = TextEditingController(text: p?.uom ?? 'PCS');
    if (p != null) {
      _type = p.productType;
      _salesPrice = p.salesPrice;
      _purchasePrice = p.purchasePrice;
      _gstRate = p.gstRate;
      _openingStock = p.openingStock;
      _reorderLevel = p.reorderLevel;
      _isActive = p.isActive;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _barcodeCtrl.dispose();
    _hsnCtrl.dispose();
    _uomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gstEnabled = ref.watch(gstEnabledProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          final result = await const DialogService().unsavedChanges(context);
          if (result == DialogResult.discard && context.mounted) {
            Navigator.of(context).pop();
          }
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_isEditing ? 'Edit Product' : 'New Product'),
            ),
            body: ApexForm(
              controller: _ctrl,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.all(
                    ResponsiveLayout.isMobile(context) ? 12 : 16,
                  ),
                  children: [
                    _section('Basic Information'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.label_outline),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _barcodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Barcode / GTIN',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code_scanner_outlined),
                        hintText: 'Scan or enter EAN, UPC or internal barcode',
                      ),
                      keyboardType: TextInputType.text,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9._/-]'),
                        ),
                        LengthLimitingTextInputFormatter(64),
                      ],
                      validator: (value) {
                        final barcode = value?.trim() ?? '';
                        if (barcode.isNotEmpty && barcode.length < 4) {
                          return 'Barcode must contain at least 4 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _skuCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SKU',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.qr_code_2_outlined),
                        hintText: 'Unique item code (optional)',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                    ApexDropdownField<ProductType>(
                      name: 'product_type',
                      label: 'Product Type *',
                      initialValue: _type,
                      options: ProductType.values,
                      toLabel: (t) => t.displayLabel,
                      onChanged: (v) => setState(() {
                        _type = v ?? ProductType.goods;
                        if (_type == ProductType.service) {
                          _openingStock = 0;
                          _reorderLevel = 0;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hsnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'HSN/SAC *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.tag_outlined),
                        hintText: '6-8 digit code',
                      ),
                      keyboardType: TextInputType.number,
                      validator: _validateHsn,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _uomCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unit of Measure *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.straighten_outlined),
                        hintText: 'PCS, NOS, KG, HRS',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _section('Pricing'),
                    const SizedBox(height: 8),
                    ApexMoneyField(
                      name: 'sales_price',
                      label: 'Sales Price *',
                      initialValue: _salesPrice,
                      validator: (v) =>
                          v == null || v < 0 ? 'Enter a valid price' : null,
                      onChanged: (v) => _salesPrice = v ?? 0,
                    ),
                    const SizedBox(height: 12),
                    ApexMoneyField(
                      name: 'purchase_price',
                      label: 'Purchase Price',
                      initialValue: _purchasePrice,
                      onChanged: (v) => _purchasePrice = v ?? 0,
                    ),
                    if (gstEnabled) ...[
                      const SizedBox(height: 16),
                      _section('Tax'),
                      const SizedBox(height: 8),
                      ApexPercentageField(
                        name: 'gst_rate',
                        label: 'GST Rate (%)',
                        initialValue: _gstRate,
                        onChanged: (v) => _gstRate = v ?? 0,
                      ),
                    ],
                    if (_isGoods) ...[
                      const SizedBox(height: 16),
                      _section('Inventory'),
                      const SizedBox(height: 8),
                      ApexMoneyField(
                        name: 'opening_stock',
                        label: 'Opening Stock',
                        initialValue: _openingStock,
                        onChanged: (v) => _openingStock = v ?? 0,
                      ),
                      const SizedBox(height: 12),
                      ApexMoneyField(
                        name: 'reorder_level',
                        label: 'Reorder Level',
                        initialValue: _reorderLevel,
                        onChanged: (v) => _reorderLevel = v ?? 0,
                      ),
                    ],
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Active'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                    const SizedBox(height: 24),
                    PermissionGate(
                      permission: Permissions.invoiceUpdate,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _isEditing
                                    ? Icons.save_rounded
                                    : Icons.add_rounded,
                              ),
                        label: Text(
                          _isEditing ? 'Update Product' : 'Create Product',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String t) =>
      Text(t, style: Theme.of(context).textTheme.titleSmall);

  String? _validateHsn(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Required';
    if (!RegExp(r'^[0-9]{6,8}$').hasMatch(s)) return 'Enter a 6-8 digit code';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final product = Product(
      id: widget.product?.id ?? '',
      name: _nameCtrl.text.trim(),
      sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim().isEmpty
          ? null
          : _barcodeCtrl.text.trim(),
      hsnSac: _hsnCtrl.text.trim(),
      productType: _type,
      uom: _uomCtrl.text.trim(),
      salesPrice: _salesPrice,
      purchasePrice: _purchasePrice,
      gstRate: _gstRate,
      openingStock: _isGoods ? _openingStock : 0,
      reorderLevel: _isGoods ? _reorderLevel : 0,
      isActive: _isActive,
    );

    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(productRepositoryProvider);

    if (_isEditing) {
      final result = await repo.update(product.id, product.toJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Product updated.');
        _pop();
      } else {
        final f = result as Failure;
        notif.error(context, f.error.message);
        setState(() => _saving = false);
      }
    } else {
      final result = await repo.create(product.toJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Product created.');
        _pop();
      } else {
        final f = result as Failure;
        notif.error(context, f.error.message);
        setState(() => _saving = false);
      }
    }
  }

  void _pop() {
    ref.read(cacheServiceProvider).invalidatePrefix('products:');
    Navigator.of(context).pop();
  }
}
