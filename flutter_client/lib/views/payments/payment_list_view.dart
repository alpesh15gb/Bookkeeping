import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/payment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';

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
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  Future<void> _cancelDisbursement(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Disbursement?', message: 'Cancel this payment disbursement?');
    if (confirm == true) {
      final provider = context.read<PaymentProvider>();
      final success = await provider.cancelDisbursement(id);
      if (!success && mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PaymentProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          if (!isMobile)
            AppCommandBar(
              title: 'Payments & Transactions',
              actions: [
                AppButton(
                  label: _tabController.index == 0 ? 'Record Receipt' : 'Record Disbursement',
                  icon: Icons.add,
                  isPrimary: true,
                  onTap: () => _showForm(_tabController.index == 0 ? 'receipt' : 'disbursement'),
                ),
              ],
            ),
          Container(
            color: AppColors.bgSurface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.brandNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.goldAccent,
              indicatorWeight: 3,
              labelStyle: AppTextStyles.tabLabel.copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: AppTextStyles.tabLabel,
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(text: 'RECEIPTS (IN)'),
                Tab(text: 'DISBURSEMENTS (OUT)'),
              ],
            ),
          ),
          Expanded(
            child: provider.isLoading
                ? ListSkeleton()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildReceiptsList(provider, isMobile),
                      _buildDisbursementsList(provider, isMobile),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showForm(_tabController.index == 0 ? 'receipt' : 'disbursement'),
              backgroundColor: AppColors.goldAccent,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildReceiptsList(PaymentProvider provider, bool isMobile) {
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: _fetch);
    }
    if (provider.receipts.isEmpty) {
      return AppEmptyState(
        icon: Icons.payments_outlined,
        title: 'No receipts yet',
        subtitle: 'Customer payment receipts will appear here',
        actionLabel: 'Record Receipt',
        onAction: () => _showForm('receipt'),
      );
    }

    num totalAmount = 0;
    for (final r in provider.receipts) {
      if (r.status != 'CANCELLED') {
        totalAmount += r.amount;
      }
    }

    if (isMobile) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: provider.receipts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final r = provider.receipts[i];
          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        r.contactName ?? 'Guest Customer',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                    AppInlineStatus(status: r.status),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      AppDate.format(r.paymentDate),
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•  ${r.paymentMode.replaceAll('_', ' ')}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AmountFormat.format(r.amount),
                      style: AppTextStyles.amount,
                    ),
                    if (r.status != 'CANCELLED')
                      AppButton(
                        label: 'Cancel',
                        icon: Icons.cancel_outlined,
                        color: AppColors.error,
                        onTap: () => _cancelReceipt(r.id),
                        isSmall: true,
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppColors.bgSurface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('DATE', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 4, child: Text('CUSTOMER', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 2, child: Text('METHOD', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 3, child: Text('REFERENCE', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 3, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text('STATUS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                    SizedBox(width: 100, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: provider.receipts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                  itemBuilder: (context, index) {
                    final r = provider.receipts[index];
                    final contactName = r.contactName ?? 'Guest Customer';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              AppDate.format(r.paymentDate),
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Row(
                              children: [
                                AppAvatar(name: contactName, size: 24),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    contactName,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brandNavy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              r.paymentMode.replaceAll('_', ' ').toUpperCase(),
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              r.referenceNumber ?? '--',
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              AmountFormat.format(r.amount),
                              style: AppTextStyles.amount,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: AppInlineStatus(status: r.status),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: r.status != 'CANCELLED'
                                ? Center(
                                    child: AppButton(
                                      label: 'Cancel',
                                      icon: Icons.cancel_outlined,
                                      color: AppColors.error,
                                      onTap: () => _cancelReceipt(r.id),
                                      isSmall: true,
                                    ),
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        AppStickyBottomBar(
          children: [
            Text(
              'Active Receipts Total',
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              AmountFormat.format(totalAmount),
              style: AppTextStyles.h2.copyWith(color: AppColors.success),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDisbursementsList(PaymentProvider provider, bool isMobile) {
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: _fetch);
    }
    if (provider.disbursements.isEmpty) {
      return AppEmptyState(
        icon: Icons.money_off_outlined,
        title: 'No disbursements yet',
        subtitle: 'Vendor payment disbursements will appear here',
        actionLabel: 'Record Disbursement',
        onAction: () => _showForm('disbursement'),
      );
    }

    num totalAmount = 0;
    for (final d in provider.disbursements) {
      if (d.status != 'CANCELLED') {
        totalAmount += d.amount;
      }
    }

    if (isMobile) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: provider.disbursements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, i) {
          final d = provider.disbursements[i];
          return AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        d.vendorName ?? 'Guest Vendor',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                    AppInlineStatus(status: d.status),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      AppDate.format(d.paymentDate),
                      style: AppTextStyles.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•  ${d.paymentMode.replaceAll('_', ' ')}',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AmountFormat.format(d.amount),
                      style: AppTextStyles.amount,
                    ),
                    if (d.status != 'CANCELLED')
                      AppButton(
                        label: 'Cancel',
                        icon: Icons.cancel_outlined,
                        color: AppColors.error,
                        onTap: () => _cancelDisbursement(d.id),
                        isSmall: true,
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: const BoxDecoration(
                  color: AppColors.bgSurface,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: const Row(
                  children: [
                    Expanded(flex: 2, child: Text('DATE', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 4, child: Text('VENDOR', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 2, child: Text('METHOD', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 3, child: Text('REFERENCE', style: AppTextStyles.labelSmall)),
                    Expanded(flex: 3, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text('STATUS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                    SizedBox(width: 100, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: provider.disbursements.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                  itemBuilder: (context, index) {
                    final d = provider.disbursements[index];
                    final vendorName = d.vendorName ?? 'Guest Vendor';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              AppDate.format(d.paymentDate),
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Row(
                              children: [
                                AppAvatar(name: vendorName, size: 24),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    vendorName,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brandNavy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              d.paymentMode.replaceAll('_', ' ').toUpperCase(),
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              d.referenceNumber ?? '--',
                              style: AppTextStyles.bodySmall,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              AmountFormat.format(d.amount),
                              style: AppTextStyles.amount,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Center(
                              child: AppInlineStatus(status: d.status),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: d.status != 'CANCELLED'
                                ? Center(
                                    child: AppButton(
                                      label: 'Cancel',
                                      icon: Icons.cancel_outlined,
                                      color: AppColors.error,
                                      onTap: () => _cancelDisbursement(d.id),
                                      isSmall: true,
                                    ),
                                  )
                                : const SizedBox(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        AppStickyBottomBar(
          children: [
            Text(
              'Active Disbursements Total',
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              AmountFormat.format(totalAmount),
              style: AppTextStyles.h2.copyWith(color: AppColors.error),
            ),
          ],
        ),
      ],
    );
  }
}
