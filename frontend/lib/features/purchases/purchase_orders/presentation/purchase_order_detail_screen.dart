/// Purchase Order Detail Screen — Professional detail view with summary, lines, receipts, timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/purchase_order.dart';
import '../models/purchase_order_status.dart';
import '../services/purchase_order_service.dart';
import 'purchase_order_form_screen.dart';
import 'purchase_order_list_provider.dart';
import 'components/po_detail_header.dart';
import 'components/po_detail_summary.dart';
import 'components/po_detail_lines.dart';
import 'components/po_detail_receipts.dart';
import 'components/po_detail_timeline.dart';

class PurchaseOrderDetailScreen extends ConsumerStatefulWidget {
  const PurchaseOrderDetailScreen({
    super.key,
    required this.poId,
    this.embedded = false,
    this.onClose,
  });

  final String poId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<PurchaseOrderDetailScreen> createState() => _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends ConsumerState<PurchaseOrderDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(purchaseOrderDetailProvider(widget.poId));
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    final content = state.when(
      data: (po) => _buildContent(context, po, colors, isMobile, isTablet),
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
    PurchaseOrder po,
    ApexColors colors,
    bool isMobile,
    bool isTablet,
  ) {
    final fmt = ref.watch(numberFormatterProvider);

    return Column(
      children: [
        // Page Header
        if (!widget.embedded)
          PODetailHeader(
            po: po,
            onClose: widget.onClose,
            onEdit: _canEdit(po) ? () => _openEdit(po) : null,
            onPrint: () => _printPO(po),
            onCancel: _canCancel(po) ? () => _cancelPO(po) : null,
            onDelete: _canDelete(po) ? () => _deletePO(po) : null,
            onCreateReceipt: _canCreateReceipt(po) ? () => _createReceipt(po) : null,
          ),

        // Tab Bar
        _buildTabBar(context, po, colors, isMobile),

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
                    PODetailSummary(po: po, fmt: fmt),
                    const SizedBox(height: 24),
                    PODetailLines(po: po, fmt: fmt),
                  ],
                ),
              ),
              // Receipts Tab
              PODetailReceipts(po: po, fmt: fmt),
              // Timeline Tab
              PODetailTimeline(po: po),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    PurchaseOrder po,
    ApexColors colors,
    bool isMobile,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final hasReceipts = (po.receipts?.isNotEmpty ?? false);

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
          Tab(text: hasReceipts ? 'Receipts (${po.receipts?.length ?? 0})' : 'Receipts'),
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
            Text('Failed to load purchase order', style: textTheme.headlineSmall?.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error.toString(), style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ApexPrimaryButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: () => ref.invalidate(purchaseOrderDetailProvider(widget.poId)),
            ),
          ],
        ),
      ),
    );
  }

  bool _canEdit(PurchaseOrder po) => po.status == PurchaseOrderStatus.draft;
  bool _canCancel(PurchaseOrder po) => po.status == PurchaseOrderStatus.draft || po.status == PurchaseOrderStatus.pending;
  bool _canDelete(PurchaseOrder po) => po.status == PurchaseOrderStatus.draft;
  bool _canCreateReceipt(PurchaseOrder po) => po.status == PurchaseOrderStatus.approved || po.status == PurchaseOrderStatus.partial;

  Future<void> _openEdit(PurchaseOrder po) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PurchaseOrderFormScreen()),
    );
    if (result != null && mounted) {
      ref.invalidate(purchaseOrderDetailProvider(widget.poId));
      ref.invalidate(purchaseOrderListProvider(const PurchaseOrderListQuery()));
    }
  }

  Future<void> _printPO(PurchaseOrder po) async {
    try {
      await ref.read(downloadServiceProvider).downloadPOPdf(po.id);
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'PO downloaded', type: SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Failed to download: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _cancelPO(PurchaseOrder po) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Purchase Order'),
        content: Text('Cancel PO ${po.poNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).error),
            child: const Text('Cancel PO'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await ref.read(purchaseOrderServiceProvider).cancel(po.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(purchaseOrderDetailProvider(widget.poId));
          ref.invalidate(purchaseOrderListProvider(const PurchaseOrderListQuery()));
          ApexSnackBar.show(context: context, message: 'PO cancelled', type: SnackBarType.success);
          if (widget.onClose != null) widget.onClose!();
        case Failure(:final error):
          ApexSnackBar.show(context: context, message: error.message, type: SnackBarType.error);
        default:
          break;
      }
    }
  }

  Future<void> _deletePO(PurchaseOrder po) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Purchase Order'),
        content: Text('Permanently delete PO ${po.poNumber}? This cannot be undone.'),
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
      final result = await ref.read(purchaseOrderServiceProvider).delete(po.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(purchaseOrderListProvider(const PurchaseOrderListQuery()));
          ApexSnackBar.show(context: context, message: 'PO deleted', type: SnackBarType.success);
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

  Future<void> _createReceipt(PurchaseOrder po) async {
    // TODO: Navigate to goods receipt creation with PO context
    if (mounted) {
      ApexSnackBar.show(context: context, message: 'Create receipt from PO not yet implemented', type: SnackBarType.info);
    }
  }
}

// ───── Providers ────────────────────────────────────────────────────────────

final purchaseOrderDetailProvider = FutureProvider.family<PurchaseOrder, String>((ref, id) async {
  final service = ref.read(purchaseOrderServiceProvider);
  final result = await service.get(id);
  return result.getOrThrow();
});