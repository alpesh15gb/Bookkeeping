import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/delivery_challan_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' hide AppCard, AppEmptyState;
import 'package:flutter_client/views/shared/design_system.dart';
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

  void _showForm() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeliveryChallanFormView()),
    ).then((_) => context.read<DeliveryChallanProvider>().fetchChallans());
  }

  void _showDetail(dynamic dc) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeliveryChallanDetailView(challanId: dc['id'])),
    ).then((_) => context.read<DeliveryChallanProvider>().fetchChallans());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    if (provider.isLoading && provider.challans.isEmpty) {
      return const LoadingState(message: 'Loading delivery challans...');
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: _showForm,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text('Delivery Challans', style: AppTextStyles.h2),
                  const Spacer(),
                  AppButton(
                    label: 'New Challan',
                    icon: Icons.add,
                    isPrimary: true,
                    isSmall: true,
                    onTap: _showForm,
                  ),
                ],
              ),
            ),
          if (provider.challans.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
              child: HeroSummaryCard(
                title: 'Total Challans',
                amount: provider.challans.length,
                subtitle: '${provider.challans.where((c) => c['status'] == 'DELIVERED').length} delivered',
                icon: Icons.local_shipping_rounded,
              ),
            ),
          Expanded(
            child: provider.challans.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      AppEmptyState(
                        icon: Icons.local_shipping_rounded,
                        title: 'No Delivery Challans',
                        subtitle: 'Create delivery challans for goods dispatched from finalized sales orders',
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: () async => provider.fetchChallans(),
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                        left: isMobile ? 12 : 20,
                        right: isMobile ? 12 : 20,
                        top: 8,
                        bottom: isMobile ? 80 : 20,
                      ),
                      itemCount: provider.challans.length,
                      itemBuilder: (context, i) {
                        final dc = provider.challans[i];
                        return AppListTile(
                          leadingText: dc['challan_number']?.toString() ?? 'N/A',
                          title: dc['customer_name']?.toString() ?? dc['contact_name']?.toString() ?? '',
                          subtitle: dc['status']?.toString() ?? 'DRAFT',
                          badge: StatusBadge(label: dc['status']?.toString() ?? 'DRAFT'),
                          onTap: () => _showDetail(dc),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
