import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/expense_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/expenses/expense_detail_view.dart';
import 'package:flutter_client/views/shared/pagination_controls.dart';

class ExpenseListView extends StatefulWidget {
  const ExpenseListView({super.key});

  @override
  State<ExpenseListView> createState() => _ExpenseListViewState();
}

class _ExpenseListViewState extends State<ExpenseListView> {
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<ExpenseProvider>().fetchExpenses());
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    final provider = context.read<ExpenseProvider>();
    setState(() {
      if (_selectedIds.length == provider.items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = provider.items.map((e) => e['id'].toString()).toSet();
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _bulkDelete() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete ${_selectedIds.length} items?',
      message: 'This action cannot be undone.',
    );
    if (confirm == true) {
      final provider = context.read<ExpenseProvider>();
      for (final id in _selectedIds) {
        await provider.deleteExpense(id);
      }
      _clearSelection();
      provider.fetchExpenses(page: provider.currentPage);
    }
  }

  void _showForm({Map<String, dynamic>? expense}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseFormView(editExpense: expense),
      ),
    ).then((updated) {
      if (updated == true) context.read<ExpenseProvider>().fetchExpenses();
    });
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseDetailView(expenseId: id),
      ),
    ).then((_) {
      context.read<ExpenseProvider>().fetchExpenses();
    });
  }

  Future<void> _deleteExpense(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Delete?', message: 'Delete this expense?');
    if (confirm == true) {
      final provider = context.read<ExpenseProvider>();
      final success = await provider.deleteExpense(id);
      if (success) {
        provider.fetchExpenses(page: provider.currentPage);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Delete failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: provider.isLoading && provider.items.isEmpty
                ? const LoadingState(message: 'Loading expenses...')
                : provider.items.isEmpty
                    ? EmptyState(
                        icon: Icons.money_off_outlined,
                        title: 'No expenses recorded',
                        subtitle: 'Expenses you record will appear here',
                        actionLabel: 'Record Expense',
                        onAction: () => _showForm(),
                      )
                    : Stack(
                        children: [
                          RefreshIndicator(
                            onRefresh: () async => provider.fetchExpenses(page: provider.currentPage),
                            child: ListView.separated(
                              padding: EdgeInsets.only(
                                left: isMobile ? 12 : 20,
                                right: isMobile ? 12 : 20,
                                top: isMobile ? 12 : 20,
                                bottom: _selectedIds.isNotEmpty ? 80 : (isMobile ? 12 : 20),
                              ),
                              itemCount: provider.items.length,
                              separatorBuilder: (context, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final exp = provider.items[i];
                                final id = exp['id'].toString();
                                final isSelected = _selectedIds.contains(id);
                                return GestureDetector(
                                  onLongPress: () {
                                    if (!_isSelectionMode) {
                                      setState(() {
                                        _isSelectionMode = true;
                                        _selectedIds.add(id);
                                      });
                                    }
                                  },
                                  child: AppCard(
                                    onTap: () {
                                      if (_isSelectionMode) {
                                        _toggleSelection(id);
                                      } else {
                                        _showDetail(exp['id']);
                                      }
                                    },
                                    child: Semantics(
                                      label: 'Expense ${exp['expense_number'] ?? 'EXPENSE'}, ${exp['status'] ?? 'POSTED'}, ${exp['category_name'] ?? exp['category']?['name'] ?? "N/A"}, ${exp['expense_date']}, ₹${double.parse((exp['amount'] ?? 0).toString()).toStringAsFixed(2)}',
                                      child: Row(
                                        children: [
                                          if (_isSelectionMode)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 12),
                                              child: Icon(
                                                isSelected ? Icons.check_circle : Icons.circle_outlined,
                                                size: 22,
                                                color: isSelected ? AppColors.brandNavy : AppColors.textMuted,
                                              ),
                                            ),
                                          Expanded(
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
                                                    if (!_isSelectionMode)
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
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_selectedIds.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.bgSurface,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, -2),
                                    ),
                                  ],
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 12 : 20,
                                  vertical: 12,
                                ),
                                child: SafeArea(
                                  top: false,
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: _selectAll,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _selectedIds.length == provider.items.length
                                                  ? Icons.check_circle
                                                  : Icons.circle_outlined,
                                              size: 22,
                                              color: _selectedIds.length == provider.items.length
                                                  ? AppColors.brandNavy
                                                  : AppColors.textMuted,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Select All',
                                              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        '${_selectedIds.length} selected',
                                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                      ),
                                      const Spacer(),
                                      OutlinedButton.icon(
                                        onPressed: _clearSelection,
                                        icon: const Icon(Icons.close, size: 14),
                                        label: const Text('Cancel'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          textStyle: AppTextStyles.buttonSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Export selected - coming soon')),
                                          );
                                        },
                                        icon: const Icon(Icons.file_download_outlined, size: 14),
                                        label: const Text('Export'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          textStyle: AppTextStyles.buttonSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        onPressed: _bulkDelete,
                                        icon: const Icon(Icons.delete_outline, size: 14),
                                        label: const Text('Delete'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          textStyle: AppTextStyles.buttonSmall,
                                          side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
          if (provider.totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: PaginationControls(
                currentPage: provider.currentPage,
                totalPages: provider.totalPages,
                onPrevious: provider.previousPage,
                onNext: provider.nextPage,
              ),
            ),
        ],
      ),
    );
  }
}
