import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/sales_analytics_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class SalesAnalyticsView extends StatefulWidget {
  const SalesAnalyticsView({super.key});

  @override
  State<SalesAnalyticsView> createState() => _SalesAnalyticsViewState();
}

class _SalesAnalyticsViewState extends State<SalesAnalyticsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesAnalyticsProvider>().fetchAll();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesAnalyticsProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Customer-Wise'),
              Tab(text: 'Period-Wise'),
              Tab(text: 'Transactions'),
            ],
          ),
        ),
      ),
      body: provider.isLoading
          ? const LoadingState(message: 'Loading sales analytics...')
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(provider.customerWise, 'customer_name', 'total_sales'),
                _buildList(provider.periodWise, 'period', 'total_sales'),
                _buildList(provider.transactions, 'invoice_number', 'total'),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> items, String titleKey, String amountKey) {
    if (items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'No Data',
            subtitle: 'Sales data will appear here as transactions are posted',
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async => context.read<SalesAnalyticsProvider>().fetchAll(),
      child: ListView.builder(
        padding: AppSpacing.pagePadding,
        itemCount: items.length,
        itemBuilder: (context, i) {
          final item = items[i];
          final amount = double.tryParse((item[amountKey] ?? 0).toString()) ?? 0.0;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.border),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Text('${item[titleKey] ?? 'N/A'}', style: AppTextStyles.h3),
              trailing: Text('₹${amount.toStringAsFixed(2)}', style: AppTextStyles.numeric),
            ),
          );
        },
      ),
    );
  }
}
