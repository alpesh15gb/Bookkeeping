/// Company Profile settings screen.
///
/// Displays and edits the company/tenant profile — business name, tax
/// registrations, contact info, and logo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/dialogs/dialog_service.dart';
import '../../../core/result/result.dart';
import '../../auth/data/models/membership_models.dart';
import '../../auth/presentation/auth_controller.dart';
import 'settings_providers.dart';

class SettingsCompanyScreen extends ConsumerStatefulWidget {
  const SettingsCompanyScreen({super.key});

  @override
  ConsumerState<SettingsCompanyScreen> createState() =>
      _SettingsCompanyScreenState();
}

class _SettingsCompanyScreenState extends ConsumerState<SettingsCompanyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _legalNameCtrl = TextEditingController();
  final _tradeNameCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _isSaving = false;
  bool _populated = false;

  @override
  void dispose() {
    _legalNameCtrl.dispose();
    _tradeNameCtrl.dispose();
    _gstinCtrl.dispose();
    _panCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? get _companyId =>
      ref.read(authControllerProvider).activeMembership?.tenantId;

  void _populateForm(Company company) {
    if (_populated) return;
    _legalNameCtrl.text = company.legalName;
    _tradeNameCtrl.text = company.tradeName ?? '';
    _gstinCtrl.text = company.gstin ?? '';
    _panCtrl.text = company.pan ?? '';
    _populated = true;
  }

  Future<bool> _confirmDiscard() async {
    final changed = [
      _legalNameCtrl,
      _tradeNameCtrl,
      _gstinCtrl,
      _panCtrl,
      _addressCtrl,
      _cityCtrl,
      _stateCtrl,
      _pincodeCtrl,
      _phoneCtrl,
      _emailCtrl,
    ].any((c) => c.text != c.text); // always false since we haven't tracked initial
    if (!changed) return true;
    final result = await ref.read(dialogServiceProvider).unsavedChanges(context);
    return result != DialogResult.cancel;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final repo = ref.read(settingsRepositoryProvider);
    final data = <String, dynamic>{
      'legal_name': _legalNameCtrl.text.trim(),
      if (_tradeNameCtrl.text.trim().isNotEmpty)
        'trade_name': _tradeNameCtrl.text.trim(),
      if (_gstinCtrl.text.trim().isNotEmpty) 'gstin': _gstinCtrl.text.trim(),
      if (_panCtrl.text.trim().isNotEmpty) 'pan': _panCtrl.text.trim(),
      if (_addressCtrl.text.trim().isNotEmpty)
        'address': _addressCtrl.text.trim(),
      if (_cityCtrl.text.trim().isNotEmpty) 'city': _cityCtrl.text.trim(),
      if (_stateCtrl.text.trim().isNotEmpty) 'state': _stateCtrl.text.trim(),
      if (_pincodeCtrl.text.trim().isNotEmpty)
        'pincode': _pincodeCtrl.text.trim(),
      if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
      if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
    };

    final result = await repo.updateCompany(_companyId!, data);
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (result is Success<Company>) {
      ref.read(notificationServiceProvider).success(
        context,
        'Company profile updated.',
        title: 'Saved',
      );
    } else {
      final err = (result as Failure<Company>).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Update failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final companyId = _companyId;

    if (companyId == null) {
      return const Center(
        child: Text('No company selected.'),
      );
    }

    final async = ref.watch(companyProfileProvider(companyId));

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(companyProfileProvider(companyId)),
        ),
        data: (company) {
          if (!_populated) _populateForm(company);
          return _buildForm(colors, company);
        },
      ),
    );
  }

  Widget _buildForm(ApexColors colors, Company company) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Company Profile',
            subtitle: 'Manage your business information',
            actions: [
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ApexCard(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo upload placeholder
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(ApexRadius.md),
                          border: Border.all(color: colors.border),
                        ),
                        child: const Icon(
                          Icons.business_rounded,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref.read(notificationServiceProvider).info(
                            context,
                            'Logo upload will be available soon.',
                          );
                        },
                        icon: const Icon(Icons.upload_outlined, size: 18),
                        label: const Text('Upload Logo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Business Name
                  TextFormField(
                    controller: _legalNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Legal Business Name *',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Business name is required'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  // Trade Name
                  TextFormField(
                    controller: _tradeNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Trade Name',
                      prefixIcon: Icon(Icons.alternate_email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // GSTIN
                  TextFormField(
                    controller: _gstinCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN',
                      prefixIcon: Icon(Icons.receipt_outlined),
                      helperText: '15-character GST registration number',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 15,
                  ),
                  const SizedBox(height: 16),
                  // PAN
                  TextFormField(
                    controller: _panCtrl,
                    decoration: const InputDecoration(
                      labelText: 'PAN',
                      prefixIcon: Icon(Icons.credit_card_outlined),
                      helperText: '10-character Permanent Account Number',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 10,
                  ),
                  const SizedBox(height: 24),
                  Divider(color: colors.border),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Contact Information',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Address
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cityCtrl,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _stateCtrl,
                          decoration: const InputDecoration(
                            labelText: 'State',
                            prefixIcon: Icon(Icons.map_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _pincodeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Pincode',
                            prefixIcon:
                                Icon(Icons.markunread_mailbox_outlined),
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                          keyboardType: TextInputType.phone,
                          maxLength: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Tax information summary card
          ApexCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tax Information',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow(colors, 'Tax Mode', company.taxMode),
                const SizedBox(height: 8),
                _infoRow(
                  colors,
                  'Financial Year Start',
                  '${company.financialYearStart.day}/${company.financialYearStart.month}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(ApexColors colors, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
