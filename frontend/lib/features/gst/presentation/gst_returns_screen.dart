/// GST Returns filing status screen — list, filter by type/status, and
/// quick-create or update returns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/skeleton_loader.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/errors/user_message.dart';
import '../services/gst_service.dart';
import '../models/gst_models.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

final _returnsFilterTypeProvider = StateProvider<String?>((ref) => null);
final _returnsFilterStatusProvider = StateProvider<String?>((ref) => null);

final _returnsListProvider = FutureProvider.autoDispose<List<GstReturn>>((
  ref,
) async {
  final type = ref.watch(_returnsFilterTypeProvider);
  final status = ref.watch(_returnsFilterStatusProvider);
  final res = await ref
      .read(gstServiceProvider)
      .listReturns(returnType: type, status: status);
  return switch (res) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => throw Exception(),
  };
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GstReturnsScreen extends ConsumerStatefulWidget {
  const GstReturnsScreen({super.key});
  @override
  ConsumerState<GstReturnsScreen> createState() => _GstReturnsScreenState();
}

class _GstReturnsScreenState extends ConsumerState<GstReturnsScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final asyncVal = ref.watch(_returnsListProvider);
    final typeFilter = ref.watch(_returnsFilterTypeProvider);
    final statusFilter = ref.watch(_returnsFilterStatusProvider);

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'GST Returns',
            subtitle: 'Track and manage return filings.',
            actions: [
              FilledButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New Return'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ApexSpacing.lg,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          // Filters
          _filterRow(typeFilter, statusFilter, colors),
          const SizedBox(height: ApexSpacing.sm),
          // Content
          Expanded(
            child: asyncVal.when(
              loading: () => const _ReturnsLoading(),
              error: (err, _) => ErrorView(
                message: userFacingErrorMessage(err),
                onRetry: () => ref.invalidate(_returnsListProvider),
              ),
              data: (returns) {
                if (returns.isEmpty) {
                  return const EmptyState(
                    icon: Icons.assignment_rounded,
                    title: 'No returns found',
                    subtitle: 'Create a new return to start tracking filings.',
                  );
                }
                return _returnsList(returns, colors);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter row
  // ---------------------------------------------------------------------------

  Widget _filterRow(
    String? typeFilter,
    String? statusFilter,
    ApexColors colors,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ApexSpacing.xl, 0, ApexSpacing.xl, 0),
      child: Row(
        children: [
          _filterChip(
            label: 'All Types',
            selected: typeFilter == null,
            onTap: () =>
                ref.read(_returnsFilterTypeProvider.notifier).state = null,
            colors: colors,
          ),
          const SizedBox(width: 6),
          _filterChip(
            label: 'GSTR-1',
            selected: typeFilter == 'GSTR1',
            onTap: () =>
                ref.read(_returnsFilterTypeProvider.notifier).state = 'GSTR1',
            colors: colors,
          ),
          const SizedBox(width: 6),
          _filterChip(
            label: 'GSTR-3B',
            selected: typeFilter == 'GSTR3B',
            onTap: () =>
                ref.read(_returnsFilterTypeProvider.notifier).state = 'GSTR3B',
            colors: colors,
          ),
          const Spacer(),
          _filterChip(
            label: 'All Status',
            selected: statusFilter == null,
            onTap: () =>
                ref.read(_returnsFilterStatusProvider.notifier).state = null,
            colors: colors,
          ),
          const SizedBox(width: 6),
          _filterChip(
            label: 'Draft',
            selected: statusFilter == 'DRAFT',
            onTap: () =>
                ref.read(_returnsFilterStatusProvider.notifier).state = 'DRAFT',
            colors: colors,
          ),
          const SizedBox(width: 6),
          _filterChip(
            label: 'Filed',
            selected: statusFilter == 'FILED',
            onTap: () =>
                ref.read(_returnsFilterStatusProvider.notifier).state = 'FILED',
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required ApexColors colors,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ApexRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceRaised,
          borderRadius: BorderRadius.circular(ApexRadius.pill),
          border: Border.all(color: selected ? colors.primary : colors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? colors.onPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Returns list
  // ---------------------------------------------------------------------------

  Widget _returnsList(List<GstReturn> returns, ApexColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        ApexSpacing.xl,
        0,
        ApexSpacing.xl,
        ApexSpacing.xxl,
      ),
      itemCount: returns.length,
      itemBuilder: (context, i) {
        final r = returns[i];
        return _returnCard(r, colors);
      },
    );
  }

  Widget _returnCard(GstReturn r, ApexColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: ApexSpacing.sm),
      padding: const EdgeInsets.all(ApexSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(ApexRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(ApexRadius.sm),
            ),
            child: Center(
              child: Text(
                r.returnType.replaceAll('GSTR', ''),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: ApexSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      r.returnType,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _badge(r.status, colors),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  r.periodLabel,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                if (r.arn != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'ARN: ${r.arn}',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                  ),
                if (r.filedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Filed: ${r.filedAt}',
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) => _handleAction(action, r),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'update_status',
                child: Text('Update Status'),
              ),
              if (r.status == 'DRAFT' || r.status == 'READY')
                const PopupMenuItem(
                  value: 'file',
                  child: Text('Mark as Filed'),
                ),
              const PopupMenuItem(value: 'edit_arn', child: Text('Edit ARN')),
            ],
            icon: Icon(
              Icons.more_vert_rounded,
              size: 18,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String status, ApexColors colors) {
    final (label, tone) = switch (status.toUpperCase()) {
      'DRAFT' => ('Draft', StatusTone.neutral),
      'READY' => ('Ready', StatusTone.info),
      'FILED' => ('Filed', StatusTone.success),
      'REVISED' => ('Revised', StatusTone.warning),
      _ => (status, StatusTone.neutral),
    };
    return StatusBadge(label: label, tone: tone);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _handleAction(String action, GstReturn r) {
    switch (action) {
      case 'update_status':
        _showUpdateDialog(r);
      case 'file':
        _markFiled(r);
      case 'edit_arn':
        _showArnDialog(r);
    }
  }

  Future<void> _markFiled(GstReturn r) async {
    final res = await ref
        .read(gstServiceProvider)
        .updateReturn(id: r.id, status: 'FILED');
    if (res is Success && mounted) {
      ref.invalidate(_returnsListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Return marked as Filed')));
    }
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<void> _showCreateDialog() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => const _ReturnCreateDialog(),
    );
    if (result == null || !mounted) return;
    final res = await ref
        .read(gstServiceProvider)
        .createReturn(
          returnType: result['type']!,
          periodStart: result['periodStart']!,
          periodEnd: result['periodEnd']!,
          status: result['status'] ?? 'DRAFT',
          arn: result['arn'],
        );
    if (res is Success && mounted) {
      ref.invalidate(_returnsListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Return created successfully')),
      );
    }
  }

  Future<void> _showUpdateDialog(GstReturn r) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _ReturnUpdateDialog(currentStatus: r.status),
    );
    if (result == null || !mounted) return;
    final res = await ref
        .read(gstServiceProvider)
        .updateReturn(id: r.id, status: result['status']!, arn: result['arn']);
    if (res is Success && mounted) {
      ref.invalidate(_returnsListProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Return updated')));
    }
  }

  Future<void> _showArnDialog(GstReturn r) async {
    final ctrl = TextEditingController(text: r.arn ?? '');
    final arn = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit ARN'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'ARN',
            hintText: 'Enter ARN',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (arn == null || !mounted) return;
    final res = await ref
        .read(gstServiceProvider)
        .updateReturn(
          id: r.id,
          status: r.status,
          arn: arn.isNotEmpty ? arn : null,
        );
    if (res is Success && mounted) {
      ref.invalidate(_returnsListProvider);
    }
  }
}

// ---------------------------------------------------------------------------
// Create Return Dialog
// ---------------------------------------------------------------------------

class _ReturnCreateDialog extends StatefulWidget {
  const _ReturnCreateDialog();
  @override
  State<_ReturnCreateDialog> createState() => _ReturnCreateDialogState();
}

class _ReturnCreateDialogState extends State<_ReturnCreateDialog> {
  String _type = 'GSTR3B';
  String _status = 'DRAFT';
  DateTime _date = DateTime.now();
  final _arnCtrl = TextEditingController();

  @override
  void dispose() {
    _arnCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return AlertDialog(
      title: const Text('Create GST Return'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Return type
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Return Type'),
            items: const [
              DropdownMenuItem(value: 'GSTR1', child: Text('GSTR-1')),
              DropdownMenuItem(value: 'GSTR2', child: Text('GSTR-2')),
              DropdownMenuItem(value: 'GSTR3B', child: Text('GSTR-3B')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'GSTR3B'),
          ),
          const SizedBox(height: ApexSpacing.md),
          // Period
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                helpText: 'Select month',
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Period (month)'),
              child: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}',
                style: TextStyle(color: colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: ApexSpacing.md),
          // Status
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
              DropdownMenuItem(value: 'READY', child: Text('Ready')),
              DropdownMenuItem(value: 'FILED', child: Text('Filed')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'DRAFT'),
          ),
          const SizedBox(height: ApexSpacing.md),
          TextField(
            controller: _arnCtrl,
            decoration: const InputDecoration(labelText: 'ARN (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final days = _daysInMonth(_date.year, _date.month);
            final periodStart =
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-01';
            final periodEnd =
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-$days';
            Navigator.pop(
              context,
              {
                    'type': _type,
                    'periodStart': periodStart,
                    'periodEnd': periodEnd,
                    'status': _status,
                    'arn': _arnCtrl.text.isNotEmpty ? _arnCtrl.text : null,
                  }
                  as Map<String, String>?,
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  int _daysInMonth(int year, int month) {
    if (month == 2) {
      if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) return 29;
      return 28;
    }
    if ([4, 6, 9, 11].contains(month)) return 30;
    return 31;
  }
}

// ---------------------------------------------------------------------------
// Update Return Dialog
// ---------------------------------------------------------------------------

class _ReturnUpdateDialog extends StatefulWidget {
  const _ReturnUpdateDialog({required this.currentStatus});
  final String currentStatus;

  @override
  State<_ReturnUpdateDialog> createState() => _ReturnUpdateDialogState();
}

class _ReturnUpdateDialogState extends State<_ReturnUpdateDialog> {
  late String _status;
  final _arnCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _status = widget.currentStatus;
  }

  @override
  void dispose() {
    _arnCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update Return Status'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
              DropdownMenuItem(value: 'READY', child: Text('Ready')),
              DropdownMenuItem(value: 'FILED', child: Text('Filed')),
              DropdownMenuItem(value: 'REVISED', child: Text('Revised')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'DRAFT'),
          ),
          const SizedBox(height: ApexSpacing.md),
          TextField(
            controller: _arnCtrl,
            decoration: const InputDecoration(labelText: 'ARN (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              {
                    'status': _status,
                    'arn': _arnCtrl.text.isNotEmpty ? _arnCtrl.text : null,
                  }
                  as Map<String, String>?,
            );
          },
          child: const Text('Update'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeleton
// ---------------------------------------------------------------------------

class _ReturnsLoading extends StatelessWidget {
  const _ReturnsLoading();

  @override
  Widget build(BuildContext context) {
    return ShimmerSkeleton(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ApexSpacing.xl,
          0,
          ApexSpacing.xl,
          ApexSpacing.xxl,
        ),
        child: Column(
          children: List.generate(
            4,
            (_) => Container(
              margin: const EdgeInsets.only(bottom: ApexSpacing.sm),
              padding: const EdgeInsets.all(ApexSpacing.lg),
              decoration: BoxDecoration(
                color: apexColors(context).skeletonBase,
                borderRadius: BorderRadius.circular(ApexRadius.lg),
              ),
              child: Row(
                children: [
                  SkeletonBox(
                    width: 40,
                    height: 40,
                    borderRadius: BorderRadius.circular(ApexRadius.sm),
                  ),
                  const SizedBox(width: ApexSpacing.md),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 120, height: 14),
                        SizedBox(height: 6),
                        SkeletonBox(width: 80, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
