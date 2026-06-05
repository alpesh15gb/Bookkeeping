import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/providers/theme_provider.dart';
import 'package:flutter_client/core/sync_manager.dart';
import 'package:flutter_client/views/banking/banking_profile_form_view.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard, AppEmptyState;
import 'package:flutter_client/views/shared/design_system.dart';
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
  final _termsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().fetchAllSettings();
      context.read<BankingProfileProvider>().fetchBankingProfiles();
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
    _termsCtrl.dispose();
    super.dispose();
  }

  String _selectedTemplate = 'professional';

  String _getFriendlyDocTypeName(String docType) {
    switch (docType) {
      case 'INVOICE':
        return 'Sales Invoice';
      case 'BILL':
        return 'Vendor Bill';
      case 'PAYMENT':
        return 'Customer Payment';
      case 'JOURNAL':
        return 'Journal Entry';
      case 'RECEIPT':
        return 'Receipt';
      case 'DISBURSEMENT':
        return 'Disbursement';
      case 'CREDIT_NOTE':
        return 'Credit Note';
      case 'DEBIT_NOTE':
        return 'Debit Note';
      case 'PURCHASE_ORDER':
        return 'Purchase Order';
      case 'SALES_ORDER':
        return 'Sales Order';
      case 'DELIVERY_CHALLAN':
        return 'Delivery Challan';
      case 'PROFORMA_INVOICE':
        return 'Estimate / Proforma Invoice';
      case 'SALES_RETURN':
        return 'Sales Return';
      case 'PURCHASE_RETURN':
        return 'Purchase Return';
      default:
        return docType;
    }
  }

  void _populateControllers(
    Map<String, dynamic> company,
    Map<String, dynamic> settings,
  ) {
    _legalNameCtrl.text = company['legal_name'] ?? '';
    _tradeNameCtrl.text = company['trade_name'] ?? '';
    _gstinCtrl.text = company['gstin'] ?? '';
    _panCtrl.text = company['pan'] ?? '';
    _stateCodeCtrl.text = settings['origin_state_code'] ?? '';

    final extraSettings =
        settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings['extra_settings']) : <String, dynamic>{};
    _selectedTemplate = extraSettings['pdf_template'] ?? 'professional';
    _addressCtrl.text = extraSettings['company_address'] ?? '';
    _phoneCtrl.text = extraSettings['company_phone'] ?? '';
    _emailCtrl.text = extraSettings['company_email'] ?? '';
    _websiteCtrl.text = extraSettings['company_website'] ?? '';
    _termsCtrl.text = extraSettings['terms'] ?? '';
  }

  Future<void> _openBankProfileForm(Map<String, dynamic>? primaryBank) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BankingProfileFormView(
          profile: primaryBank,
          defaultPrimary: primaryBank == null,
        ),
      ),
    );
    if (mounted) {
      await context.read<BankingProfileProvider>().fetchBankingProfiles();
    }
  }

  void _showCompanyProfileDialog(
    Map<String, dynamic> company,
    Map<String, dynamic> settings,
  ) {
    _populateControllers(company, settings);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Company Profile'),
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
    );
  }

  void _showTaxComplianceDialog(
    Map<String, dynamic> company,
    Map<String, dynamic> settings,
  ) {
    _populateControllers(company, settings);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Tax & Compliance'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
    );
  }

  void _showPreferencesDialog(
    Map<String, dynamic> company,
    Map<String, dynamic> settings,
  ) {
    _populateControllers(company, settings);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Preferences'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedTemplate,
                  decoration: const InputDecoration(
                    labelText: 'Default PDF Template',
                    prefixIcon: Icon(Icons.picture_as_pdf_outlined, size: 18),
                  ),
                   items: const [
                    DropdownMenuItem(
                      value: 'professional',
                      child: Text('Format 1 (Professional Navy)'),
                    ),
                    DropdownMenuItem(
                      value: 'tally_gst',
                      child: Text('Format 2 (Tally GST style)'),
                    ),
                    DropdownMenuItem(
                      value: 'classic_blue',
                      child: Text('Format 3 (Classic Blue)'),
                    ),
                    DropdownMenuItem(
                      value: 'sleek_modern',
                      child: Text('Format 4 (Sleek Modern)'),
                    ),
                    DropdownMenuItem(
                      value: 'minimal',
                      child: Text('Minimal (Clean)'),
                    ),
                    DropdownMenuItem(
                      value: 'elegant',
                      child: Text('Elegant (Green)'),
                    ),
                    DropdownMenuItem(
                      value: 'thermal',
                      child: Text('Thermal / POS'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => _selectedTemplate = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _termsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Terms & Conditions',
                    hintText: 'Default terms for invoices',
                  ),
                  maxLines: 3,
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
      'trade_name': _tradeNameCtrl.text.isNotEmpty
          ? _tradeNameCtrl.text
          : _legalNameCtrl.text,
      'gstin': _gstinCtrl.text.isNotEmpty ? _gstinCtrl.text : null,
      'pan': _panCtrl.text.isNotEmpty ? _panCtrl.text : null,
    };

    final provider = context.read<SettingsProvider>();
    final extraSettings =
        provider.settings['extra_settings'] is Map ? Map<String, dynamic>.from(provider.settings['extra_settings']) : <String, dynamic>{};
    extraSettings.remove('bank_name');
    extraSettings.remove('bank_account_no');
    extraSettings.remove('bank_ifsc');
    extraSettings.remove('bank_branch');

    final settingsPayload = <String, dynamic>{
      'extra_settings': {
        ...extraSettings,
        'pdf_template': _selectedTemplate,
        'company_address': _addressCtrl.text,
        'company_phone': _phoneCtrl.text,
        'company_email': _emailCtrl.text,
        'company_website': _websiteCtrl.text,
        'terms': _termsCtrl.text,
      },
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
        final err =
            context.read<SettingsProvider>().errorMessage ??
            'Failed to save settings';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final bankingProvider = context.watch<BankingProfileProvider>();

    if (settingsProvider.isLoading && settingsProvider.company.isEmpty) {
      return const LoadingState(message: 'Loading settings...');
    }
    if (settingsProvider.errorMessage != null &&
        settingsProvider.company.isEmpty) {
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
    final extraSettings =
        settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings['extra_settings']) : <String, dynamic>{};
    final pdfTemplate = extraSettings['pdf_template'] ?? 'professional';

    final companyAddress = extraSettings['company_address'] ?? 'Not configured';
    final companyPhone = extraSettings['company_phone'] ?? 'Not configured';
    final companyEmail = extraSettings['company_email'] ?? 'Not configured';
    final companyWebsite = extraSettings['company_website'] ?? 'Not configured';
    final bankProfiles = bankingProvider.profiles.whereType<Map<String, dynamic>>().toList();
    Map<String, dynamic>? primaryBank;
    for (final p in bankProfiles) {
      if (p['is_primary'] == true && p['is_active'] != false) {
        primaryBank = p;
        break;
      }
    }
    if (primaryBank == null) {
      for (final p in bankProfiles) {
        if (p['is_active'] != false) {
          primaryBank = p;
          break;
        }
      }
    }
    final bankName = primaryBank?['bank_name']?.toString() ?? 'Not configured';
    final bankAccountNo = primaryBank?['account_number']?.toString() ?? 'Not configured';
    final bankIfsc = primaryBank?['ifsc_code']?.toString() ?? 'Not configured';
    final bankBranch = primaryBank?['branch_name']?.toString() ?? 'Not configured';
    final terms = extraSettings['terms'] ?? 'No custom terms';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: ListView(
        padding: isMobile
            ? AppSpacing.pagePaddingMobile
            : AppSpacing.pagePadding,
        children: [
          // Company Section
          SectionedCard(
            title: 'Company Profile',
            children: [
              SettingsListTile(
                icon: Icons.business_outlined,
                title: 'Legal Name',
                subtitle: legalName,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              if (tradeName.isNotEmpty && tradeName != legalName)
                SettingsListTile(
                  icon: Icons.storefront_outlined,
                  title: 'Trade Name',
                  subtitle: tradeName,
                  onTap: () => _showCompanyProfileDialog(company, settings),
                ),
              SettingsListTile(
                icon: Icons.location_on_outlined,
                title: 'Address',
                subtitle: companyAddress,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.phone_outlined,
                title: 'Phone',
                subtitle: companyPhone,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.email_outlined,
                title: 'Email',
                subtitle: companyEmail,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.language_outlined,
                title: 'Website',
                subtitle: companyWebsite,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tax & Compliance Section
          SectionedCard(
            title: 'Tax & Compliance',
            children: [
              SettingsListTile(
                icon: Icons.badge_outlined,
                title: 'GSTIN',
                subtitle: gstin,
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.numbers_outlined,
                title: 'PAN',
                subtitle: pan,
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.location_city_outlined,
                title: 'Origin State Code',
                subtitle: stateCode,
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.fact_check_outlined,
                title: 'GST Enabled',
                subtitle: gstEnabled ? 'Yes' : 'No',
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Bank Details Section
          SectionedCard(
            title: 'Bank Details',
            children: [
              SettingsListTile(
                icon: Icons.account_balance_outlined,
                title: 'Bank Name',
                subtitle: bankName,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
              SettingsListTile(
                icon: Icons.payment_outlined,
                title: 'Account Number',
                subtitle: bankAccountNo,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
              SettingsListTile(
                icon: Icons.code_outlined,
                title: 'IFSC Code',
                subtitle: bankIfsc,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
              SettingsListTile(
                icon: Icons.store_outlined,
                title: 'Branch Name',
                subtitle: bankBranch,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preferences Section
          SectionedCard(
            title: 'Preferences',
            children: [
              SettingsListTile(
                icon: Icons.monetization_on_outlined,
                title: 'Currency',
                subtitle: currency,
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.calendar_month_outlined,
                title: 'Financial Year',
                subtitle: DateTime.now().month >= 4
                    ? '${DateTime.now().year}-${(DateTime.now().year + 1).toString().substring(2)}'
                    : '${(DateTime.now().year - 1)}-${DateTime.now().year.toString().substring(2)}',
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.picture_as_pdf_outlined,
                title: 'PDF Template Style',
                subtitle: pdfTemplate.toString().toUpperCase(),
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.description_outlined,
                title: 'Terms & Conditions',
                subtitle: terms,
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  return SettingsListTile(
                    icon: themeProvider.isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    title: 'Dark Mode',
                    subtitle: themeProvider.isDarkMode ? 'Enabled' : 'Disabled',
                    trailing: Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (_) => themeProvider.toggleTheme(),
                    ),
                    onTap: () => themeProvider.toggleTheme(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Offline & Sync Section
          AppCard(
            child: AppSection(
              title: 'Offline & Sync',
              action: Consumer<SyncManager>(
                builder: (context, sync, _) {
                  if (!sync.isOnline) {
                    return const Icon(Icons.cloud_off, color: AppColors.warning, size: 18);
                  }
                  if (sync.pendingCount > 0) {
                    return Badge(
                      label: Text('${sync.pendingCount}'),
                      child: const Icon(Icons.sync, color: AppColors.info, size: 18),
                    );
                  }
                  return const Icon(Icons.cloud_done, color: AppColors.success, size: 18);
                },
              ),
              child: Consumer<SyncManager>(
                builder: (context, sync, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsListTile(
                        icon: Icons.wifi,
                        title: 'Connection',
                        subtitle: sync.isOnline ? 'Online' : 'Offline',
                      ),
                      SettingsListTile(
                        icon: Icons.pending_actions,
                        title: 'Pending Sync Items',
                        subtitle: '${sync.pendingCount}',
                      ),
                      if (sync.lastSyncMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
                          child: Text(
                            sync.lastSyncMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                label: sync.isSyncing ? 'Syncing...' : 'Full Sync',
                                icon: Icons.sync,
                                isPrimary: true,
                                isLoading: sync.isSyncing,
                                onTap: sync.isSyncing ? null : () => sync.fullSync(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AppButton(
                                label: 'Upload Pending',
                                icon: Icons.cloud_upload,
                                isPrimary: false,
                                onTap: sync.isSyncing || sync.pendingCount == 0
                                    ? null
                                    : () => sync.syncPendingActions(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Numbering Series Section
          SectionedCard(
            title: 'Numbering Series',
            children: settingsProvider.numberingSeries.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    child: Text(
                      'No numbering series configured',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ]
              : settingsProvider.numberingSeries.map(
                  (series) => SettingsListTile(
                    icon: Icons.format_list_numbered_outlined,
                    title: _getFriendlyDocTypeName(series['document_type'] ?? 'Unknown'),
                    subtitle: '${series['prefix'] ?? ''}${'0' * (series['padding_digits'] ?? 4)}${series['suffix'] ?? ''}',
                    onTap: () => _showEditSeriesDialog(series),
                  ),
                ).toList(),
          ),
          const SizedBox(height: 12),

          // Branches Section
          SectionedCard(
            title: 'Branches',
            children: settingsProvider.branches.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    child: Text(
                      'No branches configured',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ]
              : settingsProvider.branches.map(
                  (branch) => SettingsListTile(
                    icon: Icons.location_on_outlined,
                    title: branch['name'] ?? 'Unknown',
                    subtitle: branch['gstin'] ?? branch['state_code'] ?? '',
                  ),
                ).toList(),
          ),
          const SizedBox(height: 24),

          // Change password & dangerous actions
          settingsProvider.isSaving
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppButton(
                      label: 'Change Password',
                      icon: Icons.lock_outlined,
                      isPrimary: false,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChangePasswordView(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Purge Company Data',
                      icon: Icons.delete_forever_outlined,
                      isPrimary: true,
                      color: AppColors.error,
                      textColor: AppColors.textWhite,
                      onTap: _requestPurge,
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
    final nextNumberCtrl = TextEditingController(
      text: (series['next_number'] ?? 1).toString(),
    );
    final paddingCtrl = TextEditingController(
      text: (series['padding_digits'] ?? 4).toString(),
    );
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
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  hintText: 'e.g. INV/2026/',
                ),
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
                decoration: const InputDecoration(
                  labelText: 'Padding Digits (e.g. 4 for 0001)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: suffixCtrl,
                decoration: const InputDecoration(
                  labelText: 'Suffix (Optional)',
                ),
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
              final suffix = suffixCtrl.text.isNotEmpty
                  ? suffixCtrl.text
                  : null;

              if (nextVal == null || nextVal < 1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Next Number must be 1 or greater'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              if (padVal == null || padVal < 1 || padVal > 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Padding Digits must be between 1 and 10'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              final success = await context
                  .read<SettingsProvider>()
                  .updateNumberingSeries(series['id'], {
                    'prefix': prefix,
                    'next_number': nextVal,
                    'padding_digits': padVal,
                    'suffix': suffix,
                  });
              if (mounted) {
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Numbering series updated successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  final err =
                      context.read<SettingsProvider>().errorMessage ??
                      'Update failed';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(err),
                      backgroundColor: AppColors.error,
                    ),
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
      final response = await ApiClient().post(
        Uri.parse('${ApiClient.baseUrl}/purge/request'),
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
              const Text(
                'A 6-digit OTP code has been sent to your registered email address.',
              ),
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
              ],
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
                        final res = await ApiClient().post(
                          Uri.parse('${ApiClient.baseUrl}/purge/verify'),
                          body: jsonEncode({'otp': otp}),
                        );

                        if (res.statusCode == 200) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Company data purged successfully.',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                          context.read<SettingsProvider>().fetchAllSettings();
                        } else {
                          String msg = 'Purge verification failed';
                          try {
                            final body = jsonDecode(res.body);
                            if (body is Map)
                              msg = body['detail']?.toString() ?? msg;
                          } catch (_) {}
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppColors.error,
                          ),
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
