import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/payment_provider.dart';
import '../../../providers/contact_provider.dart';
import '../../../models/contact.dart';

/// P1.2 Voucher Keyboard Workflow - Payment Form (F6)
/// Tally-style F-key shortcuts for voucher entry

class PaymentDisbursementFormScreen extends StatefulWidget {
  const PaymentDisbursementFormScreen({super.key});

  @override
  State<PaymentDisbursementFormScreen> createState() => _PaymentDisbursementFormScreenState();
}

class _PaymentDisbursementFormScreenState extends State<PaymentDisbursementFormScreen> {
  final _dateController = TextEditingController();
  final _vendorController = TextEditingController();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _narrationController = TextEditingController();
  
  final _dateFocusNode = FocusNode();
  final _vendorFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();
  final _referenceFocusNode = FocusNode();
  final _narrationFocusNode = FocusNode();
  
  ContactModel? _selectedVendor;
  bool _showVendorSearch = false;
  bool _isLoading = false;
  
  String _selectedMode = 'CASH';
  final List<String> _paymentModes = ['CASH', 'BANK', 'UPI', 'CHEQUE', 'CARD'];

  @override
  void initState() {
    super.initState();
    _dateController.text = _formatDateToday();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContactProvider>().fetchContacts();
      _vendorFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _vendorController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _narrationController.dispose();
    _dateFocusNode.dispose();
    _vendorFocusNode.dispose();
    _amountFocusNode.dispose();
    _referenceFocusNode.dispose();
    _narrationFocusNode.dispose();
    super.dispose();
  }

