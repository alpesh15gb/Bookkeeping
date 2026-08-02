/// Goods Receipt Detail Screen — Professional detail view with summary, lines, timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/goods_receipt.dart';
import '../models/goods_receipt_status.dart';
import '../services/goods_receipt_service.dart';
import 'goods_receipt_form_screen.dart';
import 'goods_receipt_list_provider.dart';
import 'components/gr_detail_header.dart';
import 'components/gr_detail_summary.dart';
import 'components/gr_detail_lines.dart';
import 'components/gr_detail_timeline.dart';

class GoodsReceiptDetailScreen extends ConsumerStatefulWidget {
  const GoodsReceiptDetailScreen({
    super.key,
    required this.grId,
    this.embedded = false,
    this.onClose,
  });

  final String grId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<GoodsReceiptDetailScreen> createState() => _GoodsReceiptDetailScreenState();
}

class _GoodsReceiptDetailScreenState extends ConsumerState<GoodsReceiptDetailScreen>
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
    final state = ref.watch(goodsReceiptDetailProvider(widget.grId));
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    final content = state.when(
      data: (gr) => _buildContent(context, gr, colors, isMobile, isTablet),
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
    GoodsReceipt gr,
    ApexColors colors,
    bool isMobile,
    bool isTablet,
  ) {
    final fmt = ref.watch(numberFormatterProvider);

    return Column(
      children: [
        // Page Header
        if (!widget.embedded)
          GRDetailHeader(
            gr: gr,
            onClose: widget.onClose,
            onEdit: _canEdit(gr) ? () => _openEdit(gr) : null,
            onPrint: () => _printGR(gr),
            onCancel: _canCancel(gr) ? () => _cancelGR(gr) : null,
            onDelete: _canDelete(gr) ? () => _deleteGR(gr) : null,
          ),

        // Tab Bar
        _buildTabBar(context, gr, colors, isMobile),

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
                    GRDetailSummary(gr: gr, fmt: fmt),
                    const SizedBox(height: 24),
                    GRDetailLines(gr: gr, fmt: fmt),
                  ],
                ),
              ),
              // Timeline Tab
              GRDetailTimeline(gr: gr),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    GoodsReceipt gr,
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
            Text('Failed to load goods receipt', style: textTheme.headlineSmall?.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error.toString(), style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ApexPrimaryButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: () => ref.invalidate(goodsReceiptDetailProvider(widget.grId)),
            ),
          ],
        ),
      ),
    );
  }

  bool _canEdit(GoodsReceipt gr) => gr.status == GoodsReceiptStatus.draft;
  bool _canCancel(GoodsReceipt gr) => gr.status == GoodsReceiptStatus.draft || gr.status == GoodsReceiptStatus.pending;
  bool _canDelete(GoodsReceipt gr) => gr.status == GoodsReceiptStatus.draft;

  Future<void> _openEdit(GoodsReceipt gr) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GoodsReceiptFormScreen()),
    );
    if (result != null && mounted) {
      ref.invalidate(goodsReceiptDetailProvider(widget.grId));
      ref.invalidate(goodsReceiptListProvider);
    }
  }

  Future<void> _printGR(GoodsReceipt gr) async {
    try {
      await ref.read(downloadServiceProvider).downloadGRPdf(gr.id);
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Goods receipt downloaded', type: SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Failed to download: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _cancelGR(GoodsReceipt gr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Goods Receipt'),
        content: Text('Cancel GRN ${gr.receiptNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).error),
            child: const Text('Cancel Receipt'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await ref.read(goodsReceiptServiceProvider).cancel(gr.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(goodsReceiptDetailProvider(widget.grId));
          ref.invalidate(goodsReceiptListProvider);
          ApexSnackBar.show(context: context, message: 'Goods receipt cancelled', type: SnackBarType.success);
          if (widget.onClose != null) widget.onClose!();
        case Failure(:final error):
          ApexSnackBar.show(context: context, message: error.message, type: SnackBarType.error);
        default:
          break;
      }
    }
  }

  Future<void> _deleteGR(GoodsReceipt gr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Goods Receipt'),
        content: Text('Permanently delete GRN ${gr.receiptNumber}? This cannot be undone.'),
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
      final result = await ref.read(goodsReceiptServiceProvider).delete(gr.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(goodsReceiptListProvider);
          ApexSnackBar.show(context: context, message: 'Goods receipt deleted', type: SnackBarType.success);
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

final goodsReceiptDetailProvider = FutureProvider.family<GoodsReceipt, String>((ref, id) async {
  final service = ref.read(goodsReceiptServiceProvider);
  final result = await service.get(id);
  return result.getOrThrow();
});