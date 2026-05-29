import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_form_view.dart';
import 'package:flutter_client/views/delivery_challans/delivery_challan_detail_view.dart';

class DeliveryChallanListView extends StatefulWidget {
  const DeliveryChallanListView({super.key});

  @override
  State<DeliveryChallanListView> createState() => _DeliveryChallanListViewState();
}

class _DeliveryChallanListViewState extends State<DeliveryChallanListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeliveryChallanProvider>().fetchChallans();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();

    if (provider.isLoading && provider.challans.isEmpty) {
      return const LoadingState(message: 'Loading delivery challans...');
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeliveryChallanFormView())).then((_) => provider.fetchChallans()),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => provider.fetchChallans(),
        child: provider.challans.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.local_shipping_rounded,
                    title: 'No Delivery Challans',
                    subtitle: 'Create delivery challans for goods dispatched from finalized sales orders',
                  ),
                ],
              )
            : ListView.builder(
                padding: AppSpacing.pagePadding,
                itemCount: provider.challans.length,
                itemBuilder: (context, i) {
                  final dc = provider.challans[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: AppRadius.card,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DeliveryChallanDetailView(challanId: dc['id']))).then((_) => provider.fetchChallans()),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE57C00).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_shipping_rounded, size: 18, color: Color(0xFFE57C00)),
                      ),
                      title: Text(dc['challan_number'] ?? 'N/A', style: AppTextStyles.h3),
                      subtitle: Text(dc['customer_name'] ?? dc['contact_name'] ?? '', style: AppTextStyles.caption),
                      trailing: StatusBadge(label: dc['status'] ?? 'DRAFT'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
