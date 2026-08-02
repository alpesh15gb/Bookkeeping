/// Invoice / document numbering series settings screen.
///
/// Lists all series for every document type and allows creating / editing
/// series configurations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/result/result.dart';
import '../data/models/series.dart';
import 'settings_providers.dart';
import 'package:apexbooks/core/errors/user_message.dart';

class SettingsInvoiceSeriesScreen extends ConsumerStatefulWidget {
  const SettingsInvoiceSeriesScreen({super.key});

  @override
  ConsumerState<SettingsInvoiceSeriesScreen> createState() =>
      _SettingsInvoiceSeriesScreenState();
}

class _SettingsInvoiceSeriesScreenState
    extends ConsumerState<SettingsInvoiceSeriesScreen> {
  bool _isProcessing = false;

  Future<void> _showSeriesDialog({InvoiceSeries? existing}) async {
    final docTypeCtrl = existing != null ? existing.documentType : '';
    final prefixCtrl = TextEditingController(text: existing?.prefix ?? '');
    final suffixCtrl = TextEditingController(text: existing?.suffix ?? '');
    final nextNumberCtrl = TextEditingController(
      text: existing?.nextNumber.toString() ?? '1',
    );
    final paddingCtrl = TextEditingController(
      text: existing?.paddingDigits.toString() ?? '3',
    );
    var selectedDocType = docTypeCtrl;
    var isActive = existing?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SeriesFormDialog(
        existing: existing,
        prefixController: prefixCtrl,
        suffixController: suffixCtrl,
        nextNumberController: nextNumberCtrl,
        paddingController: paddingCtrl,
        selectedDocType: selectedDocType,
        isActive: isActive,
        onDocTypeChanged: (v) => selectedDocType = v,
        onActiveChanged: (v) => isActive = v,
      ),
    );

    if (saved != true) {
      prefixCtrl.dispose();
      suffixCtrl.dispose();
      nextNumberCtrl.dispose();
      paddingCtrl.dispose();
      return;
    }

    setState(() => _isProcessing = true);
    final repo = ref.read(settingsRepositoryProvider);
    final data = <String, dynamic>{
      if (existing == null) 'document_type': selectedDocType,
      'prefix': prefixCtrl.text.trim(),
      'suffix': suffixCtrl.text.trim(),
      'next_number': int.tryParse(nextNumberCtrl.text.trim()) ?? 1,
      'padding_digits': int.tryParse(paddingCtrl.text.trim()) ?? 3,
      if (existing != null) 'is_active': isActive,
    };

    final result = existing != null
        ? await repo.updateSeries(existing.id, data)
        : await repo.createSeries(data);

    setState(() => _isProcessing = false);
    prefixCtrl.dispose();
    suffixCtrl.dispose();
    nextNumberCtrl.dispose();
    paddingCtrl.dispose();

    if (!mounted) return;
    if (result is Success) {
      ref.invalidate(invoiceSeriesListProvider);
      ref
          .read(notificationServiceProvider)
          .success(
            context,
            existing != null
                ? 'Series updated successfully.'
                : 'New series created.',
            title: existing != null ? 'Updated' : 'Created',
          );
    } else {
      final err = (result as Failure).error;
      ref
          .read(notificationServiceProvider)
          .error(context, err.message, title: 'Failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final async = ref.watch(invoiceSeriesListProvider);

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: userFacingErrorMessage(err),
          onRetry: () => ref.invalidate(invoiceSeriesListProvider),
        ),
        data: (series) => _buildContent(colors, series),
      ),
    );
  }

  Widget _buildContent(ApexColors colors, List<InvoiceSeries> series) {
    // Group by document type.
    final grouped = <String, List<InvoiceSeries>>{};
    for (final s in series) {
      grouped.putIfAbsent(s.documentType, () => []).add(s);
    }

    // Sort groups by document type label.
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => _docTypeLabel(a).compareTo(_docTypeLabel(b)));

    return Column(
      children: [
        PageHeader(
          title: 'Invoice Series',
          subtitle: 'Manage numbering series for documents',
          actions: [
            FilledButton.icon(
              onPressed: _isProcessing ? null : () => _showSeriesDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Series'),
            ),
          ],
        ),
        Expanded(
          child: series.isEmpty
              ? const EmptyState(
                  icon: Icons.numbers_outlined,
                  title: 'No series configured',
                  subtitle:
                      'Create numbering series for invoices, bills, and more.',
                  actionLabel: 'Create Series',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    for (final key in sortedKeys) ...[
                      _buildGroupHeader(colors, key),
                      ...grouped[key]!.map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildSeriesCard(colors, s),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildGroupHeader(ApexColors colors, String docType) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        _docTypeLabel(docType),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSeriesCard(ApexColors colors, InvoiceSeries series) {
    return ApexCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(ApexRadius_lg),
        onTap: () => _showSeriesDialog(existing: series),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: series.isActive
                    ? colors.primary.withValues(alpha: 0.1)
                    : colors.surfaceMuted,
                borderRadius: BorderRadius.circular(ApexRadius_md),
              ),
              child: Icon(
                Icons.tag_rounded,
                size: 22,
                color: series.isActive ? colors.primary : colors.textMuted,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        series.preview,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!series.isActive)
                        const StatusBadge(
                          label: 'INACTIVE',
                          tone: StatusTone.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Prefix: "${series.prefix}"  |  Suffix: "${series.suffix}"  |  Pad: ${series.paddingDigits}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Next: ${series.nextNumber}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: colors.textMuted),
          ],
        ),
      ),
    );
  }

  String _docTypeLabel(String docType) {
    return DocumentType.labels[docType] ??
        docType.replaceAll('_', ' ').toUpperCase();
  }
}

