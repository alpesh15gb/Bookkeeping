import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
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
                          series['name'] ?? 'Unknown',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '${series['prefix'] ?? ''}{NNNN}',
                        style: AppTextStyles.caption.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
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
                  ],
                ),
          const SizedBox(height: 32),
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
}
