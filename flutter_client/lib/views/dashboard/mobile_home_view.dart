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
    final activeFY = fy.activeYear?.name ?? 'Active';

    // Get overdue invoices from recentInvoices
    final overdueInvoices = d.recentInvoices.where((inv) => (inv is Map ? inv['status']?.toString().toUpperCase() : null) == 'OVERDUE').take(3).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await d.fetchDashboard();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Greeting & FY Status
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Good Morning, $name ☀️',
                      style: AppTextStyles.h2.copyWith(color: AppColors.brandNavy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'FY $activeFY · Active',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // KPI Cards (Receivable & Payable side by side)
          Row(
            children: [
              Expanded(
                child: AppCard(
                  accentColor: AppColors.accentBlue,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RECEIVABLE',
                        style: AppTextStyles.overline,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AmountFormat.format(d.receivables),
                        style: AppTextStyles.amount.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: 0.6, // Example proportion
                          color: AppColors.accentBlue,
                          backgroundColor: AppColors.borderLight,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppCard(
                  accentColor: AppColors.warning,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PAYABLE',
                        style: AppTextStyles.overline,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AmountFormat.format(d.payables),
                        style: AppTextStyles.amount.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: 0.4, // Example proportion
                          color: AppColors.warning,
                          backgroundColor: AppColors.borderLight,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick Action Grid (2x2)
          Text(
            'QUICK ACTIONS',
            style: AppTextStyles.overline,
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: [
              _quickActionCell(context, 'New Invoice', Icons.receipt_long_outlined, AppColors.brandNavy, const InvoiceFormView()),
              _quickActionCell(context, 'New Expense', Icons.money_off_rounded, AppColors.error, const ExpenseFormView()),
              _quickActionCell(
                context,
                'New Payment',
                Icons.payments_rounded,
                AppColors.success,
                Builder(
                  builder: (ctx) => PaymentFormView(
                    mode: 'receipt',
                    onSuccess: () {
                      Navigator.pop(ctx);
                      context.read<DashboardProvider>().fetchDashboard();
                    },
                  ),
                ),
              ),
              _quickActionCell(context, 'New Bill', Icons.receipt_rounded, AppColors.warning, const BillFormView()),
            ],
          ),
          const SizedBox(height: 20),

          // Overdue Alerts
          if (overdueInvoices.isNotEmpty) ...[
            Text(
              'OVERDUE ALERTS (${overdueInvoices.length})',
              style: AppTextStyles.overline.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: overdueInvoices.map((inv) {
                  final num = inv['invoice_number']?.toString() ?? 'INV';
                  final name = inv['contact_name']?.toString() ?? 'Party';
                  final total = double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;
                  final id = inv['id']?.toString() ?? inv['invoice_id']?.toString();

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text(name, style: AppTextStyles.bodyMedium),
                    subtitle: Text('#$num', style: AppTextStyles.caption),
                    trailing: Text(
                      AmountFormat.format(total),
                      style: AppTextStyles.amount.copyWith(color: AppColors.error),
                    ),
                    onTap: id != null ? () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: id)));
                    } : null,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Recent Activity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RECENT ACTIVITY',
                style: AppTextStyles.overline,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppCard(
            padding: EdgeInsets.zero,
            child: d.recentInvoices.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No recent transactions')),
                  )
                : Column(
                    children: d.recentInvoices.take(5).map((inv) {
                      final num = inv['invoice_number']?.toString() ?? 'INV';
                      final name = inv['contact_name']?.toString() ?? 'Party';
                      final total = double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;
                      final status = inv['status']?.toString() ?? 'DRAFT';
                      final id = inv['id']?.toString() ?? inv['invoice_id']?.toString();

                      return Container(
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.borderLight)),
                        ),
                        child: ListTile(
                          title: Text(name, style: AppTextStyles.bodyMedium),
                          subtitle: Row(
                            children: [
                              Text('#$num', style: AppTextStyles.caption),
                              const SizedBox(width: 8),
                              AppInlineStatus(status: status),
                            ],
                          ),
                          trailing: Text(
                            AmountFormat.format(total),
                            style: AppTextStyles.amount,
                          ),
                          onTap: id != null ? () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: id)));
                          } : null,
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCell(BuildContext context, String label, IconData icon, Color color, Widget view) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => view));
      },
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
