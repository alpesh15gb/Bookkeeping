/// Inward-supply register presented as the book side of GSTR-2B reconciliation.
library;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/download/download_service.dart';
import '../../../core/formatting/number_formatting.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/notification_service.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/presentation/design_system/tokens/app_spacing.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../models/gst_models.dart';
import '../services/gst_service.dart';

final _gstr2PeriodProvider = StateProvider<String>((ref) {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
});

int _monthDays(int year, int month) => DateTime(year, month + 1, 0).day;

final _gstr2ReportProvider = FutureProvider.autoDispose<Gstr2Summary>((
  ref,
) async {
  final period = ref.watch(_gstr2PeriodProvider);
  final parts = period.split('-');
  final days = _monthDays(int.parse(parts[0]), int.parse(parts[1]));
  final result = await ref
      .read(gstServiceProvider)
      .getGstr2(
        startDate: '$period-01',
        endDate: '$period-${days.toString().padLeft(2, '0')}',
      );
  return switch (result) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw StateError('GSTR-2 report did not complete.'),
  };
});

class Gstr2Screen extends ConsumerStatefulWidget {
  const Gstr2Screen({super.key});

  @override
  ConsumerState<Gstr2Screen> createState() => _Gstr2ScreenState();
}

class _Gstr2ScreenState extends ConsumerState<Gstr2Screen> {
  bool _downloading = false;
  bool _reconciling = false;

  ({String start, String end}) get _dates {
    final period = ref.read(_gstr2PeriodProvider);
    final parts = period.split('-');
    final days = _monthDays(int.parse(parts[0]), int.parse(parts[1]));
    return (
      start: '$period-01',
      end: '$period-${days.toString().padLeft(2, '0')}',
    );
  }

