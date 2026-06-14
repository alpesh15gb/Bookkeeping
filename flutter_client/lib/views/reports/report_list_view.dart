import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/settings_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/design_system.dart' hide AppCard, AppEmptyState;
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
  final _searchCtrl = TextEditingController();
  List<String> _pinnedReportTitles = [];

  final _allReports = [
    // Transactions
    {'icon': Icons.summarize_outlined, 'title': 'Trial Balance', 'subtitle': 'Sum of all account balances', 'view': const TrialBalanceView(), 'category': 'Transaction'},
    {'icon': Icons.account_balance_outlined, 'title': 'Balance Sheet', 'subtitle': 'Assets, liabilities & equity', 'view': const BalanceSheetView(), 'category': 'Transaction'},
    {'icon': Icons.trending_up_outlined, 'title': 'Profit & Loss', 'subtitle': 'Revenue and expenses', 'view': const ProfitLossView(), 'category': 'Transaction'},
    {'icon': Icons.account_balance_wallet_outlined, 'title': 'Cash Flow', 'subtitle': 'Operating, investing & financing flows', 'view': const CashFlowView(), 'category': 'Transaction'},
    {'icon': Icons.description_outlined, 'title': 'Day Book', 'subtitle': 'All transactions for a day', 'view': null, 'category': 'Transaction'},
    // Compliance
    {'icon': Icons.receipt_long_outlined, 'title': 'GST Returns', 'subtitle': 'GSTR-1, GSTR-3B & more', 'view': const GstReturnsView(), 'category': 'Compliance'},
    // Party
    {'icon': Icons.bar_chart_outlined, 'title': 'Aging Report', 'subtitle': 'Outstanding receivables/payables', 'view': const AgingReportView(), 'category': 'Party'},
    {'icon': Icons.receipt_long_outlined, 'title': 'Party Statement', 'subtitle': 'Ledger & summary for a specific party', 'view': const PartyStatementView(), 'category': 'Party'},
    {'icon': Icons.arrow_circle_up_outlined, 'title': 'Outstanding Receivables', 'subtitle': 'Who owes you money', 'view': const OutstandingReceivablesView(), 'category': 'Party'},
    {'icon': Icons.arrow_circle_down_outlined, 'title': 'Outstanding Payables', 'subtitle': 'Who you owe money to', 'view': const OutstandingPayablesView(), 'category': 'Party'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pinnedReportTitles = prefs.getStringList('pinned_reports') ?? [];
    });
  }

  Future<void> _togglePin(String title) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_pinnedReportTitles.contains(title)) {
        _pinnedReportTitles.remove(title);
      } else {
        _pinnedReportTitles.add(title);
      }
    });
    await prefs.setStringList('pinned_reports', _pinnedReportTitles);
  }

  void _onReportTap(Map<String, dynamic> r) {
    if (r['view'] == null) {
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

  Widget _buildReportItem(Map<String, dynamic> r) {
    final isPinned = _pinnedReportTitles.contains(r['title']);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderLight)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onReportTap(r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.brandNavy.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(r['icon'] as IconData, color: AppColors.brandNavy, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r['title'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r['subtitle'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isPinned ? AppColors.goldAccent : AppColors.textMuted,
                    size: 20,
                  ),
                  onPressed: () => _togglePin(r['title'] as String),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final gstEnabled = context.watch<SettingsProvider>().gstEnabled;
    final query = _searchCtrl.text.trim().toLowerCase();

    // Filter reports list based on search and GST settings
    final filteredReports = _allReports.where((r) {
      if (r['category'] == 'Compliance' && !gstEnabled) return false;
      if (query.isEmpty) return true;
      final title = (r['title'] as String).toLowerCase();
      final subtitle = (r['subtitle'] as String).toLowerCase();
      return title.contains(query) || subtitle.contains(query);
    }).toList();

    // Separate pinned reports
    final pinned = filteredReports.where((r) => _pinnedReportTitles.contains(r['title'])).toList();
    final remaining = filteredReports.where((r) => !_pinnedReportTitles.contains(r['title'])).toList();

    // Group remaining reports by category
    final transactionReports = remaining.where((r) => r['category'] == 'Transaction').toList();
    final complianceReports = remaining.where((r) => r['category'] == 'Compliance').toList();
    final partyReports = remaining.where((r) => r['category'] == 'Party').toList();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reports', style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search reports...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                  child: const Icon(Icons.close_rounded, size: 18),
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.brandNavy, width: 1.5),
                          ),
                          fillColor: AppColors.bgLight,
                          filled: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
        children: [
          // Banner Hint
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.goldAccent.withOpacity(0.1),
              borderRadius: AppRadius.card,
              border: Border.all(color: AppColors.goldAccent.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: AppColors.goldAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap the star icon next to a report to pin it to the top of this screen for quick access.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.brandNavy,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pinned Section
          if (pinned.isNotEmpty) ...[
            SectionedCard(
              title: 'Pinned Reports',
              children: pinned.map((r) => _buildReportItem(r)).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Transaction Section
          if (transactionReports.isNotEmpty) ...[
            SectionedCard(
              title: 'Transaction',
              children: transactionReports.map((r) => _buildReportItem(r)).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Compliance Section
          if (gstEnabled && complianceReports.isNotEmpty) ...[
            SectionedCard(
              title: 'Compliance',
              children: complianceReports.map((r) => _buildReportItem(r)).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Party Section
          if (partyReports.isNotEmpty) ...[
            SectionedCard(
              title: 'Party Reports',
              children: partyReports.map((r) => _buildReportItem(r)).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
