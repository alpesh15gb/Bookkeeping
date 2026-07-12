/// Backup, export, import and purge settings screen.
///
/// Allows exporting company data, importing from a backup, viewing export
/// history, and purging all data in a danger zone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/dialogs/dialog_service.dart';
import '../../../core/result/result.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/responsive.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/models/export_record.dart';
import '../data/settings_repository.dart';
import 'settings_providers.dart';

class SettingsBackupScreen extends ConsumerStatefulWidget {
  const SettingsBackupScreen({super.key});

  @override
  ConsumerState<SettingsBackupScreen> createState() =>
      _SettingsBackupScreenState();
}

class _SettingsBackupScreenState extends ConsumerState<SettingsBackupScreen> {
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isPurging = false;
  bool _purgeStep1Done = false;

  String? get _companyId =>
      ref.read(authControllerProvider).activeMembership?.tenantId;

  Future<void> _triggerExport() async {
    final companyId = _companyId;
    if (companyId == null) return;

    setState(() => _isExporting = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.triggerExport(companyId);
    setState(() => _isExporting = false);

    if (!mounted) return;
    if (result is Success) {
      ref.invalidate(exportHistoryProvider(companyId));
      ref.read(notificationServiceProvider).success(
        context,
        'Export has been queued. You will be notified when ready.',
        title: 'Export Started',
      );
    } else {
      final err = (result as Failure).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Export failed',
      );
    }
  }

  Future<void> _importData() async {
    // In a real app this would use file_picker. Here we show a dialog
    // to simulate the import workflow.
    final confirmed = await ref.read(dialogServiceProvider).confirm(
      context,
      title: 'Import Data',
      message:
          'This will replace existing data with the imported file. '
          'Ensure you have a backup of your current data. Continue?',
    );

    if (!confirmed) return;

    setState(() => _isImporting = true);

    // Simulated import — in production the file bytes come from a picker.
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.importData(
      _companyId!,
      fileBytes: [],
      fileName: 'import.json',
    );

    setState(() => _isImporting = false);

    if (!mounted) return;
    if (result is Success) {
      ref.read(notificationServiceProvider).success(
        context,
        'Data imported successfully.',
        title: 'Import Complete',
      );
    } else {
      final err = (result as Failure).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Import failed',
      );
    }
  }

  Future<void> _requestPurge() async {
    setState(() => _isPurging = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.requestPurge();
    setState(() {
      _isPurging = false;
      if (result is Success) _purgeStep1Done = true;
    });

    if (!mounted) return;
    if (result is Success) {
      ref.read(notificationServiceProvider).info(
        context,
        'An OTP has been sent to your registered email.',
        title: 'Purge Requested',
      );
    } else {
      final err = (result as Failure).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Request failed',
      );
    }
  }

  Future<void> _verifyPurge() async {
    final otpCtrl = TextEditingController();
    final otp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter OTP'),
        content: TextFormField(
          controller: otpCtrl,
          decoration: const InputDecoration(
            labelText: 'OTP *',
            prefixIcon: Icon(Icons.pin_outlined),
            hintText: 'Enter OTP sent to your email',
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, otpCtrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: apexColors(context).danger,
            ),
            child: const Text('Confirm Purge'),
          ),
        ],
      ),
    );

    otpCtrl.dispose();
    if (otp == null || otp.isEmpty) return;

    setState(() => _isPurging = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.verifyPurge(otp);
    setState(() {
      _isPurging = false;
      _purgeStep1Done = false;
    });

    if (!mounted) return;
    if (result is Success) {
      ref.read(notificationServiceProvider).success(
        context,
        'All company data has been purged.',
        title: 'Data Purged',
      );
    } else {
      final err = (result as Failure).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Purge failed',
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

    final async = ref.watch(exportHistoryProvider(companyId));

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(exportHistoryProvider(companyId)),
        ),
        data: (exports) => _buildContent(colors, exports),
      ),
    );
  }

  Widget _buildContent(ApexColors colors, List<ExportRecord> exports) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ResponsiveLayout(
        fallback: const SizedBox.shrink(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeader(
              title: 'Backup & Restore',
              subtitle: 'Export, import, and manage your company data',
            ),
            const SizedBox(height: 8),
            // Export section
            _buildSectionCard(
              colors: colors,
              icon: Icons.file_download_outlined,
              title: 'Export Data',
              subtitle:
                  'Download a complete backup of your company data including '
                  'all transactions and master records.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.icon(
                    onPressed: _isExporting ? null : _triggerExport,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(_isExporting
                        ? 'Exporting...'
                        : 'Request Export'),
                  ),
                  if (exports.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Recent Exports',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ...exports.take(5).map(
                      (e) => _buildExportRow(colors, e),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Import section
            _buildSectionCard(
              colors: colors,
              icon: Icons.file_upload_outlined,
              title: 'Import Data',
              subtitle:
                  'Restore data from a previously exported backup file.',
              child: FilledButton.icon(
                onPressed: _isImporting ? null : _importData,
                icon: _isImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded, size: 18),
                label: Text(_isImporting ? 'Importing...' : 'Select & Import'),
              ),
            ),
            const SizedBox(height: 24),
            // Danger Zone
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ApexRadius.lg),
                border: Border.all(color: colors.danger.withValues(alpha: 0.3)),
              ),
              child: ApexCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: colors.danger,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Danger Zone',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.danger,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Purge all company data. This action cannot be undone. '
                      'An OTP verification is required.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_purgeStep1Done)
                      OutlinedButton.icon(
                        onPressed: _isPurging ? null : _requestPurge,
                        icon: _isPurging
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_forever_outlined,
                                size: 18),
                        label: const Text('Request Data Purge'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.danger,
                          side: BorderSide(color: colors.danger),
                        ),
                      ),
                    if (_purgeStep1Done) ...[
                      FilledButton.icon(
                        onPressed: _isPurging ? null : _verifyPurge,
                        icon: _isPurging
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outlined,
                                size: 18),
                        label: const Text('Verify OTP & Purge'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.danger,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Check your registered email for the OTP.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required ApexColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return ApexCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildExportRow(ApexColors colors, ExportRecord record) {
    final statusTone = switch (record.status) {
      'completed' => StatusTone.success,
      'failed' => StatusTone.danger,
      _ => StatusTone.warning,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatDateTime(record.requestedAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (record.fileSize != null)
                  Text(
                    record.formattedSize,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          StatusBadge(
            label: record.status.toUpperCase(),
            tone: statusTone,
          ),
        ],
      ),
    );
  }
}
