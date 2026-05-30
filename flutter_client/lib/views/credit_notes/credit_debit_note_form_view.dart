import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/providers/product_provider.dart';
import 'package:flutter_client/models/product.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/search_sheets.dart';
import 'package:flutter_client/views/invoices/widgets/quick_create_product_sheet.dart';

class CreditDebitNoteFormView extends StatefulWidget {
  final bool isCredit; // true = Credit Note, false = Debit Note
  final Map<String, dynamic>? editNote;

  const CreditDebitNoteFormView({
    super.key,
    required this.isCredit,
    this.editNote,
  });

  @override
  State<CreditDebitNoteFormView> createState() => _CreditDebitNoteFormViewState();
}

class _CreditDebitNoteFormViewState extends State<CreditDebitNoteFormView> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedInvoiceId;
  late TextEditingController _dateCtrl;
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _isSaving = false;

  final List<_NoteLineItem> _lines = [];
  Timer? _previewDebounce;
  bool _isPreviewLoading = false;

  // Local real-time computed totals
  double _subtotal = 0;
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

    if (widget.editNote != null) {
      final n = widget.editNote!;
      _selectedInvoiceId = n['invoice_id']?.toString();
      _dateCtrl.text = n['issue_date'] ?? _dateCtrl.text;
      _reasonCtrl.text = n['reason'] ?? '';

      final list = n['lines'] as List? ?? n['line_items'] as List? ?? [];
      for (final item in list) {
        _lines.add(_NoteLineItem(
          productId: item['product_id'] ?? '',
          productName: item['product_name'] ?? 'Product',
          hsnSac: item['hsn_sac'] ?? '',
          quantity: double.tryParse((item['quantity'] ?? 0).toString()) ?? 1.0,
          rate: double.tryParse((item['rate'] ?? 0).toString()) ?? 0.0,
          gstRate: double.tryParse((item['gst_rate'] ?? 0.0).toString()) ?? 0.0,
        ));
      }
    }

    Future.microtask(() {
      context.read<InvoiceProvider>().fetchInvoices();
      context.read<ProductProvider>().fetchProducts();
      _recalculateTotals();
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _reasonCtrl.dispose();
    _previewDebounce?.cancel();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dateCtrl.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null && mounted) {
      setState(() {
        _dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _addEmptyLine() {
    setState(() {
      _lines.add(_NoteLineItem(
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
      _lines[index].setProduct(p, widget.isCredit);
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
    if (_lines.isEmpty || _lines.any((l) => l.productId.isEmpty)) {
      setState(() {
        _subtotal = 0;
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
        'invoice_id': _selectedInvoiceId,
        'credit_note_number': widget.isCredit && widget.editNote != null ? widget.editNote!['credit_note_number'] : null,
        'debit_note_number': !widget.isCredit && widget.editNote != null ? widget.editNote!['debit_note_number'] : null,
        'issue_date': _dateCtrl.text,
        'reason': _reasonCtrl.text.trim().isEmpty ? (widget.isCredit ? 'Sales Return' : 'Sales Correction') : _reasonCtrl.text.trim(),
        'line_items': _lines.map((l) => {
          'product_id': l.productId,
          'quantity': l.quantity,
          'rate': l.rate,
          'hsn_sac': RegExp(r'^[0-9]{4,8}$').hasMatch(l.hsnSac) ? l.hsnSac : '84716050',
          'gst_rate': l.gstRate,
        }).toList(),
      };
      final provider = context.read<DocumentProvider>();
      final preview = widget.isCredit
          ? await provider.previewCreditNote(payload)
          : await provider.previewDebitNote(payload);

      if (mounted && preview != null) {
        setState(() {
          _subtotal = double.tryParse((preview['subtotal'] ?? 0).toString()) ?? 0;
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

  Future<void> _openProductSearch(int lineIndex) async {
    final products = context.read<ProductProvider>().products;
    final selected = await showModalBottomSheet<ProductModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductSearchSheet(
        products: products,
        isPurchase: !widget.isCredit,
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
    if (_lines.isEmpty) {
      _showError('Add at least one line item');
      return;
    }
    if (_lines.any((l) => l.productId.isEmpty)) {
      _showError('Select a product for every line item');
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'invoice_id': _selectedInvoiceId,
      'credit_note_number': widget.isCredit && widget.editNote != null ? widget.editNote!['credit_note_number'] : null,
      'debit_note_number': !widget.isCredit && widget.editNote != null ? widget.editNote!['debit_note_number'] : null,
      'issue_date': _dateCtrl.text,
      'reason': _reasonCtrl.text.trim().isEmpty ? (widget.isCredit ? 'Sales Return' : 'Sales Correction') : _reasonCtrl.text.trim(),
      'line_items': _lines.map((l) => {
        'product_id': l.productId,
        'quantity': l.quantity,
        'rate': l.rate,
        'hsn_sac': RegExp(r'^[0-9]{4,8}$').hasMatch(l.hsnSac) ? l.hsnSac : '84716050',
        'gst_rate': l.gstRate,
      }).toList(),
    };

    final provider = context.read<DocumentProvider>();
    bool success;
    if (widget.isCredit) {
      success = await provider.createCreditNote(payload);
    } else {
      success = await provider.createDebitNote(payload);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        final label = widget.isCredit ? 'Credit Note' : 'Debit Note';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label saved successfully'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      } else {
        _showError(provider.errorMessage ?? 'Failed to save note');
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
    final invoices = context.watch<InvoiceProvider>().invoices;
    final label = widget.isCredit ? 'Credit Note' : 'Debit Note';

    final title = widget.editNote != null
        ? 'Edit $label'
        : 'New $label';

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
            if (_selectedInvoiceId != null)
              Text('Invoice Linked', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          ],
        ),
        actions: [
          if (_isPreviewLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton(
              onPressed: _isSaving || _isPreviewLoading ? null : _save,
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
                      widget.editNote != null ? 'Update' : 'Save',
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
              title: 'NOTE DETAILS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedInvoiceId,
                    decoration: const InputDecoration(
                      labelText: 'Linked Invoice',
                      prefixIcon: Icon(Icons.description_outlined, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Unlinked / No Invoice'),
                      ),
                      ...invoices.map((inv) => DropdownMenuItem<String>(
                        value: inv.id,
                        child: Text('${inv.invoiceNumber} — ${inv.contact?.name ?? "N/A"}'),
                      )),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedInvoiceId = v;
                        // Auto-populate lines from invoice if selected and lines are currently empty
                        if (v != null && _lines.isEmpty) {
                          final match = invoices.where((i) => i.id == v);
                          if (match.isNotEmpty) {
                            final fullInv = match.first;
                            for (final line in fullInv.lines) {
                              _lines.add(_NoteLineItem(
                                productId: line.productId,
                                productName: line.productName ?? 'Product',
                                hsnSac: line.hsnSac,
                                quantity: line.quantity,
                                rate: line.rate,
                                gstRate: line.gstRate,
                              ));
                            }
                          }
                        }
                      });
                      _recalculateTotals();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (isMobile) ...[
                    _DateField(ctrl: _dateCtrl, label: 'Issue Date', onTap: _pickDate),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reason for Note',
                        prefixIcon: Icon(Icons.edit_note_outlined, size: 18),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(child: _DateField(ctrl: _dateCtrl, label: 'Issue Date', onTap: _pickDate)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _reasonCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Reason for Note',
                              prefixIcon: Icon(Icons.edit_note_outlined, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildLineItemsSection(),
            const SizedBox(height: 16),
            _buildSummaryCard(),
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
          decoration: BoxDecoration(
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
          if (_cgst > 0) _SummaryRow('CGST', _cgst),
          if (_sgst > 0) _SummaryRow('SGST', _sgst),
          if (_igst > 0) _SummaryRow('IGST', _igst),
          if (_roundOff != 0) _SummaryRow('Round Off', _roundOff),
          const Divider(height: 24, thickness: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Amount', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(
                '₹${_total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.brandNavy,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NoteLineItem (data model for this form)
// ─────────────────────────────────────────────────────────────────────────────

class _NoteLineItem {
  final String uid = UniqueKey().toString();
  String productId;
  String productName;
  String hsnSac;
  double quantity;
  double rate;
  double gstRate;

  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController gstCtrl;
  final TextEditingController hsnCtrl;
  final TextEditingController descCtrl;

  _NoteLineItem({
    required this.productId,
    required this.productName,
    this.hsnSac = '',
    this.quantity = 1,
    this.rate = 0,
    this.gstRate = 0,
  })  : qtyCtrl = TextEditingController(text: quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString()),
        rateCtrl = TextEditingController(text: rate == 0 ? '' : rate.toStringAsFixed(2)),
        gstCtrl = TextEditingController(text: gstRate.toStringAsFixed(0)),
        hsnCtrl = TextEditingController(text: hsnSac),
        descCtrl = TextEditingController();

  void setProduct(ProductModel p, bool isCredit) {
    productId = p.id;
    productName = p.name;
    hsnSac = p.hsnSac;
    rate = isCredit ? p.salesPrice : p.purchasePrice;
    gstRate = p.gstRate;
    quantity = 1;
    rateCtrl.text = rate == 0 ? '' : rate.toStringAsFixed(2);
    gstCtrl.text = gstRate.toStringAsFixed(0);
    hsnCtrl.text = hsnSac;
    qtyCtrl.text = '1';
  }

  double get amount => quantity * rate;

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
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
  final _NoteLineItem line;
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

  _NoteLineItem get line => widget.line;
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
          // Card header
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

          // Card body
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        if (_hasProduct) ...[
                          Text('change', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
                          const SizedBox(width: 2),
                          const Icon(Icons.swap_horiz_rounded, size: 14, color: AppColors.textMuted),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Qty | Rate | GST%
                Row(
                  children: [
                    _SmallField(label: 'Qty', ctrl: line.qtyCtrl, onChanged: (v) {
                      line.quantity = double.tryParse(v) ?? 1;
                      widget.onChanged();
                    }),
                    const SizedBox(width: 8),
                    _SmallField(label: 'Rate (₹)', ctrl: line.rateCtrl, flex: 2, onChanged: (v) {
                      line.rate = double.tryParse(v) ?? 0;
                      widget.onChanged();
                    }),
                    const SizedBox(width: 8),
                    _SmallField(label: 'GST %', ctrl: line.gstCtrl, onChanged: (v) {
                      line.gstRate = double.tryParse(v) ?? 0;
                      widget.onChanged();
                    }),
                  ],
                ),

                // Collapsible HSN + Description
                if (_showDetails) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: line.hsnCtrl,
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) => line.hsnSac = v,
                          decoration: const InputDecoration(
                            labelText: 'HSN / SAC',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: line.descCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Item Description',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                // Amount chip
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _hasProduct ? AppColors.brandNavy.withValues(alpha: 0.08) : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Amount: ',
                          style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                        ),
                        Text(
                          '₹${line.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _hasProduct ? AppColors.brandNavy : AppColors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final Function(String) onChanged;
  final int flex;

  const _SmallField({
    required this.label,
    required this.ctrl,
    required this.onChanged,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          const SizedBox(height: 3),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            onChanged: onChanged,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

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
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
          Text(
            '${value < 0 ? "-" : ""}₹${value.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
