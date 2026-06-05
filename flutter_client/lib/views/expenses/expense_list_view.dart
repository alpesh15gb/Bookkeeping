import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/expense_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/design_system.dart' as ds;
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

  void _bulkCancel() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${_selectedIds.length} expenses?',
      message: 'This will reverse ledger entries for each selected expense.',
    );
    if (confirm == true) {
      final provider = context.read<ExpenseProvider>();
      int successCount = 0;
      for (final id in _selectedIds) {
        final ok = await provider.cancelExpense(id);
        if (ok) successCount++;
      }
      if (mounted) {
        AppToast.info(context, '$successCount of ${_selectedIds.length} expenses cancelled');
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
        AppToast.error(context, provider.errorMessage ?? 'Delete failed');
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
          if (provider.items.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
              child: Builder(
                builder: (_) {
                  num totalAmount = 0;
                  for (final e in provider.items) {
                    totalAmount += double.tryParse((e['amount'] ?? 0).toString()) ?? 0;
                  }
                  return HeroSummaryCard(
                    title: 'Total Expenses',
                    amount: totalAmount,
                    subtitle: '${provider.items.length} expenses recorded',
                    icon: Icons.money_off_outlined,
                  );
                },
              ),
            ),
          Expanded(
            child: provider.isLoading && provider.items.isEmpty
                ? const LoadingState(message: 'Loading expenses...')
                : provider.items.isEmpty
                    ? ds.AppEmptyState(
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
                                final category = exp['category_name'] ?? exp['category']?['name'] ?? 'N/A';
                                final amount = double.tryParse((exp['amount'] ?? 0).toString()) ?? 0.0;

                                return GestureDetector(
                                  onLongPress: () {
                                    if (!_isSelectionMode) {
                                      setState(() {
                                        _isSelectionMode = true;
                                        _selectedIds.add(id);
                                      });
                                    }
                                  },
                                  child: Semantics(
                                    label: 'Expense ${exp['expense_number'] ?? 'EXPENSE'}, ${exp['status'] ?? 'POSTED'}, $category, ${exp['expense_date']}, ₹${amount.toStringAsFixed(2)}',
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
                                          child: ds.AppListTile(
                                            leadingText: 'E',
                                            title: exp['expense_number'] ?? 'EXPENSE',
                                            subtitle: '$category • ${ds.AppDate.format(exp['expense_date'])}',
                                            trailingWidget: ds.AppAmount(amount: amount),
                                            badge: StatusBadge(label: exp['status'] ?? 'POSTED'),
                                            hoverActions: _isSelectionMode
                                                ? null
                                                : [
                                                    ds.AppButton(
                                                      label: 'Edit',
                                                      icon: Icons.edit_outlined,
                                                      isSmall: true,
                                                      onTap: () => _showForm(expense: exp),
                                                    ),
                                                    ds.AppButton(
                                                      label: 'Delete',
                                                      icon: Icons.delete_outline,
                                                      isSmall: true,
                                                      color: AppColors.error,
                                                      textColor: AppColors.textWhite,
                                                      onTap: () => _deleteExpense(exp['id']),
                                                    ),
                                                  ],
                                            onTap: () {
                                              if (_isSelectionMode) {
                                                _toggleSelection(id);
                                              } else {
                                                _showDetail(exp['id']);
                                              }
                                            },
                                            isSelected: isSelected,
                                          ),
                                        ),
                                      ],
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
                                      ds.AppButton(
                                        label: 'Clear',
                                        icon: Icons.close,
                                        onTap: _clearSelection,
                                      ),
                                      const SizedBox(width: 8),
                                      ds.AppButton(
                                        label: 'Cancel',
                                        icon: Icons.cancel_outlined,
                                        color: AppColors.error,
                                        textColor: AppColors.textWhite,
                                        onTap: _bulkCancel,
                                      ),
                                      const SizedBox(width: 8),
                                      ds.AppButton(
                                        label: 'Delete',
                                        icon: Icons.delete_outline,
                                        color: AppColors.error,
                                        textColor: AppColors.textWhite,
                                        onTap: _bulkDelete,
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
