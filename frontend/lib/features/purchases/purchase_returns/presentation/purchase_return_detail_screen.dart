/// Purchase Return Detail Screen — Professional detail view with summary, lines, timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_return.dart';
import '../models/purchase_return_status.dart';
import '../services/purchase_return_service.dart';
import 'purchase_return_form_screen.dart';
import 'purchase_return_list_provider.dart';
import 'components/pr_detail_header.dart';
import 'components/pr_detail_summary.dart';
import 'components/pr_detail_lines.dart';
import 'components/pr_detail_timeline.dart';

class PurchaseReturnDetailScreen extends ConsumerStatefulWidget {
  const PurchaseReturnDetailScreen({
    super.key,
    required this.returnId,
    this.embedded = false,
    this.onClose,
  });

  final String returnId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<PurchaseReturnDetailScreen> createState() => _PurchaseReturnDetailScreenState();
}

class _PurchaseReturnDetailScreenState extends ConsumerState<PurchaseReturnDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseReturnDetailProvider(widget.returnId));
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    final content = state.when(
      data: (pr) => _buildContent(context, pr, colors, isMobile, isTablet),
      loading: () => const Center(child: ApexSkeletonLoader()),
      error: (error, _) => _buildErrorState(error),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: SafeArea(child: content),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PurchaseReturn pr,
    ApexColors colors,
    bool isMobile,
    bool isTablet,
  ) {
    final fmt = ref.watch(numberFormatterProvider);

    return Column(
      children: [
        // Page Header
        if (!widget.embedded)
          PRDetailHeader(
            pr: pr,
            onClose: widget.onClose,
            onEdit: _canEdit(pr) ? () => _openEdit(pr) : null,
            onPrint: () => _printPR(pr),
            onCancel: _canCancel(pr) ? () => _cancelPR(pr) : null,
            onDelete: _canDelete(pr) ? () => _deletePR(pr) : null,
          ),

        // Tab Bar
        _buildTabBar(context, pr, colors, isMobile),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Overview Tab
              SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PRDetailSummary(pr: pr, fmt: fmt),
                    const SizedBox(height: 24),
                    PRDetailLines(pr: pr, fmt: fmt),
                  ],
                ),
              ),
              // Timeline Tab
              PRDetailTimeline(pr: pr),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    PurchaseReturn pr,
    ApexColors colors,
    bool isMobile,
  ) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      color: colors.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: colors.primary,
        indicatorWeight: 3,
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
        tabs: [
          const Tab(text: 'Overview'),
          const Tab(text: 'Timeline'),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    final colors = apexColors(context);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: colors.error),
            const SizedBox(height: 16),
            Text('Failed to load purchase return', style: textTheme.headlineSmall?.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error.toString(), style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ApexPrimaryButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: () => ref.invalidate(purchaseReturnDetailProvider(widget.returnId)),
            ),
          ],
        ),
      ),
    );
  }

  bool _canEdit(PurchaseReturn pr) => pr.status == PurchaseReturnStatus.draft;
  bool _canCancel(PurchaseReturn pr) => pr.status == PurchaseReturnStatus.draft || pr.status == PurchaseReturnStatus.pending;
  bool _canDelete(PurchaseReturn pr) => pr.status == PurchaseReturnStatus.draft;

  Future<void> _openEdit(PurchaseReturn pr) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PurchaseReturnFormScreen()),
    );
    if (result != null && mounted) {
      ref.invalidate(purchaseReturnDetailProvider(widget.returnId));
      ref.invalidate(purchaseReturnListProvider);
    }
  }

  Future<void> _printPR(PurchaseReturn pr) async {
    try {
      await ref.read(downloadServiceProvider).downloadPRPdf(pr.id);
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Return downloaded', type: SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Failed to download: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _cancelPR(PurchaseReturn pr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Purchase Return'),
        content: Text('Cancel return ${pr.returnNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).error),
            child: const Text('Cancel Return'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await ref.read(purchaseReturnServiceProvider).cancel(pr.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(purchaseReturnDetailProvider(widget.returnId));
          ref.invalidate(purchaseReturnListProvider);
          ApexSnackBar.show(context: context, message: 'Return cancelled', type: SnackBarType.success);
          if (widget.onClose != null) widget.onClose!();
        case Failure(:final error):
          ApexSnackBar.show(context: context, message: error.message, type: SnackBarType.error);
        default:
          break;
      }
    }
  }

  Future<void> _deletePR(PurchaseReturn pr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase Return'),
        content: Text('Permanently delete return ${pr.returnNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await ref.read(purchaseReturnServiceProvider).delete(pr.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(purchaseReturnListProvider);
          ApexSnackBar.show(context: context, message: 'Return deleted', type: SnackBarType.success);
          if (widget.onClose != null) {
            widget.onClose!();
          } else if (mounted) {
          Navigator.of(context).pop();
        }
        case Failure(:final error):
          ApexSnackBar.show(context: context, message: error.message, type: SnackBarType.error);
        default:
          break;
      }
    }
  }
}

// ───── Providers ────────────────────────────────────────────────────────────

final purchaseReturnDetailProvider = FutureProvider.family<PurchaseReturn, String>((ref, id) async {
  final service = ref.read(purchaseReturnServiceProvider);
  final result = await service.get(id);
  return result.getOrThrow();
});