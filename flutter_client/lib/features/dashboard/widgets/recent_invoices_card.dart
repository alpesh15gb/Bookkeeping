import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/invoice.dart';
import '../../../providers/dashboard_provider.dart';

class RecentInvoicesCard extends StatelessWidget {
  const RecentInvoicesCard({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = context.watch<DashboardProvider>();
    final invoices = dashboard.recentInvoices;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'RECENT INVOICES',
            action: AppButton(
              label: 'View All',
              style: AppButtonStyle.ghost,
              isCompact: true,
              onPressed: () => context.go('/invoices'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (dashboard.isLoading && invoices.isEmpty) ...[
            const AppLoadingRow(),
            const SizedBox(height: AppSpacing.sm),
            const AppLoadingRow(),
            const SizedBox(height: AppSpacing.sm),
            const AppLoadingRow(),
          ] else if (invoices.isEmpty)
            AppEmptyState(
              icon: Icons.receipt_long,
              title: 'No invoices yet',
              subtitle: 'Create your first invoice to get started',
            )
          else
            ...invoices.take(5).map((inv) {
              final invoice = inv is InvoiceModel ? inv : null;
              final invoiceNumber = invoice?.invoiceNumber ?? (inv['invoice_number'] ?? '');
              final contactName = invoice?.contactName ?? (inv['contact_name'] ?? 'Unknown');
              final total = invoice?.total ?? double.tryParse((inv['total'] ?? 0).toString()) ?? 0.0;
              final amountPaid = invoice?.amountPaid ?? double.tryParse((inv['amount_paid'] ?? 0).toString()) ?? 0.0;
              final status = invoice?.status ?? (inv['status'] ?? 'DRAFT');
              final id = invoice?.id ?? (inv['id'] ?? '');
              final balance = total - amountPaid;

              final invoiceStatus = _parseStatus(status);

              return Column(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/invoices/$id'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(invoiceNumber, style: AppTypography.labelLarge),
                                Text(
                                  contactName,
                                  style: AppTypography.bodySmall.copyWith(color: AppColors.gray500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: AppAmountText(amount: balance, style: AppTypography.amountTiny),
                          ),
                          AppStatusBadge(status: invoiceStatus, isCompact: true),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: AppSpacing.lg),
                ],
              );
            }),
        ],
      ),
    );
  }

  InvoiceStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
        return InvoiceStatus.paid;
      case 'PARTIAL':
        return InvoiceStatus.partial;
      case 'OVERDUE':
        return InvoiceStatus.overdue;
      case 'DRAFT':
        return InvoiceStatus.draft;
      case 'CANCELLED':
        return InvoiceStatus.cancelled;
      default:
        return InvoiceStatus.pending;
    }
  }
}
