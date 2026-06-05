import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class ExpenseFormView extends StatefulWidget {
  final dynamic editExpense;

  const ExpenseFormView({super.key, this.editExpense});

  @override
  State<ExpenseFormView> createState() => _ExpenseFormViewState();
}

class _ExpenseFormViewState extends State<ExpenseFormView> {
  final _formKey = GlobalKey<FormState>();

  String? _categoryId;
  String? _bankAccountId;
  late TextEditingController _dateCtrl;
  final TextEditingController _vendorCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  double _gstRate = 0.0;
  bool _isGstInclusive = false;

  bool _isSaving = false;
  Map<String, dynamic>? _previewData;

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _dateCtrl = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );

    if (widget.editExpense != null && widget.editExpense is Map) {
      final e = widget.editExpense as Map<String, dynamic>;
      _categoryId = e['expense_category_id']?.toString();
      _bankAccountId = e['bank_account_id']?.toString();
      _dateCtrl.text = e['expense_date'] ?? _dateCtrl.text;
      _vendorCtrl.text = e['vendor_name'] ?? '';
      _descCtrl.text = e['description'] ?? '';
      _amountCtrl.text = e['amount']?.toString() ?? '';
      _gstRate = double.tryParse((e['gst_rate'] ?? 0.0).toString()) ?? 0.0;
    }

    _amountCtrl.addListener(_onAmountChanged);

    Future.microtask(() {
      context.read<DocumentProvider>().fetchExpenseCategories();
      context.read<AccountingProvider>().fetchAccounts();
      _triggerPreview();
    });
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    _dateCtrl.dispose();
    _vendorCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    _triggerPreview();
  }

  void _triggerPreview() async {
    final amt = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amt <= 0) {
      setState(() => _previewData = null);
      return;
    }
    final baseAmt = _isGstInclusive ? (amt / (1 + _gstRate / 100)) : amt;
    final preview = await context.read<DocumentProvider>().previewExpense(baseAmt, _gstRate);
    if (mounted) {
      setState(() => _previewData = preview);
    }
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

  void _addNewCategoryDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Category Name *'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              final success = await context.read<DocumentProvider>().createExpenseCategory(name);
              if (success && mounted) {
                AppToast.success(context, 'Category created');
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      AppToast.error(context, 'Please select an expense category');
      return;
    }

    setState(() => _isSaving = true);

    final amt = double.parse(_amountCtrl.text);
    final baseAmt = _isGstInclusive ? (amt / (1 + _gstRate / 100)) : amt;

    final payload = {
      'expense_category_id': _categoryId,
      'bank_account_id': _bankAccountId,
      'expense_date': _dateCtrl.text,
      'vendor_name': _vendorCtrl.text.trim().isEmpty ? null : _vendorCtrl.text.trim(),
      'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'amount': baseAmt,
      'gst_rate': _gstRate,
    };

    final provider = context.read<DocumentProvider>();
    final success = widget.editExpense != null
        ? await provider.updateExpense(widget.editExpense!['id'], payload)
        : await provider.createExpense(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        AppToast.success(context, widget.editExpense != null ? 'Expense updated' : 'Expense recorded');
        Navigator.pop(context, true);
      } else {
        AppToast.error(context, provider.errorMessage ?? 'Failed to save expense');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final docProvider = context.watch<DocumentProvider>();
    final acctProvider = context.watch<AccountingProvider>();

    final categories = docProvider.expenseCategories;
    final allAccounts = acctProvider.accountsList ?? [];

    final bankAccounts = allAccounts.where((a) {
      final type = a['account_type'] ?? '';
      final name = (a['name'] ?? '').toString();
      return type == 'ASSET' && (name.startsWith('Cash') || name.startsWith('Bank'));
    }).toList();

    final title = widget.editExpense != null ? 'Edit Expense' : 'Record Expense';

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
              title: 'EXPENSE DETAILS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppDropdown<String>(
                          value: _categoryId,
                          label: 'Category *',
                          prefixIcon: Icons.category_outlined,
                          items: categories.map((c) {
                            return DropdownMenuItem<String>(
                              value: c['id']?.toString(),
                              child: Text(c['name'] ?? 'N/A'),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _categoryId = val),
                          validator: (val) => val == null ? 'Category is required' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.brandNavy),
                        onPressed: _addNewCategoryDialog,
                        tooltip: 'Add category',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppDropdown<String>(
                    value: _bankAccountId,
                    label: 'Paid From (Bank/Cash Account)',
                    prefixIcon: Icons.account_balance_wallet_outlined,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Unspecified'),
                      ),
                      ...bankAccounts.map((a) {
                        return DropdownMenuItem<String>(
                          value: a['id']?.toString(),
                          child: Text(a['name'] ?? 'N/A'),
                        );
                      }),
                    ],
                    onChanged: (val) => setState(() => _bankAccountId = val),
                  ),
                  const SizedBox(height: 16),
                  AppDateField(
                    controller: _dateCtrl,
                    label: 'Expense Date *',
                    onTap: _pickDate,
                    validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Amounts Card
            _FormCard(
              title: 'AMOUNT & TAX',
              child: Column(
                children: [
                  AppTextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    label: 'Amount (₹) *',
                    prefixIcon: Icons.attach_money_outlined,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Amount required';
                      final amt = double.tryParse(v);
                      if (amt == null || amt <= 0) return 'Enter a valid positive amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppDropdown<double>(
                    value: _gstRate,
                    label: 'GST Rate (%)',
                    prefixIcon: Icons.percent,
                    items: const [
                      DropdownMenuItem(value: 0.0, child: Text('0%')),
                      DropdownMenuItem(value: 5.0, child: Text('5%')),
                      DropdownMenuItem(value: 12.0, child: Text('12%')),
                      DropdownMenuItem(value: 18.0, child: Text('18%')),
                      DropdownMenuItem(value: 28.0, child: Text('28%')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _gstRate = val;
                        });
                        _triggerPreview();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Checkbox(
                        value: _isGstInclusive,
                        activeColor: AppColors.brandNavy,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _isGstInclusive = val;
                            });
                            _triggerPreview();
                          }
                        },
                      ),
                      const Text(
                        'GST Inclusive',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Additional Info
            _FormCard(
              title: 'ADDITIONAL INFORMATION',
              child: Column(
                children: [
                  AppTextField(
                    controller: _vendorCtrl,
                    label: 'Vendor Name',
                    prefixIcon: Icons.store_outlined,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Preview Summary
            if (_previewData != null) ...[
              _FormCard(
                title: 'TAX SUMMARY',
                child: Column(
                  children: [
                    SummaryRow(label: 'Subtotal', value: '₹${double.parse(_previewData!['amount'].toString()).toStringAsFixed(2)}'),
                    SummaryRow(label: 'CGST', value: '₹${double.parse(_previewData!['cgst_amount'].toString()).toStringAsFixed(2)}'),
                    SummaryRow(label: 'SGST', value: '₹${double.parse(_previewData!['sgst_amount'].toString()).toStringAsFixed(2)}'),
                    SummaryRow(label: 'IGST', value: '₹${double.parse(_previewData!['igst_amount'].toString()).toStringAsFixed(2)}'),
                    SummaryRow(label: 'Round Off', value: '₹${double.parse(_previewData!['round_off'].toString()).toStringAsFixed(2)}'),
                    const Divider(),
                    SummaryRow(
                      label: 'Total Amount',
                      value: '₹${double.parse(_previewData!['total'].toString()).toStringAsFixed(2)}',
                      isBold: true,
                      valueColor: AppColors.brandNavy,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormCard({required this.title, required this.child});

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
          Text(title, style: AppTextStyles.labelSmall),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
