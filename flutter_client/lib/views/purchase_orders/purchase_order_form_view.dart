import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class PurchaseOrderFormView extends StatefulWidget {
  final Map<String, dynamic>? editOrder;
  final String orderType;

  const PurchaseOrderFormView({
    super.key,
    this.editOrder,
    this.orderType = 'purchase',
  });

  @override
  State<PurchaseOrderFormView> createState() => _PurchaseOrderFormViewState();
}

class _PurchaseOrderFormViewState extends State<PurchaseOrderFormView> {
  final _formKey = GlobalKey<FormState>();

  ContactModel? _selectedVendor;
  late TextEditingController _dateCtrl;
  late TextEditingController _deliveryDateCtrl;
  TextEditingController _notesCtrl = TextEditingController();
  bool _isSaving = false;

  final List<_POLineItem> _lines = [];
  String? _errorMessage;

  final bool _isPurchase = true;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _dateCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
    _deliveryDateCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${(now.day + 7).toString().padLeft(2, '0')}',
    );

    if (widget.editOrder != null) {
      final o = widget.editOrder!;
      _dateCtrl.text = o['order_date'] ?? o['issue_date'] ?? _dateCtrl.text;
      _deliveryDateCtrl.text = o['due_date'] ?? o['delivery_date'] ?? _deliveryDateCtrl.text;
      _notesCtrl.text = o['notes'] ?? o['terms'] ?? '';

      final list = o['lines'] as List? ?? o['line_items'] as List? ?? [];
      for (final item in list) {
        _lines.add(_POLineItem(
          productId: item['product_id'],
          productName: item['product_name'] ?? 'Product',
          hsnSac: item['hsn_sac'] ?? '',
          quantity: double.tryParse(item['quantity'].toString()) ?? 1.0,
          rate: double.tryParse(item['rate'].toString()) ?? 0.0,
          gstRate: double.tryParse((item['gst_rate'] ?? 0).toString()) ?? 0.0,
          discount: double.tryParse((item['discount'] ?? 0).toString()) ?? 0.0,
        ));
      }

      Future.microtask(() {
        final contacts = context.read<ContactProvider>().contacts;
        if (o['contact_id'] != null) {
          final match = contacts.where((c) => c.id == o['contact_id']);
          if (match.isNotEmpty) setState(() => _selectedVendor = match.first);
        }
      });
    }

    Future.microtask(() {
      context.read<ContactProvider>().fetchContacts();
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _deliveryDateCtrl.dispose();
    _notesCtrl.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      ctrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  void _addLine(ProductModel product) {
    setState(() {
      _lines.add(_POLineItem(
        productId: product.id,
        productName: product.name,
        hsnSac: product.hsnSac,
        quantity: 1,
        rate: product.purchasePrice,
        gstRate: product.gstRate,
      ));
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  double get _subtotal => _lines.fold(0, (sum, l) => sum + l.quantity * l.rate * (1 - l.discount / 100));

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVendor == null) {
      _showError('Please select a vendor');
      return;
    }
    if (_lines.isEmpty) {
      _showError('Add at least one line item');
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'contact_id': _selectedVendor!.id,
      'po_number': widget.editOrder != null ? widget.editOrder!['po_number'] : 'PO/2026-27/${1000 + DateTime.now().millisecond % 9000}',
      'order_date': _dateCtrl.text,
      'due_date': _deliveryDateCtrl.text,
      'pos_state_code': _selectedVendor!.stateCode,
      'notes': _notesCtrl.text,
      'line_items': _lines.map((l) => {
        'product_id': l.productId,
        'quantity': l.quantity,
        'rate': l.rate,
        'discount': l.discount,
        'hsn_sac': l.hsnSac,
        'gst_rate': l.gstRate,
      }).toList(),
    };

    final provider = context.read<DocumentProvider>();
    final success = widget.editOrder != null
        ? await provider.updatePurchaseOrder(widget.editOrder!['id'], payload)
        : await provider.createPurchaseOrder(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.editOrder != null ? 'Purchase Order updated' : 'Purchase Order created'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        _showError(provider.errorMessage ?? 'Failed to save');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vendors = context.watch<ContactProvider>().vendors;
    final products = context.watch<ProductProvider>().products;
    final isMobile = AdaptiveLayout.isMobile(context);
    final title = widget.editOrder != null ? 'Edit Purchase Order' : 'New Purchase Order';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('SAVE'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
          children: [
            // ── Header ──
            _FormCard(
              title: 'PURCHASE ORDER DETAILS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<ContactModel>(
                    value: _selectedVendor,
                    decoration: const InputDecoration(
                      labelText: 'Vendor *',
                      prefixIcon: Icon(Icons.store_outlined, size: 18),
                    ),
                    items: vendors.map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(v.name),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedVendor = v),
                    validator: (v) => v == null ? 'Vendor required' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Order Date',
                            prefixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                          ),
                          readOnly: true,
                          onTap: () => _pickDate(_dateCtrl),
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _deliveryDateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Delivery Date',
                            prefixIcon: Icon(Icons.event_outlined, size: 16),
                          ),
                          readOnly: true,
                          onTap: () => _pickDate(_deliveryDateCtrl),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Line Items ──
            _FormCard(
              title: 'ITEMS ORDERED',
              trailing: PopupMenuButton<ProductModel>(
                onSelected: _addLine,
                offset: const Offset(0, 40),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Add Item', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                itemBuilder: (context) => products.map((p) => PopupMenuItem<ProductModel>(
                  value: p,
                  child: Text('${p.name}  —  ₹${p.purchasePrice.toStringAsFixed(2)}'),
                )).toList(),
              ),
              child: _lines.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('Add items to this order', style: AppTextStyles.bodySmall)),
                    )
                  : Column(
                      children: [
                        // Header row
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: AppColors.borderLight,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Row(
                            children: [
                              const Expanded(flex: 3, child: Text('ITEM', style: AppTextStyles.labelSmall)),
                              const Expanded(flex: 1, child: Text('QTY', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                              const Expanded(flex: 2, child: Text('RATE', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                              const Expanded(flex: 1, child: Text('DISC%', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                              const Expanded(flex: 2, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                              const SizedBox(width: 28),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _lines.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final line = _lines[i];
                            final amount = line.quantity * line.rate * (1 - line.discount / 100);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(flex: 3, child: Text(line.productName, style: AppTextStyles.bodySmall)),
                                  Expanded(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 32,
                                      child: TextField(
                                        controller: line.qtyCtrl,
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder()),
                                        onChanged: (v) => setState(() => line.quantity = double.tryParse(v) ?? 0),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: 32,
                                      child: TextField(
                                        controller: line.rateCtrl,
                                        textAlign: TextAlign.right,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: const TextStyle(fontSize: 12),
                                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder()),
                                        onChanged: (v) => setState(() => line.rate = double.tryParse(v) ?? 0),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: SizedBox(
                                      height: 32,
                                      child: TextField(
                                        controller: line.discountCtrl,
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontSize: 12),
                                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4), border: OutlineInputBorder()),
                                        onChanged: (v) => setState(() => line.discount = double.tryParse(v) ?? 0),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text('₹${amount.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 14, color: AppColors.error),
                                      onPressed: () => _removeLine(i),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),

            // ── Summary ──
            _FormCard(
              title: 'SUMMARY',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: AppTextStyles.h3),
                  Text('₹${_subtotal.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Notes ──
            _FormCard(
              title: 'NOTES & TERMS',
              child: TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  hintText: 'Delivery terms, payment terms...',
                  border: InputBorder.none,
                  filled: false,
                ),
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _POLineItem {
  String productId;
  String productName;
  String hsnSac;
  double quantity;
  double rate;
  double gstRate;
  double discount;

  late final TextEditingController qtyCtrl;
  late final TextEditingController rateCtrl;
  late final TextEditingController discountCtrl;

  _POLineItem({
    required this.productId,
    required this.productName,
    this.hsnSac = '',
    this.quantity = 1,
    this.rate = 0,
    this.gstRate = 0,
    this.discount = 0,
  }) {
    qtyCtrl = TextEditingController(text: quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString());
    rateCtrl = TextEditingController(text: rate.toStringAsFixed(2));
    discountCtrl = TextEditingController(text: discount.toStringAsFixed(0));
  }

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
    discountCtrl.dispose();
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
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: AppTextStyles.labelSmall),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
