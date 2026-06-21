import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/banking_profile_provider.dart';
import '../../../views/banking/banking_profile_form_view.dart';
import '../../../views/auth/change_password_view.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
  final _eInvoiceUsernameCtrl = TextEditingController();
  final _eInvoicePasswordCtrl = TextEditingController();
  final _eWayBillUsernameCtrl = TextEditingController();
  final _eWayBillPasswordCtrl = TextEditingController();
  final _upiIdCtrl = TextEditingController();
  bool _eInvoicingEnabled = false;
  String _selectedTemplate = 'professional';

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
    _eInvoiceUsernameCtrl.dispose();
    _eInvoicePasswordCtrl.dispose();
    _eWayBillUsernameCtrl.dispose();
    _eWayBillPasswordCtrl.dispose();
    _upiIdCtrl.dispose();
    super.dispose();
  }

  void _populateControllers(Map<String, dynamic> company, Map<String, dynamic> settings) {
    _legalNameCtrl.text = company['legal_name'] ?? '';
    _tradeNameCtrl.text = company['trade_name'] ?? '';
    _gstinCtrl.text = company['gstin'] ?? '';
    _panCtrl.text = company['pan'] ?? '';
    _stateCodeCtrl.text = settings['origin_state_code'] ?? '';
    _eInvoiceUsernameCtrl.text = settings['e_invoice_username'] ?? '';
    _eInvoicePasswordCtrl.text = '';
    _eWayBillUsernameCtrl.text = settings['e_way_bill_username'] ?? '';
    _eWayBillPasswordCtrl.text = '';
    _eInvoicingEnabled = settings['e_invoicing_enabled'] ?? false;
    final extra = settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings['extra_settings']) : <String, dynamic>{};
    _selectedTemplate = extra['pdf_template'] ?? 'professional';
    _addressCtrl.text = extra['company_address'] ?? '';
    _phoneCtrl.text = extra['company_phone'] ?? '';
    _emailCtrl.text = extra['company_email'] ?? '';
    _websiteCtrl.text = extra['company_website'] ?? '';
    _termsCtrl.text = extra['terms'] ?? '';
    _upiIdCtrl.text = settings['upi_id'] ?? '';
  }

  Future<void> _saveSettings() async {
    final companyPayload = {
      'legal_name': _legalNameCtrl.text,
      'trade_name': _tradeNameCtrl.text.isNotEmpty ? _tradeNameCtrl.text : _legalNameCtrl.text,
      'gstin': _gstinCtrl.text.isNotEmpty ? _gstinCtrl.text : null,
      'pan': _panCtrl.text.isNotEmpty ? _panCtrl.text : null,
    };
    final provider = context.read<SettingsProvider>();
    final extra = provider.settings['extra_settings'] is Map ? Map<String, dynamic>.from(provider.settings['extra_settings']) : <String, dynamic>{};
    extra.remove('bank_name');
    extra.remove('bank_account_no');
    extra.remove('bank_ifsc');
    extra.remove('bank_branch');
    final settingsPayload = <String, dynamic>{
      'extra_settings': {
        ...extra,
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
    final success = await provider.saveSettings(companyPayload: companyPayload, settingsPayload: settingsPayload);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Settings saved successfully' : (provider.errorMessage ?? 'Failed to save')),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final company = settings.company;
    final isLoading = settings.isLoading;
    final taxMode = settings.taxMode;
    final extra = settings.settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings.settings['extra_settings']) : <String, dynamic>{};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: AppTypography.headlineLarge),
          const SizedBox(height: AppSpacing.sectionGap),

          // Company Profile
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'COMPANY PROFILE'),
                const SizedBox(height: AppSpacing.lg),
                if (isLoading)
                  const AppLoadingRow()
                else ...[
                  _buildInfoRow('Legal Name', company['legal_name'] ?? company['name'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Trade Name', company['trade_name'] ?? company['name'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Phone', extra['company_phone'] ?? company['phone'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Email', extra['company_email'] ?? company['email'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Website', extra['company_website'] ?? company['website'] ?? '-'),
                ],
                const SizedBox(height: AppSpacing.md),
                AppButton(label: 'Edit Profile', icon: Icons.edit, style: AppButtonStyle.secondary, onPressed: () {
                  _populateControllers(company, settings.settings);
                  _showCompanyProfileDialog(company, settings.settings);
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // Tax & Compliance
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'TAX & COMPLIANCE'),
                const SizedBox(height: AppSpacing.lg),
                if (isLoading)
                  const AppLoadingRow()
                else ...[
                  _buildInfoRow('GSTIN', company['gstin'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('PAN', company['pan'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('State Code', settings.settings['origin_state_code'] ?? '-'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('Tax Mode', taxMode == 'GST_REGULAR' ? 'GST Registered' : taxMode == 'GST_COMPOSITION' ? 'Composition Scheme' : 'Non-GST'),
                  const SizedBox(height: AppSpacing.sm),
                  _buildInfoRow('E-Invoicing', settings.settings['e_invoicing_enabled'] == true ? 'Enabled' : 'Disabled'),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    AppButton(label: 'Edit Tax Info', icon: Icons.edit, style: AppButtonStyle.secondary, onPressed: () {
                      _populateControllers(company, settings.settings);
                      _showTaxComplianceDialog(company, settings.settings);
                    }),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton(label: 'Change Tax Mode', icon: Icons.swap_horiz, style: AppButtonStyle.secondary, onPressed: () => _showTaxModeDialog(taxMode)),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton(label: 'E-Invoice Config', icon: Icons.electric_bolt, style: AppButtonStyle.secondary, onPressed: () {
                      _populateControllers(company, settings.settings);
                      _showEInvoicingDialog(settings.settings);
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // Bank Details
          _buildBankDetailsSection(),
          const SizedBox(height: AppSpacing.sectionGap),

          // UPI
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'UPI & PAYMENT'),
                const SizedBox(height: AppSpacing.lg),
                _buildInfoRow('UPI ID', settings.settings['upi_id']?.toString().isNotEmpty == true ? settings.settings['upi_id'] : 'Not configured'),
                const SizedBox(height: AppSpacing.md),
                AppButton(label: 'Edit UPI ID', icon: Icons.qr_code, style: AppButtonStyle.secondary, onPressed: () => _showUpiIdDialog(settings.settings)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // Preferences
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'PREFERENCES'),
                const SizedBox(height: AppSpacing.lg),
                _buildInfoRow('PDF Template', _selectedTemplate.toUpperCase()),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Terms', extra['terms']?.toString().isNotEmpty == true ? extra['terms'] : 'No custom terms'),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dark Mode', style: AppTypography.bodySmall),
                    Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (_) => themeProvider.toggleTheme(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(label: 'Edit Preferences', icon: Icons.tune, style: AppButtonStyle.secondary, onPressed: () {
                  _populateControllers(company, settings.settings);
                  _showPreferencesDialog(company, settings.settings);
                }),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // Invoice Layout
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'INVOICE LAYOUT'),
                const SizedBox(height: AppSpacing.lg),
                _buildInfoRow('Signee', extra['signee_name']?.toString().isNotEmpty == true ? extra['signee_name'] : 'Default'),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Show Bank', extra['show_bank_details'] != false ? 'Yes' : 'No'),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Show UPI QR', extra['show_upi_qr'] != false ? 'Yes' : 'No'),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Show HSN', extra['show_hsn'] != false ? 'Yes' : 'No'),
                const SizedBox(height: AppSpacing.md),
                AppButton(label: 'Customize Layout', icon: Icons.design_services, style: AppButtonStyle.secondary, onPressed: () => _showFormatPreferencesDialog(settings.settings)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // Transaction Preferences
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(title: 'PRICING & TRANSACTIONS'),
                const SizedBox(height: AppSpacing.lg),
                _buildInfoRow('Tax Inclusive', extra['tax_inclusive_rates'] == true ? 'Yes' : 'No'),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Price Decimals', '${extra['price_decimals'] ?? 2}'),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Qty Decimals', '${extra['qty_decimals'] ?? 2}'),
                const SizedBox(height: AppSpacing.sm),
                _buildInfoRow('Payment Terms', extra['default_payment_terms']?.toString() ?? 'Due on Receipt'),
                const SizedBox(height: AppSpacing.md),
                AppButton(label: 'Edit Transaction Prefs', icon: Icons.settings, style: AppButtonStyle.secondary, onPressed: () => _showTransactionPreferencesDialog(settings.settings)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sectionGap),

          // Numbering Series
          _buildNumberingSeriesSection(settings),
          const SizedBox(height: AppSpacing.sectionGap),

          // Branches
          _buildBranchesSection(settings),
          const SizedBox(height: AppSpacing.sectionGap),

          // Actions
          AppButton(label: 'Change Password', icon: Icons.lock_outlined, style: AppButtonStyle.secondary, onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordView()));
          }),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Flexible(child: Text(value, style: AppTypography.labelMedium, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildBankDetailsSection() {
    return Consumer<BankingProfileProvider>(
      builder: (context, bankingProv, _) {
        final profiles = bankingProv.profiles;
        Map<String, dynamic>? primary;
        for (final p in profiles) {
          final map = p is Map<String, dynamic> ? p : null;
          if (map != null && map['is_primary'] == true && map['is_active'] != false) {
            primary = map;
            break;
          }
        }
        if (primary == null) {
          for (final p in profiles) {
            final map = p is Map<String, dynamic> ? p : null;
            if (map != null && map['is_active'] != false) {
              primary = map;
              break;
            }
          }
        }
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionHeader(title: 'BANK DETAILS'),
              const SizedBox(height: AppSpacing.lg),
              _buildInfoRow('Bank', primary?['bank_name']?.toString() ?? 'Not configured'),
              const SizedBox(height: AppSpacing.sm),
              _buildInfoRow('Account #', primary?['account_number']?.toString() ?? 'Not configured'),
              const SizedBox(height: AppSpacing.sm),
              _buildInfoRow('IFSC', primary?['ifsc_code']?.toString() ?? 'Not configured'),
              const SizedBox(height: AppSpacing.sm),
              _buildInfoRow('Branch', primary?['branch_name']?.toString() ?? 'Not configured'),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: 'Edit Bank Details', icon: Icons.account_balance, style: AppButtonStyle.secondary, onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BankingProfileFormView(profile: primary, defaultPrimary: primary == null),
                ));
                if (mounted) {
                  await context.read<BankingProfileProvider>().fetchBankingProfiles();
                }
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNumberingSeriesSection(SettingsProvider settings) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppSectionHeader(title: 'NUMBERING SERIES'),
              const Spacer(),
              AppButton(label: '+ Add', icon: Icons.add, style: AppButtonStyle.secondary, onPressed: () => _showCreateSeriesDialog()),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (settings.numberingSeries.isEmpty)
            Text('No numbering series configured', style: AppTypography.bodySmall.copyWith(color: AppColors.gray500))
          else
            ...settings.numberingSeries.map((s) {
              final docType = _getFriendlyDocType(s['document_type'] ?? '');
              final prefix = s['prefix'] ?? '';
              final padding = s['padding_digits'] ?? 4;
              final suffix = s['suffix'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(docType, style: AppTypography.labelLarge),
                        Text('$prefix${'0' * padding}$suffix', style: AppTypography.bodySmall),
                      ],
                    ),
                    AppButton(label: 'Edit', icon: Icons.edit, style: AppButtonStyle.secondary, onPressed: () => _showEditSeriesDialog(s)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBranchesSection(SettingsProvider settings) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(title: 'BRANCHES'),
          const SizedBox(height: AppSpacing.lg),
          if (settings.branches.isEmpty)
            Text('No branches configured', style: AppTypography.bodySmall.copyWith(color: AppColors.gray500))
          else
            ...settings.branches.map((b) {
              final map = b is Map<String, dynamic> ? b : <String, dynamic>{};
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(map['name'] ?? 'Unknown', style: AppTypography.labelLarge),
                        Text(map['gstin'] ?? map['state_code'] ?? '', style: AppTypography.bodySmall),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Branch?'),
                            content: Text('Delete ${map['name'] ?? 'this branch'}?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          final ok = await settings.deleteBranch(map['id']);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok ? 'Branch deleted' : (settings.errorMessage ?? 'Failed')),
                                backgroundColor: ok ? AppColors.success : AppColors.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _getFriendlyDocType(String docType) {
    const map = {
      'INVOICE': 'Sales Invoice', 'BILL': 'Vendor Bill', 'PAYMENT': 'Customer Payment',
      'JOURNAL': 'Journal Entry', 'RECEIPT': 'Receipt', 'DISBURSEMENT': 'Disbursement',
      'CREDIT_NOTE': 'Credit Note', 'DEBIT_NOTE': 'Debit Note', 'PURCHASE_ORDER': 'Purchase Order',
      'SALES_ORDER': 'Sales Order', 'DELIVERY_CHALLAN': 'Delivery Challan', 'PROFORMA_INVOICE': 'Estimate',
    };
    return map[docType] ?? docType;
  }

  void _showCompanyProfileDialog(Map<String, dynamic> company, Map<String, dynamic> settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Company Profile'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _legalNameCtrl, decoration: const InputDecoration(labelText: 'Legal Name *')),
            const SizedBox(height: 12),
            TextField(controller: _tradeNameCtrl, decoration: const InputDecoration(labelText: 'Trade Name')),
            const SizedBox(height: 12),
            TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Address'), maxLines: 2),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 12),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextField(controller: _websiteCtrl, decoration: const InputDecoration(labelText: 'Website')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { Navigator.pop(context); _saveSettings(); }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _showTaxComplianceDialog(Map<String, dynamic> company, Map<String, dynamic> settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Tax & Compliance'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _gstinCtrl, decoration: const InputDecoration(labelText: 'GSTIN'), textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 12),
            TextField(controller: _panCtrl, decoration: const InputDecoration(labelText: 'PAN'), textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 12),
            TextField(controller: _stateCodeCtrl, decoration: const InputDecoration(labelText: 'Origin State Code'), keyboardType: TextInputType.number),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { Navigator.pop(context); _saveSettings(); }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _showTaxModeDialog(String currentTaxMode) {
    String selectedMode = currentTaxMode;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tax Mode'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            RadioListTile<String>(title: const Text('Non-GST Business'), value: 'NON_GST', groupValue: selectedMode, onChanged: (v) => setDialogState(() => selectedMode = v!)),
            RadioListTile<String>(title: const Text('GST Registered'), value: 'GST_REGULAR', groupValue: selectedMode, onChanged: (v) => setDialogState(() => selectedMode = v!)),
            RadioListTile<String>(title: const Text('Composition Scheme'), value: 'GST_COMPOSITION', groupValue: selectedMode, onChanged: (v) => setDialogState(() => selectedMode = v!)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () async {
              Navigator.pop(context);
              if (selectedMode != currentTaxMode) {
                final ok = await context.read<SettingsProvider>().toggleGstMode(selectedMode);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Tax mode updated' : 'Failed'), backgroundColor: ok ? AppColors.success : AppColors.error),
                  );
                }
              }
            }, child: const Text('Apply')),
          ],
        ),
      ),
    );
  }

  void _showEInvoicingDialog(Map<String, dynamic> settings) {
    bool localEnabled = _eInvoicingEnabled;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('E-Invoicing & E-Way Bill'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enable E-Invoicing'), value: localEnabled, onChanged: (v) => setDialogState(() => localEnabled = v)),
              const SizedBox(height: 12),
              TextField(controller: _eInvoiceUsernameCtrl, decoration: const InputDecoration(labelText: 'E-Invoice Username')),
              const SizedBox(height: 12),
              TextField(controller: _eInvoicePasswordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'E-Invoice Password (leave blank to keep)')),
              const SizedBox(height: 12),
              TextField(controller: _eWayBillUsernameCtrl, decoration: const InputDecoration(labelText: 'E-Way Bill Username')),
              const SizedBox(height: 12),
              TextField(controller: _eWayBillPasswordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'E-Way Bill Password (leave blank to keep)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () async {
              Navigator.pop(context);
              setState(() => _eInvoicingEnabled = localEnabled);
              final payload = <String, dynamic>{'e_invoicing_enabled': localEnabled};
              if (_eInvoiceUsernameCtrl.text.isNotEmpty) payload['e_invoice_username'] = _eInvoiceUsernameCtrl.text;
              if (_eInvoicePasswordCtrl.text.isNotEmpty) payload['e_invoice_password'] = _eInvoicePasswordCtrl.text;
              if (_eWayBillUsernameCtrl.text.isNotEmpty) payload['e_way_bill_username'] = _eWayBillUsernameCtrl.text;
              if (_eWayBillPasswordCtrl.text.isNotEmpty) payload['e_way_bill_password'] = _eWayBillPasswordCtrl.text;
              final ok = await context.read<SettingsProvider>().saveSettings(companyPayload: {}, settingsPayload: payload);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'E-Invoicing settings saved' : 'Failed'), backgroundColor: ok ? AppColors.success : AppColors.error),
                );
              }
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  void _showUpiIdDialog(Map<String, dynamic> settings) {
    _upiIdCtrl.text = settings['upi_id'] ?? '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('UPI ID'),
        content: TextField(controller: _upiIdCtrl, decoration: const InputDecoration(labelText: 'UPI ID', hintText: 'e.g. name@upi')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            Navigator.pop(context);
            final ok = await context.read<SettingsProvider>().saveSettings(companyPayload: {}, settingsPayload: {'upi_id': _upiIdCtrl.text.trim()});
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? 'UPI ID saved' : 'Failed'), backgroundColor: ok ? AppColors.success : AppColors.error),
              );
            }
          }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _showPreferencesDialog(Map<String, dynamic> company, Map<String, dynamic> settings) {
    final termsCtrl = TextEditingController(text: _termsCtrl.text);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Preferences'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: _selectedTemplate,
                decoration: const InputDecoration(labelText: 'PDF Template'),
                items: const [
                  DropdownMenuItem(value: 'professional', child: Text('Professional Navy')),
                  DropdownMenuItem(value: 'tally_gst', child: Text('Tally GST')),
                  DropdownMenuItem(value: 'classic_blue', child: Text('Classic Blue')),
                  DropdownMenuItem(value: 'sleek_modern', child: Text('Sleek Modern')),
                  DropdownMenuItem(value: 'minimal', child: Text('Minimal')),
                  DropdownMenuItem(value: 'elegant', child: Text('Elegant Green')),
                  DropdownMenuItem(value: 'thermal', child: Text('Thermal / POS')),
                ],
                onChanged: (v) { if (v != null) setDialogState(() => _selectedTemplate = v); },
              ),
              const SizedBox(height: 12),
              TextField(controller: termsCtrl, decoration: const InputDecoration(labelText: 'Terms & Conditions'), maxLines: 3, onChanged: (v) => _termsCtrl.text = v),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () { Navigator.pop(context); _saveSettings(); }, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  void _showFormatPreferencesDialog(Map<String, dynamic> settings) {
    final extra = settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings['extra_settings']) : <String, dynamic>{};
    final signeeNameCtrl = TextEditingController(text: extra['signee_name'] ?? '');
    final signeeDesigCtrl = TextEditingController(text: extra['signee_designation'] ?? '');
    bool showBank = extra['show_bank_details'] != false;
    bool showUpi = extra['show_upi_qr'] != false;
    bool showHsn = extra['show_hsn'] != false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invoice Layout'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: signeeNameCtrl, decoration: const InputDecoration(labelText: 'Signee Name')),
              const SizedBox(height: 12),
              TextField(controller: signeeDesigCtrl, decoration: const InputDecoration(labelText: 'Signee Designation')),
              const SizedBox(height: 12),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Show Bank Details'), value: showBank, onChanged: (v) => setDialogState(() => showBank = v!)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Show UPI QR'), value: showUpi, onChanged: (v) => setDialogState(() => showUpi = v!)),
              CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Show HSN/SAC'), value: showHsn, onChanged: (v) => setDialogState(() => showHsn = v!)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () async {
              Navigator.pop(context);
              final provider = context.read<SettingsProvider>();
              final currentExtra = provider.settings['extra_settings'] is Map ? Map<String, dynamic>.from(provider.settings['extra_settings']) : <String, dynamic>{};
              currentExtra.addAll({'signee_name': signeeNameCtrl.text, 'signee_designation': signeeDesigCtrl.text, 'show_bank_details': showBank, 'show_upi_qr': showUpi, 'show_hsn': showHsn});
              await provider.saveSettings(companyPayload: {}, settingsPayload: {'extra_settings': currentExtra});
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  void _showTransactionPreferencesDialog(Map<String, dynamic> settings) {
    final extra = settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings['extra_settings']) : <String, dynamic>{};
    bool taxInclusive = extra['tax_inclusive_rates'] == true;
    int priceDec = extra['price_decimals'] is int ? extra['price_decimals'] : 2;
    int qtyDec = extra['qty_decimals'] is int ? extra['qty_decimals'] : 2;
    String paymentTerms = extra['default_payment_terms']?.toString() ?? 'Due on Receipt';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Transaction Preferences'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tax Inclusive Rates'), value: taxInclusive, onChanged: (v) => setDialogState(() => taxInclusive = v)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(value: priceDec, decoration: const InputDecoration(labelText: 'Price Decimals'), items: const [DropdownMenuItem(value: 2, child: Text('2')), DropdownMenuItem(value: 3, child: Text('3')), DropdownMenuItem(value: 4, child: Text('4'))], onChanged: (v) => setDialogState(() => priceDec = v!)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(value: qtyDec, decoration: const InputDecoration(labelText: 'Qty Decimals'), items: const [DropdownMenuItem(value: 0, child: Text('0')), DropdownMenuItem(value: 2, child: Text('2')), DropdownMenuItem(value: 3, child: Text('3'))], onChanged: (v) => setDialogState(() => qtyDec = v!)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(value: paymentTerms, decoration: const InputDecoration(labelText: 'Payment Terms'), items: const [DropdownMenuItem(value: 'Due on Receipt', child: Text('Due on Receipt')), DropdownMenuItem(value: 'Net 15', child: Text('Net 15')), DropdownMenuItem(value: 'Net 30', child: Text('Net 30')), DropdownMenuItem(value: 'Net 60', child: Text('Net 60'))], onChanged: (v) => setDialogState(() => paymentTerms = v!)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () async {
              Navigator.pop(context);
              final provider = context.read<SettingsProvider>();
              final currentExtra = provider.settings['extra_settings'] is Map ? Map<String, dynamic>.from(provider.settings['extra_settings']) : <String, dynamic>{};
              currentExtra.addAll({'tax_inclusive_rates': taxInclusive, 'price_decimals': priceDec, 'qty_decimals': qtyDec, 'default_payment_terms': paymentTerms});
              await provider.saveSettings(companyPayload: {}, settingsPayload: {'extra_settings': currentExtra});
            }, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  void _showCreateSeriesDialog() {
    String selectedDocType = 'INVOICE';
    final prefixCtrl = TextEditingController();
    final nextNumberCtrl = TextEditingController(text: '1');
    final paddingCtrl = TextEditingController(text: '4');
    final suffixCtrl = TextEditingController();

    final docTypes = [
      {'value': 'INVOICE', 'label': 'Sales Invoice'}, {'value': 'BILL', 'label': 'Vendor Bill'},
      {'value': 'PAYMENT', 'label': 'Customer Payment'}, {'value': 'JOURNAL', 'label': 'Journal Entry'},
      {'value': 'CREDIT_NOTE', 'label': 'Credit Note'}, {'value': 'DEBIT_NOTE', 'label': 'Debit Note'},
      {'value': 'PURCHASE_ORDER', 'label': 'Purchase Order'}, {'value': 'SALES_ORDER', 'label': 'Sales Order'},
      {'value': 'DELIVERY_CHALLAN', 'label': 'Delivery Challan'}, {'value': 'PROFORMA_INVOICE', 'label': 'Estimate'},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Numbering Series'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(value: selectedDocType, decoration: const InputDecoration(labelText: 'Document Type'), items: docTypes.map((d) => DropdownMenuItem(value: d['value'], child: Text(d['label']!))).toList(), onChanged: (v) { if (v != null) setDialogState(() => selectedDocType = v); }),
              const SizedBox(height: 12),
              TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefix', hintText: 'e.g. INV/2026/')),
              const SizedBox(height: 12),
              TextField(controller: nextNumberCtrl, decoration: const InputDecoration(labelText: 'Next Number'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: paddingCtrl, decoration: const InputDecoration(labelText: 'Padding Digits'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: suffixCtrl, decoration: const InputDecoration(labelText: 'Suffix (Optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () async {
              final prefix = prefixCtrl.text.trim();
              final nextVal = int.tryParse(nextNumberCtrl.text);
              final padVal = int.tryParse(paddingCtrl.text);
              final suffix = suffixCtrl.text.trim().isNotEmpty ? suffixCtrl.text.trim() : null;
              if (prefix.isEmpty || nextVal == null || nextVal < 1 || padVal == null || padVal < 1) return;
              Navigator.pop(context);
              await context.read<SettingsProvider>().createNumberingSeries({'document_type': selectedDocType, 'prefix': prefix, 'next_number': nextVal, 'padding_digits': padVal, 'suffix': suffix});
            }, child: const Text('Create')),
          ],
        ),
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
        title: Text('Edit: ${_getFriendlyDocType(series['document_type'] ?? '')}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefix')),
            const SizedBox(height: 12),
            TextField(controller: nextNumberCtrl, decoration: const InputDecoration(labelText: 'Next Number'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: paddingCtrl, decoration: const InputDecoration(labelText: 'Padding Digits'), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: suffixCtrl, decoration: const InputDecoration(labelText: 'Suffix')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            final nextVal = int.tryParse(nextNumberCtrl.text);
            final padVal = int.tryParse(paddingCtrl.text);
            if (nextVal == null || nextVal < 1 || padVal == null || padVal < 1) return;
            Navigator.pop(context);
            await context.read<SettingsProvider>().updateNumberingSeries(series['id'], {'prefix': prefixCtrl.text, 'next_number': nextVal, 'padding_digits': padVal, 'suffix': suffixCtrl.text});
          }, child: const Text('Save')),
        ],
      ),
    );
  }
}
