/// Payment form screen — offline-first draft editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../offline_repository_providers.dart';
import '../../domain/commands/payment_commands.dart';
import 'payment_detail_screen.dart';
import 'package:apexbooks/core/errors/user_message.dart';

final _paymentContactsProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return (db.select(db.contacts)
        ..where(
          (row) => row.companyId.equals(companyId) & row.isActive.equals(true),
        )
        ..orderBy([(row) => OrderingTerm.asc(row.name)]))
      .watch();
});

final _paymentAccountsProvider = StreamProvider.autoDispose((ref) {
  final db = ref.watch(databaseProvider);
  final companyId =
      ref.watch(authControllerProvider).activeMembership?.tenantId ?? '';
  return (db.select(db.accounts)
        ..where(
          (row) =>
              row.companyId.equals(companyId) &
              row.isActive.equals(true) &
              row.accountType.equals('asset'),
        )
        ..orderBy([(row) => OrderingTerm.asc(row.name)]))
      .watch();
});

class PaymentFormScreen extends ConsumerStatefulWidget {
  const PaymentFormScreen({super.key, this.existingLocalId});
  final String? existingLocalId;

  @override
  ConsumerState<PaymentFormScreen> createState() => _PaymentFormScreenState();
}

class _PaymentFormScreenState extends ConsumerState<PaymentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _paymentType = 'RECEIPT';
  String _paymentDate = '';
  String _paymentMode = 'BANK';
  String _amountStr = '';
  String? _contactId;
  String? _contactName;
  String? _accountId;
  String? _referenceNumber;
  String? _description;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _paymentDate =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveDraft() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final amountPaise = Money.fromRupees(
      double.tryParse(_amountStr) ?? 0,
    ).toPaise();
    if (amountPaise <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

    setState(() => _saving = true);
    try {
      final companyId =
          ref.read(authControllerProvider).activeMembership?.tenantId ?? '';
      final payment = await ref
          .read(paymentRepositoryProvider)
          .saveDraft(
            SavePaymentDraftCommand(
              companyId: companyId,
              paymentType: _paymentType,
              paymentDate: _paymentDate,
              contactId: _contactId!,
              contactName: _contactName!,
              paymentMode: _paymentMode,
              accountId: _accountId!,
              amountPaise: amountPaise,
              referenceNumber: _referenceNumber,
              description: _description,
            ),
          );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentDetailScreen(localId: payment.localId),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = userFacingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final contacts =
        ref.watch(_paymentContactsProvider).valueOrNull ?? const [];
    final accounts =
        ref.watch(_paymentAccountsProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'New Payment',
            subtitle: 'Record a receipt or payment.',
            actions: [
              FilledButton.icon(
                onPressed: _saving ? null : _saveDraft,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save draft'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type toggle.
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'RECEIPT',
                          label: Text('Receipt'),
                          icon: Icon(Icons.arrow_downward),
                        ),
                        ButtonSegment(
                          value: 'PAYMENT',
                          label: Text('Payment'),
                          icon: Icon(Icons.arrow_upward),
                        ),
                      ],
                      selected: {_paymentType},
                      onSelectionChanged: (v) =>
                          setState(() => _paymentType = v.first),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: _paymentDate,
                      decoration: const InputDecoration(
                        labelText: 'Payment date',
                        hintText: 'YYYY-MM-DD',
                        prefixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      onChanged: (v) => _paymentDate = v,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _contactId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Contact',
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      items: [
                        for (final contact in contacts)
                          DropdownMenuItem(
                            value: contact.localId,
                            child: Text(contact.name),
                          ),
                      ],
                      onChanged: (value) {
                        final contact = contacts
                            .where((item) => item.localId == value)
                            .firstOrNull;
                        setState(() {
                          _contactId = value;
                          _contactName = contact?.name;
                        });
                      },
                      validator: (value) =>
                          value == null ? 'Select a contact' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMode,
                      decoration: const InputDecoration(
                        labelText: 'Payment mode',
                        prefixIcon: Icon(Icons.payment_rounded),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(
                          value: 'BANK',
                          child: Text('Bank Transfer'),
                        ),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(
                          value: 'CHEQUE',
                          child: Text('Cheque'),
                        ),
                        DropdownMenuItem(
                          value: 'POS',
                          child: Text('Card / POS'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _paymentMode = v ?? 'BANK'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _accountId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Cash / bank account',
                        prefixIcon: Icon(Icons.account_balance_rounded),
                      ),
                      items: [
                        for (final account in accounts)
                          DropdownMenuItem(
                            value: account.localId,
                            child: Text('${account.code} · ${account.name}'),
                          ),
                      ],
                      onChanged: (value) => setState(() => _accountId = value),
                      validator: (value) =>
                          value == null ? 'Select an account' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixIcon: Icon(Icons.money_rounded),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _amountStr = v,
                      validator: (v) {
                        final amt = double.tryParse(v ?? '');
                        if (amt == null || amt <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Reference number',
                        prefixIcon: Icon(Icons.tag_rounded),
                      ),
                      onChanged: (value) => _referenceNumber = value.trim(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      maxLines: 2,
                      onChanged: (value) => _description = value.trim(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: colors.danger)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
