import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports & Compliance', style: AppTypography.headlineLarge),
          const SizedBox(height: AppSpacing.sectionGap),
          _buildSection('FINANCIAL REPORTS', [
            _buildReportCard(Icons.balance, 'Trial Balance', 'View account balances'),
            _buildReportCard(Icons.account_balance, 'Balance Sheet', 'Assets, liabilities, equity'),
            _buildReportCard(Icons.trending_up, 'Profit & Loss', 'Revenue and expenses'),
            _buildReportCard(Icons.account_balance_wallet, 'Cash Flow', 'Money in and out'),
          ]),
          const SizedBox(height: AppSpacing.sectionGap),
          _buildSection('COMPLIANCE', [
            _buildReportCard(Icons.description, 'GST Returns', 'GSTR-1, GSTR-3B'),
            _buildReportCard(Icons.local_shipping, 'E-Way Bills', 'Generate and manage'),
          ]),
          const SizedBox(height: AppSpacing.sectionGap),
          _buildSection('PARTY REPORTS', [
            _buildReportCard(Icons.assessment, 'Aging Report', 'Receivables and payables'),
            _buildReportCard(Icons.receipt, 'Party Statement', 'Account statements'),
            _buildReportCard(Icons.people, 'Outstanding', 'Receivables and payables'),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelMedium.copyWith(color: AppColors.gray500)),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: cards,
        ),
      ],
    );
  }

  Widget _buildReportCard(IconData icon, String title, String subtitle) {
    return AppCard(
      width: 250,
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: AppTypography.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.gray500)),
        ],
      ),
    );
  }
}

class SalesAnalyticsScreen extends StatelessWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sales Analytics', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: 'Export', icon: Icons.download, style: AppButtonStyle.secondary, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppKpiCard(
                icon: Icons.trending_up,
                label: 'TOTAL REVENUE',
                value: '₹12,50,000',
                trendValue: '12%',
                trend: KpiTrend.up,
                iconColor: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.receipt,
                label: 'INVOICES',
                value: '45',
                trendValue: '8%',
                trend: KpiTrend.up,
                iconColor: AppColors.info,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.people,
                label: 'CUSTOMERS',
                value: '24',
                trendValue: '3',
                trend: KpiTrend.up,
                iconColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.receipt_long,
                label: 'AVG ORDER',
                value: '₹27,778',
                trendValue: '5%',
                trend: KpiTrend.up,
                iconColor: AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class GstReturnsScreen extends StatelessWidget {
  const GstReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GST Returns', style: AppTypography.headlineLarge),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeader(title: 'GSTR-1'),
                    const SizedBox(height: AppSpacing.md),
                    _buildStatusRow('Status', 'Filed', AppColors.success),
                    const SizedBox(height: AppSpacing.sm),
                    _buildStatusRow('Period', 'June 2025', AppColors.gray600),
                    const SizedBox(height: AppSpacing.sm),
                    _buildStatusRow('Filed On', 'Jul 11, 2025', AppColors.gray600),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppSectionHeader(title: 'GSTR-3B'),
                    const SizedBox(height: AppSpacing.md),
                    _buildStatusRow('Status', 'Pending', AppColors.warning),
                    const SizedBox(height: AppSpacing.sm),
                    _buildStatusRow('Period', 'June 2025', AppColors.gray600),
                    const SizedBox(height: AppSpacing.sm),
                    _buildStatusRow('Due Date', 'Jul 20, 2025', AppColors.error),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(label: 'File Return', icon: Icons.send, onPressed: () {}),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.bodySmall),
        Text(value, style: AppTypography.labelMedium.copyWith(color: color)),
      ],
    );
  }
}

class EwayBillsScreen extends StatelessWidget {
  const EwayBillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('E-Way Bills', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ E-Way Bill', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'E-Way Bill #', width: 140),
              TableColumn(label: 'Invoice #', width: 120),
              TableColumn(label: 'Customer', width: 180),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Valid Until', width: 110),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Audit Log', style: AppTypography.headlineLarge),
            const Spacer(),
            AppSearchField(hintText: 'Search audit log...', width: 300),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: 156, isSelected: true),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Invoices', count: 45),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Payments', count: 28),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Settings', count: 12),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Timestamp', width: 160),
              TableColumn(label: 'User', width: 150),
              TableColumn(label: 'Action', width: 120),
              TableColumn(label: 'Entity', width: 120),
              TableColumn(label: 'Details', width: 250),
            ],
            rows: [
              AppTableRow(cells: [
                Text('Jun 15, 14:20', style: AppTypography.bodySmall),
                Text('Ravi Kumar', style: AppTypography.bodyMedium),
                Text('Created', style: AppTypography.bodySmall),
                Text('Invoice', style: AppTypography.bodySmall),
                Text('INV-045 for Sharma Enterprises', style: AppTypography.bodySmall),
              ]),
              AppTableRow(cells: [
                Text('Jun 15, 14:25', style: AppTypography.bodySmall),
                Text('Ravi Kumar', style: AppTypography.bodyMedium),
                Text('Emailed', style: AppTypography.bodySmall),
                Text('Invoice', style: AppTypography.bodySmall),
                Text('Sent INV-045 to sharma@enterprises.com', style: AppTypography.bodySmall),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