  String _formatDateToday() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  bool get _canSave => _selectedVendor != null && 
                       _amountController.text.isNotEmpty && 
                       double.tryParse(_amountController.text) != null;

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactProvider>().contacts;
    final vendors = contacts.where((c) => c.contactType == 'VENDOR' || c.contactType == 'BOTH').toList();
    final filteredVendors = _filterVendors(vendors);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.f2): const _ChangeDateIntent(),
        SingleActivator(LogicalKeyboardKey.f6): const _SavePaymentIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true): const _SavePaymentIntent(),
        SingleActivator(LogicalKeyboardKey.escape): const _CloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _ChangeDateIntent: CallbackAction<_ChangeDateIntent>(
            onInvoke: (_) {
              _showDatePicker();
              return null;
            },
          ),
          _SavePaymentIntent: CallbackAction<_SavePaymentIntent>(
            onInvoke: (_) {
              if (_canSave && !_isLoading) _savePayment();
              return null;
            },
          ),
          _CloseIntent: CallbackAction<_CloseIntent>(
            onInvoke: (_) {
              if (mounted) Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: KeyboardListener(
          focusNode: FocusNode(),
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
              _moveToNextField();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: AppSpacing.lg),
              _buildKeyboardHints(),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildDateField(),
                      const SizedBox(height: AppSpacing.md),
                      _buildVendorField(vendors, filteredVendors),
                      const SizedBox(height: AppSpacing.md),
                      _buildPaymentModeField(),
                      const SizedBox(height: AppSpacing.md),
                      _buildAmountField(),
                      const SizedBox(height: AppSpacing.md),
                      _buildReferenceField(),
                      const SizedBox(height: AppSpacing.md),
                      _buildNarrationField(),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.error.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.arrow_upward, color: AppColors.error, size: 24),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment', style: AppTypography.headlineMedium),
                  Text('F6 - Record payment made', style: AppTypography.bodySmall),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        AppButton(
          label: 'Save (Ctrl+S)',
          icon: Icons.save,
          onPressed: _canSave ? _savePayment : null,
          isLoading: _isLoading,
        ),
      ],
    );
  }

  Widget _buildKeyboardHints() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          _hint('F2', 'Change Date'),
          _hint('F6', 'Save Payment'),
          _hint('Ctrl+S', 'Save'),
          _hint('Enter', 'Next Field'),
          _hint('Esc', 'Close'),
        ],
      ),
    );
  }

  Widget _hint(String key, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            border: Border.all(color: AppColors.gray300),
          ),
          child: Text(key, style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.bold, fontSize: 10)),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(action, style: AppTypography.bodySmall.copyWith(color: AppColors.gray600, fontSize: 10)),
      ],
    );
  }

  Widget _buildDateField() {
    return _buildFieldContainer(
      label: 'Date (F2)',
      child: TextField(
        controller: _dateController,
        focusNode: _dateFocusNode,
        readOnly: true,
        decoration: _inputDecoration(Icons.calendar_today, 'Payment date'),
      ),
    );
  }

  Widget _buildVendorField(List<ContactModel> vendors, List<ContactModel> filteredVendors) {
    return _buildFieldContainer(
      label: 'Vendor',
      child: Column(
        children: [
          TextField(
            controller: _vendorController,
            focusNode: _vendorFocusNode,
            decoration: _inputDecoration(Icons.person, 'Select vendor'),
            onChanged: (value) {
              setState(() => _showVendorSearch = true);
            },
            onTap: () => setState(() => _showVendorSearch = true),
          ),
          if (_showVendorSearch && filteredVendors.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.gray200),
                boxShadow: AppShadow.elevated,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filteredVendors.take(8).length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final vendor = filteredVendors[index];
                  return ListTile(
                    dense: true,
                    title: Text(vendor.name, style: AppTypography.labelMedium),
                    subtitle: Text(vendor.phone ?? '', style: AppTypography.bodySmall),
                    onTap: () => _selectVendor(vendor),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentModeField() {
    return _buildFieldContainer(
      label: 'Payment Mode',
      child: DropdownButtonFormField<String>(
        value: _selectedMode,
        decoration: _inputDecoration(Icons.payment, 'Select mode'),
        items: _paymentModes.map((mode) {
          return DropdownMenuItem(value: mode, child: Text(mode));
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _selectedMode = value);
        },
      ),
    );
  }

  Widget _buildAmountField() {
    return _buildFieldContainer(
      label: 'Amount',
      child: TextField(
        controller: _amountController,
        focusNode: _amountFocusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _inputDecoration(Icons.currency_rupee, 'Enter amount'),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _buildReferenceField() {
    return _buildFieldContainer(
      label: 'Reference No.',
      child: TextField(
        controller: _referenceController,
        focusNode: _referenceFocusNode,
        decoration: _inputDecoration(Icons.tag, 'Cheque/Transaction reference'),
      ),
    );
  }

  Widget _buildNarrationField() {
    return _buildFieldContainer(
      label: 'Narration',
      child: TextField(
        controller: _narrationController,
        focusNode: _narrationFocusNode,
        maxLines: 3,
        decoration: _inputDecoration(Icons.note_alt, 'Additional notes'),
      ),
    );
  }

  Widget _buildFieldContainer({required String label, required Widget child}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint) {
    return InputDecoration(
      prefixIcon: Icon(icon, size: 20),
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.gray200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.gray200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  List<ContactModel> _filterVendors(List<ContactModel> vendors) {
    final query = _vendorController.text.trim().toLowerCase();
    if (query.isEmpty) return vendors;
    return vendors.where((c) {
      final values = [
        c.name.toLowerCase(),
        c.phone?.toLowerCase() ?? '',
        c.gstin?.toLowerCase() ?? '',
      ];
      return values.any((v) => v.contains(query));
    }).toList();
  }

  void _selectVendor(ContactModel vendor) {
    setState(() {
      _selectedVendor = vendor;
      _vendorController.text = vendor.name;
      _showVendorSearch = false;
    });
    _moveToNextField();
  }

  void _moveToNextField() {
    if (_vendorFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_amountFocusNode);
    } else if (_amountFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_referenceFocusNode);
    } else if (_referenceFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_narrationFocusNode);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _showDatePicker() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null && mounted) {
      setState(() {
        _dateController.text = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      });
    }
  }

  Future<void> _savePayment() async {
    if (!_canSave) return;
    
    setState(() => _isLoading = true);
    
    final paymentProvider = context.read<PaymentProvider>();
    final payload = {
      'contact_id': _selectedVendor!.id,
      'payment_date': _dateController.text,
      'amount': double.parse(_amountController.text),
      'payment_mode': _selectedMode,
      'reference_number': _referenceController.text.trim(),
      'narration': _narrationController.text.trim(),
    };
    
    final success = await paymentProvider.createDisbursement(payload);
    
    if (!mounted) return;
    setState(() => _isLoading = false);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment saved successfully'), backgroundColor: AppColors.success),
      );
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(paymentProvider.errorMessage ?? 'Failed to save payment')),
      );
    }
  }
}

class _ChangeDateIntent extends Intent { const _ChangeDateIntent(); }
class _SavePaymentIntent extends Intent { const _SavePaymentIntent(); }
class _CloseIntent extends Intent { const _CloseIntent(); }