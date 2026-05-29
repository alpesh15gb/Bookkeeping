import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/reports/trial_balance_view.dart';
import 'package:flutter_client/views/reports/balance_sheet_view.dart';
import 'package:flutter_client/views/reports/profit_loss_view.dart';
import 'package:flutter_client/views/reports/gst_returns_view.dart';
import 'package:flutter_client/views/reports/aging_report_view.dart';

class ReportListView extends StatefulWidget {
  const ReportListView({super.key});

  @override
  State<ReportListView> createState() => _ReportListViewState();
}

class _ReportListViewState extends State<ReportListView> {
  final _reports = [
    {'icon': Icons.summarize_outlined, 'title': 'Trial Balance', 'subtitle': 'Sum of all account balances', 'view': const TrialBalanceView()},
    {'icon': Icons.account_balance_outlined, 'title': 'Balance Sheet', 'subtitle': 'Assets, liabilities & equity', 'view': const BalanceSheetView()},
    {'icon': Icons.trending_up_outlined, 'title': 'Profit & Loss', 'subtitle': 'Revenue and expenses', 'view': const ProfitLossView()},
    {'icon': Icons.receipt_long_outlined, 'title': 'GST Returns', 'subtitle': 'GSTR-1, GSTR-3B & more', 'view': const GstReturnsView()},
    {'icon': Icons.bar_chart_outlined, 'title': 'Aging Report', 'subtitle': 'Outstanding receivables/payables', 'view': const AgingReportView()},
    {'icon': Icons.description_outlined, 'title': 'Day Book', 'subtitle': 'All transactions for a day', 'view': null},
  ];

  void _onReportTap(Map<String, dynamic> r) {
    if (r['view'] == null) {
      // Day Book (Not yet implemented on backend)
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Day Book Report'),
          content: const Text('The Day Book report is currently not implemented on the backend API. Please check back later.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => r['view'] as Widget),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: Center(child: Text('Reports', style: AppTextStyles.h3)),
        ),
      ),
      body: ListView.separated(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = _reports[i];
          return AppCard(
            onTap: () => _onReportTap(r),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(r['icon'] as IconData, color: AppColors.brandNavy, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['title'] as String, style: AppTextStyles.h3),
                      const SizedBox(height: 2),
                      Text(r['subtitle'] as String, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}
