/// Expense Category list screen — reuses BaseListScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/tables/table_controller.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import '../data/models/expense_category.dart';
import 'expense_category_controller.dart';
import 'expense_category_form_screen.dart';
import 'expense_category_detail_screen.dart';

final expenseCategoryTableControllerProvider =
    ChangeNotifierProvider.autoDispose<ApexTableController>((ref) {
      return ApexTableController();
    });

class ExpenseCategoryListScreen extends ConsumerStatefulWidget {
  const ExpenseCategoryListScreen({super.key});
  @override
  ConsumerState<ExpenseCategoryListScreen> createState() =>
      _ExpenseCategoryListScreenState();
}

class _ExpenseCategoryListScreenState
    extends ConsumerState<ExpenseCategoryListScreen> {
  late final ApexTableController _tableCtrl;

  @override
  void initState() {
    super.initState();
    _tableCtrl = ref.read(expenseCategoryTableControllerProvider);
  }

  List<ApexColumn<ExpenseCategory>> _buildColumns() {
    final colors = apexColors(context);
    return [
      ApexColumn<ExpenseCategory>(
        id: 'name',
        label: 'Name',
        value: (c) => c.name,
        sortable: true,
        width: 200,
        cellBuilder: (ctx, c, _) => Row(
          children: [
            Icon(
              Icons.category_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      ApexColumn<ExpenseCategory>(
        id: 'description',
        label: 'Description',
        value: (c) => c.description ?? '\u2014',
        width: 300,
      ),
      ApexColumn<ExpenseCategory>(
        id: 'status',
        label: 'Status',
        value: (c) => c.isActive ? 'Active' : 'Inactive',
        sortable: true,
        width: 90,
        cellBuilder: (ctx, c, _) => Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: c.isActive ? 'ACTIVE' : 'INACTIVE',
            tone: c.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BaseListScreen<ExpenseCategory>(
      title: 'Expense Categories',
      columns: _buildColumns(),
      provider: expenseCategoryControllerProvider,
      tableCtrl: _tableCtrl,
      searchHint: 'Search by name or description',
      emptyTitle: 'No expense categories yet',
      emptySubtitle: 'Add your first expense category.',
      onCreate: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ExpenseCategoryFormScreen()),
      ),
      onRowTap: (c) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExpenseCategoryDetailScreen(category: c),
        ),
      ),
    );
  }
}
