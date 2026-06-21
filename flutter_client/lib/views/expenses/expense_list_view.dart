import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/expense_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/expenses/expense_form_view.dart';
import 'package:flutter_client/views/expenses/expense_detail_view.dart';
import 'package:flutter_client/views/shared/pagination_controls.dart';

class ExpenseListView extends StatefulWidget {
  const ExpenseListView({super.key});

  @override
  State<ExpenseListView> createState() => _ExpenseListViewState();
}

class _ExpenseListViewState extends State<ExpenseListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<ExpenseProvider>().fetchExpenses());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      if (mounted) AppToast.info(context, '$successCount of ${cancellable.length} expenses cancelled');
      _clearSelection();
      provider.fetchExpenses(page: provider.currentPage);
    }
  }

  void _showForm({Map<String, dynamic>? expense}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExpenseFormView(editExpense: expense)),
    ).then((updated) {
      if (updated == true) context.read<ExpenseProvider>().fetchExpenses();
    });
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExpenseDetailView(expenseId: id)),
    ).then((_) => context.read<ExpenseProvider>().fetchExpenses());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final items = provider.items;

    final totalCount = items.length;
    final draftCount = items.where((e) => e['status'] == 'DRAFT').length;
    final postedCount = items.where((e) => e['status'] == 'POSTED').length;
    final cancelledCount = items.where((e) => e['status'] == 'CANCELLED').length;

    num totalAmount = 0;
    for (final e in items) {
      if (e['status'] != 'CANCELLED') {
        totalAmount += double.tryParse((e['amount'] ?? 0).toString()) ?? 0;
      }
    }

    final filteredItems = items.where((e) {
      final matchesStatus = _statusFilter == 'ALL' || e['status'] == _statusFilter;
      final query = _searchCtrl.text.trim().toLowerCase();
      if (query.isEmpty) return matchesStatus;
      final number = (e['expense_number'] ?? '').toString().toLowerCase();
      final category = (e['category_name'] ?? e['category']?['name'] ?? '').toString().toLowerCase();
      return matchesStatus && (number.contains(query) || category.contains(query));
    }).toList();

    final docItems = filteredItems.map((exp) {
      return DocumentItemData(
        id: exp['id'].toString(),
        docNumber: exp['expense_number'] ?? 'EXP',
        partyName: exp['category_name'] ?? exp['category']?['name'] ?? 'N/A',
        date: exp['expense_date']?.toString(),
        amount: double.tryParse((exp['amount'] ?? 0).toString()) ?? 0,
        status: exp['status'] ?? 'POSTED',
      );
    }).toList();

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
          Expanded(
            child: DocumentListView(
              title: 'Expenses',
              searchController: _searchCtrl,
              searchHint: 'Search expenses...',
              onSearchChanged: (_) => setState(() {}),
              filterTabs: [
                FilterTab('ALL', totalCount),
                FilterTab('DRAFT', draftCount),
                FilterTab('POSTED', postedCount),
                FilterTab('CANCELLED', cancelledCount),
              ],
              activeFilter: _statusFilter,
              onFilterChanged: (tab) => setState(() => _statusFilter = tab),
              summary: ListSummaryData(totalAmount: totalAmount.toDouble(), totalCount: totalCount),
              items: docItems,
              isLoading: provider.isLoading && items.isEmpty,
              onRefresh: () async => provider.fetchExpenses(page: provider.currentPage),
              emptyTitle: 'No expenses recorded',
              emptySubtitle: 'Expenses you record will appear here',
              emptyIcon: Icons.money_off_outlined,
              detailBuilder: (ctx, item) => ExpenseDetailView(expenseId: item.id),
              itemBuilder: (context, item, index) {
                final id = item.id;
                final isSelected = _selectedIds.contains(id);

                return GestureDetector(
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(id);
                    } else {
                      _showDetail(id);
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
                    docNumber: item.docNumber,
                    partyName: item.partyName,
                    date: item.date,
                    amount: item.amount,
                    status: item.status,
                    isSelected: isSelected,
                    isSelectionMode: _isSelectionMode,
                  ),
                );
              },
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
