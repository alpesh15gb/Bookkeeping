import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/eway_bill_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/einvoice/eway_bill_form_view.dart';

class EwayBillListView extends StatefulWidget {
  const EwayBillListView({super.key});

  @override
  State<EwayBillListView> createState() => _EwayBillListViewState();
}

class _EwayBillListViewState extends State<EwayBillListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EwayBillProvider>().fetchEwayBills();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final provider = context.watch<EwayBillProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EwayBillFormView())).then((_) => provider.fetchEwayBills()),
              child: const Icon(Icons.add),
            )
          : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'E-Way Bills'),
              Tab(text: 'E-Invoices'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEwayBillList(context, provider),
          _buildEinvoiceList(context),
        ],
      ),
    );
  }

  Widget _buildEwayBillList(BuildContext context, EwayBillProvider provider) {
    if (provider.isLoading && provider.ewayBills.isEmpty) {
      return const LoadingState(message: 'Loading e-way bills...');
    }

    return RefreshIndicator(
      onRefresh: () async => provider.fetchEwayBills(),
      child: provider.ewayBills.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'No E-Way Bills',
                  subtitle: 'E-way bills generated from finalized invoices will appear here',
                ),
              ],
            )
          : ListView.builder(
              padding: AppSpacing.pagePadding,
              itemCount: provider.ewayBills.length,
              itemBuilder: (context, i) {
                final ewb = provider.ewayBills[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: AppRadius.card,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.brandNavy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.local_shipping_outlined, size: 18, color: AppColors.brandNavy),
                    ),
                    title: Text(ewb['eway_bill_number'] ?? ewb['id'] ?? 'N/A', style: AppTextStyles.h3),
                    subtitle: Text(ewb['invoice_number'] ?? 'N/A', style: AppTextStyles.caption),
                    trailing: StatusBadge(label: ewb['status'] ?? 'PENDING'),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEinvoiceList(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'E-Invoices',
          subtitle: 'E-invoices generated via the GST portal from finalized invoices will appear here',
        ),
      ],
    );
  }
}
