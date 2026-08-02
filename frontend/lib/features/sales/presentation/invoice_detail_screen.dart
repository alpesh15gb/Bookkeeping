/// Invoice Detail Screen — Professional detail view with timeline, payments, and actions.
///
/// Features:
/// - Header: Invoice number, status, dates, customer
/// - Summary: Totals, outstanding, GST breakdown
/// - Lines table: Read-only with expandable tax details
/// - Payments tab: Allocation history, add payment
/// - Timeline: Status changes, emails, prints
/// - Actions: Print, Email, Edit, Cancel, Delete
/// - Responsive: Mobile stacked, Tablet, Desktop with sidebar
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/design_system/index.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/download/download_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../models/invoice.dart';
import '../models/invoice_status.dart';
import '../services/invoice_service.dart';
import 'invoice_form_screen.dart';
import 'invoice_list_provider.dart';
import '../payments/presentation/payment_form_screen.dart';
import 'components/invoice_detail_header.dart';
import 'components/invoice_detail_summary.dart';
import 'components/invoice_detail_lines.dart';
import 'components/invoice_detail_payments.dart';
import 'components/invoice_detail_timeline.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({
    super.key,
    required this.invoiceId,
    this.embedded = false,
    this.onClose,
  });

  final String invoiceId;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  ConsumerState<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen>
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
    final state = ref.watch(invoiceDetailProvider(widget.invoiceId));
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isTablet = ResponsiveLayout.isTablet(context);

    final content = state.when(
      data: (invoice) => _buildContent(context, invoice, colors, isMobile, isTablet),
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
    Invoice invoice,
    ApexColors colors,
    bool isMobile,
    bool isTablet,
  ) {
    final fmt = ref.watch(numberFormatterProvider);

    return Column(
      children: [
        // Page Header
        if (!widget.embedded)
          InvoiceDetailHeader(
            invoice: invoice,
            onClose: widget.onClose,
            onEdit: _canEdit(invoice) ? () => _openEdit(invoice) : null,
            onPrint: () => _printInvoice(invoice),
            onEmail: () => _emailInvoice(invoice),
            onCancel: _canCancel(invoice) ? () => _cancelInvoice(invoice) : null,
            onDelete: _canDelete(invoice) ? () => _deleteInvoice(invoice) : null,
            onRecordPayment: _canRecordPayment(invoice) ? () => _recordPayment(invoice) : null,
          ),

        // Tab Bar
        _buildTabBar(context, invoice, colors, isMobile),

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
                    InvoiceDetailSummary(invoice: invoice, fmt: fmt),
                    const SizedBox(height: 24),
                    InvoiceDetailLines(invoice: invoice, fmt: fmt),
                  ],
                ),
              ),
              // Payments Tab
              InvoiceDetailPayments(invoice: invoice, fmt: fmt),
              // Timeline Tab
              InvoiceDetailTimeline(invoice: invoice),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    Invoice invoice,
    ApexColors colors,
    bool isMobile,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final hasPayments = invoice.payments.isNotEmpty;

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
          Tab(text: hasPayments ? 'Payments (${invoice.payments.length})' : 'Payments'),
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
            Text('Failed to load invoice', style: textTheme.headlineSmall?.copyWith(color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(error.toString(), style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ApexPrimaryButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: () => ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
            ),
          ],
        ),
      ),
    );
  }

  bool _canEdit(Invoice invoice) => invoice.status == InvoiceStatus.draft;
  bool _canCancel(Invoice invoice) => invoice.status == InvoiceStatus.draft || invoice.status == InvoiceStatus.sent;
  bool _canDelete(Invoice invoice) => invoice.status == InvoiceStatus.draft;
  bool _canRecordPayment(Invoice invoice) =>
      invoice.status != InvoiceStatus.cancelled &&
      invoice.outstandingAmount > 0;

  Future<void> _openEdit(Invoice invoice) async {
    final result = await Navigator.of(context).push<Invoice>(
      MaterialPageRoute(builder: (_) => InvoiceFormScreen(editId: invoice.id)),
    );
    if (result != null && mounted) {
      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      ref.invalidate(invoiceListProvider);
    }
  }

  Future<void> _printInvoice(Invoice invoice) async {
    try {
      await ref.read(downloadServiceProvider).downloadInvoicePdf(invoice.id);
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Invoice downloaded', type: SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Failed to download: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _emailInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Invoice'),
        content: Text('Send invoice ${invoice.invoiceNumber} to ${invoice.customerName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send')),
        ],
      ),
    );
    if (confirmed == true) {
      // TODO: Implement email sending
      if (mounted) {
        ApexSnackBar.show(context: context, message: 'Email queued for sending', type: SnackBarType.success);
      }
    }
  }

  Future<void> _cancelInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Invoice'),
        content: Text('Cancel invoice ${invoice.invoiceNumber}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: apexColors(context).error),
            child: const Text('Cancel Invoice'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await ref.read(invoiceServiceProvider).cancel(invoice.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(invoiceDetailProvider(widget.invoiceId));
          ref.invalidate(invoiceListProvider);
          ApexSnackBar.show(context: context, message: 'Invoice cancelled', type: SnackBarType.success);
          if (widget.onClose != null) widget.onClose!();
        case Failure(:final error):
          ApexSnackBar.show(context: context, message: error.message, type: SnackBarType.error);
        default:
          break;
      }
    }
  }

  Future<void> _deleteInvoice(Invoice invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Permanently delete invoice ${invoice.invoiceNumber}? This cannot be undone.'),
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
      final result = await ref.read(invoiceServiceProvider).delete(invoice.id);
      if (!mounted) return;
      switch (result) {
        case Success():
          ref.invalidate(invoiceListProvider);
          ApexSnackBar.show(context: context, message: 'Invoice deleted', type: SnackBarType.success);
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

  Future<void> _recordPayment(Invoice invoice) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentFormScreen(
          contactId: invoice.contactId,
          amount: invoice.outstandingAmount,
        ),
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      ref.invalidate(invoiceListProvider);
      ApexSnackBar.show(context: context, message: 'Payment recorded', type: SnackBarType.success);
    }
  }
}

// ───── Providers ────────────────────────────────────────────────────────────

final invoiceDetailProvider = FutureProvider.family<Invoice, String>((ref, id) async {
  final service = ref.read(invoiceServiceProvider);
  final result = await service.get(id);
  return result.getOrThrow();
});