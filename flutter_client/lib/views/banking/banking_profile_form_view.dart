import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class BankingProfileFormView extends StatefulWidget {
  final Map<String, dynamic>? profile;

  const BankingProfileFormView({super.key, this.profile});

  @override
  State<BankingProfileFormView> createState() => _BankingProfileFormViewState();
}

class _BankingProfileFormViewState extends State<BankingProfileFormView> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  late final TextEditingController _bankNameCtrl;
  late final TextEditingController _accountNumberCtrl;
  late final TextEditingController _ifscCtrl;
  late final TextEditingController _holderNameCtrl;
  late final TextEditingController _upiIdCtrl;
  late final TextEditingController _branchCtrl;
  bool _isPrimary = false;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _bankNameCtrl = TextEditingController(text: p?['bank_name'] ?? '');
    _accountNumberCtrl = TextEditingController(text: p?['account_number'] ?? '');
    _ifscCtrl = TextEditingController(text: p?['ifsc_code'] ?? '');
    _holderNameCtrl = TextEditingController(text: p?['account_holder_name'] ?? '');
    _upiIdCtrl = TextEditingController(text: p?['upi_id'] ?? '');
    _branchCtrl = TextEditingController(text: p?['branch'] ?? '');
    _isPrimary = p?['is_primary'] == true;
    _isActive = p?['is_active'] ?? true;
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ifscCtrl.dispose();
    _holderNameCtrl.dispose();
    _upiIdCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final payload = <String, dynamic>{
      'bank_name': _bankNameCtrl.text.trim(),
      'account_number': _accountNumberCtrl.text.trim(),
      'ifsc_code': _ifscCtrl.text.trim().isEmpty ? null : _ifscCtrl.text.trim().toUpperCase(),
      'account_holder_name': _holderNameCtrl.text.trim(),
      'upi_id': _upiIdCtrl.text.trim().isEmpty ? null : _upiIdCtrl.text.trim(),
      'branch': _branchCtrl.text.trim().isEmpty ? null : _branchCtrl.text.trim(),
      'is_primary': _isPrimary,
      'is_active': _isActive,
    };

    final provider = context.read<BankingProfileProvider>();
    final success = widget.profile != null
        ? await provider.updateBankingProfile(widget.profile!['id'], payload)
        : await provider.createBankingProfile(payload);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.profile != null ? 'Profile updated' : 'Profile created'), backgroundColor: AppColors.success),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Failed to save'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final title = widget.profile != null ? 'Edit Banking Profile' : 'Add Banking Profile';

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
            _FormCard(
              title: 'BANK DETAILS',
              child: Column(
                children: [
                  TextFormField(
                    controller: _bankNameCtrl,
                    decoration: const InputDecoration(labelText: 'Bank Name *', prefixIcon: Icon(Icons.account_balance, size: 18)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _accountNumberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Account Number *', prefixIcon: Icon(Icons.numbers, size: 18)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _ifscCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'IFSC Code', prefixIcon: Icon(Icons.qr_code, size: 18)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _holderNameCtrl,
                    decoration: const InputDecoration(labelText: 'Account Holder Name *', prefixIcon: Icon(Icons.person, size: 18)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _FormCard(
              title: 'ADDITIONAL INFO',
              child: Column(
                children: [
                  TextFormField(
                    controller: _upiIdCtrl,
                    decoration: const InputDecoration(labelText: 'UPI ID', prefixIcon: Icon(Icons.qr_code_2, size: 18)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _branchCtrl,
                    decoration: const InputDecoration(labelText: 'Branch', prefixIcon: Icon(Icons.location_on_outlined, size: 18)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Primary Account', style: AppTextStyles.h3),
                    subtitle: const Text('Used for GST invoices and default payments', style: AppTextStyles.caption),
                    value: _isPrimary,
                    onChanged: (v) => setState(() => _isPrimary = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Active', style: AppTextStyles.h3),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    contentPadding: EdgeInsets.zero,
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
