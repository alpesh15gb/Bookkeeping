import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../design_system/design_system.dart';
import '../../providers/dashboard_provider.dart';
import 'widgets/action_required_card.dart';
import 'widgets/outstanding_collections_card.dart';
import 'widgets/cash_flow_card.dart';
import 'widgets/gst_status_card.dart';
import 'widgets/customers_followup_card.dart';
import 'widgets/recent_invoices_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().fetchDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final dashboard = context.watch<DashboardProvider>();

    return RefreshIndicator(
      onRefresh: () => context.read<DashboardProvider>().fetchDashboard(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiStrip(isMobile, dashboard),
            const SizedBox(height: AppSpacing.sectionGap),

            if (isMobile) ...[
              const ActionRequiredCard(),
              const SizedBox(height: AppSpacing.sectionGap),
              const OutstandingCollectionsCard(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 2, child: ActionRequiredCard()),
                  const SizedBox(width: AppSpacing.sectionGap),
                  const Expanded(flex: 3, child: OutstandingCollectionsCard()),
                ],
              ),
            const SizedBox(height: AppSpacing.sectionGap),

            if (isMobile) ...[
              const CashFlowCard(),
              const SizedBox(height: AppSpacing.sectionGap),
              const GstStatusCard(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: CashFlowCard()),
                  const SizedBox(width: AppSpacing.sectionGap),
                  const Expanded(child: GstStatusCard()),
                ],
              ),
            const SizedBox(height: AppSpacing.sectionGap),

            if (isMobile) ...[
              const CustomersFollowupCard(),
              const SizedBox(height: AppSpacing.sectionGap),
              const RecentInvoicesCard(),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(flex: 2, child: CustomersFollowupCard()),
                  const SizedBox(width: AppSpacing.sectionGap),
                  const Expanded(flex: 3, child: RecentInvoicesCard()),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiStrip(bool isMobile, DashboardProvider dashboard) {
    if (dashboard.isLoading && dashboard.metrics.isEmpty) {
      return Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 3 ? AppSpacing.kpiGap : 0),
              child: const AppLoadingSkeleton(width: double.infinity, height: 80),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: AppKpiCard(
            icon: Icons.account_balance_wallet,
            label: 'RECEIVABLES',
            value: '₹${_formatAmount(dashboard.receivables)}',
            iconColor: AppColors.success,
          ),
        ),
        if (!isMobile) const SizedBox(width: AppSpacing.kpiGap),
        if (isMobile) const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppKpiCard(
            icon: Icons.trending_down,
            label: 'PAYABLES',
            value: '₹${_formatAmount(dashboard.payables)}',
            iconColor: AppColors.warning,
          ),
        ),
        if (!isMobile) const SizedBox(width: AppSpacing.kpiGap),
        if (isMobile) const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppKpiCard(
            icon: Icons.trending_up,
            label: 'REVENUE',
            value: '₹${_formatAmount(dashboard.revenue)}',
            iconColor: AppColors.primary,
          ),
        ),
        if (!isMobile) const SizedBox(width: AppSpacing.kpiGap),
        if (isMobile) const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppKpiCard(
            icon: Icons.account_balance,
            label: 'NET PROFIT',
            value: '₹${_formatAmount(dashboard.netProfit)}',
            iconColor: dashboard.netProfit >= 0 ? AppColors.success : AppColors.error,
          ),
        ),
      ],
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 10000000) return '${(amount / 10000000).toStringAsFixed(1)}Cr';
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }
}
