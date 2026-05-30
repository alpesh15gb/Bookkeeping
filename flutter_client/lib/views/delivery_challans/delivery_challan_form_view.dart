import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/contact.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class DeliveryChallanFormView extends StatefulWidget {
  final Map<String, dynamic>? challan;

  const DeliveryChallanFormView({super.key, this.challan});

  @override
  State<DeliveryChallanFormView> createState() => _DeliveryChallanFormViewState();
}

class _DeliveryChallanFormViewState extends State<DeliveryChallanFormView> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  ContactModel? _customer;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _dueDateCtrl;
  late final TextEditingController _notesCtrl;
  final List<_DCLineItem> _lines = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    _dueDateCtrl = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    _notesCtrl = TextEditingController();

    if (widget.challan != null) {
      _dateCtrl.text = widget.challan!['challan_date'] ?? _dateCtrl.text;
      _dueDateCtrl.text = widget.challan!['due_date'] ?? _dueDateCtrl.text;
      _notesCtrl.text = widget.challan!['notes'] ?? '';
      for (final item in (widget.challan!['lines'] as List? ?? widget.challan!['line_items'] as List? ?? [])) {
        _lines.add(_DCLineItem(
          productId: item['product_id'],
          productName: item['product_name'] ?? '',
          quantity: double.tryParse((item['quantity'] ?? 1).toString()) ?? 1,
          rate: double.tryParse((item['rate'] ?? 0).toString()) ?? 0,
          discount: double.tryParse((item['discount'] ?? 0).toString()) ?? 0,
          gstRate: double.tryParse((item['gst_rate'] ?? 0).toString()) ?? 0,
          hsnSac: item['hsn_sac'] ?? '',
        ));
      }
      Future.microtask(() {
        final contacts = context.read<ContactProvider>().contacts;
        final match = contacts.where((c) => c.id == widget.challan!['contact_id']);
        if (match.isNotEmpty) setState(() => _customer = match.first);
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
    _dueDateCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) { l.dispose(); }
    super.dispose();
  }

  void _addLine(ProductModel product) {
    setState(() => _lines.add(_DCLineItem(
      productId: product.id,
      productName: product.name,
      rate: product.purchasePrice,
      gstRate: product.gstRate,
      hsnSac: product.hsnSac,
    )));
  }

  void _removeLine(int i) {
    setState(() {
      _lines[i].dispose();
      _lines.removeAt(i);
    });
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customer == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a customer'), backgroundColor: AppColors.error)); return; }
    if (_lines.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one item'), backgroundColor: AppColors.error)); return; }
    if (_lines.any((l) => l.quantity <= 0)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity must be greater than 0 for all items'), backgroundColor: AppColors.error)); return; }

    setState(() => _isSaving = true);
    final payload = {
      'contact_id': _customer!.id,
      'challan_number': widget.challan != null ? widget.challan!['challan_number'] : 'DC-${DateTime.now().millisecondsSinceEpoch}',
      'challan_date': _dateCtrl.text,
      'due_date': _dueDateCtrl.text,
      'pos_state_code': _customer!.stateCode,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      'line_items': _lines.map((l) => {
        'product_id': l.productId,
        'quantity': l.quantity,
        'rate': l.rate,
        'discount': l.discount,
        'hsn_sac': l.hsnSac,
        'gst_rate': l.gstRate,
      }).toList(),
    };

    final provider = context.read<DeliveryChallanProvider>();
    final success = widget.challan != null
        ? await provider.updateChallan(widget.challan!['id'], payload)
        : await provider.createChallan(payload);

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
    final customers = context.watch<ContactProvider>().customers;
    final products = context.watch<ProductProvider>().products;
    final title = widget.challan != null ? 'Edit Delivery Challan' : 'New Delivery Challan';

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
              title: 'CHALLAN DETAILS',
              child: Column(
                children: [
                  DropdownButtonFormField<ContactModel>(
                    value: _customer,
                    decoration: const InputDecoration(labelText: 'Customer *', prefixIcon: Icon(Icons.person, size: 18)),
                    items: customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                    onChanged: (c) => setState(() => _customer = c),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dateCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Challan Date *', prefixIcon: Icon(Icons.calendar_today, size: 16)),
                    onTap: () => _pickDate(_dateCtrl),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dueDateCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Due Date', prefixIcon: Icon(Icons.event_outlined, size: 16)),
                    onTap: () => _pickDate(_dueDateCtrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormCard(
              title: 'ITEMS DISPATCHED',
              trailing: PopupMenuButton<ProductModel>(
                onSelected: _addLine,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.brandNavy, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, color: Colors.white, size: 14), SizedBox(width: 4), Text('Add Item', style: TextStyle(color: Colors.white, fontSize: 12))]),
                ),
                itemBuilder: (_) => products.map((p) => PopupMenuItem(value: p, child: Text('${p.name}'))).toList(),
              ),
              child: _lines.isEmpty
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('Add items to dispatch', style: AppTextStyles.bodySmall)))
                  : Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(color: AppColors.borderLight, borderRadius: BorderRadius.circular(AppRadius.sm)),
                          child: const Row(children: [
                            Expanded(flex: 3, child: Text('ITEM', style: AppTextStyles.labelSmall)),
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
            const SizedBox(height: 16),
            _FormCard(
              title: 'NOTES',
              child: TextFormField(controller: _notesCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Dispatch notes...', border: InputBorder.none, filled: false)),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (date != null) ctrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _DCLineItem {
  String productId;
  String productName;
  double quantity;
  double rate;
  double discount;
  double gstRate;
  String hsnSac;
  late final TextEditingController qtyCtrl;
  late final TextEditingController rateCtrl;
  late final TextEditingController discCtrl;
  late final TextEditingController gstCtrl;
  late final TextEditingController hsnCtrl;

  _DCLineItem({required this.productId, required this.productName, this.quantity = 1, this.rate = 0, this.discount = 0, this.gstRate = 0, this.hsnSac = ''}) {
    qtyCtrl = TextEditingController(text: quantity.toString());
    rateCtrl = TextEditingController(text: rate == 0 ? '' : rate.toStringAsFixed(2));
    discCtrl = TextEditingController(text: discount == 0 ? '' : discount.toStringAsFixed(0));
    gstCtrl = TextEditingController(text: gstRate.toStringAsFixed(0));
    hsnCtrl = TextEditingController(text: hsnSac);
  }

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
    discCtrl.dispose();
    gstCtrl.dispose();
    hsnCtrl.dispose();
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
