/// Backup, export, import and purge settings screen.
///
/// Allows exporting company data, importing from a backup, viewing export
/// history, and purging all data in a danger zone.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/errors/user_message.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/dialogs/dialog_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/responsive.dart';
import '../../../core/download/download_service.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/models/export_record.dart';
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
  bool _isVyaparImporting = false;
  bool _isPurging = false;
  bool _purgeStep1Done = false;

  String? get _companyId =>
      ref.read(authControllerProvider).activeMembership?.tenantId;

  Future<void> _triggerExport() async {
    final companyId = _companyId;
    if (companyId == null) return;

    setState(() => _isExporting = true);
    final result = await ref
        .read(downloadServiceProvider)
        .download(
          relativeUrl: '/companies/$companyId/export',
          filename:
              'apexbooks-backup-${DateTime.now().toIso8601String().split('T').first}',
          kind: ExportKind.json,
        );
    setState(() => _isExporting = false);

    if (!mounted) return;
    if (result is Success<DownloadResult>) {
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            'Backup saved to ${result.value.path}.',
            title: 'Export complete',
          );
    } else {
      final err = (result as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Export failed');
    }
  }

  Future<void> _importData() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = selected?.files.single;
    if (file == null || file.bytes == null || !mounted) return;

    Map<String, dynamic> backup;
    try {
      final decoded = jsonDecode(utf8.decode(file.bytes!));
      if (decoded is! Map) throw const FormatException('Expected JSON object');
      backup = Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('SettingsBackupScreen: invalid backup file — $e');
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            'The selected file is not a valid ApexBooks JSON backup.',
            title: 'Invalid backup',
          );
      return;
    }

    final confirmed = await ref
        .read(dialogServiceProvider)
        .confirm(
          context,
          title: 'Import Data',
          message:
              'This adds records that are missing from the current company. '
              'Existing records with the same IDs are kept unchanged. '
              'Create a current backup before continuing.',
        );

    if (!confirmed) return;

    setState(() => _isImporting = true);

    // Simulated import — in production the file bytes come from a picker.
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.importData(_companyId!, backup: backup);

    setState(() => _isImporting = false);

    if (!mounted) return;
    if (result is Success) {
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            'Data imported successfully.',
            title: 'Import Complete',
          );
    } else {
      final err = (result as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Import failed');
    }
  }

  Future<void> _importVyaparBackup() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['vyb'],
      withData: true,
    );
    final file = selected?.files.single;
    if (file == null || file.bytes == null || !mounted) return;

    final confirmed = await ref
        .read(dialogServiceProvider)
        .confirm(
          context,
          title: 'Import Vyapar Backup',
          message:
              'This imports parties, items, invoices, purchases, payments, '
              'opening balances, and stock from ${file.name}. Existing '
              'matching records are retained. Create an ApexBooks backup '
              'before continuing.',
        );
    if (!confirmed || !mounted) return;

    setState(() => _isVyaparImporting = true);
    final result = await ref
        .read(settingsRepositoryProvider)
        .importVyaparBackup(bytes: file.bytes!, filename: file.name);
    if (!mounted) return;
    setState(() => _isVyaparImporting = false);

    if (result is Success<Map<String, dynamic>>) {
      final summary = result.value;
      final imported = <String>[
        _importCount(summary, 'contacts_imported', 'parties'),
        _importCount(summary, 'products_imported', 'items'),
        _importCount(summary, 'invoices_imported', 'invoices'),
        _importCount(summary, 'bills_imported', 'purchases'),
        _importCount(summary, 'payments_imported', 'payments'),
        _importCount(summary, 'stock_entries_imported', 'stock entries'),
      ].where((value) => value.isNotEmpty).join(', ');
      final errors = summary['errors'] is List
          ? (summary['errors'] as List).length
          : 0;
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            imported.isEmpty
                ? 'Vyapar backup processed. No new records were added.'
                : 'Imported $imported${errors > 0 ? ' with $errors warning(s)' : ''}.',
            title: 'Vyapar Import Complete',
          );
    } else {
      final err = (result as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Vyapar import failed');
    }
  }

  String _importCount(Map<String, dynamic> summary, String key, String label) {
    final value = summary[key];
    final count = value is num ? value.toInt() : 0;
    return count > 0 ? '$count $label' : '';
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
      ref
          .read(notificationServiceProvider)
          .info(
            context,
            'An OTP has been sent to your registered email.',
            title: 'Purge Requested',
          );
    } else {
      final err = (result as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Request failed');
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
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            'All company data has been purged.',
            title: 'Data Purged',
          );
    } else {
      final err = (result as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Purge failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final companyId = _companyId;

    if (companyId == null) {
      return const Center(child: Text('No company selected.'));
    }

    final exportsAsync = ref.watch(exportRecordsProvider(companyId));

    return Scaffold(
      appBar: null,
      body: exportsAsync.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => Column(
          children: [
            MaterialBanner(
              content: Text(
                'Could not load export history: ${userFacingErrorMessage(err)}',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      ref.invalidate(exportRecordsProvider(companyId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
            Expanded(child: _buildContent(colors, const [])),
          ],
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      _isExporting ? 'Exporting...' : 'Request Export',
                    ),
                  ),
                  if (exports.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Recent Exports',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...exports.take(5).map((e) => _buildExportRow(colors, e)),
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
              subtitle: 'Restore data from a previously exported backup file.',
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
            const SizedBox(height: 16),
            _buildSectionCard(
              colors: colors,
              icon: Icons.swap_horiz_rounded,
              title: 'Import from Vyapar',
              subtitle:
                  'Migrate company data from a Vyapar .vyb backup file. '
                  'Large backups can take several minutes to process.',
              child: FilledButton.icon(
                onPressed: _isVyaparImporting ? null : _importVyaparBackup,
                icon: _isVyaparImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  _isVyaparImporting
                      ? 'Importing Vyapar backup...'
                      : 'Select Vyapar Backup',
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Danger Zone
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ApexRadius_lg),
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
                          style: Theme.of(context).textTheme.titleSmall
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.delete_forever_outlined,
                                size: 18,
                              ),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle_outlined, size: 18),
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
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
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
          StatusBadge(label: record.status.toUpperCase(), tone: statusTone),
        ],
      ),
    );
  }
}
