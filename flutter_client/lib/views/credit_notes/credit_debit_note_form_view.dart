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
  String? _errorMessage;

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
          productId: item['product_id'],
          productName: item['product_name'] ?? 'Product',
          hsnSac: item['hsn_sac'] ?? '',
          quantity: double.tryParse(item['quantity'].toString()) ?? 1.0,
          rate: double.tryParse(item['rate'].toString()) ?? 0.0,
          gstRate: double.tryParse((item['gst_rate'] ?? 0.0).toString()) ?? 0.0,
        ));
      }
    }

    Future.microtask(() {
      context.read<InvoiceProvider>().fetchInvoices();
      context.read<ProductProvider>().fetchProducts();
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _reasonCtrl.dispose();
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
    if (date != null) {
      setState(() {
        _dateCtrl.text = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _addLine(ProductModel product) {
    setState(() {
      _lines.add(_NoteLineItem(
        productId: product.id,
        productName: product.name,
        hsnSac: product.hsnSac.isNotEmpty ? product.hsnSac : '84716050',
        quantity: 1,
        rate: widget.isCredit ? product.salesPrice : product.purchasePrice,
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

  double get _subtotal => _lines.fold(0.0, (sum, l) => sum + l.quantity * l.rate);

  double get _cgst => _lines.fold(0.0, (sum, l) => sum + (l.quantity * l.rate * (l.gstRate / 100)) / 2);
  double get _sgst => _lines.fold(0.0, (sum, l) => sum + (l.quantity * l.rate * (l.gstRate / 100)) / 2);
  double get _total => _subtotal + _cgst + _sgst;

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one line item'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'invoice_id': _selectedInvoiceId,
      'credit_note_number': widget.isCredit && widget.editNote != null ? widget.editNote!['credit_note_number'] : null,
      'debit_note_number': !widget.isCredit && widget.editNote != null ? widget.editNote!['debit_note_number'] : null,
      'issue_date': _dateCtrl.text,
      'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      'line_items': _lines.map((l) => {
        'product_id': l.productId,
        'quantity': l.quantity,
        'rate': l.rate,
        'hsn_sac': l.hsnSac.isNotEmpty ? l.hsnSac : '84716050',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Failed to save note'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final invoices = context.watch<InvoiceProvider>().invoices;
    final products = context.watch<ProductProvider>().products;

    final title = widget.editNote != null
        ? (widget.isCredit ? 'Edit Credit Note' : 'Edit Debit Note')
        : (widget.isCredit ? 'New Credit Note' : 'New Debit Note');

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
            // Details Card
            _FormCard(
              title: 'NOTE DETAILS',
              child: Column(
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
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Issue Date *',
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                    ),
                    readOnly: true,
                    onTap: _pickDate,
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Note',
                      prefixIcon: Icon(Icons.edit_note_outlined, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Lines Card
            _FormCard(
              title: 'ITEMS',
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
                  child: Text('${p.name}  —  ₹${(widget.isCredit ? p.salesPrice : p.purchasePrice).toStringAsFixed(2)}'),
                )).toList(),
              ),
              child: _lines.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('Add items to this note', style: AppTextStyles.bodySmall)),
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
                              const Expanded(flex: 4, child: Text('ITEM', style: AppTextStyles.labelSmall)),
                              const Expanded(flex: 2, child: Text('QTY', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                              const Expanded(flex: 3, child: Text('RATE', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                              const Expanded(flex: 3, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
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
                            final amt = line.quantity * line.rate;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(line.productName, style: AppTextStyles.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  Expanded(
                                    flex: 2,
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
                                    flex: 3,
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
                                    flex: 3,
                                    child: Text('₹${amt.toStringAsFixed(2)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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

            // Summary Card
            _FormCard(
              title: 'SUMMARY',
              child: Column(
                children: [
                  SummaryRow(label: 'Subtotal', value: '₹${_subtotal.toStringAsFixed(2)}'),
                  SummaryRow(label: 'CGST', value: '₹${_cgst.toStringAsFixed(2)}'),
                  SummaryRow(label: 'SGST', value: '₹${_sgst.toStringAsFixed(2)}'),
                  const Divider(),
                  SummaryRow(
                    label: 'Total',
                    value: '₹${_total.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: AppColors.brandNavy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _NoteLineItem {
  String productId;
  String productName;
  String hsnSac;
  double quantity;
  double rate;
  double gstRate;

  late final TextEditingController qtyCtrl;
  late final TextEditingController rateCtrl;

  _NoteLineItem({
    required this.productId,
    required this.productName,
    this.hsnSac = '',
    this.quantity = 1,
    this.rate = 0,
    this.gstRate = 0,
  }) {
    qtyCtrl = TextEditingController(text: quantity % 1 == 0 ? quantity.toInt().toString() : quantity.toString());
    rateCtrl = TextEditingController(text: rate.toStringAsFixed(2));
  }

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
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
