import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';

class BankingScreen extends StatelessWidget {
  const BankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Banking', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Bank Account', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppKpiCard(
                icon: Icons.account_balance,
                label: 'TOTAL BALANCE',
                value: '₹4,85,000',
                iconColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.savings,
                label: 'SAVINGS',
                value: '₹2,45,000',
                iconColor: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.business,
                label: 'CURRENT',
                value: '₹1,80,000',
                iconColor: AppColors.info,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.wallet,
                label: 'PETTY CASH',
                value: '₹60,000',
                iconColor: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Bank', width: 200),
              TableColumn(label: 'Account #', width: 180),
              TableColumn(label: 'IFSC', width: 120),
              TableColumn(label: 'Balance', width: 140),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [
              AppTableRow(cells: [
                Text('HDFC Savings', style: AppTypography.bodyMedium),
                Text('1234567890', style: AppTypography.bodySmall),
                Text('HDFC0001234', style: AppTypography.bodySmall),
                Text('₹2,45,000', style: AppTypography.amountTiny),
                const AppStatusBadge(status: InvoiceStatus.paid),
              ]),
              AppTableRow(cells: [
                Text('SBI Current', style: AppTypography.bodyMedium),
                Text('9876543210', style: AppTypography.bodySmall),
                Text('SBIN0005678', style: AppTypography.bodySmall),
                Text('₹1,80,000', style: AppTypography.amountTiny),
                const AppStatusBadge(status: InvoiceStatus.paid),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class BankReconciliationScreen extends StatelessWidget {
  const BankReconciliationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Bank Reconciliation', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Upload Statement', icon: Icons.upload, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: 45, isSelected: true),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Unmatched', count: 12, selectedColor: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Matched', count: 33, selectedColor: AppColors.success),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Description', width: 250),
              TableColumn(label: 'Bank Amount', width: 130),
              TableColumn(label: 'Ledger Amount', width: 130),
              TableColumn(label: 'Status', width: 100),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class CashBookScreen extends StatelessWidget {
  const CashBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Cash Book', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: 'Export', icon: Icons.download, style: AppButtonStyle.secondary, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppKpiCard(
                icon: Icons.arrow_downward,
                label: 'TOTAL IN',
                value: '₹8,50,000',
                iconColor: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.arrow_upward,
                label: 'TOTAL OUT',
                value: '₹6,20,000',
                iconColor: AppColors.error,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.account_balance_wallet,
                label: 'CLOSING BALANCE',
                value: '₹2,30,000',
                iconColor: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Particulars', width: 250),
              TableColumn(label: 'Voucher Type', width: 130),
              TableColumn(label: 'Debit', width: 120),
              TableColumn(label: 'Credit', width: 120),
              TableColumn(label: 'Balance', width: 120),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class JournalEntriesScreen extends StatelessWidget {
  const JournalEntriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Journal Entries', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Journal Entry', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Entry #', width: 120),
              TableColumn(label: 'Date', width: 100),
              TableColumn(label: 'Reference', width: 150),
              TableColumn(label: 'Description', width: 250),
              TableColumn(label: 'Amount', width: 120),
            ],
            rows: [],
          ),
        ),
      ],
    );
  }
}

class ChartOfAccountsScreen extends StatelessWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Chart of Accounts', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Account', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: 45, isSelected: true),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Assets', count: 12),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Liabilities', count: 8),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Income', count: 10),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Expenses', count: 15),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: AppTable(
            columns: const [
              TableColumn(label: 'Code', width: 100),
              TableColumn(label: 'Account Name', width: 250),
              TableColumn(label: 'Type', width: 120),
              TableColumn(label: 'Balance', width: 140),
            ],
            rows: [
              AppTableRow(cells: [
                Text('1000', style: AppTypography.labelLarge),
                Text('Cash in Hand', style: AppTypography.bodyMedium),
                Text('Asset', style: AppTypography.bodySmall),
                Text('₹60,000', style: AppTypography.amountTiny),
              ]),
              AppTableRow(cells: [
                Text('1010', style: AppTypography.labelLarge),
                Text('Bank Account', style: AppTypography.bodyMedium),
                Text('Asset', style: AppTypography.bodySmall),
                Text('₹4,25,000', style: AppTypography.amountTiny),
              ]),
              AppTableRow(cells: [
                Text('1200', style: AppTypography.labelLarge),
                Text('Accounts Receivable', style: AppTypography.bodyMedium),
                Text('Asset', style: AppTypography.bodySmall),
                Text('₹2,52,500', style: AppTypography.amountTiny),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}
