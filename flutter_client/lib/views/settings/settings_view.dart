import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/auth/change_password_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  // Controllers for edit dialog
  final _legalNameCtrl = TextEditingController();
  final _tradeNameCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _stateCodeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankAccCtrl = TextEditingController();
  final _bankIfscCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().fetchAllSettings();
    });
  }

  @override
  void dispose() {
    _legalNameCtrl.dispose();
    _tradeNameCtrl.dispose();
    _gstinCtrl.dispose();
    _panCtrl.dispose();
    _stateCodeCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _websiteCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankBranchCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  String _selectedTemplate = 'professional';

  void _showEditDialog(Map<String, dynamic> company, Map<String, dynamic> settings) {
    _legalNameCtrl.text = company['legal_name'] ?? '';
    _tradeNameCtrl.text = company['trade_name'] ?? '';
    _gstinCtrl.text = company['gstin'] ?? '';
    _panCtrl.text = company['pan'] ?? '';
    _stateCodeCtrl.text = settings['origin_state_code'] ?? '';

    final extraSettings = settings['extra_settings'] as Map<String, dynamic>? ?? {};
    _selectedTemplate = extraSettings['pdf_template'] ?? 'professional';
    _addressCtrl.text = extraSettings['company_address'] ?? '';
    _phoneCtrl.text = extraSettings['company_phone'] ?? '';
    _emailCtrl.text = extraSettings['company_email'] ?? '';
    _websiteCtrl.text = extraSettings['company_website'] ?? '';
    _bankNameCtrl.text = extraSettings['bank_name'] ?? '';
    _bankAccCtrl.text = extraSettings['bank_account_no'] ?? '';
    _bankIfscCtrl.text = extraSettings['bank_ifsc'] ?? '';
    _bankBranchCtrl.text = extraSettings['bank_branch'] ?? '';
    _termsCtrl.text = extraSettings['terms'] ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Company Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _legalNameCtrl,
                  decoration: const InputDecoration(labelText: 'Legal Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tradeNameCtrl,
                  decoration: const InputDecoration(labelText: 'Trade Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gstinCtrl,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN',
                    hintText: 'e.g. 27AAPFU0939F1ZV',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _panCtrl,
                  decoration: const InputDecoration(
                    labelText: 'PAN',
                    hintText: 'e.g. AAPFU0939F',
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stateCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Origin State Code',
                    hintText: 'e.g. 27 for Maharashtra',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Company physical address',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone',
                    hintText: 'e.g. 8521794522',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact Email',
                    hintText: 'e.g. info@company.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _websiteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    hintText: 'e.g. www.company.com',
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Bank Details', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                TextField(
                  controller: _bankNameCtrl,
                  decoration: const InputDecoration(labelText: 'Bank Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankAccCtrl,
                  decoration: const InputDecoration(labelText: 'Account Number'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankIfscCtrl,
                  decoration: const InputDecoration(labelText: 'IFSC Code'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankBranchCtrl,
                  decoration: const InputDecoration(labelText: 'Branch Name'),
                ),
                const SizedBox(height: 12),
                const Divider(),
                TextField(
                  controller: _termsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terms & Conditions',
                    hintText: 'Default terms for invoices',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedTemplate,
                  decoration: const InputDecoration(
                    labelText: 'Default PDF Template',
                    prefixIcon: Icon(Icons.picture_as_pdf_outlined, size: 18),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'professional', child: Text('Professional (Navy)')),
                    DropdownMenuItem(value: 'modern', child: Text('Modern (Indigo)')),
                    DropdownMenuItem(value: 'thermal', child: Text('Thermal / POS')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => _selectedTemplate = v);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _saveSettings();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    final companyPayload = {
      'legal_name': _legalNameCtrl.text,
      'trade_name': _tradeNameCtrl.text.isNotEmpty ? _tradeNameCtrl.text : _legalNameCtrl.text,
      'gstin': _gstinCtrl.text.isNotEmpty ? _gstinCtrl.text : null,
      'pan': _panCtrl.text.isNotEmpty ? _panCtrl.text : null,
    };

    final provider = context.read<SettingsProvider>();
    final extraSettings = provider.settings['extra_settings'] as Map<String, dynamic>? ?? {};

    final settingsPayload = <String, dynamic>{
      'extra_settings': {
        ...extraSettings,
        'pdf_template': _selectedTemplate,
        'company_address': _addressCtrl.text,
        'company_phone': _phoneCtrl.text,
        'company_email': _emailCtrl.text,
        'company_website': _websiteCtrl.text,
        'bank_name': _bankNameCtrl.text,
        'bank_account_no': _bankAccCtrl.text,
        'bank_ifsc': _bankIfscCtrl.text,
        'bank_branch': _bankBranchCtrl.text,
        'terms': _termsCtrl.text,
      }
    };
    if (_stateCodeCtrl.text.isNotEmpty) {
      settingsPayload['origin_state_code'] = _stateCodeCtrl.text;
    }

    final success = await provider.saveSettings(
      companyPayload: companyPayload,
      settingsPayload: settingsPayload,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        final err = context.read<SettingsProvider>().errorMessage ?? 'Failed to save settings';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final settingsProvider = context.watch<SettingsProvider>();

    if (settingsProvider.isLoading && settingsProvider.company.isEmpty) {
      return const LoadingState(message: 'Loading settings...');
    }
    if (settingsProvider.errorMessage != null && settingsProvider.company.isEmpty) {
      return ErrorState(
        message: settingsProvider.errorMessage!,
        onRetry: () => context.read<SettingsProvider>().fetchAllSettings(),
      );
    }

    final company = settingsProvider.company;
    final settings = settingsProvider.settings;

    final legalName = company['legal_name'] ?? 'Not set';
    final tradeName = company['trade_name'] ?? '';
    final gstin = company['gstin'] ?? 'Not configured';
    final pan = company['pan'] ?? 'Not configured';
    final currency = settings['currency'] ?? 'INR';
    final gstEnabled = settings['gst_enabled'] == true;
    final stateCode = settings['origin_state_code'] ?? 'Not configured';
    final extraSettings = settings['extra_settings'] as Map<String, dynamic>? ?? {};
    final pdfTemplate = extraSettings['pdf_template'] ?? 'professional';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: ListView(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        children: [
          // Company Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Company', style: AppTextStyles.h3),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Text('Active', style: TextStyle(fontSize: 11, color: AppColors.brandNavy, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _settingRow(Icons.business_outlined, 'Legal Name', legalName),
                if (tradeName.isNotEmpty && tradeName != legalName)
                  _settingRow(Icons.storefront_outlined, 'Trade Name', tradeName),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tax & Compliance Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tax & Compliance', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                _settingRow(Icons.badge_outlined, 'GSTIN', gstin),
                _settingRow(Icons.numbers_outlined, 'PAN', pan),
                _settingRow(Icons.location_city_outlined, 'Origin State Code', stateCode),
                _settingRow(
                  Icons.fact_check_outlined,
                  'GST Enabled',
                  gstEnabled ? 'Yes' : 'No',
                  valueColor: gstEnabled ? AppColors.success : AppColors.textMuted,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Preferences Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Preferences', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                _settingRow(Icons.monetization_on_outlined, 'Currency', currency),
                _settingRow(
                  Icons.calendar_month_outlined,
                  'Financial Year',
                  DateTime.now().month >= 4 ? '${DateTime.now().year}-${(DateTime.now().year + 1).toString().substring(2)}' : '${(DateTime.now().year - 1)}-${DateTime.now().year.toString().substring(2)}',
                ),
                _settingRow(
                  Icons.picture_as_pdf_outlined,
                  'PDF Template Style',
                  pdfTemplate.toString().toUpperCase(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Numbering Series Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Numbering Series', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                if (settingsProvider.numberingSeries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No numbering series configured', style: AppTextStyles.bodySmall),
                  ),
                ...settingsProvider.numberingSeries.map((series) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.tag_outlined, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          series['document_type'] ?? 'Unknown',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${series['prefix'] ?? ''}${'0' * (series['padding_digits'] ?? 4)}${series['suffix'] ?? ''}',
                        style: AppTextStyles.caption.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.brandNavy),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showEditSeriesDialog(series),
                        tooltip: 'Edit numbering series',
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Branches Section
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Branches', style: AppTextStyles.h3),
                const SizedBox(height: 12),
                if (settingsProvider.branches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No branches configured', style: AppTextStyles.bodySmall),
                  ),
                ...settingsProvider.branches.map((branch) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.business_outlined, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          branch['name'] ?? 'Unknown',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        branch['gstin'] ?? branch['state_code'] ?? '',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Edit button
          settingsProvider.isSaving
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ActionButton(
                      label: 'Edit Company Settings',
                      tier: ActionTier.safe,
                      onPressed: () => _showEditDialog(company, settings),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChangePasswordView()),
                        );
                      },
                      icon: const Icon(Icons.lock_outlined, size: 16),
                      label: const Text('Change Password'),
                    ),
                    const SizedBox(height: 12),
                    ActionButton(
                      label: 'Purge Company Data',
                      tier: ActionTier.dangerous,
                      icon: Icons.delete_forever_outlined,
                      onPressed: _requestPurge,
                    ),
                  ],
                ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showEditSeriesDialog(Map<String, dynamic> series) {
    final prefixCtrl = TextEditingController(text: series['prefix'] ?? '');
    final nextNumberCtrl = TextEditingController(text: (series['next_number'] ?? 1).toString());
    final paddingCtrl = TextEditingController(text: (series['padding_digits'] ?? 4).toString());
    final suffixCtrl = TextEditingController(text: series['suffix'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Series: ${series['document_type']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: prefixCtrl,
                decoration: const InputDecoration(labelText: 'Prefix', hintText: 'e.g. INV/2026/'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nextNumberCtrl,
                decoration: const InputDecoration(labelText: 'Next Number'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: paddingCtrl,
                decoration: const InputDecoration(labelText: 'Padding Digits (e.g. 4 for 0001)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: suffixCtrl,
                decoration: const InputDecoration(labelText: 'Suffix (Optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final prefix = prefixCtrl.text;
              final nextVal = int.tryParse(nextNumberCtrl.text);
              final padVal = int.tryParse(paddingCtrl.text);
              final suffix = suffixCtrl.text.isNotEmpty ? suffixCtrl.text : null;

              if (nextVal == null || nextVal < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Next Number must be 1 or greater'), backgroundColor: AppColors.error),
                );
                return;
              }

              if (padVal == null || padVal < 1 || padVal > 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Padding Digits must be between 1 and 10'), backgroundColor: AppColors.error),
                );
                return;
              }
              
              final success = await context.read<SettingsProvider>().updateNumberingSeries(
                series['id'],
                {
                  'prefix': prefix,
                  'next_number': nextVal,
                  'padding_digits': padVal,
                  'suffix': suffix,
                },
              );
              if (mounted) {
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Numbering series updated successfully'), backgroundColor: AppColors.success),
                  );
                } else {
                  final err = context.read<SettingsProvider>().errorMessage ?? 'Update failed';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _settingRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            value,
            style: AppTextStyles.caption.copyWith(
              color: valueColor ?? AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPurge() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Purge Company Data'),
          ],
        ),
        content: const Text(
          'WARNING: This will permanently delete all invoices, bills, estimates, '
          'payments, contacts, products, and expenses for this company context.\n\n'
          'This action CANNOT be undone. Are you sure you want to proceed and receive a verification OTP on your email?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(ctx);
              _sendPurgeOtpRequest();
            },
            child: const Text('Yes, Request OTP'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPurgeOtpRequest() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Requesting verification OTP...')),
    );
    try {
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/purge/request'),
        headers: {
          if (ApiClient.accessToken != null)
            'Authorization': 'Bearer ${ApiClient.accessToken}',
          if (ApiClient.tenantId != null)
            'X-Tenant-ID': ApiClient.tenantId!,
        },
      );

      if (response.statusCode == 200) {
        _showOtpVerifyDialog();
      } else {
        String msg = 'Failed to request OTP';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) msg = body['detail']?.toString() ?? msg;
        } catch (_) {}
        _showError(msg);
      }
    } catch (e) {
      _showError('Connection error: $e');
    }
  }

  Future<void> _showOtpVerifyDialog() {
    final otpCtrl = TextEditingController();
    bool verifying = false;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Enter Verification OTP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('A 6-digit OTP code has been sent to your registered email address.'),
              const SizedBox(height: 16),
              TextField(
                controller: otpCtrl,
                decoration: const InputDecoration(
                  labelText: 'OTP Code',
                  hintText: 'e.g. 123456',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              if (verifying) ...[
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
              ]
            ],
          ),
          actions: [
            TextButton(
              onPressed: verifying ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: verifying
                  ? null
                  : () async {
                      final otp = otpCtrl.text.trim();
                      if (otp.length != 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('OTP must be 6 digits')),
                        );
                        return;
                      }

                      setDialogState(() => verifying = true);
                      try {
                        final res = await http.post(
                          Uri.parse('${ApiClient.baseUrl}/purge/verify'),
                          headers: {
                            'Content-Type': 'application/json',
                            if (ApiClient.accessToken != null)
                              'Authorization': 'Bearer ${ApiClient.accessToken}',
                            if (ApiClient.tenantId != null)
                              'X-Tenant-ID': ApiClient.tenantId!,
                          },
                          body: jsonEncode({'otp': otp}),
                        );

                        if (res.statusCode == 200) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Company data purged successfully.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                          context.read<SettingsProvider>().fetchAllSettings();
                        } else {
                          String msg = 'Purge verification failed';
                          try {
                            final body = jsonDecode(res.body);
                            if (body is Map) msg = body['detail']?.toString() ?? msg;
                          } catch (_) {}
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(msg), backgroundColor: AppColors.error),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                        );
                      } finally {
                        setDialogState(() => verifying = false);
                      }
                    },
              child: const Text('Purge Data'),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}
