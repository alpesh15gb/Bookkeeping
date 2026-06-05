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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EwayBillProvider>().fetchEwayBills();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showForm() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EwayBillFormView()),
    ).then((_) => context.read<EwayBillProvider>().fetchEwayBills());
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final provider = context.watch<EwayBillProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: _tabController.index == 0 && isMobile
          ? FloatingActionButton(
              onPressed: _showForm,
              child: const Icon(Icons.add),
            )
          : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'E-Way Bills'),
                    Tab(text: 'E-Invoices'),
                  ],
                ),
              ),
              if (!isMobile && _tabController.index == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child:                     ElevatedButton.icon(
                    onPressed: _showForm,
                    icon: const Icon(Icons.add, size: 16, color: AppColors.textWhite),
                    label: const Text('New E-Way Bill', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandNavy,
                      foregroundColor: AppColors.textWhite,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEwayBillList(context, provider, isMobile),
          _buildEinvoiceList(context),
        ],
      ),
    );
  }

  Widget _buildEwayBillList(BuildContext context, EwayBillProvider provider, bool isMobile) {
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
          : ListView.separated(
              padding: EdgeInsets.only(
                left: isMobile ? 12 : 20,
                right: isMobile ? 12 : 20,
                top: 8,
                bottom: isMobile ? 80 : 20,
              ),
              itemCount: provider.ewayBills.length,
              separatorBuilder: (context, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final ewb = provider.ewayBills[i];
                return CompactDocumentCard(
                  docNumber: ewb['eway_bill_number'] ?? ewb['id']?.toString() ?? 'N/A',
                  partyName: ewb['invoice_number'] ?? '',
                  amount: 0,
                  status: ewb['status'] ?? 'PENDING',
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
