import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/providers/theme_provider.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
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

  // E-Invoicing & E-Way Bill Controllers
  final _eInvoiceUsernameCtrl = TextEditingController();
  final _eInvoicePasswordCtrl = TextEditingController();
  final _eWayBillUsernameCtrl = TextEditingController();
  final _eWayBillPasswordCtrl = TextEditingController();
  bool _eInvoicingEnabled = false;
  bool _isUploadingLogo = false;

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

    _eInvoiceUsernameCtrl.text = settings['e_invoice_username'] ?? '';
    _eInvoicePasswordCtrl.text = '';
    _eWayBillUsernameCtrl.text = settings['e_way_bill_username'] ?? '';
    _eWayBillPasswordCtrl.text = '';
    _eInvoicingEnabled = settings['e_invoicing_enabled'] ?? false;

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

  void _showTaxModeDialog(String currentTaxMode) {
    String selectedMode = currentTaxMode;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tax Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('Non-GST Business'),
                subtitle: const Text('Simple invoicing, no GST fields'),
                value: 'NON_GST',
                groupValue: selectedMode,
                onChanged: (v) => setDialogState(() => selectedMode = v!),
              ),
              RadioListTile<String>(
                title: const Text('GST Registered Business'),
                subtitle: const Text('Full GST with CGST/SGST/IGST'),
                value: 'GST_REGULAR',
                groupValue: selectedMode,
                onChanged: (v) => setDialogState(() => selectedMode = v!),
              ),
              RadioListTile<String>(
                title: const Text('Composition Scheme'),
                subtitle: const Text('Composition GST with turnover limit'),
                value: 'GST_COMPOSITION',
                groupValue: selectedMode,
                onChanged: (v) => setDialogState(() => selectedMode = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                if (selectedMode == 'NON_GST' && currentTaxMode != 'NON_GST') {
                  await _confirmDisableGst();
                } else if (selectedMode != 'NON_GST' && currentTaxMode == 'NON_GST') {
                  await _confirmEnableGst(selectedMode);
                } else if (selectedMode != currentTaxMode) {
                  await context.read<SettingsProvider>().toggleGstMode(selectedMode);
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEnableGst(String newMode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable GST'),
        content: Text(
          newMode == 'GST_REGULAR'
              ? 'GST fields (HSN, GST Rate, CGST/SGST/IGST) will appear on all invoices, bills, and expenses.'
              : 'Composition scheme GST fields will be enabled. Turnover limit applies.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable GST')),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await context.read<SettingsProvider>().toggleGstMode(newMode);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GST enabled successfully'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  Future<void> _confirmDisableGst() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
        title: const Text('Disable GST?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('GST fields will be hidden from all forms. Existing GST data is preserved.'),
            SizedBox(height: 8),
            Text('What changes:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('- GST fields hidden on Invoice, Bill, Expense forms'),
            Text('- GST reports hidden from Reports section'),
            Text('- E-Way Bills and E-Invoice hidden'),
            Text('- GST calculations bypassed (rate forced to 0)'),
            SizedBox(height: 8),
            Text('What stays:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('- All historical GST data preserved'),
            Text('- GST accounts remain in Chart of Accounts'),
            Text('- Can re-enable anytime from Settings'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable GST'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final ok = await context.read<SettingsProvider>().toggleGstMode('NON_GST');
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GST disabled. GST data preserved.'), backgroundColor: AppColors.success),
        );
      }
    }
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

  Future<void> _pickAndUploadLogo() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        dialogTitle: 'Select Company Logo (PNG/JPG)',
        withData: true,
      );
    } catch (e) {
      _showError('Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final fileBytes = picked.bytes;
    if (fileBytes == null || fileBytes.isEmpty) {
      _showError('Could not read the selected image file.');
      return;
    }

    setState(() => _isUploadingLogo = true);

    try {
      final uri = Uri.parse('${ApiClient.baseUrl}/settings/logo');
      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer ${ApiClient.accessToken ?? ''}';
      request.headers['X-Tenant-ID'] = ApiClient.tenantId ?? '';

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: picked.name,
      ));

      final streamed = await ApiClient().send(request);
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo uploaded successfully'), backgroundColor: AppColors.success),
        );
        await context.read<SettingsProvider>().fetchAllSettings();
      } else {
        String msg = 'Logo upload failed';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) msg = body['detail']?.toString() ?? msg;
        } catch (_) {}
        _showError(msg);
      }
    } catch (e) {
      _showError('Upload error: $e');
    } finally {
      if (mounted) {
        setState(() => _isUploadingLogo = false);
      }
    }
  }

  void _showEInvoicingDialog(Map<String, dynamic> settings) {
    final settingsProvider = context.read<SettingsProvider>();
    _populateControllers(settingsProvider.company, settings);
    bool localEnabled = _eInvoicingEnabled;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('E-Invoicing & E-Way Bill Config'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable E-Invoicing'),
                  subtitle: const Text('Generate IRN via NIC sandbox portal'),
                  value: localEnabled,
                  onChanged: (v) {
                    setDialogState(() {
                      localEnabled = v;
                    });
                  },
                ),
                const SizedBox(height: 12),
                const Text('E-Invoice Portal Credentials:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _eInvoiceUsernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-Invoice Username',
                    hintText: 'Portal API username',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _eInvoicePasswordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'E-Invoice Password',
                    hintText: 'Leave blank to keep existing',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('E-Way Bill Portal Credentials:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _eWayBillUsernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-Way Bill Username',
                    hintText: 'Portal API username',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _eWayBillPasswordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'E-Way Bill Password',
                    hintText: 'Leave blank to keep existing',
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
                final settingsPayload = <String, dynamic>{
                  'e_invoicing_enabled': localEnabled,
                };
                if (_eInvoiceUsernameCtrl.text.isNotEmpty) {
                  settingsPayload['e_invoice_username'] = _eInvoiceUsernameCtrl.text;
                }
                if (_eInvoicePasswordCtrl.text.isNotEmpty) {
                  settingsPayload['e_invoice_password'] = _eInvoicePasswordCtrl.text;
                }
                if (_eWayBillUsernameCtrl.text.isNotEmpty) {
                  settingsPayload['e_way_bill_username'] = _eWayBillUsernameCtrl.text;
                }
                if (_eWayBillPasswordCtrl.text.isNotEmpty) {
                  settingsPayload['e_way_bill_password'] = _eWayBillPasswordCtrl.text;
                }

                setState(() => _eInvoicingEnabled = localEnabled);

                final provider = context.read<SettingsProvider>();
                final success = await provider.saveSettings(
                  companyPayload: {},
                  settingsPayload: settingsPayload,
                );

                if (mounted) {
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('E-Invoicing settings saved successfully'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else {
                    final err = provider.errorMessage ?? 'Failed to save settings';
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
      {'value': 'INVOICE', 'label': 'Sales Invoice'},
      {'value': 'BILL', 'label': 'Vendor Bill'},
      {'value': 'PAYMENT', 'label': 'Customer Payment'},
      {'value': 'JOURNAL', 'label': 'Journal Entry'},
      {'value': 'RECEIPT', 'label': 'Receipt'},
      {'value': 'DISBURSEMENT', 'label': 'Disbursement'},
      {'value': 'CREDIT_NOTE', 'label': 'Credit Note'},
      {'value': 'DEBIT_NOTE', 'label': 'Debit Note'},
      {'value': 'PURCHASE_ORDER', 'label': 'Purchase Order'},
      {'value': 'SALES_ORDER', 'label': 'Sales Order'},
      {'value': 'DELIVERY_CHALLAN', 'label': 'Delivery Challan'},
      {'value': 'PROFORMA_INVOICE', 'label': 'Estimate / Proforma Invoice'},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Numbering Series'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedDocType,
                  decoration: const InputDecoration(labelText: 'Document Type *'),
                  items: docTypes
                      .map((d) => DropdownMenuItem(
                            value: d['value'],
                            child: Text(d['label']!),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedDocType = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prefixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Prefix *',
                    hintText: 'e.g. INV/2026/',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nextNumberCtrl,
                  decoration: const InputDecoration(labelText: 'Next Number *'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: paddingCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Padding Digits * (e.g. 4 for 0001)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: suffixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Suffix (Optional)',
                    hintText: 'e.g. /A',
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
                final prefix = prefixCtrl.text.trim();
                final nextVal = int.tryParse(nextNumberCtrl.text);
                final padVal = int.tryParse(paddingCtrl.text);
                final suffix = suffixCtrl.text.trim().isNotEmpty
                    ? suffixCtrl.text.trim()
                    : null;

                if (prefix.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Prefix is required'), backgroundColor: AppColors.error),
                  );
                  return;
                }

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

                Navigator.pop(context);
                final success = await context.read<SettingsProvider>().createNumberingSeries({
                  'document_type': selectedDocType,
                  'prefix': prefix,
                  'next_number': nextVal,
                  'padding_digits': padVal,
                  'suffix': suffix,
                });

                if (mounted) {
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Numbering series created successfully'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } else {
                    final err = context.read<SettingsProvider>().errorMessage ?? 'Creation failed';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      prefixCtrl.dispose();
      nextNumberCtrl.dispose();
      paddingCtrl.dispose();
      suffixCtrl.dispose();
    });
  }

  void _showFormatPreferencesDialog(Map<String, dynamic> settings) {
    final extraSettings = settings['extra_settings'] is Map
        ? Map<String, dynamic>.from(settings['extra_settings'])
        : <String, dynamic>{};

    final signeeNameCtrl = TextEditingController(text: extraSettings['signee_name'] ?? '');
    final signeeDesigCtrl = TextEditingController(text: extraSettings['signee_designation'] ?? '');
    bool showBank = extraSettings['show_bank_details'] is! bool || extraSettings['show_bank_details'] == true;
    bool showUpi = extraSettings['show_upi_qr'] is! bool || extraSettings['show_upi_qr'] == true;
    bool showHsn = extraSettings['show_hsn'] is! bool || extraSettings['show_hsn'] == true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invoice Format Customization'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: signeeNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Signature Label / Company Name',
                    hintText: 'e.g. for Settings Tester Co.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: signeeDesigCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Signee Designation',
                    hintText: 'e.g. Director / Authorised Signatory',
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Bank Details'),
                  subtitle: const Text('Include primary bank account info on PDF'),
                  value: showBank,
                  onChanged: (v) => setDialogState(() => showBank = v!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show UPI Scan-to-Pay QR'),
                  subtitle: const Text('Render dynamic payment QR on PDF'),
                  value: showUpi,
                  onChanged: (v) => setDialogState(() => showUpi = v!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show HSN/SAC Column'),
                  subtitle: const Text('Display HSN codes for line items'),
                  value: showHsn,
                  onChanged: (v) => setDialogState(() => showHsn = v!),
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
                final provider = context.read<SettingsProvider>();
                final currentExtra = provider.settings['extra_settings'] is Map
                    ? Map<String, dynamic>.from(provider.settings['extra_settings'])
                    : <String, dynamic>{};

                final updatedExtra = {
                  ...currentExtra,
                  'signee_name': signeeNameCtrl.text.trim(),
                  'signee_designation': signeeDesigCtrl.text.trim(),
                  'show_bank_details': showBank,
                  'show_upi_qr': showUpi,
                  'show_hsn': showHsn,
                };

                final success = await provider.saveSettings(
                  companyPayload: {},
                  settingsPayload: {'extra_settings': updatedExtra},
                );

                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Layout formatting saved successfully'), backgroundColor: AppColors.success),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      signeeNameCtrl.dispose();
      signeeDesigCtrl.dispose();
    });
  }

  void _showTransactionPreferencesDialog(Map<String, dynamic> settings) {
    final extraSettings = settings['extra_settings'] is Map
        ? Map<String, dynamic>.from(settings['extra_settings'])
        : <String, dynamic>{};

    bool taxInclusive = extraSettings['tax_inclusive_rates'] == true;
    int priceDec = extraSettings['price_decimals'] is int ? extraSettings['price_decimals'] : 2;
    int qtyDec = extraSettings['qty_decimals'] is int ? extraSettings['qty_decimals'] : 2;
    String paymentTerms = extraSettings['default_payment_terms']?.toString() ?? 'Due on Receipt';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Transaction Preferences'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tax Inclusive Rates'),
                  subtitle: const Text('Product unit rates include tax by default'),
                  value: taxInclusive,
                  onChanged: (v) => setDialogState(() => taxInclusive = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: priceDec,
                  decoration: const InputDecoration(labelText: 'Price Decimal Precision'),
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 Decimals (e.g. 10.50)')),
                    DropdownMenuItem(value: 3, child: Text('3 Decimals (e.g. 10.500)')),
                    DropdownMenuItem(value: 4, child: Text('4 Decimals (e.g. 10.5000)')),
                  ],
                  onChanged: (v) => setDialogState(() => priceDec = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: qtyDec,
                  decoration: const InputDecoration(labelText: 'Quantity Decimal Precision'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0 Decimals (e.g. 5)')),
                    DropdownMenuItem(value: 2, child: Text('2 Decimals (e.g. 5.00)')),
                    DropdownMenuItem(value: 3, child: Text('3 Decimals (e.g. 5.000)')),
                  ],
                  onChanged: (v) => setDialogState(() => qtyDec = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentTerms,
                  decoration: const InputDecoration(labelText: 'Default Payment Terms'),
                  items: const [
                    DropdownMenuItem(value: 'Due on Receipt', child: Text('Due on Receipt')),
                    DropdownMenuItem(value: 'Net 15', child: Text('Net 15 Days')),
                    DropdownMenuItem(value: 'Net 30', child: Text('Net 30 Days')),
                    DropdownMenuItem(value: 'Net 60', child: Text('Net 60 Days')),
                  ],
                  onChanged: (v) => setDialogState(() => paymentTerms = v!),
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
                final provider = context.read<SettingsProvider>();
                final currentExtra = provider.settings['extra_settings'] is Map
                    ? Map<String, dynamic>.from(provider.settings['extra_settings'])
                    : <String, dynamic>{};

                final updatedExtra = {
                  ...currentExtra,
                  'tax_inclusive_rates': taxInclusive,
                  'price_decimals': priceDec,
                  'qty_decimals': qtyDec,
                  'default_payment_terms': paymentTerms,
                };

                final success = await provider.saveSettings(
                  companyPayload: {},
                  settingsPayload: {'extra_settings': updatedExtra},
                );

                if (mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction preferences saved successfully'), backgroundColor: AppColors.success),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
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
    final gstEnabled = settingsProvider.gstEnabled;
    final taxMode = settingsProvider.taxMode;
    final stateCode = settings['origin_state_code'] ?? 'Not configured';
    final extraSettings =
        settings['extra_settings'] is Map ? Map<String, dynamic>.from(settings['extra_settings']) : <String, dynamic>{};
    final pdfTemplate = extraSettings['pdf_template'] ?? 'professional';
    final showBank = extraSettings['show_bank_details'] is! bool || extraSettings['show_bank_details'] == true;
    final showUpi = extraSettings['show_upi_qr'] is! bool || extraSettings['show_upi_qr'] == true;
    final showHsn = extraSettings['show_hsn'] is! bool || extraSettings['show_hsn'] == true;
    final signeeName = extraSettings['signee_name']?.toString() ?? 'Default Signature';
    final signeeDesig = extraSettings['signee_designation']?.toString() ?? 'Authorised Signatory';

    final taxInclusive = extraSettings['tax_inclusive_rates'] == true;
    final priceDec = extraSettings['price_decimals'] is int ? extraSettings['price_decimals'] : 2;
    final qtyDec = extraSettings['qty_decimals'] is int ? extraSettings['qty_decimals'] : 2;
    final paymentTerms = extraSettings['default_payment_terms']?.toString() ?? 'Due on Receipt';

    final companyAddress = extraSettings['company_address'] ?? 'Not configured';
    final companyPhone = extraSettings['company_phone'] ?? 'Not configured';
    final companyEmail = extraSettings['company_email'] ?? 'Not configured';
    final companyWebsite = extraSettings['company_website'] ?? 'Not configured';
    final bankProfiles = bankingProvider.profiles
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('Settings', style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: isMobile
            ? AppSpacing.pagePaddingMobile
            : AppSpacing.pagePadding,
        children: [
          // Company Section
          SectionedCard(
            title: 'Company Profile',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.bgLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: settings['logo_url'] != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.network(
                                settings['logo_url'],
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 30),
                              ),
                            )
                          : const Icon(Icons.business, size: 30, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Company Logo', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
                          Text(
                            settings['logo_url'] != null ? 'Click to change logo' : 'No logo uploaded',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    _isUploadingLogo
                        ? const CircularProgressIndicator()
                        : OutlinedButton.icon(
                            onPressed: _pickAndUploadLogo,
                            icon: const Icon(Icons.upload, size: 16),
                            label: Text(settings['logo_url'] != null ? 'Change' : 'Upload'),
                          ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SettingsListTile(
                icon: Icons.business_outlined,
                iconColor: Colors.blue.shade700,
                title: 'Legal Name',
                subtitle: legalName,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              if (tradeName.isNotEmpty && tradeName != legalName)
                SettingsListTile(
                  icon: Icons.storefront_outlined,
                  iconColor: Colors.purple.shade600,
                  title: 'Trade Name',
                  subtitle: tradeName,
                  onTap: () => _showCompanyProfileDialog(company, settings),
                ),
              SettingsListTile(
                icon: Icons.location_on_outlined,
                iconColor: Colors.red.shade600,
                title: 'Address',
                subtitle: companyAddress,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.phone_outlined,
                iconColor: Colors.green.shade600,
                title: 'Phone',
                subtitle: companyPhone,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.email_outlined,
                iconColor: Colors.orange.shade700,
                title: 'Email',
                subtitle: companyEmail,
                onTap: () => _showCompanyProfileDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.language_outlined,
                iconColor: Colors.teal.shade600,
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
                iconColor: Colors.indigo.shade600,
                title: 'GSTIN',
                subtitle: gstin,
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.numbers_outlined,
                iconColor: Colors.cyan.shade700,
                title: 'PAN',
                subtitle: pan,
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.location_city_outlined,
                iconColor: Colors.pink.shade600,
                title: 'Origin State Code',
                subtitle: stateCode,
                onTap: () => _showTaxComplianceDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.fact_check_outlined,
                iconColor: Colors.amber.shade800,
                title: 'Tax Mode',
                showNewBadge: true,
                subtitle: taxMode == 'GST_REGULAR'
                    ? 'GST Registered Business'
                    : taxMode == 'GST_COMPOSITION'
                        ? 'Composition Scheme'
                        : 'Non-GST Business',
                onTap: () => _showTaxModeDialog(taxMode),
              ),
              SettingsListTile(
                icon: Icons.electric_bolt_outlined,
                iconColor: Colors.purple.shade600,
                title: 'E-Invoicing & E-Way Bill',
                subtitle: settings['e_invoicing_enabled'] == true ? 'Enabled' : 'Disabled',
                onTap: () => _showEInvoicingDialog(settings),
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
                iconColor: Colors.blueGrey.shade700,
                title: 'Bank Name',
                subtitle: bankName,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
              SettingsListTile(
                icon: Icons.payment_outlined,
                iconColor: Colors.teal.shade700,
                title: 'Account Number',
                subtitle: bankAccountNo,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
              SettingsListTile(
                icon: Icons.code_outlined,
                iconColor: Colors.orange.shade800,
                title: 'IFSC Code',
                subtitle: bankIfsc,
                onTap: () => _openBankProfileForm(primaryBank),
              ),
              SettingsListTile(
                icon: Icons.store_outlined,
                iconColor: Colors.deepOrange.shade600,
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
                iconColor: Colors.green.shade700,
                title: 'Currency',
                subtitle: currency,
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.calendar_month_outlined,
                iconColor: Colors.indigo.shade500,
                title: 'Financial Year',
                subtitle: DateTime.now().month >= 4
                    ? '${DateTime.now().year}-${(DateTime.now().year + 1).toString().substring(2)}'
                    : '${(DateTime.now().year - 1)}-${DateTime.now().year.toString().substring(2)}',
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.picture_as_pdf_outlined,
                iconColor: Colors.red.shade700,
                title: 'PDF Template Style',
                subtitle: pdfTemplate.toString().toUpperCase(),
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              SettingsListTile(
                icon: Icons.description_outlined,
                iconColor: Colors.blue.shade600,
                title: 'Terms & Conditions',
                subtitle: terms,
                onTap: () => _showPreferencesDialog(company, settings),
              ),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  return SettingsListTile(
                    icon: themeProvider.isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    iconColor: Colors.yellow.shade900,
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

          // Invoice Layout Customization Section
          SectionedCard(
            title: 'Invoice Layout Customization',
            children: [
              SettingsListTile(
                icon: Icons.border_color_outlined,
                iconColor: Colors.blue.shade600,
                title: 'Signatory & Labels',
                subtitle: 'Name: "$signeeName" | Desig: "$signeeDesig"',
                onTap: () => _showFormatPreferencesDialog(settings),
              ),
              SettingsListTile(
                icon: Icons.visibility_outlined,
                iconColor: Colors.teal.shade600,
                title: 'Visibility Toggles',
                subtitle: 'Bank Details: ${showBank ? "Show" : "Hide"} | UPI QR: ${showUpi ? "Show" : "Hide"} | HSN: ${showHsn ? "Show" : "Hide"}',
                onTap: () => _showFormatPreferencesDialog(settings),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pricing & Transaction Preferences Section
          SectionedCard(
            title: 'Pricing & Transactions',
            children: [
              SettingsListTile(
                icon: Icons.price_change_outlined,
                iconColor: Colors.orange.shade600,
                title: 'Tax Inclusivity',
                subtitle: 'Rates include tax: ${taxInclusive ? "Yes" : "No (Tax Exclusive)"}',
                onTap: () => _showTransactionPreferencesDialog(settings),
              ),
              SettingsListTile(
                icon: Icons.settings_input_component_outlined,
                iconColor: Colors.indigo.shade600,
                title: 'Decimal Precision',
                subtitle: 'Price Decimals: $priceDec | Quantity Decimals: $qtyDec',
                onTap: () => _showTransactionPreferencesDialog(settings),
              ),
              SettingsListTile(
                icon: Icons.rule_folder_outlined,
                iconColor: Colors.amber.shade700,
                title: 'Default Payment Terms',
                subtitle: paymentTerms,
                onTap: () => _showTransactionPreferencesDialog(settings),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Accounting Period Lock Section
          Consumer<FinancialYearProvider>(
            builder: (context, fyProvider, _) {
              final activeFy = fyProvider.activeYear;
              if (activeFy == null) return const SizedBox.shrink();
              final isLocked = activeFy.isClosedOrLocked;

              return SectionedCard(
                title: 'Accounting Period Lock',
                children: [
                  SettingsListTile(
                    icon: isLocked ? Icons.lock_outline : Icons.lock_open_outlined,
                    iconColor: isLocked ? Colors.red.shade700 : Colors.green.shade700,
                    title: 'Status: ${isLocked ? "LOCKED" : "OPEN"}',
                    subtitle: 'Active Period: FY ${activeFy.name} (${activeFy.dateRange})',
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isLocked ? AppColors.brandNavy : Colors.red.shade700,
                        foregroundColor: AppColors.textWhite,
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(isLocked ? 'Unlock Period?' : 'Lock Period (Close FY)?'),
                            content: Text(isLocked
                                ? 'Reopening the financial period allows users to create, edit, or delete transactions in this year context. Do you want to proceed?'
                                : 'Locking the period creates a closing journal entry, transfers inventory balances, and locks all transactions in this year from any further modification. Do you want to proceed?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(isLocked ? 'Unlock' : 'Lock & Close')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          if (isLocked) {
                            final ok = await fyProvider.reopenFinancialYear(activeFy.id);
                            if (mounted && ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Financial year reopened successfully'), backgroundColor: AppColors.success),
                              );
                            }
                          } else {
                            final res = await fyProvider.closeFinancialYear(activeFy.id);
                            if (mounted && res != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Financial year locked successfully'), backgroundColor: AppColors.success),
                              );
                            }
                          }
                        }
                      },
                      child: Text(isLocked ? 'Unlock' : 'Lock'),
                    ),
                  ),
                ],
              );
            },
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
                            style: TextStyle(
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
            action: InkWell(
              onTap: _showCreateSeriesDialog,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: AppColors.brandNavy),
                    const SizedBox(width: 4),
                    Text(
                      'Add Series',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            children: settingsProvider.numberingSeries.isEmpty
              ? [
                  Padding(
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
                  Padding(
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
        String? devOtp;
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['detail'] != null) {
            final detail = body['detail'].toString();
            if (detail.contains('Development OTP code:')) {
              devOtp = detail.split('Development OTP code:').last.trim();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(detail), duration: const Duration(seconds: 8)),
            );
          }
        } catch (_) {}
        _showOtpVerifyDialog(prefilledOtp: devOtp);
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

  Future<void> _showOtpVerifyDialog({String? prefilledOtp}) {
    final otpCtrl = TextEditingController(text: prefilledOtp ?? '');
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
    ).whenComplete(() => otpCtrl.dispose());
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}
