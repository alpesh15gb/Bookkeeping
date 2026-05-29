import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/payment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';

class PaymentListView extends StatefulWidget {
  const PaymentListView({super.key});

  @override
  State<PaymentListView> createState() => _PaymentListViewState();
}

class _PaymentListViewState extends State<PaymentListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  void _fetch() {
    context.read<PaymentProvider>().fetchReceipts();
    context.read<PaymentProvider>().fetchDisbursements();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showForm(String mode) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
        child: PaymentFormView(
          mode: mode,
          onSuccess: () {
            Navigator.of(ctx).pop();
            _fetch();
          },
        ),
      ),
    );
  }

  Future<void> _cancelReceipt(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Receipt?', message: 'Cancel this payment receipt?');
    if (confirm == true) {
      final provider = context.read<PaymentProvider>();
      final success = await provider.cancelReceipt(id);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _cancelDisbursement(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Disbursement?', message: 'Cancel this payment disbursement?');
    if (confirm == true) {
      final provider = context.read<PaymentProvider>();
      final success = await provider.cancelDisbursement(id);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PaymentProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Receipts'),
              Tab(text: 'Disbursements'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _showForm(_tabController.index == 0 ? 'receipt' : 'disbursement'),
        backgroundColor: AppColors.goldAccent,
        foregroundColor: AppColors.textWhite,
        child: const Icon(Icons.add, size: 20),
      ),
      body: provider.isLoading
          ? const LoadingState(message: 'Loading payments...')
          : TabBarView(
              controller: _tabController,
              children: [
                _buildReceiptsList(provider, isMobile),
                _buildDisbursementsList(provider, isMobile),
              ],
            ),
    );
  }

  Widget _buildReceiptsList(PaymentProvider provider, bool isMobile) {
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: _fetch);
    }
    if (provider.receipts.isEmpty) {
      return EmptyState(
        icon: Icons.payments_outlined,
        title: 'No receipts yet',
        subtitle: 'Customer payments will appear here',
      );
    }
    return ListView.separated(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: provider.receipts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final r = provider.receipts[i];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(r.contactName ?? 'Receipt', style: AppTextStyles.h3)),
                  StatusBadge(label: r.status),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(r.paymentDate, style: AppTextStyles.caption),
                  const SizedBox(width: 16),
                  Icon(Icons.account_balance_outlined, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(r.paymentMode.replaceAll('_', ' '), style: AppTextStyles.caption),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('₹${r.amount.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                  Row(
                    children: [
                      if (r.referenceNumber != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(r.referenceNumber!, style: AppTextStyles.caption),
                        ),
                      if (r.status != 'CANCELLED')
                        OutlinedButton.icon(
                          onPressed: () => _cancelReceipt(r.id),
                          icon: const Icon(Icons.cancel_outlined, size: 14),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: AppTextStyles.buttonSmall,
                            side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisbursementsList(PaymentProvider provider, bool isMobile) {
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: _fetch);
    }
    if (provider.disbursements.isEmpty) {
      return EmptyState(
        icon: Icons.money_off_outlined,
        title: 'No disbursements yet',
        subtitle: 'Vendor payments will appear here',
      );
    }
    return ListView.separated(
      padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
      itemCount: provider.disbursements.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final d = provider.disbursements[i];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(d.vendorName ?? 'Disbursement', style: AppTextStyles.h3)),
                  StatusBadge(label: d.status),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(d.paymentDate, style: AppTextStyles.caption),
                  const SizedBox(width: 16),
                  Icon(Icons.account_balance_outlined, size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text(d.paymentMode.replaceAll('_', ' '), style: AppTextStyles.caption),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('₹${d.amount.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                  Row(
                    children: [
                      if (d.referenceNumber != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(d.referenceNumber!, style: AppTextStyles.caption),
                        ),
                      if (d.status != 'CANCELLED')
                        OutlinedButton.icon(
                          onPressed: () => _cancelDisbursement(d.id),
                          icon: const Icon(Icons.cancel_outlined, size: 14),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            textStyle: AppTextStyles.buttonSmall,
                            side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
