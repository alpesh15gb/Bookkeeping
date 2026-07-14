/// GST Configuration settings screen.
///
/// Allows toggling the GST tax mode (REGULAR / COMPOSITION / NON_GST),
/// selecting the state code, registration type, and filing frequency.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/result/result.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/models/gst_config.dart';
import 'settings_providers.dart';

class SettingsGstConfigScreen extends ConsumerStatefulWidget {
  const SettingsGstConfigScreen({super.key});

  @override
  ConsumerState<SettingsGstConfigScreen> createState() =>
      _SettingsGstConfigScreenState();
}

class _SettingsGstConfigScreenState
    extends ConsumerState<SettingsGstConfigScreen> {
  bool _isSaving = false;
  bool _populated = false;

  String? get _companyId =>
      ref.read(authControllerProvider).activeMembership?.tenantId;

  String _taxMode = TaxMode.nonGst;
  String? _stateCode;
  String? _registrationType;
  String? _filingFrequency;
  String? _gstin;

  void _initFields(GstConfig config) {
    if (_populated) return;
    _taxMode = config.taxMode;
    _stateCode = config.stateCode;
    _registrationType = config.registrationType;
    _filingFrequency = config.filingFrequency;
    _gstin = config.gstin;
    _populated = true;
  }

  Future<void> _save() async {
    final companyId = _companyId;
    if (companyId == null) return;
    if (_taxMode != TaxMode.nonGst && _stateCode == null) {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            'Select the GST registration state before saving.',
            title: 'State required',
          );
      return;
    }
    if (_taxMode != TaxMode.nonGst && (_gstin?.trim().isEmpty ?? true)) {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            'Add a valid GSTIN in Company Profile before enabling GST.',
            title: 'GSTIN required',
          );
      return;
    }

    setState(() => _isSaving = true);
    final repo = ref.read(settingsRepositoryProvider);

    final gstResult = await repo.updateGstConfig(
      companyId,
      GstConfig(
        taxMode: _taxMode,
        stateCode: _stateCode,
        registrationType: _registrationType,
        filingFrequency: _filingFrequency,
      ),
    );

    setState(() => _isSaving = false);

    if (!mounted) return;
    if (gstResult is Success) {
      ref.invalidate(gstConfigProvider);
      ref.invalidate(tenantSettingsProvider);
      ref.invalidate(companyProfileProvider(companyId));
      await ref.read(authControllerProvider.notifier).refreshMemberships();
      ref
          .read(notificationServiceProvider)
          .success(context, 'GST configuration updated.', title: 'Saved');
    } else {
      final err = (gstResult as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Save failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final async = ref.watch(gstConfigProvider);

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(gstConfigProvider),
        ),
        data: (config) {
          _initFields(config);
          return _buildContent(colors, config);
        },
      ),
    );
  }

  Widget _buildContent(ApexColors colors, GstConfig config) {
    final isGst = _taxMode != TaxMode.nonGst;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'GST Configuration',
            subtitle: 'Set up your GST registration and filing preferences',
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
          // Tax Mode
          ApexCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tax Mode',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose how your business is registered for GST.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _taxMode,
                  decoration: const InputDecoration(
                    labelText: 'Tax Mode',
                    prefixIcon: Icon(Icons.receipt_outlined),
                  ),
                  items: TaxMode.labels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _taxMode = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // GST Details (only when GST is enabled)
          if (isGst)
            ApexCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GST Details',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Provide your registration details.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // GSTIN (read-only display)
                  if (config.gstin != null && config.gstin!.isNotEmpty) ...[
                    TextFormField(
                      initialValue: config.gstin,
                      decoration: const InputDecoration(
                        labelText: 'GSTIN',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                  // State Code
                  DropdownButtonFormField<String>(
                    value: _stateCode,
                    decoration: const InputDecoration(
                      labelText: 'State Code *',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                    items: IndianStates.codes.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text('${e.key} — ${e.value}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _stateCode = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Registration Type
                  DropdownButtonFormField<String>(
                    value: _registrationType,
                    decoration: const InputDecoration(
                      labelText: 'Registration Type',
                      prefixIcon: Icon(Icons.assignment_outlined),
                    ),
                    items: RegistrationType.labels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _registrationType = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Filing Frequency
                  DropdownButtonFormField<String>(
                    value: _filingFrequency,
                    decoration: const InputDecoration(
                      labelText: 'Filing Frequency',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    items: FilingFrequency.labels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _filingFrequency = v);
                      }
                    },
                  ),
                ],
              ),
            ),
          // Non-GST info card
          if (!isGst)
            ApexCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: colors.info,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your company is set to Non-GST. Switch to Regular or '
                      'Composition mode to configure state and filing details.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