/// Dialog for creating or editing a numbering series.
class _SeriesFormDialog extends StatefulWidget {
  const _SeriesFormDialog({
    this.existing,
    required this.prefixController,
    required this.suffixController,
    required this.nextNumberController,
    required this.paddingController,
    required this.selectedDocType,
    required this.isActive,
    required this.onDocTypeChanged,
    required this.onActiveChanged,
  });

  final InvoiceSeries? existing;
  final TextEditingController prefixController;
  final TextEditingController suffixController;
  final TextEditingController nextNumberController;
  final TextEditingController paddingController;
  final String selectedDocType;
  final bool isActive;
  final ValueChanged<String> onDocTypeChanged;
  final ValueChanged<bool> onActiveChanged;

  @override
  State<_SeriesFormDialog> createState() => _SeriesFormDialogState();
}

class _SeriesFormDialogState extends State<_SeriesFormDialog> {
  late String _docType;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _docType = widget.selectedDocType;
    _isActive = widget.isActive;
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isEdit = widget.existing != null;

    return AlertDialog(
      icon: Icon(Icons.tag_rounded, size: 36, color: colors.primary),
      title: Text(isEdit ? 'Edit Series' : 'New Series'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Document Type
              DropdownButtonFormField<String>(
                initialValue: _docType.isNotEmpty ? _docType : null,
                decoration: const InputDecoration(
                  labelText: 'Document Type *',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                items: DocumentType.labels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: isEdit
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() => _docType = v);
                          widget.onDocTypeChanged(v);
                        }
                      },
              ),
              const SizedBox(height: 16),
              // Prefix
              TextFormField(
                controller: widget.prefixController,
                decoration: const InputDecoration(
                  labelText: 'Prefix',
                  hintText: 'e.g. INV-',
                  prefixIcon: Icon(Icons.text_fields),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              // Suffix
              TextFormField(
                controller: widget.suffixController,
                decoration: const InputDecoration(
                  labelText: 'Suffix',
                  hintText: 'e.g. /FY26',
                  prefixIcon: Icon(Icons.text_fields),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              // Next Number + Padding
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: widget.nextNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Next Number *',
                        prefixIcon: Icon(Icons.looks_one_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: widget.paddingController,
                      decoration: const InputDecoration(
                        labelText: 'Padding Digits',
                        prefixIcon: Icon(Icons.grid_view_outlined),
                        helperText: 'e.g. 3 → 001',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (isEdit) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Active'),
                  subtitle: Text(
                    _isActive
                        ? 'Series will be used for new documents'
                        : 'Series is disabled',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  value: _isActive,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) {
                    setState(() => _isActive = v);
                    widget.onActiveChanged(v);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_docType.isEmpty && !isEdit)
              ? null
              : () => Navigator.pop(context, true),
          child: Text(isEdit ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
