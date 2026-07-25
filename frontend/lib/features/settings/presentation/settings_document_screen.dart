/// Tenant-wide document, PDF, payment QR and signature defaults.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../inventory/warehouse/presentation/warehouse_providers.dart';
import '../../inventory/warehouse/services/warehouse_service.dart';
import '../data/models/tenant_settings.dart';
import 'settings_providers.dart';

class SettingsDocumentScreen extends ConsumerStatefulWidget {
  const SettingsDocumentScreen({super.key});

  @override
  ConsumerState<SettingsDocumentScreen> createState() =>
      _SettingsDocumentScreenState();
}

class _SettingsDocumentScreenState
    extends ConsumerState<SettingsDocumentScreen> {
  final _upi = TextEditingController();
  final _website = TextEditingController();
  final _terms = TextEditingController();
  final _signee = TextEditingController();
  final _designation = TextEditingController();
  String _template = 'professional';
  bool _showBank = true;
  bool _showUpi = true;
  String? _defaultWarehouseId;
  bool _populated = false;
  bool _saving = false;

  @override
  void dispose() {
    _upi.dispose();
    _website.dispose();
    _terms.dispose();
    _signee.dispose();
    _designation.dispose();
    super.dispose();
  }

  void _populate(TenantSettings settings) {
    if (_populated) return;
    final extra = settings.extraSettings;
    _upi.text = settings.upiId ?? '';
    _website.text = (extra['company_website'] ?? '').toString();
    _terms.text = (extra['terms'] ?? '').toString();
    _signee.text = (extra['signee_name'] ?? '').toString();
    _designation.text = (extra['signee_designation'] ?? '').toString();
    final storedTemplate = (extra['pdf_template'] ?? 'professional').toString();
    const supportedTemplates = {
      'professional',
      'modern',
      'tally_gst',
      'classic_blue',
      'sleek_modern',
      'minimal',
      'elegant',
      'thermal',
    };
    _template = supportedTemplates.contains(storedTemplate)
        ? storedTemplate
        : 'professional';
    _showBank = extra['show_bank_details'] != false;
    _showUpi = extra['show_upi_qr'] != false;
    _defaultWarehouseId = extra['default_warehouse_id']?.toString();
    _populated = true;
  }

  Future<void> _save(TenantSettings settings) async {
    setState(() => _saving = true);
    final extra = Map<String, dynamic>.from(settings.extraSettings)
      ..['pdf_template'] = _template
      ..['company_website'] = _website.text.trim()
      ..['terms'] = _terms.text.trim()
      ..['signee_name'] = _signee.text.trim()
      ..['signee_designation'] = _designation.text.trim()
      ..['show_bank_details'] = _showBank
      ..['show_upi_qr'] = _showUpi
      ..['default_warehouse_id'] = _defaultWarehouseId;
    final result = await ref
        .read(settingsRepositoryProvider)
        .updateTenantSettings({
          'upi_id': _upi.text.trim(),
          'extra_settings': extra,
        });
    if (mounted) setState(() => _saving = false);
    if (!mounted) return;
    if (result is Success<TenantSettings>) {
      ref.invalidate(tenantSettingsProvider);
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            'Document and print defaults updated.',
            title: 'Saved',
          );
    } else {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            (result as Failure<TenantSettings>).error.message,
            title: 'Save failed',
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tenantSettingsProvider);
    final warehouses =
        ref.watch(warehouseListProvider).valueOrNull ?? const <Warehouse>[];
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(tenantSettingsProvider),
        ),
        data: (settings) {
          _populate(settings);
          return _content(settings, warehouses);
        },
      ),
    );
  }

  Widget _content(TenantSettings settings, List<Warehouse> warehouses) {
    final colors = apexColors(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Documents & Printing',
            subtitle: 'Defaults used by invoices, purchases and PDFs',
            actions: [
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(settings),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── PDF Template ──
          _sectionLabel(colors, 'PDF Template', Icons.description_outlined),
          const SizedBox(height: 8),
          ApexCard(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              initialValue: _template,
              decoration: const InputDecoration(
                labelText: 'Template',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'professional',
                  child: Text('Professional A4'),
                ),
                DropdownMenuItem(value: 'modern', child: Text('Modern A4')),
                DropdownMenuItem(
                  value: 'tally_gst',
                  child: Text('Tally GST A4'),
                ),
                DropdownMenuItem(
                  value: 'classic_blue',
                  child: Text('Classic Blue A4'),
                ),
                DropdownMenuItem(
                  value: 'sleek_modern',
                  child: Text('Sleek Modern A4'),
                ),
                DropdownMenuItem(
                  value: 'minimal',
                  child: Text('Minimal A4'),
                ),
                DropdownMenuItem(
                  value: 'elegant',
                  child: Text('Elegant A4'),
                ),
                DropdownMenuItem(
                  value: 'thermal',
                  child: Text('Thermal / POS'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _template = value);
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── Payment on Invoice ──
          _sectionLabel(colors, 'Payment on Invoice', Icons.payment_outlined),
          const SizedBox(height: 8),
          ApexCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextFormField(
                  controller: _upi,
                  decoration: const InputDecoration(
                    labelText: 'UPI ID',
                    hintText: 'accounts@bank',
                    prefixIcon: Icon(Icons.qr_code_2_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show UPI QR on invoices'),
                  value: _showUpi,
                  onChanged: (value) => setState(() => _showUpi = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show primary bank details'),
                  value: _showBank,
                  onChanged: (value) => setState(() => _showBank = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Warehouse ──
          _sectionLabel(colors, 'Stock Defaults', Icons.inventory_2_outlined),
          const SizedBox(height: 8),
          ApexCard(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              initialValue: warehouses.any((w) => w.id == _defaultWarehouseId)
                  ? _defaultWarehouseId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Default Warehouse',
                helperText:
                    'Used for direct invoices, purchases, returns and adjustments.',
                prefixIcon: Icon(Icons.warehouse_outlined),
              ),
              items: warehouses
                  .where((warehouse) => warehouse.isActive)
                  .map(
                    (warehouse) => DropdownMenuItem(
                      value: warehouse.id,
                      child: Text(warehouse.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _defaultWarehouseId = value),
            ),
          ),
          const SizedBox(height: 20),

          // ── Legal / Footer ──
          _sectionLabel(colors, 'Legal & Footer', Icons.gavel_outlined),
          const SizedBox(height: 8),
          ApexCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextFormField(
                  controller: _website,
                  decoration: const InputDecoration(
                    labelText: 'Website',
                    prefixIcon: Icon(Icons.language_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _terms,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Default Terms & Conditions',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _signee,
                        decoration: const InputDecoration(
                          labelText: 'Authorised Signatory',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _designation,
                        decoration: const InputDecoration(
                          labelText: 'Designation',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'These defaults apply to newly generated PDFs. Existing posted '
            'documents retain their accounting values.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(ApexColors colors, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
