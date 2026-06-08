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
    final provider = context.read<ExpenseProvider>();
    final cancellable = _selectedIds.where((id) {
      final match = provider.items.where((e) => e is Map ? e['id']?.toString() == id : false);
      if (match.isEmpty) return false;
      return match.first['status'] == 'POSTED';
    }).toList();
    if (cancellable.isEmpty) {
      AppToast.info(context, 'No cancellable expenses selected (only Posted can be cancelled)');
      return;
    }
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${cancellable.length} expenses?',
      message: 'This will reverse ledger entries for each selected expense.',
    );
    if (confirm == true) {
      int successCount = 0;
      for (final id in cancellable) {
        final ok = await provider.cancelExpense(id);
        if (ok) successCount++;
      }
      if (mounted) {
        AppToast.info(context, '$successCount of ${cancellable.length} expenses cancelled');
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
    final items = provider.items;

    num totalAmount = 0;
    for (final e in items) {
      totalAmount += double.tryParse((e['amount'] ?? 0).toString()) ?? 0;
    }

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        floatingActionButton: _isSelectionMode
            ? null
            : FloatingActionButton(
                onPressed: () => _showForm(),
                child: const Icon(Icons.add),
              ),
        body: Column(
          children: [
            AppStatusTabBar(
              tabs: const ['ALL', 'DRAFT', 'POSTED', 'CANCELLED'],
              activeTab: 'ALL',
              onTabChanged: (_) {},
              badges: {
                'ALL': items.length,
                'DRAFT': items.where((e) => e['status'] == 'DRAFT').length,
                'POSTED': items.where((e) => e['status'] == 'POSTED').length,
                'CANCELLED': items.where((e) => e['status'] == 'CANCELLED').length,
              },
            ),
            Expanded(
              child: provider.isLoading && items.isEmpty
                  ? const LoadingState(message: 'Loading expenses...')
                  : items.isEmpty
                      ? AppEmptyState(
                          icon: Icons.money_off_outlined,
                          title: 'No expenses recorded',
                          subtitle: 'Expenses you record will appear here',
                          actionLabel: 'Record Expense',
                          onAction: () => _showForm(),
                        )
                      : RefreshIndicator(
                          onRefresh: () async => provider.fetchExpenses(page: provider.currentPage),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: items.length,
                            separatorBuilder: (context, _) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final exp = items[i];
                              final id = exp['id'].toString();
                              final isSelected = _selectedIds.contains(id);
                              final category = exp['category_name'] ?? exp['category']?['name'] ?? 'N/A';
                              final amount = double.tryParse((exp['amount'] ?? 0).toString()) ?? 0.0;

                              return GestureDetector(
                                onTap: () {
                                  if (_isSelectionMode) {
                                    _toggleSelection(id);
                                  } else {
                                    _showDetail(exp['id']);
                                  }
                                },
                                onLongPress: () {
                                  if (!_isSelectionMode) {
                                    setState(() {
                                      _isSelectionMode = true;
                                      _selectedIds.add(id);
                                    });
                                  }
                                },
                                child: CompactDocumentCard(
                                  docNumber: exp['expense_number'] ?? 'EXP',
                                  partyName: category,
                                  date: exp['expense_date'],
                                  amount: amount,
                                  status: exp['status'] ?? 'POSTED',
                                  isSelected: isSelected,
                                  isSelectionMode: _isSelectionMode,
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          AppCommandBar(
            title: 'Expenses',
            actions: [
              AppButton(
                label: 'Record Expense',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => _showForm(),
              ),
            ],
          ),
          AppStatusTabBar(
            tabs: const ['ALL', 'DRAFT', 'POSTED', 'CANCELLED'],
            activeTab: 'ALL',
            onTabChanged: (_) {},
            badges: {
              'ALL': items.length,
              'DRAFT': items.where((e) => e['status'] == 'DRAFT').length,
              'POSTED': items.where((e) => e['status'] == 'POSTED').length,
              'CANCELLED': items.where((e) => e['status'] == 'CANCELLED').length,
            },
          ),
          Expanded(
            child: provider.isLoading && items.isEmpty
                ? const LoadingState(message: 'Loading expenses...')
                : items.isEmpty
                    ? AppEmptyState(
                        icon: Icons.money_off_outlined,
                        title: 'No expenses recorded',
                        subtitle: 'Expenses you record will appear here',
                        actionLabel: 'Record Expense',
                        onAction: () => _showForm(),
                      )
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: const BoxDecoration(
                              color: AppColors.bgSurface,
                              border: Border(bottom: BorderSide(color: AppColors.border)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: Checkbox(
                                    value: _selectedIds.length == items.length && items.isNotEmpty,
                                    onChanged: (_) => _selectAll(),
                                  ),
                                ),
                                const Expanded(flex: 2, child: Text('DATE', style: AppTextStyles.labelSmall)),
                                const Expanded(flex: 2, child: Text('NUMBER', style: AppTextStyles.labelSmall)),
                                const Expanded(flex: 4, child: Text('CATEGORY', style: AppTextStyles.labelSmall)),
                                const Expanded(flex: 3, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                const Expanded(flex: 2, child: Text('STATUS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                const SizedBox(width: 120, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                              itemBuilder: (context, index) {
                                final exp = items[index];
                                final id = exp['id'].toString();
                                final isSelected = _selectedIds.contains(id);
                                final category = exp['category_name'] ?? exp['category']?['name'] ?? 'N/A';
                                final amount = double.tryParse((exp['amount'] ?? 0).toString()) ?? 0.0;

                                return InkWell(
                                  onTap: () => _showDetail(exp['id']),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    color: isSelected ? AppColors.bgLight : Colors.transparent,
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 40,
                                          child: Checkbox(
                                            value: isSelected,
                                            onChanged: (_) => _toggleSelection(id),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            AppDate.format(exp['expense_date']),
                                            style: AppTextStyles.bodySmall,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            exp['expense_number'] ?? 'EXP',
                                            style: AppTextStyles.bodyMedium.copyWith(
                                              color: AppColors.brandNavy,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 4,
                                          child: Text(
                                            category,
                                            style: AppTextStyles.partyName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            AmountFormat.format(amount),
                                            style: AppTextStyles.amount,
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Center(
                                            child: AppInlineStatus(status: exp['status'] ?? 'POSTED'),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: AppRowActions(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.visibility_outlined, size: 16),
                                                onPressed: () => _showDetail(exp['id']),
                                                tooltip: 'View Detail',
                                              ),
                                              if (exp['status'] == 'DRAFT')
                                                IconButton(
                                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                                  onPressed: () => _showForm(expense: exp),
                                                  tooltip: 'Edit',
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline, size: 16),
                                                onPressed: () => _deleteExpense(exp['id']),
                                                tooltip: 'Delete',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
          if (_selectedIds.isNotEmpty)
            AppStickyBottomBar(
              children: [
                Text(
                  '${_selectedIds.length} selected',
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    AppButton(
                      label: 'Cancel Selected',
                      icon: Icons.cancel_outlined,
                      onTap: _bulkCancel,
                      color: AppColors.error,
                      isSmall: true,
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Delete Selected',
                      icon: Icons.delete_outline,
                      onTap: _bulkDelete,
                      color: AppColors.error,
                      isSmall: true,
                    ),
                  ],
                ),
              ],
            )
          else
            AppStickyBottomBar(
              children: [
                Text(
                  'Total Expenses: ${AmountFormat.format(totalAmount)}',
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Count: ${items.length}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          if (provider.totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
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
