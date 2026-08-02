/// Vendor Bill Detail Screen — Professional detail view with summary, lines, payments, timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/vendor_bill.dart';
import '../models/bill_status.dart';
import '../services/vendor_bill_service.dart';
import 'bill_form_screen.dart';
import 'bill_list_provider.dart';
import 'components/bill_detail_header.dart';
import 'components/bill_detail_summary.dart';
import 'components/bill_detail_lines.dart';
import 'components/bill_detail_payments.dart';
import 'components/bill_detail_timeline.dart';

class BillDetailScreen extends ConsumerStatefulWidget {
  const BillDetailScreen({
    super.key,
    required this.billId,
    this.embedded = false,
    this.onClose,
  });

  final String billId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen>
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
    final state = ref.watch(billDetailProvider(widget.billId));
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    final content = state.when(
      data: (bill) => _buildContent(context, bill, colors, isMobile, isTablet),
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
    VendorBill bill,
    ApexColors colors,
    bool isMobile,
    bool isTablet,
  ) {
    final fmt = ref.watch(numberFormatterProvider);

    return Column(
      children: [
        // Page Header
        if (!widget.embedded)
          BillDetailHeader(
            bill: bill,
            onClose: widget.onClose,
            onEdit: _canEdit(bill) ? () => _openEdit(bill) : null,
            onPrint: () => _printBill(bill),
            onCancel: _canCancel(bill) ? () => _cancelBill(bill) : null,
            onDelete: _canDelete(bill) ? () => _deleteBill(bill) : null,
            onRecordPayment: _canRecordPayment(bill) ? () => _recordPayment(bill) : null,
          ),

        // Tab Bar
        _buildTabBar(context, bill, colors, isMobile),

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
                    BillDetailSummary(bill: bill, fmt: fmt),
                    const SizedBox(height: 24),
                    BillDetailLines(bill: bill, fmt: fmt),
                  ],
                ),
              ),
              // Payments Tab
              BillDetailPayments(bill: bill, fmt: fmt),
              // Timeline Tab
              BillDetailTimeline(bill: bill),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    VendorBill bill,
    ApexColors colors,
    bool isMobile,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final hasPayments = bill.payments.isNotEmpty;

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
          Tab(text: hasPayments ? 'Payments (${bill.payments.length})' : 'Payments'),
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
            Text('Failed to load bill', style: textTheme.headlineSmall?.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error.toString(), style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ApexPrimaryButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: () => ref.invalidate(billDetailProvider(widget.billId)),
            ),
          ],
        ),
      ),
    );
  }

  bool _canEdit(VendorBill bill) => bill.status == BillStatus.draft;
  bool _canCancel(VendorBill bill) => bill.status == BillStatus.draft || bill.status == BillStatus.posted || bill.status == BillStatus.unpaid;
  bool _canDelete(VendorBill bill) => bill.status == BillStatus.draft;
  bool _canRecordPayment(VendorBill bill) =>
      bill.status != BillStatus.cancelled &&
      (bill.total - bill.amountPaid) > 0;

  Future<void> _openEdit(VendorBill bill) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BillFormScreen()),
    );
    if (result != null && mounted) {
      ref.invalidate(billDetailProvider(widget.billId));
      ref.invalidate(billsListProvider);
    }
  }

  Future<void> _printBill(VendorBill bill) async {
    try {
      await ref.read(downloadServiceProvider).downloadBillPdf(bill.id);
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Bill downloaded', type: SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Failed to download: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _cancelBill(VendorBill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Bill'),
        content: Text('Cancel bill ${bill.billNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).error),
            child: const Text('Cancel Bill'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await ref.read(vendorBillServiceProvider).cancel(bill.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(billDetailProvider(widget.billId));
          ref.invalidate(billsListProvider);
          ApexSnackBar.show(context: context, message: 'Bill cancelled', type: SnackBarType.success);
          if (widget.onClose != null) widget.onClose!();
        case Failure(:final error):
          ApexSnackBar.show(context: context, message: error.message, type: SnackBarType.error);
        default:
          break;
      }
    }
  }

  Future<void> _deleteBill(VendorBill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Permanently delete bill ${bill.billNumber}? This cannot be undone.'),
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
      final result = await ref.read(vendorBillServiceProvider).delete(bill.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(billsListProvider);
          ApexSnackBar.show(context: context, message: 'Bill deleted', type: SnackBarType.success);
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

  Future<void> _recordPayment(VendorBill bill) async {
    // TODO: Navigate to payment form with bill context
    if (mounted) {
      ApexSnackBar.show(context: context, message: 'Payment form not yet implemented', type: SnackBarType.info);
    }
  }
}

// ───── Providers ────────────────────────────────────────────────────────────

final billDetailProvider = FutureProvider.family<VendorBill, String>((ref, id) async {
  final service = ref.read(vendorBillServiceProvider);
  final result = await service.get(id);
  return result.getOrThrow();
});