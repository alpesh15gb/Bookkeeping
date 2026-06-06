import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/reports/trial_balance_view.dart';
import 'package:flutter_client/views/reports/balance_sheet_view.dart';
import 'package:flutter_client/views/reports/profit_loss_view.dart';
import 'package:flutter_client/views/reports/gst_returns_view.dart';
import 'package:flutter_client/views/reports/aging_report_view.dart';
import 'package:flutter_client/views/reports/party_statement_view.dart';
import 'package:flutter_client/views/reports/cash_flow_view.dart';
import 'package:flutter_client/views/reports/outstanding_view.dart';

class ReportListView extends StatefulWidget {
  const ReportListView({super.key});

  @override
  State<ReportListView> createState() => _ReportListViewState();
}

class _ReportListViewState extends State<ReportListView> {
  final _transactionReports = [
    {'icon': Icons.summarize_outlined, 'title': 'Trial Balance', 'subtitle': 'Sum of all account balances', 'view': const TrialBalanceView()},
    {'icon': Icons.account_balance_outlined, 'title': 'Balance Sheet', 'subtitle': 'Assets, liabilities & equity', 'view': const BalanceSheetView()},
    {'icon': Icons.trending_up_outlined, 'title': 'Profit & Loss', 'subtitle': 'Revenue and expenses', 'view': const ProfitLossView()},
    {'icon': Icons.account_balance_wallet_outlined, 'title': 'Cash Flow', 'subtitle': 'Operating, investing & financing flows', 'view': const CashFlowView()},
    {'icon': Icons.description_outlined, 'title': 'Day Book', 'subtitle': 'All transactions for a day', 'view': null},
  ];

  final _complianceReports = [
    {'icon': Icons.receipt_long_outlined, 'title': 'GST Returns', 'subtitle': 'GSTR-1, GSTR-3B & more', 'view': const GstReturnsView()},
  ];

  final _partyReports = [
    {'icon': Icons.bar_chart_outlined, 'title': 'Aging Report', 'subtitle': 'Outstanding receivables/payables', 'view': const AgingReportView()},
    {'icon': Icons.receipt_long_outlined, 'title': 'Party Statement', 'subtitle': 'Ledger & summary for a specific party', 'view': const PartyStatementView()},
    {'icon': Icons.arrow_circle_up_outlined, 'title': 'Outstanding Receivables', 'subtitle': 'Who owes you money', 'view': const OutstandingReceivablesView()},
    {'icon': Icons.arrow_circle_down_outlined, 'title': 'Outstanding Payables', 'subtitle': 'Who you owe money to', 'view': const OutstandingPayablesView()},
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

  Widget _buildSection(String title, List<Map<String, dynamic>> reports) {
    if (reports.isEmpty) return const SizedBox.shrink();
    return SectionedCard(
      title: title,
      children: reports.map((r) => SettingsListTile(
        icon: r['icon'] as IconData,
        title: r['title'] as String,
        subtitle: r['subtitle'] as String,
        onTap: () => _onReportTap(r),
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final gstEnabled = context.watch<SettingsProvider>().gstEnabled;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: AppColors.bgSurface,
          child: Center(child: Text('Reports', style: AppTextStyles.h3)),
        ),
      ),
      body: ListView(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        children: [
          _buildSection('Transaction', _transactionReports),
          if (gstEnabled) ...[
            const SizedBox(height: 12),
            _buildSection('Compliance', _complianceReports),
          ],
          const SizedBox(height: 12),
          _buildSection('Party', _partyReports),
        ],
      ),
    );
  }
}
