import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/views/shared/app_components.dart';

/// Editable preview dialog for scanned vendor bills.
///
/// The user can edit every field before confirming.
/// On confirm, [onSave] is called with the edited payload.
class ScannedBillPreviewDialog extends StatefulWidget {
  final Map<String, dynamic> previewData;
  final Future<bool> Function(Map<String, dynamic> editedPayload) onSave;

  const ScannedBillPreviewDialog({
    super.key,
    required this.previewData,
    required this.onSave,
  });

  @override
  State<ScannedBillPreviewDialog> createState() =>
      _ScannedBillPreviewDialogState();
}

class _ScannedBillPreviewDialogState extends State<ScannedBillPreviewDialog> {
  late final TextEditingController _vendorNameCtrl;
  late final TextEditingController _vendorGstinCtrl;
  late final TextEditingController _vendorAddressCtrl;
  late final TextEditingController _billNumberCtrl;
  late final TextEditingController _issueDateCtrl;
  late final TextEditingController _dueDateCtrl;
  late final TextEditingController _poNumberCtrl;
  late final TextEditingController _notesCtrl;

  late List<Map<String, dynamic>> _lineItems;
  bool _isSaving = false;
  bool _isGstInclusive = false;

  double get _subtotal {
    double s = 0;
    for (final l in _lineItems) {
      final qty = (l['quantity'] as num?)?.toDouble() ?? 1.0;
      final rate = (l['rate'] as num?)?.toDouble() ?? 0.0;
      final gstRate = (l['gst_rate'] as num?)?.toDouble() ?? 0.0;
      if (_isGstInclusive) {
        s += (qty * rate) / (1 + gstRate / 100);
      } else {
        s += qty * rate;
      }
    }
    return s;
  }

  double get _totalTax {
    double t = 0;
    for (final l in _lineItems) {
      final qty = (l['quantity'] as num?)?.toDouble() ?? 1.0;
      final rate = (l['rate'] as num?)?.toDouble() ?? 0.0;
      final gstRate = (l['gst_rate'] as num?)?.toDouble() ?? 0.0;
      if (_isGstInclusive) {
        final amt = qty * rate;
        t += amt - (amt / (1 + gstRate / 100));
      } else {
        t += qty * rate * (gstRate / 100);
      }
    }
    return t;
  }

  double get _total => _isGstInclusive ? _subtotal + _totalTax : _subtotal + _totalTax;