  Future<void> _download(ExportKind kind) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final dates = _dates;
    final result = await ref
        .read(downloadServiceProvider)
        .download(
          relativeUrl: kind == ExportKind.pdf
              ? '/gst/gstr2/pdf'
              : '/gst/gstr2/export',
          filename: 'GSTR2_Books_${ref.read(_gstr2PeriodProvider)}',
          kind: kind,
          queryParameters: {'start_date': dates.start, 'end_date': dates.end},
        );
    if (!mounted) return;
    setState(() => _downloading = false);
    final notifications = ref.read(notificationServiceProvider);
    switch (result) {
      case Success(:final value):
        notifications.success(
          context,
          'Saved to ${value.path}',
          title: 'Report downloaded',
        );
      case Failure(:final error):
        notifications.error(context, error.message, title: 'Download failed');
      default:
        break;
    }
  }

  Future<void> _reconcilePortalJson() async {
    if (_reconciling) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    if (!mounted) return;
    if (file.bytes == null) {
      ref
          .read(notificationServiceProvider)
          .error(context, 'The selected JSON file could not be read.');
      return;
    }
    setState(() => _reconciling = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/gst/gstr2a/upload',
            data: FormData.fromMap({
              'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
            }),
          );
      if (!mounted) return;
      final data = response.data ?? const <String, dynamic>{};
      await showDialog<void>(
        context: context,
        builder: (context) => _ReconciliationDialog(data: data),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final body = error.response?.data;
      final message = body is Map && body['detail'] is String
          ? body['detail'] as String
          : 'The portal JSON could not be reconciled. Verify that it is an unmodified GSTR-2B or GSTR-2A download.';
      ref
          .read(notificationServiceProvider)
          .error(context, message, title: 'Reconciliation failed');
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final report = ref.watch(_gstr2ReportProvider);
    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Purchase ITC / GSTR-2B',
            subtitle:
                'Book-side inward supplies for vendor GST and ITC reconciliation.',
            actions: [
              FilledButton.icon(
                onPressed: _reconciling ? null : _reconcilePortalJson,
                icon: _reconciling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.compare_arrows_outlined, size: 18),
                label: Text(_reconciling ? 'Reconciling...' : 'Reconcile 2B'),
              ),
              OutlinedButton.icon(
                onPressed: _downloading
                    ? null
                    : () => _download(ExportKind.pdf),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _downloading
                    ? null
                    : () => _download(ExportKind.excel),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Excel'),
              ),
              _periodButton(colors),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.info.withValues(alpha: .08),
                border: Border.all(color: colors.info.withValues(alpha: .25)),
                borderRadius: BorderRadius.circular(ApexRadius_md),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.info, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'GSTR-2 is not an active return for normal filing. This report shows ApexBooks purchases; compare it with the static GSTR-2B downloaded from the GST portal before claiming ITC in GSTR-3B.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: report.when(
              loading: () => const Center(child: LoadingSpinner()),
              error: (error, _) => ErrorView(
                message: userFacingErrorMessage(error),
                onRetry: () => ref.invalidate(_gstr2ReportProvider),
              ),
              data: (value) => _report(value, colors),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodButton(ApexColors colors) {
    final period = ref.watch(_gstr2PeriodProvider);
    return OutlinedButton.icon(
      onPressed: () async {
        final parts = period.split('-');
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1])),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          helpText: 'Select return month',
        );
        if (picked != null) {
          ref.read(_gstr2PeriodProvider.notifier).state =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
        }
      },
      icon: const Icon(Icons.calendar_month_outlined, size: 18),
      label: Text(period),
    );
  }

  Widget _report(Gstr2Summary report, ApexColors colors) {
    final fmt = ref.watch(numberFormatterProvider);
    final lines = report.all;
    final taxable = lines.fold<double>(0, (sum, row) => sum + row.taxableValue);
    final itc = lines.fold<double>(
      0,
      (sum, row) => sum + row.cgstAmount + row.sgstAmount + row.igstAmount,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric('Purchase documents', '${lines.length}', colors),
            _metric('Taxable purchases', fmt.currency(taxable), colors),
            _metric('Potential ITC in books', fmt.currency(itc), colors),
            _metric(
              'Unregistered / RCM review',
              '${report.unregistered.length}',
              colors,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (lines.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No posted purchase bills',
            subtitle: 'Posted vendor bills for this period will appear here.',
          )
        else
          ApexCard(
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Vendor / GSTIN')),
                  DataColumn(label: Text('Bill')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Taxable'), numeric: true),
                  DataColumn(label: Text('CGST'), numeric: true),
                  DataColumn(label: Text('SGST/UTGST'), numeric: true),
                  DataColumn(label: Text('IGST'), numeric: true),
                  DataColumn(label: Text('Total'), numeric: true),
                ],
                rows: lines
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 210,
                              child: Text(
                                '${row.vendorName}\n${row.vendorGstin}',
                              ),
                            ),
                          ),
                          DataCell(Text(row.billNumber)),
                          DataCell(Text(row.billDate)),
                          DataCell(Text(fmt.currency(row.taxableValue))),
                          DataCell(Text(fmt.currency(row.cgstAmount))),
                          DataCell(Text(fmt.currency(row.sgstAmount))),
                          DataCell(Text(fmt.currency(row.igstAmount))),
                          DataCell(Text(fmt.currency(row.totalValue))),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _metric(String label, String value, ApexColors colors) => SizedBox(
    width: 220,
    child: ApexCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _ReconciliationDialog extends StatelessWidget {
  const _ReconciliationDialog({required this.data});

  final Map<String, dynamic> data;

  int _count(String key) => (data[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final matches = (data['matches'] as List?) ?? const [];
    final unmatched = (data['unmatched_items'] as List?) ?? const [];
    return AlertDialog(
      title: const Text('GSTR-2B reconciliation'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${_count('matched')} matched')),
                  Chip(
                    label: Text(
                      '${_count('partially_matched')} value/tax differences',
                    ),
                  ),
                  Chip(label: Text('${_count('unmatched')} missing in books')),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Review differences before claiming ITC. A match checks supplier GSTIN, normalized invoice number, invoice value, and total tax within ₹1.',
              ),
              if (matches.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Matched / different documents',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...matches.take(20).map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      row['status'] == 'matched'
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_outlined,
                    ),
                    title: Text(
                      '${row['supplier_name'] ?? row['supplier_gstin']} · ${row['bill_number']}',
                    ),
                    subtitle: Text(
                      'Value difference ₹${row['difference']} · Tax difference ₹${row['tax_difference'] ?? 0}',
                    ),
                  );
                }),
              ],
              if (unmatched.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Portal documents missing in books',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...unmatched.take(20).map((raw) {
                  final row = Map<String, dynamic>.from(raw as Map);
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(
                      '${row['supplier_name'] ?? row['supplier_gstin']} · ${row['invoice_number']}',
                    ),
                    subtitle: Text(
                      '${row['invoice_date']} · ₹${row['invoice_value']}',
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
