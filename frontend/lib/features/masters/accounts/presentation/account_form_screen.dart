/// Account form screen — create / edit a Chart of Accounts entry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/forms/apex_form.dart';
import 'package:apexbooks/core/forms/dropdown_date_fields.dart';
import 'package:apexbooks/core/forms/money_field.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/account.dart';
import 'account_controller.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.account, this.existing = const []});
  final Account? account;
  final List<Account> existing;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = ApexFormController<Map<String, dynamic>>(_serialize);

  late TextEditingController _nameCtrl, _codeCtrl, _groupCtrl;
  AccountType _type = AccountType.asset;
  Account? _parent;
  double _openingBalance = 0;
  bool _isActive = true;
  bool _saving = false;

  static Map<String, dynamic> _serialize(
    Map<String, ApexFormField<dynamic>> fields,
  ) {
    return {'fields': fields};
  }

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _nameCtrl = TextEditingController(text: a?.name ?? '');
    _codeCtrl = TextEditingController(text: a?.code ?? '');
    _groupCtrl = TextEditingController(text: a?.accountGroup ?? '');
    if (a != null) {
      _type = a.accountType;
      _openingBalance = a.openingBalance;
      _isActive = a.isActive;
      _parent = a.parentId == null
          ? null
          : widget.existing.firstWhere(
              (e) => e.id == a.parentId,
              orElse: () => a,
            );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  List<Account> get _parentOptions {
    final editing = widget.account;
    final all = widget.existing;
    if (editing == null) return all;
    final excluded = <String>{editing.id};
    void collectChildren(String parentId) {
      for (final a in all) {
        if (a.parentId == parentId && !excluded.contains(a.id)) {
          excluded.add(a.id);
          collectChildren(a.id);
        }
      }
    }

    collectChildren(editing.id);
    return all.where((a) => !excluded.contains(a.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Account' : 'New Account')),
      body: ApexForm(
        controller: _ctrl,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Account Details'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Code *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers_outlined),
                  hintText: 'e.g. 1001',
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              ApexDropdownField<AccountType>(
                name: 'account_type',
                label: 'Account Type *',
                initialValue: _type,
                options: AccountType.values,
                toLabel: (t) => '${t.displayLabel} (${t.statementGroup})',
                onChanged: (v) =>
                    setState(() => _type = v ?? AccountType.asset),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _groupCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account Group',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder_outlined),
                  hintText: 'e.g. Cash & Bank, Receivables (optional)',
                ),
              ),
              const SizedBox(height: 12),
              ApexDropdownField<Account?>(
                name: 'parent_id',
                label: 'Parent Account',
                initialValue: _parent,
                options: [null, ..._parentOptions],
                toLabel: (a) =>
                    a == null ? '— None (root) —' : '${a.code} · ${a.name}',
                onChanged: (v) => setState(() => _parent = v),
              ),
              const SizedBox(height: 16),
              _section('Opening Balance'),
              const SizedBox(height: 8),
              ApexMoneyField(
                name: 'opening_balance',
                label: 'Opening Balance',
                initialValue: _openingBalance,
                onChanged: (v) => _openingBalance = v ?? 0,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _type.debitIncreases
                      ? 'Debit increases this account.'
                      : 'Credit increases this account.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Active'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 24),
              PermissionGate(
                permission: Permissions.accountsManage,
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
                  label: Text(_isEditing ? 'Update Account' : 'Create Account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String t) =>
      Text(t, style: Theme.of(context).textTheme.titleSmall);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final editing = widget.account;
    final newParentId = _parent?.id;
    if (editing != null &&
        wouldCreateCycle(widget.existing, editing.id, newParentId)) {
      ref
          .read(notificationServiceProvider)
          .error(
            context,
            'The selected parent would create a circular reference.',
          );
      return;
    }
    setState(() => _saving = true);
    final account = Account(
      id: editing?.id ?? '',
      name: _nameCtrl.text.trim(),
      code: _codeCtrl.text.trim(),
      accountType: _type,
      accountGroup: _groupCtrl.text.trim().isEmpty
          ? null
          : _groupCtrl.text.trim(),
      parentId: _parent?.id,
      openingBalance: _openingBalance,
      isActive: _isActive,
    );
    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(accountRepositoryProvider);
    if (_isEditing) {
      final result = await repo.update(account.id, account.toUpdateJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Account updated.');
        _pop();
      } else {
        notif.error(context, (result as Failure).error.message);
        setState(() => _saving = false);
      }
    } else {
      final result = await repo.create(account.toJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Account created.');
        _pop();
      } else {
        notif.error(context, (result as Failure).error.message);
        setState(() => _saving = false);
      }
    }
  }

  void _pop() {
    ref.read(cacheServiceProvider).invalidatePrefix('accounts:');
    Navigator.of(context).pop();
  }
}
