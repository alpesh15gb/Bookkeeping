import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/expenses/expense_detail_view.dart';

class ExpenseListView extends StatefulWidget {
  const ExpenseListView({super.key});

  @override
  State<ExpenseListView> createState() => _ExpenseListViewState();
}

class _ExpenseListViewState extends State<ExpenseListView> {
  List<dynamic> _expenses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() async {
    setState(() => _isLoading = true);
    final list = await context.read<DocumentProvider>().fetchExpenses();
    if (mounted) {
      setState(() {
        _expenses = list;
        _isLoading = false;
      });
    }
  }

  void _showForm({Map<String, dynamic>? expense}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormView(editExpense: expense),
      ),
    ).then((updated) {
      if (updated == true) _fetch();
    });
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailView(expenseId: id),
      ),
    ).then((updated) {
      _fetch();
    });
  }

  Future<void> _deleteExpense(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Delete?', message: 'Delete this expense?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.deleteExpense(id);
      if (success) {
        _fetch();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Delete failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading expenses...')
          : _expenses.isEmpty
              ? EmptyState(
                  icon: Icons.money_off_outlined,
                  title: 'No expenses recorded',
                  subtitle: 'Expenses you record will appear here',
                  actionLabel: 'Record Expense',
                  onAction: () => _showForm(),
                )
              : ListView.separated(
                  padding: isMobile ? AppSpacing.pagePaddingMobile : AppSpacing.pagePadding,
                  itemCount: _expenses.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final exp = _expenses[i];
                    return AppCard(
                      onTap: () => _showDetail(exp['id']),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(exp['expense_number'] ?? 'EXPENSE', style: AppTextStyles.h3),
                              ),
                              StatusBadge(label: exp['status'] ?? 'POSTED'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.category_outlined, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text('${exp['category_name'] ?? exp['category']?['name'] ?? "N/A"}', style: AppTextStyles.bodySmall),
                              const SizedBox(width: 16),
                              Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text('${exp['expense_date']}', style: AppTextStyles.caption),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '₹${double.parse((exp['amount'] ?? 0).toString()).toStringAsFixed(2)}',
                                style: AppTextStyles.numericLarge,
                              ),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _showForm(expense: exp),
                                    icon: const Icon(Icons.edit_outlined, size: 14),
                                    label: const Text('Edit'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      textStyle: AppTextStyles.buttonSmall,
                                      side: const BorderSide(color: AppColors.borderInput),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => _deleteExpense(exp['id']),
                                    icon: const Icon(Icons.delete_outlined, size: 14),
                                    label: const Text('Delete'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      textStyle: AppTextStyles.buttonSmall,
                                      side: BorderSide(color: AppColors.error.withOpacity(0.3)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
