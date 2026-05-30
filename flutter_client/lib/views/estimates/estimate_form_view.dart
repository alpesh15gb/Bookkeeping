import 'dart:async';
import 'dart:ui';
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
import 'package:flutter_client/views/shared/search_sheets.dart';
import 'package:flutter_client/views/invoices/widgets/quick_create_product_sheet.dart';
import 'package:flutter_client/views/invoices/widgets/quick_create_customer_sheet.dart';

class EstimateFormView extends StatefulWidget {
  final Map<String, dynamic>? editEstimate;

  const EstimateFormView({super.key, this.editEstimate});

  @override
  State<EstimateFormView> createState() => _EstimateFormViewState();
}

class _EstimateFormViewState extends State<EstimateFormView> {
  final _formKey = GlobalKey<FormState>();

  ContactModel? _selectedCustomer;
  late TextEditingController _dateCtrl;
  late TextEditingController _expiryCtrl;
  final TextEditingController _notesCtrl = TextEditingController();
  bool _isSaving = false;
  Timer? _previewDebounce;
  bool _isPreviewLoading = false;

  final List<_EstLineItem> _lines = [];

  // Local real-time computed totals
  double _subtotal = 0;
  double _discountTotal = 0;
  double _cgst = 0;
  double _sgst = 0;
  double _igst = 0;
  double _roundOff = 0;
  double _total = 0;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _dateCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );
    final expiry = now.add(const Duration(days: 15));
    _expiryCtrl = TextEditingController(
      text: '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}',
    );

    if (widget.editEstimate != null) {
      final e = widget.editEstimate!;
      _dateCtrl.text = e['issue_date'] ?? _dateCtrl.text;
      _expiryCtrl.text = e['expiry_date'] ?? _expiryCtrl.text;
      _notesCtrl.text = e['notes'] ?? e['terms'] ?? '';

      if (e['contact_id'] != null) {
        Future.microtask(() {
          final contacts = context.read<ContactProvider>().contacts;
          final match = contacts.where((c) => c.id == e['contact_id']);
          if (match.isNotEmpty) {
            setState(() {
              _selectedCustomer = match.first;
              _recalculateTotals();
            });
          }
        });
      }

      if (e['line_items'] != null) {
        for (final li in e['line_items'] as List) {
          final item = _EstLineItem(
            productId: li['product_id'] ?? '',
            productName: li['product_name'] ?? 'Product',
            hsnSac: li['hsn_sac'] ?? '',
            quantity: double.tryParse((li['quantity'] ?? 0).toString()) ?? 1,
            rate: double.tryParse((li['rate'] ?? 0).toString()) ?? 0,
            gstRate: double.tryParse((li['gst_rate'] ?? 0).toString()) ?? 0,
            discount: double.tryParse((li['discount'] ?? 0).toString()) ?? 0,
          );
          item.descCtrl.text = li['description'] ?? '';
          _lines.add(item);
        }
        _recalculateTotals();
      }
    }

    Future.microtask(() {
      context.read<ContactProvider>().fetchContacts();
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _expiryCtrl.dispose();
    _notesCtrl.dispose();
    _previewDebounce?.cancel();
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
    if (date != null && mounted) {
      setState(() {
        ctrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _onContactSelected(ContactModel c) {
    setState(() {
      _selectedCustomer = c;
    });
    _recalculateTotals();
  }

  void _addEmptyLine() {
    setState(() {
      _lines.add(_EstLineItem(
        productId: '',
        productName: '',
        quantity: 1,
        rate: 0,
        gstRate: 18,
      ));
    });
    _recalculateTotals();
  }

  void _setLineProduct(int index, ProductModel p) {
    setState(() {
      _lines[index].setProduct(p);
    });
    _recalculateTotals();
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
    _recalculateTotals();
  }

  void _reorderLines(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _lines.removeAt(oldIndex);
      _lines.insert(newIndex, item);
    });
  }

  void _recalculateTotals() {
    _previewDebounce?.cancel();
    if (_selectedCustomer == null || _lines.isEmpty || _lines.any((l) => l.productId.isEmpty)) {
      setState(() {
        _subtotal = 0;
        _discountTotal = 0;
        _cgst = 0;
        _sgst = 0;
        _igst = 0;
        _roundOff = 0;
        _total = 0;
        _isPreviewLoading = false;
      });
      return;
    }
    setState(() => _isPreviewLoading = true);
    _previewDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final payload = {
        'contact_id': _selectedCustomer!.id,
        'proforma_number': widget.editEstimate != null ? (widget.editEstimate!['proforma_number'] ?? 'EST') : 'EST',
        'issue_date': _dateCtrl.text,
        'due_date': _expiryCtrl.text,
        'pos_state_code': RegExp(r'^[0-9]{2}$').hasMatch(_selectedCustomer!.stateCode) ? _selectedCustomer!.stateCode : '27',
        'line_items': _lines.map((l) => {
          'product_id': l.productId,
          'quantity': l.quantity,
          'rate': l.rate,
          'discount': l.discount,
          'hsn_sac': RegExp(r'^[0-9]{4,8}$').hasMatch(l.hsnSac) ? l.hsnSac : '84716050',
          'gst_rate': l.gstRate,
        }).toList(),
      };
      final preview = await context.read<DocumentProvider>().previewEstimate(payload);
      if (mounted && preview != null) {
        setState(() {
          _subtotal = double.tryParse((preview['subtotal'] ?? 0).toString()) ?? 0;
          _discountTotal = double.tryParse((preview['discount_total'] ?? 0).toString()) ?? 0;
          _cgst = double.tryParse((preview['cgst_amount'] ?? 0).toString()) ?? 0;
          _sgst = double.tryParse((preview['sgst_amount'] ?? 0).toString()) ?? 0;
          _igst = double.tryParse((preview['igst_amount'] ?? 0).toString()) ?? 0;
          _roundOff = double.tryParse((preview['round_off'] ?? 0).toString()) ?? 0;
          _total = double.tryParse((preview['total'] ?? 0).toString()) ?? 0;
          _isPreviewLoading = false;
        });
      } else {
        if (mounted) setState(() => _isPreviewLoading = false);
      }
    });
  }

  Future<void> _openCustomerSearch() async {
    final customers = context.read<ContactProvider>().customers;
    final selected = await showModalBottomSheet<ContactModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContactSearchSheet(
        contacts: customers,
        title: 'Select Customer',
        placeholder: 'Search name, phone, GSTIN...',
        createLabel: 'Add as new customer',
        onCreateNew: (name) async {
          Navigator.pop(context);
          final created = await showQuickCreateCustomer(context, initialName: name);
          if (created != null && mounted) _onContactSelected(created);
        },
      ),
    );
    if (selected != null && mounted) _onContactSelected(selected);
  }

  Future<void> _openProductSearch(int lineIndex) async {
    final products = context.read<ProductProvider>().products;
    final selected = await showModalBottomSheet<ProductModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductSearchSheet(
        products: products,
        onCreateNew: (name) async {
          Navigator.pop(context);
          final created = await showQuickCreateProduct(context, initialName: name);
          if (created != null && mounted) _setLineProduct(lineIndex, created);
        },
      ),
    );
    if (selected != null && mounted) _setLineProduct(lineIndex, selected);
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      _showError('Please select a customer');
      return;
    }
    if (_lines.isEmpty) {
      _showError('Add at least one line item');
      return;
    }
    if (_lines.any((l) => l.productId.isEmpty)) {
      _showError('Select a product for every line item');
      return;
    }
    if (_lines.any((l) => l.quantity <= 0)) {
      _showError('Quantity must be greater than 0 for all line items');
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'contact_id': _selectedCustomer!.id,
      'proforma_number': widget.editEstimate != null ? widget.editEstimate!['proforma_number'] : 'EST-${DateTime.now().millisecondsSinceEpoch}',
      'issue_date': _dateCtrl.text,
      'due_date': _expiryCtrl.text,
      'pos_state_code': RegExp(r'^[0-9]{2}$').hasMatch(_selectedCustomer!.stateCode) ? _selectedCustomer!.stateCode : '27',
      'notes': _notesCtrl.text.trim(),
      'line_items': _lines.map((l) => {
        'product_id': l.productId,
        'quantity': l.quantity,
        'rate': l.rate,
        'discount': l.discount,
        'hsn_sac': RegExp(r'^[0-9]{4,8}$').hasMatch(l.hsnSac) ? l.hsnSac : '84716050',
        'gst_rate': l.gstRate,
        if (l.descCtrl.text.trim().isNotEmpty)
          'description': l.descCtrl.text.trim(),
      }).toList(),
    };

    final provider = context.read<DocumentProvider>();
    final success = widget.editEstimate != null
        ? await provider.updateEstimate(widget.editEstimate!['id'], payload)
        : await provider.createEstimate(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.editEstimate != null ? 'Estimate updated' : 'Estimate created'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        _showError(provider.errorMessage ?? 'Failed to save estimate');
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
    final isMobile = AdaptiveLayout.isMobile(context);
    final title = widget.editEstimate != null ? 'Edit Estimate' : 'New Estimate';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTextStyles.h3),
            if (_selectedCustomer != null)
              Text(_selectedCustomer!.name, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ],
        ),
        actions: [
          if (_isPreviewLoading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      widget.editEstimate != null ? 'Update' : 'Save',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
          children: [
            _SectionCard(
              title: 'ESTIMATE DETAILS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer selection card
                  FormField<ContactModel>(
                    validator: (_) => _selectedCustomer == null ? 'Customer is required' : null,
                    builder: (state) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: _openCustomerSearch,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: state.hasError ? AppColors.error : (_selectedCustomer != null ? AppColors.brandNavy.withValues(alpha: 0.4) : AppColors.border),
                                width: _selectedCustomer != null ? 1.5 : 1,
                              ),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              color: _selectedCustomer != null ? AppColors.brandNavy.withValues(alpha: 0.03) : null,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: _selectedCustomer != null ? AppColors.brandNavy : AppColors.borderLight,
                                  child: _selectedCustomer != null
                                      ? Text(
                                          _selectedCustomer!.name[0].toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                        )
                                      : const Icon(Icons.business_outlined, size: 15, color: AppColors.textMuted),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedCustomer != null ? _selectedCustomer!.name : 'Select Customer *',
                                        style: _selectedCustomer != null ? AppTextStyles.bodyMedium : AppTextStyles.body.copyWith(color: AppColors.textMuted),
                                      ),
                                      if (_selectedCustomer?.gstin != null)
                                        Text('GSTIN: ${_selectedCustomer!.gstin}', style: AppTextStyles.caption),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.search_rounded,
                                  size: 18,
                                  color: _selectedCustomer != null ? AppColors.brandNavy : AppColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (state.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 12),
                            child: Text(state.errorText!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isMobile) ...[
                    _DateField(ctrl: _dateCtrl, label: 'Issue Date', onTap: () => _pickDate(_dateCtrl)),
                    const SizedBox(height: 12),
                    _DateField(ctrl: _expiryCtrl, label: 'Expiry Date', onTap: () => _pickDate(_expiryCtrl)),
                  ] else
                    Row(
                      children: [
                        Expanded(child: _DateField(ctrl: _dateCtrl, label: 'Issue Date', onTap: () => _pickDate(_dateCtrl))),
                        const SizedBox(width: 12),
                        Expanded(child: _DateField(ctrl: _expiryCtrl, label: 'Expiry Date', onTap: () => _pickDate(_expiryCtrl))),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildLineItemsSection(),
            const SizedBox(height: 16),
            _buildSummaryCard(),
            const SizedBox(height: 16),
            _buildNotesCard(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildLineItemsSection() {
    return _SectionCard(
      title: 'LINE ITEMS',
      trailing: _lines.isNotEmpty
          ? TextButton.icon(
              onPressed: _addEmptyLine,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add Item'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandNavy,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            )
          : null,
      child: _lines.isEmpty
          ? _buildEmptyLineItems()
          : Column(
              children: [
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorder: _reorderLines,
                  proxyDecorator: (child, _, animation) => ScaleTransition(
                    scale: animation.drive(Tween(begin: 1.0, end: 1.02)),
                    child: Material(elevation: 8, color: Colors.transparent, child: child),
                  ),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) => _LineItemCard(
                    key: ValueKey(_lines[i].uid),
                    index: i,
                    line: _lines[i],
                    onPickProduct: () => _openProductSearch(i),
                    onChanged: _recalculateTotals,
                    onRemove: () => _removeLine(i),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _addEmptyLine,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                  label: const Text('Add Another Item'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyLineItems() {
    return Column(
      children: [
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.borderLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.receipt_long_outlined, size: 32, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        const Text('No items added yet', style: AppTextStyles.bodySmall),
        const SizedBox(height: 4),
        const Text('Search existing products or create new ones on the fly', style: AppTextStyles.caption, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _addEmptyLine,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add First Item'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandNavy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return _SectionCard(
      title: 'TAX & TOTAL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow('Subtotal', _subtotal),
          if (_discountTotal > 0) _SummaryRow('Discount', -_discountTotal, color: AppColors.success),
          if (_cgst > 0) _SummaryRow('CGST', _cgst),
          if (_sgst > 0) _SummaryRow('SGST', _sgst),
          if (_igst > 0) _SummaryRow('IGST', _igst),
          if (_roundOff != 0) _SummaryRow('Round Off', _roundOff),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTextStyles.h2),
              Text(
                '₹${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return _SectionCard(
      title: 'NOTES & TERMS',
      child: TextFormField(
        controller: _notesCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Terms, validity, delivery info...',
          border: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EstLineItem (data model)
// ─────────────────────────────────────────────────────────────────────────────

class _EstLineItem {
  final String uid = UniqueKey().toString();
  String productId;
  String productName;
  String hsnSac;
  double quantity;
  double rate;
  double gstRate;
  double discount;

  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController discCtrl;
  final TextEditingController gstCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController descCtrl;

  _EstLineItem({
    required this.productId,
    required this.productName,
    this.hsnSac = '',
    this.quantity = 1,
    this.rate = 0,
    this.gstRate = 18,
    this.discount = 0,
  })  : qtyCtrl = TextEditingController(
            text: quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString()),
        rateCtrl = TextEditingController(
            text: rate == 0 ? '' : rate.toStringAsFixed(2)),
        discCtrl = TextEditingController(
            text: discount == 0 ? '' : discount.toStringAsFixed(0)),
        gstCtrl = TextEditingController(
            text: gstRate.toStringAsFixed(0)),
        hsnCtrl = TextEditingController(text: hsnSac),
        descCtrl = TextEditingController();

  void setProduct(ProductModel p) {
    productId = p.id;
    productName = p.name;
    hsnSac = p.hsnSac;
    rate = p.salesPrice;
    gstRate = p.gstRate;
    quantity = 1;
    rateCtrl.text = p.salesPrice == 0 ? '' : p.salesPrice.toStringAsFixed(2);
    gstCtrl.text = p.gstRate.toStringAsFixed(0);
    hsnCtrl.text = p.hsnSac;
    qtyCtrl.text = '1';
    discCtrl.text = '';
    discount = 0;
  }

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
    discCtrl.dispose();
    gstCtrl.dispose();
    hsnCtrl.dispose();
    descCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LineItemCard widget
// ─────────────────────────────────────────────────────────────────────────────

class _LineItemCard extends StatefulWidget {
  final int index;
  final _EstLineItem line;
  final VoidCallback onPickProduct;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _LineItemCard({
    super.key,
    required this.index,
    required this.line,
    required this.onPickProduct,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_LineItemCard> createState() => _LineItemCardState();
}

class _LineItemCardState extends State<_LineItemCard> {
  bool _showDetails = false;

  _EstLineItem get line => widget.line;
  bool get _hasProduct => line.productId.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(
          color: _hasProduct ? AppColors.brandNavy.withValues(alpha: 0.18) : AppColors.border,
          width: _hasProduct ? 1.5 : 1,
        ),
        boxShadow: [
          if (_hasProduct)
            BoxShadow(
              color: AppColors.brandNavy.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              color: _hasProduct ? AppColors.brandNavy.withValues(alpha: 0.04) : AppColors.borderLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.drag_handle_rounded, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _hasProduct ? AppColors.brandNavy : AppColors.border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#${(widget.index + 1).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Row(
                      children: [
                        Text(
                          _showDetails ? 'Less' : 'Details',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                        ),
                        Icon(
                          _showDetails ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          size: 16, color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: widget.onRemove,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product picker
                GestureDetector(
                  onTap: widget.onPickProduct,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _hasProduct ? AppColors.brandNavy.withValues(alpha: 0.04) : AppColors.bgLight,
                      border: Border.all(
                        color: _hasProduct ? AppColors.brandNavy.withValues(alpha: 0.25) : AppColors.border,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _hasProduct ? Icons.inventory_2_outlined : Icons.search_rounded,
                          size: 16,
                          color: _hasProduct ? AppColors.brandNavy : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _hasProduct ? line.productName : 'Search or type a product name...',
                            style: _hasProduct
                                ? AppTextStyles.bodyMedium.copyWith(color: AppColors.brandNavy, fontWeight: FontWeight.w600)
                                : AppTextStyles.body.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Compact numerical inputs row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: line.qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                        onChanged: (v) {
                          line.quantity = double.tryParse(v) ?? 0;
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: line.rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Rate', prefixText: '₹', isDense: true),
                        onChanged: (v) {
                          line.rate = double.tryParse(v) ?? 0;
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: line.discCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Disc%', isDense: true),
                        onChanged: (v) {
                          line.discount = double.tryParse(v) ?? 0;
                          widget.onChanged();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: line.gstCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'GST%', isDense: true),
                        onChanged: (v) {
                          line.gstRate = double.tryParse(v) ?? 0;
                          widget.onChanged();
                        },
                      ),
                    ),
                  ],
                ),
                if (_showDetails) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: line.hsnCtrl,
                          decoration: const InputDecoration(labelText: 'HSN/SAC', isDense: true),
                          onChanged: (v) => line.hsnSac = v.trim(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: line.descCtrl,
                    decoration: const InputDecoration(labelText: 'Item Description', isDense: true),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  const _SectionCard({required this.title, this.trailing, required this.child});

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

class _DateField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final VoidCallback onTap;
  const _DateField({required this.ctrl, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      onTap: onTap,
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: AppTextStyles.numeric.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
