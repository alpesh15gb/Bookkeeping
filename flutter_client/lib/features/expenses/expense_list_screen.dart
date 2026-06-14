import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/expense_provider.dart';

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpenseProvider>().fetchExpenses();
    });
  }

  @override
  Widget build(BuildContext context) {
    final expenseProvider = context.watch<ExpenseProvider>();
    final expenses = expenseProvider.items;
    final isLoading = expenseProvider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Expenses', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Expense', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && expenses.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : expenses.isEmpty
                  ? AppEmptyState(icon: Icons.receipt_long, title: 'No expenses yet', subtitle: 'Track your business expenses')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Date', width: 110),
                        TableColumn(label: 'Category', width: 150),
                        TableColumn(label: 'Vendor', width: 180),
                        TableColumn(label: 'Description', width: 220),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: expenses.map((exp) {
                        final map = exp is Map<String, dynamic> ? exp : {};
                        return AppTableRow(
                          cells: [
                            Text(_formatDate(map['expense_date'] ?? ''), style: AppTypography.bodySmall),
                            Text(map['category_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(map['vendor_name'] ?? '', style: AppTypography.bodyMedium),
                            Text(map['description'] ?? '', style: AppTypography.bodySmall, overflow: TextOverflow.ellipsis),
                            AppAmountText(
                              amount: double.tryParse((map['total'] ?? 0).toString()) ?? 0.0,
                              style: AppTypography.amountTiny,
                            ),
                            AppStatusBadge(status: _parseStatus(map['status'] ?? 'DRAFT')),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  InvoiceStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'POSTED': return InvoiceStatus.paid;
      case 'CANCELLED': return InvoiceStatus.cancelled;
      default: return InvoiceStatus.draft;
    }
  }

  String _formatDate(String date) {
    if (date.isEmpty) return '-';
    try {
      final d = DateTime.parse(date);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
    } catch (_) {
      return date;
    }
  }
}
