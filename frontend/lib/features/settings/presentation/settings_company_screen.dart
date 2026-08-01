/// Company Profile settings screen.
///
/// Displays and edits the company/tenant profile — business name, tax
/// registrations, contact info, and logo.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/data/models/membership_models.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/models/tenant_settings.dart';
import 'settings_providers.dart';
import 'package:apexbooks/core/errors/user_message.dart';

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

  void _populateForm(Company company, TenantSettings settings) {
    if (_populated) return;
    _legalNameCtrl.text = company.legalName;
    _tradeNameCtrl.text = company.tradeName ?? '';
    _gstinCtrl.text = company.gstin ?? '';
    _panCtrl.text = company.pan ?? '';
    final extra = settings.extraSettings;
    final address = extra['company_address'];
    if (address is Map) {
      _addressCtrl.text = (address['street'] ?? '').toString();
      _cityCtrl.text = (address['city'] ?? '').toString();
      _stateCtrl.text = (address['state'] ?? '').toString();
      _pincodeCtrl.text = (address['pincode'] ?? '').toString();
    } else if (address != null) {
      _addressCtrl.text = address.toString();
    }
    _phoneCtrl.text = (extra['company_phone'] ?? '').toString();
    _emailCtrl.text = (extra['company_email'] ?? '').toString();
    _populated = true;
  }

  Future<void> _save(Company company, TenantSettings settings) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final repo = ref.read(settingsRepositoryProvider);
    final data = <String, dynamic>{
      'legal_name': _legalNameCtrl.text.trim(),
      'trade_name': _tradeNameCtrl.text.trim().isEmpty
          ? null
          : _tradeNameCtrl.text.trim(),
      'gstin': _gstinCtrl.text.trim().isEmpty
          ? null
          : _gstinCtrl.text.trim().toUpperCase(),
      'pan': _panCtrl.text.trim().isEmpty
          ? null
          : _panCtrl.text.trim().toUpperCase(),
      // The deployed update endpoint uses CompanyCreate. Always preserve these
      // values so an ordinary profile edit cannot reset tax/FY configuration.
      'tax_mode': company.taxMode,
      'financial_year_start': company.financialYearStart
          .toIso8601String()
          .split('T')
          .first,
    };

    final result = await repo.updateCompany(_companyId!, data);
    Result<TenantSettings>? settingsResult;
    if (result is Success<Company>) {
      final extra = Map<String, dynamic>.from(settings.extraSettings)
        ..['company_address'] = {
          'street': _addressCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'state': _stateCtrl.text.trim(),
          'pincode': _pincodeCtrl.text.trim(),
          'country': 'India',
        }
        ..['company_phone'] = _phoneCtrl.text.trim()
        ..['company_email'] = _emailCtrl.text.trim();
      settingsResult = await repo.updateTenantSettings({
        'extra_settings': extra,
      });
    }
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (result is Success<Company> &&
        settingsResult is Success<TenantSettings>) {
      ref.invalidate(companyProfileProvider(_companyId!));
      ref.invalidate(tenantSettingsProvider);
      ref
          .read(notificationServiceProvider)
          .success(context, 'Company profile updated.', title: 'Saved');
    } else {
      final err = result is Failure<Company>
          ? result.error
          : (settingsResult as Failure<TenantSettings>).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Update failed');
    }
  }

  Future<void> _uploadLogo() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null || !mounted) return;
    final result = await ref
        .read(settingsRepositoryProvider)
        .uploadLogo(bytes: file.bytes!, filename: file.name);
    if (!mounted) return;
    if (result is Success<String>) {
      ref.invalidate(tenantSettingsProvider);
      ref
          .read(notificationServiceProvider)
          .success(context, 'Company logo updated.', title: 'Logo saved');
    } else {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            (result as Failure<String>).error.message,
            title: 'Upload failed',
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final companyId = _companyId;

    if (companyId == null) {
      return const Center(child: Text('No company selected.'));
    }

    final async = ref.watch(companyProfileProvider(companyId));

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(companyProfileProvider(companyId)),
        ),
        data: (company) => ref
            .watch(tenantSettingsProvider)
            .when(
              loading: () => const Center(child: LoadingSpinner(size: 36)),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(tenantSettingsProvider),
              ),
              data: (settings) {
                if (!_populated) _populateForm(company, settings);
                return _buildForm(colors, company, settings);
              },
            ),
      ),
    );
  }

  Widget _buildForm(
    ApexColors colors,
    Company company,
    TenantSettings settings,
  ) {
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
                onPressed: _isSaving ? null : () => _save(company, settings),
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
                        child: settings.logoUrl == null
                            ? const Icon(Icons.business_rounded, size: 36)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  ApexRadius.md,
                                ),
                                child: Image.network(
                                  settings.logoUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.broken_image_outlined,
                                    size: 32,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      OutlinedButton.icon(
                        onPressed: _uploadLogo,
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
                    validator: (v) => (v == null || v.trim().isEmpty)
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
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    validator: (value) {
                      final gstin = value?.trim().toUpperCase() ?? '';
                      if (company.taxMode != 'NON_GST' && gstin.isEmpty) {
                        return 'GSTIN is required while GST is enabled';
                      }
                      if (gstin.isNotEmpty &&
                          !RegExp(
                            r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                          ).hasMatch(gstin)) {
                        return 'Enter a valid 15-character GSTIN';
                      }
                      return null;
                    },
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
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    validator: (value) {
                      final pan = value?.trim().toUpperCase() ?? '';
                      if (pan.isNotEmpty &&
                          !RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) {
                        return 'Enter a valid 10-character PAN';
                      }
                      return null;
                    },
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
                            prefixIcon: Icon(Icons.markunread_mailbox_outlined),
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
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
      ],
    );
  }
}
