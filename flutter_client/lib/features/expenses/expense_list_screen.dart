import 'package:flutter/material.dart';
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
                  : _buildEnhancedTable(expenses),
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
  Widget _buildEnhancedTable(List<dynamic> expenseList) {
    final expenses = expenseList.map((exp) {
      final map = exp is Map<String, dynamic> ? exp : {};
      return <String, dynamic>{
        'expense_date': _formatDate(map['expense_date'] ?? ''),
        'category_name': map['category_name'] ?? '',
        'vendor_name': map['vendor_name'] ?? '',
        'description': map['description'] ?? '',
        'total': double.tryParse((map['total'] ?? 0).toString()) ?? 0.0,
        'status': map['status'] ?? 'DRAFT',
        '_parseStatus': _parseStatus(map['status'] ?? 'DRAFT'),
      };
    }).toList();

    final totalAmount = expenses.fold<double>(0, (sum, exp) => sum + exp['total'] as double);

    return AppTable(
      title: '${expenses.length} expense${expenses.length == 1 ? '' : 's'}',
      columns: const [
        AppTableColumn(label: 'Date', width: 110, fieldKey: 'expense_date', isSortable: true),
        AppTableColumn(label: 'Category', width: 150, fieldKey: 'category_name', isSortable: true),
        AppTableColumn(label: 'Vendor', width: 180, fieldKey: 'vendor_name', isSortable: true),
        AppTableColumn(label: 'Description', width: 220, fieldKey: 'description'),
        AppTableColumn(label: 'Amount', width: 120, fieldKey: 'total', alignment: Alignment.centerRight, isSortable: true),
        AppTableColumn(label: 'Status', width: 100, fieldKey: 'status', alignment: Alignment.center, isSortable: true),
      ],
      rows: expenses,
      stickyHeader: true,
      stickyFooter: true,
      density: AppTableDensity.comfortable,
      enableKeyboardNav: true,
      enableColumnChooser: true,
      enableExport: true,
      summaryRows: [
        {
          'expense_date': 'TOTALS',
          'category_name': '',
          'vendor_name': '',
          'description': '',
          'total': totalAmount,
          'status': '',
        },
      ],
    );
  }
