/// Expense Category detail screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/widgets/entity_detail_page.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/expense_category.dart';
import 'expense_category_controller.dart';
import 'expense_category_form_screen.dart';

class ExpenseCategoryDetailScreen extends ConsumerWidget {
  const ExpenseCategoryDetailScreen({super.key, required this.category});
  final ExpenseCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = (String? v) => v ?? '\u2014';

    return EntityDetailPage(
      title: category.name,
      chips: [
        DetailChip(
          label: category.isActive ? 'Active' : 'Inactive',
          color: category.isActive ? Colors.green : Colors.red,
        ),
      ],
      sections: [
        DetailSection(
          title: 'Category Details',
          rows: [
            DetailRow('Name', category.name),
            DetailRow('Description', fmt(category.description)),
            DetailRow('Linked Account ID', fmt(category.linkedAccountId)),
            DetailRow('Status', category.isActive ? 'Active' : 'Inactive'),
          ],
        ),
      ],
      actions: [
        ActionItem(
          icon: Icons.edit_rounded,
          label: 'Edit',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExpenseCategoryFormScreen(category: category),
              ),
            );
          },
        ),
        ActionItem(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onTap: () => _delete(context, ref),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete category "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(expenseCategoryRepositoryProvider);
    final result = await repo.delete(category.id);
    if (!context.mounted) return;
    if (result is Success) {
      notif.success(context, 'Category deleted.');
      ref.read(cacheServiceProvider).invalidatePrefix('expense-categories:');
      Navigator.of(context).pop();
    } else {
      notif.error(context, 'Failed to delete.');
    }
  }
}
