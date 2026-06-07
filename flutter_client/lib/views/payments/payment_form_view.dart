import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/payment_provider.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';

class PaymentFormView extends StatefulWidget {
  final String mode; // 'receipt' or 'disbursement'
  final VoidCallback onSuccess;

  const PaymentFormView({
    super.key,
    required this.mode,
    required this.onSuccess,
  });

  @override
  State<PaymentFormView> createState() => _PaymentFormViewState();
}

class _PaymentFormViewState extends State<PaymentFormView> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _client = ApiClient();

  String? _selectedContactId;
  String _paymentMode = 'BANK';
  DateTime _paymentDate = DateTime.now();
  late TextEditingController _dateCtrl;
  bool _isSubmitting = false;

  // Outstanding invoices / bills for allocation
  List<Map<String, dynamic>> _openDocs = [];
  bool _isLoadingDocs = false;

  // Allocation amounts per document id
  final Map<String, TextEditingController> _allocCtrl = {};

  final _modes = ['BANK', 'CASH', 'UPI', 'POS', 'OTHER'];
  final Map<String, String> _modeLabels = {
    'BANK': 'Bank Transfer / Cheque',
    'CASH': 'Cash',
    'UPI': 'UPI',
    'POS': 'Card / POS',
    'OTHER': 'Other',
  };

  bool get _isReceipt => widget.mode == 'receipt';

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: _formattedDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    _dateCtrl.dispose();
    for (final c in _allocCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOpenDocs(String contactId) async {
    setState(() {
      _isLoadingDocs = true;
      _openDocs = [];
      // dispose old controllers
      for (final c in _allocCtrl.values) c.dispose();
      _allocCtrl.clear();
    });
    try {
      final url = _isReceipt
          ? '${ApiClient.baseUrl}/invoices?contact_id=$contactId&limit=100'
          : '${ApiClient.baseUrl}/bills?contact_id=$contactId&limit=100';
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        List<dynamic> items;
        if (body is Map && body['items'] != null) {
          items = body['items'] is List ? body['items'] as List : [];
        } else if (body is List) {
          items = body;
        } else {
          items = [];
        }
        // Filter to only open/partially-paid docs
        final filtered = items.where((d) {
          final status = (d['status'] ?? '').toString();
          return status == 'PARTIALLY_PAID' || status == 'POSTED';
        }).toList();

        if (!mounted) return;
        setState(() {
          _openDocs = filtered.whereType<Map<String, dynamic>>().toList();
          for (final doc in _openDocs) {
            final id = doc['id'].toString();
            final total = double.tryParse((doc['total'] ?? 0).toString()) ?? 0;
            final paid =
                double.tryParse((doc['amount_paid'] ?? 0).toString()) ?? 0;
            final remaining = total - paid;
            _allocCtrl[id] = TextEditingController(
              text: remaining.toStringAsFixed(2),
            );
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingDocs = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() {
      _paymentDate = picked;
      _dateCtrl.text = _formattedDate;
    });
  }

  String get _formattedDate {
    return '${_paymentDate.year}-${_paymentDate.month.toString().padLeft(2, '0')}-${_paymentDate.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _isReceipt
        ? context.watch<ContactProvider>().customers
        : context.watch<ContactProvider>().vendors;
    final title = _isReceipt ? 'New Receipt' : 'New Disbursement';

    return Container(
      width: 520,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: AppSpacing.cardPadding,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Row(
              children: [
                Icon(
                  _isReceipt
                      ? Icons.payments_outlined
                      : Icons.money_off_outlined,
                  color: AppColors.brandNavy,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(title, style: AppTextStyles.h2),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Contact picker
                    AppDropdown<String>(
                      value: _selectedContactId,
                      label: _isReceipt ? 'Customer *' : 'Vendor *',
                      prefixIcon: Icons.person_outlined,
                      items: contacts
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedContactId = v);
                        if (v != null) _loadOpenDocs(v);
                      },
                      validator: (v) => v == null ? 'Select a contact' : null,
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    AppTextField(
                      controller: _amountCtrl,
                      label: 'Total Amount (₹) *',
                      prefixIcon: Icons.currency_rupee_outlined,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter amount';
                        if (double.tryParse(v) == null) return 'Invalid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Payment Date
                    AppDateField(
                      controller: _dateCtrl,
                      label: 'Payment Date *',
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 14),

                    // Payment Mode
                    AppDropdown<String>(
                      value: _paymentMode,
                      label: 'Payment Mode *',
                      items: _modes
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(_modeLabels[m] ?? m),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _paymentMode = v!),
                    ),
                    const SizedBox(height: 14),

                    // Reference
                    AppTextField(
                      controller: _refCtrl,
                      label: 'Reference Number (optional)',
                      prefixIcon: Icons.tag_outlined,
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),

                    // Allocations section
                    if (_selectedContactId != null) ...[
                      Row(
                        children: [
                          Text(
                            _isReceipt
                                ? 'Allocate to Invoices'
                                : 'Allocate to Bills',
                            style: AppTextStyles.labelSmall,
                          ),
                          const SizedBox(width: 8),
                          if (_isLoadingDocs)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (!_isLoadingDocs && _openDocs.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.borderLight,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            _isReceipt
                                ? 'No posted or partially-paid invoices for this customer.'
                                : 'No posted or partially-paid bills for this vendor.',
                            style: AppTextStyles.caption,
                          ),
                        )
                      else
                        ..._openDocs.map((doc) {
                          final id = doc['id'].toString();
                          final num =
                              doc['invoice_number'] ?? doc['bill_number'] ?? id;
                          final total =
                              double.tryParse((doc['total'] ?? 0).toString()) ??
                              0;
                          final paid =
                              double.tryParse(
                                (doc['amount_paid'] ?? 0).toString(),
                              ) ??
                              0;
                          final remaining = total - paid;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        num.toString(),
                                        style: AppTextStyles.bodyMedium,
                                      ),
                                      Text(
                                        'Outstanding: ₹${remaining.toStringAsFixed(2)}',
                                        style: AppTextStyles.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _allocCtrl[id],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      prefixText: '₹',
                                      border: OutlineInputBorder(),
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ActionButton(
                  label: _isSubmitting ? 'Saving...' : 'Save',
                  tier: ActionTier.safe,
                  isLoading: _isSubmitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    // Build allocations list
    final List<Map<String, dynamic>> allocations = [];
    for (final doc in _openDocs) {
      final id = doc['id'].toString();
      final amt = double.tryParse(_allocCtrl[id]?.text ?? '0') ?? 0;
      if (amt > 0) {
        allocations.add({
          _isReceipt ? 'invoice_id' : 'bill_id': id,
          'amount': amt,
        });
      }
    }

    final paymentAmount = double.tryParse(_amountCtrl.text) ?? 0;
    final allocatedTotal = allocations.fold<double>(
      0,
      (sum, a) => sum + (double.tryParse(a['amount'].toString()) ?? 0),
    );

    if (allocations.isEmpty) {
      if (mounted) setState(() => _isSubmitting = false);
      AppToast.error(context, _isReceipt
          ? 'Select at least one posted invoice allocation.'
          : 'Select at least one posted bill allocation.');
      return;
    }

    if ((allocatedTotal - paymentAmount).abs() > 0.01) {
      setState(() => _isSubmitting = false);
      AppToast.error(context, 'Allocated total (${allocatedTotal.toStringAsFixed(2)}) must equal payment amount (${paymentAmount.toStringAsFixed(2)}).');
      return;
    }

    final payload = <String, dynamic>{
      'contact_id': _selectedContactId,
      'amount': paymentAmount,
      'payment_mode': _paymentMode,
      'payment_date': _formattedDate,
      if (_refCtrl.text.isNotEmpty) 'reference_number': _refCtrl.text,
      if (_notesCtrl.text.isNotEmpty) 'description': _notesCtrl.text,
      if (allocations.isNotEmpty) 'allocations': allocations,
    };

    final provider = context.read<PaymentProvider>();
    final success = _isReceipt
        ? await provider.createReceipt(payload)
        : await provider.createDisbursement(payload);

    if (mounted) setState(() => _isSubmitting = false);

    if (success && mounted) {
      widget.onSuccess();
    } else if (mounted && provider.errorMessage != null) {
      AppToast.error(context, provider.errorMessage!);
    }
  }
}
