import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/payment_provider.dart';
import 'package:flutter_client/providers/contact_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
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
          ? '${ApiClient.baseUrl}/invoices?contact_id=$contactId&status=SENT'
          : '${ApiClient.baseUrl}/bills?contact_id=$contactId&status=POSTED';
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        List<dynamic> items;
        if (body is Map && body['items'] != null) {
          items = body['items'] as List;
        } else if (body is List) {
          items = body;
        } else {
          items = [];
        }
        // Filter to only open/partially-paid docs
        final filtered = items.where((d) {
          final status = (d['status'] ?? '').toString();
          return status == 'SENT' || status == 'PARTIALLY_PAID' || status == 'POSTED';
        }).toList();

        setState(() {
          _openDocs = filtered.cast<Map<String, dynamic>>();
          for (final doc in _openDocs) {
            final id = doc['id'].toString();
            final total = double.tryParse((doc['total'] ?? 0).toString()) ?? 0;
            final paid = double.tryParse((doc['amount_paid'] ?? 0).toString()) ?? 0;
            final remaining = total - paid;
            _allocCtrl[id] = TextEditingController(text: remaining.toStringAsFixed(2));
          }
        });
      }
    } catch (_) {}
    setState(() => _isLoadingDocs = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _paymentDate = picked);
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
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                  _isReceipt ? Icons.payments_outlined : Icons.money_off_outlined,
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
                    DropdownButtonFormField<String>(
                      value: _selectedContactId,
                      decoration: InputDecoration(
                        labelText: _isReceipt ? 'Customer *' : 'Vendor *',
                        prefixIcon: const Icon(Icons.person_outlined, size: 18),
                      ),
                      items: contacts.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      )).toList(),
                      onChanged: (v) {
                        setState(() => _selectedContactId = v);
                        if (v != null) _loadOpenDocs(v);
                      },
                      validator: (v) => v == null ? 'Select a contact' : null,
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    TextFormField(
                      controller: _amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Total Amount (₹) *',
                        prefixIcon: Icon(Icons.currency_rupee_outlined, size: 18),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter amount';
                        if (double.tryParse(v) == null) return 'Invalid amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Payment Date
                    InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Payment Date *',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                          suffixIcon: Icon(Icons.arrow_drop_down, size: 18),
                        ),
                        child: Text(_formattedDate, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Payment Mode
                    DropdownButtonFormField<String>(
                      value: _paymentMode,
                      decoration: const InputDecoration(labelText: 'Payment Mode *'),
                      items: _modes.map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(_modeLabels[m] ?? m),
                      )).toList(),
                      onChanged: (v) => setState(() => _paymentMode = v!),
                    ),
                    const SizedBox(height: 14),

                    // Reference
                    TextFormField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reference Number (optional)',
                        prefixIcon: Icon(Icons.tag_outlined, size: 16),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),

                    // Allocations section
                    if (_selectedContactId != null) ...[
                      Row(
                        children: [
                          Text(
                            _isReceipt ? 'Allocate to Invoices' : 'Allocate to Bills',
                            style: AppTextStyles.labelSmall,
                          ),
                          const SizedBox(width: 8),
                          if (_isLoadingDocs)
                            const SizedBox(
                              width: 14, height: 14,
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
                                ? 'No outstanding invoices for this customer.\nPayment will be recorded as advance.'
                                : 'No outstanding bills for this vendor.\nPayment will be recorded as advance.',
                            style: AppTextStyles.caption,
                          ),
                        )
                      else
                        ..._openDocs.map((doc) {
                          final id = doc['id'].toString();
                          final num = doc['invoice_number'] ?? doc['bill_number'] ?? id;
                          final total = double.tryParse((doc['total'] ?? 0).toString()) ?? 0;
                          final paid = double.tryParse((doc['amount_paid'] ?? 0).toString()) ?? 0;
                          final remaining = total - paid;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(num.toString(), style: AppTextStyles.bodyMedium),
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
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

    // If no open docs or no allocations entered, require at least dummy allocation
    // The backend requires at least one allocation for receipts
    if (allocations.isEmpty && _openDocs.isNotEmpty) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an allocation amount for at least one document.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final payload = <String, dynamic>{
      'contact_id': _selectedContactId,
      'amount': double.parse(_amountCtrl.text),
      'payment_mode': _paymentMode,
      'payment_date': _formattedDate,
      if (_refCtrl.text.isNotEmpty) 'reference_number': _refCtrl.text,
      if (_notesCtrl.text.isNotEmpty) 'notes': _notesCtrl.text,
      if (allocations.isNotEmpty) 'allocations': allocations,
    };

    final provider = context.read<PaymentProvider>();
    final success = _isReceipt
        ? await provider.createReceipt(payload)
        : await provider.createDisbursement(payload);

    setState(() => _isSubmitting = false);

    if (success && mounted) {
      widget.onSuccess();
    } else if (mounted && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage!), backgroundColor: AppColors.error),
      );
    }
  }
}
