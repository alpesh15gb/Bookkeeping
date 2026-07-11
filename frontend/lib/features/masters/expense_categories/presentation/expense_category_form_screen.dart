/// Expense Category form screen — create / edit an expense category.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/forms/apex_form.dart';
import 'package:apexbooks/core/forms/apex_text_field.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/expense_category.dart';
import 'expense_category_controller.dart';

class ExpenseCategoryFormScreen extends ConsumerStatefulWidget {
  const ExpenseCategoryFormScreen({super.key, this.category});
  final ExpenseCategory? category;

  @override
  ConsumerState<ExpenseCategoryFormScreen> createState() =>
      _ExpenseCategoryFormScreenState();
}

class _ExpenseCategoryFormScreenState
    extends ConsumerState<ExpenseCategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = ApexFormController<Map<String, dynamic>>(
    (fields) => <String, dynamic>{'fields': fields},
  );

  bool _isActive = true;
  bool _saving = false;
  late TextEditingController _descCtrl;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    if (c != null) _isActive = c.isActive;
    _descCtrl = TextEditingController(text: c?.description ?? '');
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  String? _field(String name) => _ctrl.fields[name]?.value as String?;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Category' : 'New Expense Category'),
      ),
      body: ApexForm(
        controller: _ctrl,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ApexTextField(
                name: 'name',
                label: 'Category Name *',
                initialValue: widget.category?.name,
                textCapitalization: TextCapitalization.sentences,
                prefixIcon: Icons.category_outlined,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              Text(
                'Linked ledger account is auto-resolved by the system.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_isEditing)
                SwitchListTile(
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              const SizedBox(height: 24),
              PermissionGate(
                permission: Permissions.ledgerManualPost,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isEditing ? Icons.save_rounded : Icons.add_rounded,
                        ),
                  label: Text(
                    _isEditing ? 'Update Category' : 'Create Category',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final category = ExpenseCategory(
      id: widget.category?.id ?? '',
      name: _field('name') ?? '',
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      linkedAccountId: widget.category?.linkedAccountId,
      isActive: _isActive,
    );

    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(expenseCategoryRepositoryProvider);

    if (_isEditing) {
      final result = await repo.update(category.id, category.toUpdateJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Category updated.');
        _pop();
      } else {
        notif.error(context, (result as Failure).error.message);
        setState(() => _saving = false);
      }
    } else {
      final result = await repo.create(category.toJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Category created.');
        _pop();
      } else {
        notif.error(context, (result as Failure).error.message);
        setState(() => _saving = false);
      }
    }
  }

  void _pop() {
    ref.read(cacheServiceProvider).invalidatePrefix('expense-categories:');
    Navigator.of(context).pop();
  }
}
