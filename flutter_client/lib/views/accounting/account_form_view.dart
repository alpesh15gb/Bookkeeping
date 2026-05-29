import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/accounting_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';

class AccountFormView extends StatefulWidget {
  final Map<String, dynamic>? editAccount;
  final VoidCallback onSuccess;

  const AccountFormView({
    super.key,
    this.editAccount,
    required this.onSuccess,
  });

  @override
  State<AccountFormView> createState() => _AccountFormViewState();
}

class _AccountFormViewState extends State<AccountFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String? _accountType;
  bool _isSubmitting = false;

  final _types = ['ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE', 'CONTRA'];

  @override
  void initState() {
    super.initState();
    if (widget.editAccount != null) {
      _nameCtrl.text = widget.editAccount!['name'] ?? '';
      _codeCtrl.text = widget.editAccount!['code'] ?? '';
      _accountType = widget.editAccount!['account_type'];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420,
      padding: AppSpacing.cardPadding,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_outlined, color: AppColors.brandNavy, size: 22),
                const SizedBox(width: 10),
                Text(widget.editAccount != null ? 'Edit Account' : 'New Account', style: AppTextStyles.h2),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Account Name'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _accountType,
              decoration: const InputDecoration(labelText: 'Account Type'),
              items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => _accountType = v,
              validator: (v) => v == null ? 'Select type' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeCtrl,
              decoration: const InputDecoration(labelText: 'Account Code (optional)'),
            ),
            const SizedBox(height: 24),
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

    final payload = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'account_type': _accountType,
      if (_codeCtrl.text.isNotEmpty) 'code': _codeCtrl.text.trim(),
    };

    final provider = context.read<AccountingProvider>();
    final success = widget.editAccount != null
        ? await provider.updateAccount(widget.editAccount!['id'], payload)
        : await provider.createAccount(payload);

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
