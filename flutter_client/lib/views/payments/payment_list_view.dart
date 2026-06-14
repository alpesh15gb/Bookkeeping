import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/payment_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart' hide AppCard;
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';

class PaymentListView extends StatefulWidget {
  const PaymentListView({super.key});

  @override
  State<PaymentListView> createState() => _PaymentListViewState();
}

class _PaymentListViewState extends State<PaymentListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch() {
    context.read<PaymentProvider>().fetchReceipts();
    context.read<PaymentProvider>().fetchDisbursements();
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

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(_tabController.index == 0 ? 'receipt' : 'disbursement'),
        backgroundColor: AppColors.goldAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
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
                ? const LoadingState(message: 'Loading payments...')
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildReceiptsTab(provider),
                      _buildDisbursementsTab(provider),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptsTab(PaymentProvider provider) {
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: _fetch);
    }

    final allReceipts = provider.receipts;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allReceipts
        : allReceipts.where((r) {
            final name = (r.contactName ?? '').toString().toLowerCase();
            final ref = (r.referenceNumber ?? '').toString().toLowerCase();
            return name.contains(query) || ref.contains(query);
          }).toList();

    num totalAmount = 0;
    for (final r in allReceipts) {
      if (r.status != 'CANCELLED') totalAmount += r.amount;
    }

    final items = filtered.map((r) {
      return DocumentItemData(
        id: r.id,
        docNumber: r.contactName ?? 'Guest Customer',
        partyName: r.paymentMode.replaceAll('_', ' ').toUpperCase(),
        date: r.paymentDate,
        amount: r.amount,
        status: r.status,
        balanceLabel: 'Ref',
        balanceAmount: 0,
      );
    }).toList();

    return DocumentListView(
      title: 'Receipts',
      searchController: _searchCtrl,
      searchHint: 'Search receipts...',
      onSearchChanged: (_) => setState(() {}),
      filterTabs: const [],
      activeFilter: '',
      onFilterChanged: (_) {},
      summary: ListSummaryData(totalAmount: totalAmount.toDouble()),
      items: items,
      isLoading: false,
      onRefresh: () async => _fetch(),
      emptyTitle: 'No receipts yet',
      emptySubtitle: 'Customer payment receipts will appear here',
      emptyIcon: Icons.payments_outlined,
      detailBuilder: (ctx, item) => const SizedBox(),
      itemBuilder: (context, item, index) {
        final r = filtered[index];
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
                  Text(AppDate.format(r.paymentDate), style: AppTextStyles.bodySmall),
                  const SizedBox(width: 8),
                  Text('•  ${r.paymentMode.replaceAll('_', ' ')}', style: AppTextStyles.bodySmall),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AmountFormat.format(r.amount), style: AppTextStyles.amount),
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

  Widget _buildDisbursementsTab(PaymentProvider provider) {
    if (provider.errorMessage != null) {
      return ErrorState(message: provider.errorMessage!, onRetry: _fetch);
    }

    final allDisbursements = provider.disbursements;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allDisbursements
        : allDisbursements.where((d) {
            final name = (d.vendorName ?? '').toString().toLowerCase();
            final ref = (d.referenceNumber ?? '').toString().toLowerCase();
            return name.contains(query) || ref.contains(query);
          }).toList();

    num totalAmount = 0;
    for (final d in allDisbursements) {
      if (d.status != 'CANCELLED') totalAmount += d.amount;
    }

    final items = filtered.map((d) {
      return DocumentItemData(
        id: d.id,
        docNumber: d.vendorName ?? 'Guest Vendor',
        partyName: d.paymentMode.replaceAll('_', ' ').toUpperCase(),
        date: d.paymentDate,
        amount: d.amount,
        status: d.status,
      );
    }).toList();

    return DocumentListView(
      title: 'Disbursements',
      searchController: _searchCtrl,
      searchHint: 'Search disbursements...',
      onSearchChanged: (_) => setState(() {}),
      filterTabs: const [],
      activeFilter: '',
      onFilterChanged: (_) {},
      summary: ListSummaryData(totalAmount: totalAmount.toDouble()),
      items: items,
      isLoading: false,
      onRefresh: () async => _fetch(),
      emptyTitle: 'No disbursements yet',
      emptySubtitle: 'Vendor payment disbursements will appear here',
      emptyIcon: Icons.money_off_outlined,
      detailBuilder: (ctx, item) => const SizedBox(),
      itemBuilder: (context, item, index) {
        final d = filtered[index];
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
                  Text(AppDate.format(d.paymentDate), style: AppTextStyles.bodySmall),
                  const SizedBox(width: 8),
                  Text('•  ${d.paymentMode.replaceAll('_', ' ')}', style: AppTextStyles.bodySmall),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(AmountFormat.format(d.amount), style: AppTextStyles.amount),
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
}
