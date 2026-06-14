import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/dashboard_provider.dart';
import 'package:flutter_client/providers/financial_year_provider.dart';
import 'package:flutter_client/providers/auth_provider.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/payments/payment_form_view.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/invoices/invoice_detail_view.dart';

class MobileHomeView extends StatelessWidget {
  const MobileHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DashboardProvider>();
    final fy = context.watch<FinancialYearProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final name = user?.fullName ?? 'User';
    final activeFY = fy.activeYear?.name ?? '';

    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    final overdueInvoices = d.recentInvoices
        .where((inv) => (inv is Map ? inv['status']?.toString().toUpperCase() : null) == 'OVERDUE')
        .take(3)
        .toList();

    return RefreshIndicator(
      onRefresh: () async => d.fetchDashboard(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 100),
        children: [
          _buildHeroCard(context, name, greeting, activeFY, d),
          const SizedBox(height: 16),
          _buildFinancialSnapshot(context, d),
          const SizedBox(height: 16),
          _buildQuickActions(context),
          const SizedBox(height: 20),
          if (overdueInvoices.isNotEmpty) ...[
            _buildOverdueAlerts(context, overdueInvoices),
            const SizedBox(height: 20),
          ],
          _buildRecentTransactions(context, d),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, String name, String greeting, String fy, DashboardProvider d) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F234A).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F234A), Color(0xFF1A3A6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                      blurRadius: 40,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$greeting,', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7))),
                            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.goldAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('FY $fy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandNavy)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildHeroStat('TOTAL SALES', AmountFormat.format(d.revenue)),
                      Container(width: 1, height: 32, color: Colors.white.withValues(alpha: 0.2), margin: const EdgeInsets.symmetric(horizontal: 16)),
                      _buildHeroStat('RECEIVABLE', AmountFormat.format(d.receivables)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.6), letterSpacing: 0.8)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildFinancialSnapshot(BuildContext context, DashboardProvider d) {
    return Row(
      children: [
        Expanded(child: _buildSnapshotCard('PAYABLE', AmountFormat.format(d.payables), AppColors.warning, Icons.arrow_upward_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _buildSnapshotCard('EXPENSES', AmountFormat.format(d.totalExpenses ?? 0), AppColors.error, Icons.receipt_long_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _buildSnapshotCard('PROFIT', AmountFormat.format(d.netProfit), AppColors.success, Icons.trending_up_rounded)),
      ],
    );
  }

  Widget _buildSnapshotCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(color: color.withValues(alpha: 0.35), width: 1),
          right: BorderSide(color: color.withValues(alpha: 0.35), width: 1),
          bottom: BorderSide(color: color.withValues(alpha: 0.35), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK ACTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildQuickAction(context, 'Invoice', Icons.receipt_long_outlined, AppColors.brandNavy, const InvoiceFormView()),
            const SizedBox(width: 8),
            _buildQuickAction(context, 'Bill', Icons.receipt_rounded, AppColors.warning, const BillFormView()),
            const SizedBox(width: 8),
            _buildQuickAction(context, 'Expense', Icons.money_off_rounded, AppColors.error, const ExpenseFormView()),
            const SizedBox(width: 8),
            _buildQuickAction(context, 'Payment', Icons.payments_rounded, AppColors.success,
              Builder(builder: (ctx) => PaymentFormView(mode: 'receipt', onSuccess: () => Navigator.pop(ctx)))),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction(BuildContext context, String label, IconData icon, Color color, Widget view) {
    return Expanded(
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => view)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.15), width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverdueAlerts(BuildContext context, List<dynamic> overdueInvoices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
            ),
            const SizedBox(width: 8),
            Text('OVERDUE (${overdueInvoices.length})', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.error, letterSpacing: 0.8)),
          ],
        ),
        const SizedBox(height: 10),
        ...overdueInvoices.map((inv) {
          final num = inv['invoice_number']?.toString() ?? 'INV';
          final name = inv['contact_name']?.toString() ?? 'Party';
          final total = double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;
          final id = inv['id']?.toString() ?? inv['invoice_id']?.toString();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.15), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text('#$num', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Text(AmountFormat.format(total), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.error)),
                if (id != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRecentTransactions(BuildContext context, DashboardProvider d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RECENT TRANSACTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.8)),
            Text('See All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brandNavy)),
          ],
        ),
        const SizedBox(height: 10),
        if (d.recentInvoices.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 36, color: AppColors.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('No transactions yet', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
            ),
          )
        else
          ...d.recentInvoices.take(5).map((inv) {
            final num = inv['invoice_number']?.toString() ?? 'INV';
            final name = inv['contact_name']?.toString() ?? 'Party';
            final total = double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;
            final status = inv['status']?.toString() ?? 'DRAFT';
            final id = inv['id']?.toString() ?? inv['invoice_id']?.toString();
            final isCredit = status == 'CANCELLED';

            Color statusDotColor;
            switch (status.toUpperCase()) {
              case 'PAID':
                statusDotColor = AppColors.success;
                break;
              case 'PARTIALLY_PAID':
              case 'PARTIAL':
              case 'PENDING':
                statusDotColor = AppColors.warning;
                break;
              case 'OVERDUE':
              case 'CANCELLED':
                statusDotColor = AppColors.error;
                break;
              default:
                statusDotColor = AppColors.textMuted;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isCredit ? AppColors.error : AppColors.brandNavy).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isCredit ? AppColors.error : AppColors.brandNavy),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Row(
                          children: [
                            Text('#$num', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            const SizedBox(width: 6),
                            AppInlineStatus(status: status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    AmountFormat.format(total),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