  @override
  void initState() {
    super.initState();
    final vendor = widget.previewData['vendor'] as Map<String, dynamic>? ?? {};
    final bill = widget.previewData['bill'] as Map<String, dynamic>? ?? {};

    _vendorNameCtrl = TextEditingController(text: vendor['name']?.toString() ?? '');
    _vendorGstinCtrl = TextEditingController(text: vendor['gstin']?.toString() ?? '');
    _vendorAddressCtrl = TextEditingController(text: vendor['address']?.toString() ?? '');
    _billNumberCtrl = TextEditingController(text: bill['bill_number']?.toString() ?? '');
    _issueDateCtrl = TextEditingController(text: bill['issue_date']?.toString() ?? '');
    _dueDateCtrl = TextEditingController(text: bill['due_date']?.toString() ?? '');
    _poNumberCtrl = TextEditingController(text: bill['reference_number']?.toString() ?? '');
    _notesCtrl = TextEditingController(text: bill['notes']?.toString() ?? '');

    final rawLines = widget.previewData['line_items'];
    if (rawLines is List) {
      _lineItems = rawLines
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final copy = Map<String, dynamic>.from(e);
            // Attach controllers so focus isn't lost on rebuild
            copy['_nameCtrl'] = TextEditingController(text: copy['product_name']?.toString() ?? '');
            copy['_hsnCtrl'] = TextEditingController(text: copy['hsn_sac']?.toString() ?? '');
            copy['_qtyCtrl'] = TextEditingController(text: (copy['quantity'] as num?)?.toString() ?? '1');
            copy['_rateCtrl'] = TextEditingController(text: (copy['rate'] as num?)?.toStringAsFixed(2) ?? '0.00');
            return copy;
          })
          .toList();
    } else {
      _lineItems = [];
    }
  }

  @override
  void dispose() {
    _vendorNameCtrl.dispose();
    _vendorGstinCtrl.dispose();
    _vendorAddressCtrl.dispose();
    _billNumberCtrl.dispose();
    _issueDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _poNumberCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lineItems) {
      (l['_nameCtrl'] as TextEditingController?)?.dispose();
      (l['_hsnCtrl'] as TextEditingController?)?.dispose();
      (l['_qtyCtrl'] as TextEditingController?)?.dispose();
      (l['_rateCtrl'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  void _addLine() {
    setState(() {
      final newLine = <String, dynamic>{
        'product_id': null,
        'product_name': '',
        'hsn_sac': '',
        'quantity': 1,
        'rate': 0.0,
        'gst_rate': 18.0,
        'discount': 0.0,
        'amount': 0.0,
        'product_exists': false,
      };
      newLine['_nameCtrl'] = TextEditingController();
      newLine['_hsnCtrl'] = TextEditingController();
      newLine['_qtyCtrl'] = TextEditingController(text: '1');
      newLine['_rateCtrl'] = TextEditingController(text: '0.00');
      _lineItems.add(newLine);
    });
  }

  void _removeLine(int index) {
    final line = _lineItems[index];
    (line['_nameCtrl'] as TextEditingController?)?.dispose();
    (line['_hsnCtrl'] as TextEditingController?)?.dispose();
    (line['_qtyCtrl'] as TextEditingController?)?.dispose();
    (line['_rateCtrl'] as TextEditingController?)?.dispose();
    setState(() => _lineItems.removeAt(index));
  }

  void _updateLineAmount(int index) {
    final qty = (_lineItems[index]['quantity'] as num?)?.toDouble() ?? 1.0;
    final rate = (_lineItems[index]['rate'] as num?)?.toDouble() ?? 0.0;
    final gst = (_lineItems[index]['gst_rate'] as num?)?.toDouble() ?? 0.0;
    if (_isGstInclusive) {
      _lineItems[index]['amount'] = qty * rate;
    } else {
      _lineItems[index]['amount'] = qty * rate * (1 + gst / 100);
    }
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final initial = DateTime.tryParse(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _confirm() async {
    if (_vendorNameCtrl.text.trim().isEmpty) {
      _showSnack('Vendor name is required', error: true);
      return;
    }
    if (_lineItems.isEmpty) {
      _showSnack('At least one line item is required', error: true);
      return;
    }
    if (_lineItems.any((l) => (l['product_name']?.toString().trim() ?? '').isEmpty)) {
      _showSnack('Product name is required for all line items', error: true);
      return;
    }

    setState(() => _isSaving = true);

    final List<Map<String, dynamic>> processedLines = _lineItems.map((l) {
      final copy = Map<String, dynamic>.from(l);
      final rate = (copy['rate'] as num?)?.toDouble() ?? 0.0;
      final gst = (copy['gst_rate'] as num?)?.toDouble() ?? 0.0;
      if (_isGstInclusive) {
        copy['rate'] = rate / (1 + gst / 100);
      }
      copy.remove('_nameCtrl');
      copy.remove('_hsnCtrl');
      copy.remove('_qtyCtrl');
      copy.remove('_rateCtrl');
      return copy;
    }).toList();

    final editedPayload = {
      'vendor': {
        'contact_id': widget.previewData['vendor']?['contact_id'],
        'name': _vendorNameCtrl.text.trim(),
        'gstin': _vendorGstinCtrl.text.trim().toUpperCase(),
        'address': _vendorAddressCtrl.text.trim(),
        'state_code': _vendorGstinCtrl.text.trim().length >= 2
            ? _vendorGstinCtrl.text.trim().substring(0, 2)
            : '',
      },
      'bill': {
        'bill_number': _billNumberCtrl.text.trim(),
        'issue_date': _issueDateCtrl.text,
        'due_date': _dueDateCtrl.text,
        'reference_number': _poNumberCtrl.text.trim(),
        'pos_state_code': _vendorGstinCtrl.text.trim().length >= 2
            ? _vendorGstinCtrl.text.trim().substring(0, 2)
            : '',
        'notes': _notesCtrl.text.trim(),
      },
      'line_items': processedLines,
    };

    final ok = await widget.onSave(editedPayload);
    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) Navigator.pop(context, true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final confidence = ((widget.previewData['ocr_confidence'] as num?)?.toDouble() ?? 0.0) * 100;
    final warnings = (widget.previewData['warnings'] as List?)?.cast<String>() ?? [];

    return Dialog(
      insetPadding: EdgeInsets.all(isDesktop ? 40 : 16),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Scaffold(
          backgroundColor: AppColors.bgLight,
          appBar: AppBar(
            backgroundColor: AppColors.bgSurface,
            foregroundColor: AppColors.brandNavy,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: const Text('Review Scanned Bill'),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (_isSaving)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ElevatedButton.icon(
                    onPressed: _confirm,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Create Bill'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.button),
                    ),
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Confidence + warnings
                _buildHeaderChip(confidence, warnings),
                const SizedBox(height: 16),

                // Vendor card
                _buildVendorCard(),
                const SizedBox(height: 16),

                // Bill details card
                _buildBillDetailsCard(isDesktop),
                const SizedBox(height: 16),

                // Line items
                _buildLineItemsSection(isDesktop),
                const SizedBox(height: 16),

                // Totals
                _buildTotalsCard(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderChip(double confidence, List<String> warnings) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: confidence >= 70
                ? AppColors.successBg
                : confidence >= 40
                    ? AppColors.warningBg
                    : AppColors.errorBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                confidence >= 70
                    ? Icons.check_circle_rounded
                    : confidence >= 40
                        ? Icons.warning_amber_rounded
                        : Icons.error_rounded,
                size: 14,
                color: confidence >= 70
                    ? AppColors.success
                    : confidence >= 40
                        ? AppColors.warning
                        : AppColors.error,
              ),
              const SizedBox(width: 6),
              Text(
                'Confidence: ${confidence.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: confidence >= 70
                      ? AppColors.success
                      : confidence >= 40
                          ? AppColors.warning
                          : AppColors.error,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (warnings.isNotEmpty)
          Tooltip(
            message: warnings.join('\n'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: 4),
                Text('${warnings.length} warning${warnings.length > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.warning)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildVendorCard() {
    final vendor = widget.previewData['vendor'] as Map<String, dynamic>? ?? {};
    final bool exists = vendor['exists'] == true;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: 18, color: AppColors.brandNavy),
              const SizedBox(width: 8),
              Text('VENDOR', style: AppTextStyles.labelSmall.copyWith(color: AppColors.brandNavy)),
              const Spacer(),
              if (exists)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 12, color: AppColors.success),
                      SizedBox(width: 4),
                      Text('Existing', style: TextStyle(fontSize: 11, color: AppColors.success)),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline, size: 12, color: AppColors.warning),
                      SizedBox(width: 4),
                      Text('Will Create', style: TextStyle(fontSize: 11, color: AppColors.warning)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vendorNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Vendor Name *',
              prefixIcon: Icon(Icons.business_outlined, size: 16),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vendorGstinCtrl,
            decoration: const InputDecoration(
              labelText: 'GSTIN',
              prefixIcon: Icon(Icons.confirmation_number_outlined, size: 16),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]')),
              LengthLimitingTextInputFormatter(15),
            ],
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _vendorAddressCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Address',
              prefixIcon: Icon(Icons.location_on_outlined, size: 16),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillDetailsCard(bool isDesktop) {
    final children = [
      Expanded(
        child: TextField(
          controller: _billNumberCtrl,
          decoration: const InputDecoration(
            labelText: 'Bill Number *',
            prefixIcon: Icon(Icons.tag, size: 16),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _DateFieldPreview(
          ctrl: _issueDateCtrl,
          label: 'Bill Date *',
          onTap: () => _pickDate(_issueDateCtrl),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _DateFieldPreview(
          ctrl: _dueDateCtrl,
          label: 'Due Date',
          onTap: () => _pickDate(_dueDateCtrl),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: TextField(
          controller: _poNumberCtrl,
          decoration: const InputDecoration(
            labelText: 'PO / Reference #',
            prefixIcon: Icon(Icons.receipt_long_outlined, size: 16),
          ),
        ),
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_outlined, size: 18, color: AppColors.brandNavy),
              const SizedBox(width: 8),
              Text('BILL DETAILS', style: AppTextStyles.labelSmall.copyWith(color: AppColors.brandNavy)),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _isGstInclusive,
                    activeColor: AppColors.brandNavy,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _isGstInclusive = val;
                          for (int i = 0; i < _lineItems.length; i++) {
                            _updateLineAmount(i);
                          }
                        });
                      }
                    },
                  ),
                  const Text('GST Inclusive', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isDesktop)
            Row(children: children)
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                children[0],
                const SizedBox(height: 12),
                children[2], // skip SizedBox wrappers
                const SizedBox(height: 12),
                children[4],
                const SizedBox(height: 12),
                children[6],
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: InputBorder.none,
              hintText: 'Enter notes...',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemsSection(bool isDesktop) {
    return AppCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.brandNavy,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('S.No', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Product / Description *', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                SizedBox(
                  width: 90,
                  child: Text('HSN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                ),
                SizedBox(
                  width: 70,
                  child: Text('Qty *', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                ),
                SizedBox(
                  width: 100,
                  child: Text('Rate (₹) *', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
                ),
                SizedBox(
                  width: 80,
                  child: Text('GST %', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                ),
                SizedBox(
                  width: 100,
                  child: Text('Amount (₹)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.right),
                ),
                SizedBox(width: 40),
              ],
            ),
          ),
          if (_lineItems.isEmpty)
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No items found', style: TextStyle(color: AppColors.textMuted))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _lineItems.length,
              itemBuilder: (context, index) {
                final line = _lineItems[index];
                final exists = line['product_exists'] == true;
                final qty = (line['quantity'] as num?)?.toDouble() ?? 1.0;
                final rate = (line['rate'] as num?)?.toDouble() ?? 0.0;
                final gstRate = (line['gst_rate'] as num?)?.toDouble() ?? 0.0;
                final amount = _isGstInclusive ? (qty * rate) : (qty * rate * (1 + gstRate / 100));

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            if (!exists)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('NEW', style: TextStyle(fontSize: 9, color: AppColors.warning, fontWeight: FontWeight.w700)),
                              ),
                            Expanded(
                              child: TextField(
                                controller: line['_nameCtrl'] as TextEditingController,
                                onChanged: (v) => line['product_name'] = v,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(10),
                                  hintText: 'Product name',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: line['_hsnCtrl'] as TextEditingController,
                          onChanged: (v) => line['hsn_sac'] = v,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 70,
                        child: TextField(
                          controller: line['_qtyCtrl'] as TextEditingController,
                          onChanged: (v) {
                            line['quantity'] = double.tryParse(v) ?? 1;
                            _updateLineAmount(index);
                            setState(() {});
                          },
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(10)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: line['_rateCtrl'] as TextEditingController,
                          onChanged: (v) {
                            line['rate'] = double.tryParse(v) ?? 0;
                            _updateLineAmount(index);
                            setState(() {});
                          },
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(10), prefixText: '₹'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: DropdownButtonFormField<String>(
                          initialValue: (line['gst_rate'] as num?)?.toStringAsFixed(0) ?? '18',
                          isDense: true,
                          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
                          items: const [
                            DropdownMenuItem(value: '0', child: Text('0%')),
                            DropdownMenuItem(value: '5', child: Text('5%')),
                            DropdownMenuItem(value: '12', child: Text('12%')),
                            DropdownMenuItem(value: '18', child: Text('18%')),
                            DropdownMenuItem(value: '28', child: Text('28%')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              line['gst_rate'] = double.tryParse(v) ?? 18;
                              _updateLineAmount(index);
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: Text(
                          '₹${amount.toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                          onPressed: () => _removeLine(index),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Row'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandNavy,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow('Subtotal', _subtotal),
          _SummaryRow('Total Tax', _totalTax),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text('₹${_total.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.brandNavy)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateFieldPreview extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final VoidCallback onTap;
  const _DateFieldPreview({required this.ctrl, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      onTap: onTap,
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
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Text('₹${value.toStringAsFixed(2)}', style: AppTextStyles.numeric),
        ],
      ),
    );
  }
}
