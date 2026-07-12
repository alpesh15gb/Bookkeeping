/// Banking Profile form — uses ApexTextField for standard inputs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/forms/apex_form.dart';
import 'package:apexbooks/core/forms/apex_text_field.dart';
import 'package:apexbooks/core/permissions/permissions_constants.dart';
import 'package:apexbooks/core/permissions/permission_gate.dart';
import 'package:apexbooks/core/services/notification_service.dart';
import 'package:apexbooks/core/cache/cache_service.dart';
import 'package:apexbooks/core/dialogs/dialog_service.dart';
import 'package:apexbooks/core/result/result.dart';
import '../data/models/banking_profile.dart';
import 'banking_profile_controller.dart';

class BankingProfileFormScreen extends ConsumerStatefulWidget {
  const BankingProfileFormScreen({super.key, this.profile});
  final BankingProfile? profile;

  @override
  ConsumerState<BankingProfileFormScreen> createState() =>
      _BankingProfileFormScreenState();
}

class _BankingProfileFormScreenState
    extends ConsumerState<BankingProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = ApexFormController<Map<String, dynamic>>(
    (fields) => <String, dynamic>{'fields': fields},
  );

  bool _isPrimary = false;
  bool _isActive = true;
  bool _saving = false;

  bool get _isEditing => widget.profile != null;

  bool get _hasUnsavedChanges =>
      (_field('bank_name')?.isNotEmpty ?? false) ||
      (_field('account_number')?.isNotEmpty ?? false) ||
      (_field('ifsc_code')?.isNotEmpty ?? false) ||
      (_field('branch_name')?.isNotEmpty ?? false) ||
      (_field('account_holder')?.isNotEmpty ?? false) ||
      (_field('upi_id')?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    if (p != null) {
      _isPrimary = p.isPrimary;
      _isActive = p.isActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          final result = await const DialogService().unsavedChanges(context);
          if (result == DialogResult.discard && context.mounted) {
            Navigator.of(context).pop();
          }
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Bank Account' : 'New Bank Account'),
      ),
      body: ApexForm(
        controller: _ctrl,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('Bank Details'),
              const SizedBox(height: 8),
              ApexTextField(
                name: 'bank_name',
                label: 'Bank Name *',
                initialValue: widget.profile?.bankName,
                textCapitalization: TextCapitalization.words,
                prefixIcon: Icons.account_balance_outlined,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              ApexTextField(
                name: 'account_number',
                label: 'Account Number *',
                initialValue: widget.profile?.accountNumber,
                keyboardType: TextInputType.number,
                prefixIcon: Icons.numbers_outlined,
                hintText: 'e.g. 12345678901',
                validator: validateAccountNumber,
              ),
              const SizedBox(height: 12),
              ApexTextField(
                name: 'ifsc_code',
                label: 'IFSC Code *',
                initialValue: widget.profile?.ifscCode,
                textCapitalization: TextCapitalization.characters,
                maxLength: 11,
                prefixIcon: Icons.qr_code_outlined,
                hintText: 'e.g. HDFC0001234',
                validator: validateIfsc,
              ),
              const SizedBox(height: 12),
              ApexTextField(
                name: 'branch_name',
                label: 'Branch Name',
                initialValue: widget.profile?.branchName,
                textCapitalization: TextCapitalization.words,
                prefixIcon: Icons.location_on_outlined,
                hintText: 'Optional',
              ),
              const SizedBox(height: 16),
              _section('Account Holder'),
              const SizedBox(height: 8),
              ApexTextField(
                name: 'account_holder',
                label: 'Account Holder Name *',
                initialValue: widget.profile?.accountHolderName,
                textCapitalization: TextCapitalization.words,
                prefixIcon: Icons.person_outline,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _section('UPI & Preferences'),
              const SizedBox(height: 8),
              ApexTextField(
                name: 'upi_id',
                label: 'UPI ID',
                initialValue: widget.profile?.upiId,
                prefixIcon: Icons.payments_outlined,
                hintText: 'e.g. name@bank',
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Set as Primary Account'),
                subtitle: const Text(
                  'Primary accounts are used by default for payments/receipts.',
                ),
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v),
              ),
              const SizedBox(height: 8),
              if (_isEditing)
                SwitchListTile(
                  title: const Text('Active'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              const SizedBox(height: 24),
              PermissionGate(
                permission: Permissions.tenantUpdate,
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
      ),
    );
  }

  Widget _section(String t) =>
      Text(t, style: Theme.of(context).textTheme.titleSmall);

  String? _field(String name) => _ctrl.fields[name]?.value as String?;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = BankingProfile(
      id: widget.profile?.id ?? '',
      bankName: _field('bank_name') ?? '',
      accountNumber: _field('account_number') ?? '',
      ifscCode: (_field('ifsc_code') ?? '').toUpperCase(),
      branchName: _field('branch_name'),
      accountHolderName: _field('account_holder') ?? '',
      upiId: _field('upi_id'),
      isPrimary: _isPrimary,
      isActive: _isActive,
    );

    final notif = ref.read(notificationServiceProvider);
    final repo = ref.read(bankingProfileRepositoryProvider);

    if (_isEditing) {
      final result = await repo.update(profile.id, profile.toUpdateJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Bank account updated.');
        _pop();
      } else {
        notif.error(context, (result as Failure).error.message);
        setState(() => _saving = false);
      }
    } else {
      final result = await repo.create(profile.toJson());
      if (!mounted) return;
      if (result is Success) {
        notif.success(context, 'Bank account created.');
        _pop();
      } else {
        notif.error(context, (result as Failure).error.message);
        setState(() => _saving = false);
      }
    }
  }

  void _pop() {
    ref.read(cacheServiceProvider).invalidatePrefix('banking-profiles:');
    Navigator.of(context).pop();
  }
}
