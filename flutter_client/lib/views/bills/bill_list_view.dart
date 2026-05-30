import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/bills/bill_detail_view.dart';

class BillListView extends StatefulWidget {
  const BillListView({super.key});

  @override
  State<BillListView> createState() => _BillListViewState();
}

class _BillListViewState extends State<BillListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BillProvider>().fetchBills();
    });
  }

  void _showForm({BillModel? bill}) async {
    BillModel? fullBill = bill;
    if (bill != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      fullBill = await context.read<BillProvider>().fetchBillDetail(bill.id);
      if (mounted) Navigator.pop(context);
      if (fullBill == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load bill details'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BillFormView(editBill: fullBill)),
      ).then((_) => context.read<BillProvider>().fetchBills());
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillDetailView(billId: id)),
    ).then((_) => context.read<BillProvider>().fetchBills());
  }

  Future<void> _cancelBill(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Bill?', message: 'Cancel this vendor bill?');
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      final success = await provider.cancelBill(id);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final billProvider = context.watch<BillProvider>();

    if (billProvider.isLoading && billProvider.bills.isEmpty) {
      return const LoadingState(message: 'Loading vendor bills...');
    }
    if (billProvider.errorMessage != null && billProvider.bills.isEmpty) {
      return ErrorState(
        message: billProvider.errorMessage!,
        onRetry: () => context.read<BillProvider>().fetchBills(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: billProvider.bills.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No vendor bills yet',
              subtitle: 'Vendor bills will appear here once added',
              actionLabel: 'Add Bill',
              onAction: () => _showForm(),
            )
          : ListView.separated(
              padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
              itemCount: billProvider.bills.length,
              separatorBuilder: (context, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final bill = billProvider.bills[i];
                return AppCard(
                  onTap: () => _showDetail(bill.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(bill.billNumber, style: AppTextStyles.h3)),
                          StatusBadge(label: bill.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person_outlined, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(bill.contact?.name ?? 'N/A', style: AppTextStyles.bodySmall),
                          const SizedBox(width: 16),
                          Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(bill.billDate, style: AppTextStyles.caption),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₹${bill.total.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _showDetail(bill.id),
                                icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                                label: const Text('View'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  textStyle: AppTextStyles.buttonSmall,
                                  side: const BorderSide(color: AppColors.borderInput),
                                ),
                              ),
                              if (bill.status == 'DRAFT') ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _showForm(bill: bill),
                                  icon: const Icon(Icons.edit_outlined, size: 14),
                                  label: const Text('Edit'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    textStyle: AppTextStyles.buttonSmall,
                                    side: const BorderSide(color: AppColors.borderInput),
                                  ),
                                ),
                              ],
                              if (bill.status != 'CANCELLED') ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _cancelBill(bill.id),
                                  icon: const Icon(Icons.cancel_outlined, size: 14),
                                  label: const Text('Cancel'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    textStyle: AppTextStyles.buttonSmall,
                                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
