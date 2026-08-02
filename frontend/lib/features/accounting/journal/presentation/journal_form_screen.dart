import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull, Column;
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/database/database_provider.dart' as local_db;
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/features/masters/accounts/data/models/account.dart';
import 'package:apexbooks/features/masters/accounts/presentation/account_controller.dart';
import '../models/direction.dart';
import '../models/journal_line.dart';
import 'journal_form_notifier.dart';
import '../../../../features/journals/domain/entities/journal_entity.dart';

final _localJournalAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) {
    final db = ref.watch(local_db.databaseProvider);
    final query = db.select(db.accounts)
      ..where((account) => account.isActive.equals(true))
      ..orderBy([(account) => OrderingTerm.asc(account.code)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => Account(
              id: row.remoteId.isNotEmpty ? row.remoteId : row.localId,
              name: row.name,
              code: row.code,
              accountType: AccountType.fromApi(row.accountType),
              accountGroup: row.accountGroup,
              parentId: row.parentRemoteId,
              isActive: row.isActive,
              updatedAt: row.updatedAt.toIso8601String(),
            ),
          )
          .toList(),
    );
  },
);

class JournalFormScreen extends ConsumerStatefulWidget {
  const JournalFormScreen({super.key, this.entry});

  final JournalEntryEntity? entry;

  @override
  ConsumerState<JournalFormScreen> createState() => _JournalFormScreenState();
}

class _JournalFormScreenState extends ConsumerState<JournalFormScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(accountControllerProvider.notifier)
          .load(const ListQuery(limit: 100)),
    );
  }

  Future<void> _saveDraft() async {
    final saved = await ref
        .read(journalFormProvider(widget.entry).notifier)
        .saveDraft();
    if (!mounted) return;
    if (saved) Navigator.of(context).pop(true);
  }

  Future<void> _post() async {
    final posted = await ref
        .read(journalFormProvider(widget.entry).notifier)
        .post();
    if (!mounted) return;
    if (posted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final form = ref.watch(journalFormProvider(widget.entry));
    final notifier = ref.read(journalFormProvider(widget.entry).notifier);
    final localAccounts = ref.watch(_localJournalAccountsProvider).valueOrNull;
    final accountState = ref.watch(accountControllerProvider);
    final remoteAccounts = accountState is ListData<Account>
        ? accountState.paged.items.where((account) => account.isActive).toList()
        : <Account>[];
    final accounts = localAccounts != null && localAccounts.isNotEmpty
        ? localAccounts
        : remoteAccounts;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveDraft,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveDraft,
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true):
            notifier.addLine,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surfaceMuted,
          appBar: AppBar(
            title: Text(
              isMobile
                  ? (widget.entry == null ? 'New Journal' : 'Edit Draft')
                  : (widget.entry == null
                        ? 'New Journal Entry'
                        : 'Edit Journal Draft'),
            ),
            actions: [
              if (!isMobile)
                TextButton(
                  onPressed: form.saving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              const SizedBox(width: ApexSpacing.sm),
              TextButton(
                onPressed: form.saving ? null : _saveDraft,
                child: Text(isMobile ? 'Save' : 'Save draft  Ctrl+S'),
              ),
              Padding(
                padding: EdgeInsets.only(
                  right: isMobile ? ApexSpacing.sm : ApexSpacing.lg,
                ),
                child: FilledButton.icon(
                  onPressed: form.saving ? null : _post,
                  icon: form.saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(isMobile ? 'Post' : 'Post journal'),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: EdgeInsets.all(
                  isMobile ? ApexSpacing.md : ApexSpacing.xl,
                ),
                children: [
                  if (form.error != null) ...[
                    _ErrorBanner(message: form.error!, colors: colors),
                    const SizedBox(height: ApexSpacing.md),
                  ],
                  ApexCard(
                    padding: EdgeInsets.all(
                      isMobile ? ApexSpacing.md : ApexSpacing.lg,
                    ),
                    child: _HeaderFields(
                      isMobile: isMobile,
                      initialDate: form.entryDate,
                      onDateChanged: notifier.setDate,
                      onReferenceChanged: notifier.setReference,
                      onDescriptionChanged: notifier.setDescription,
                    ),
                  ),
                  const SizedBox(height: ApexSpacing.md),
                  ApexCard(
                    padding: EdgeInsets.all(
                      isMobile ? ApexSpacing.md : ApexSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Journal lines',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: ApexSpacing.md),
                        ...form.lines.asMap().entries.map(
                          (entry) => _JournalLineEditor(
                            key: ValueKey('journal-line-${entry.key}'),
                            line: entry.value,
                            accounts: accounts,
                            canRemove: form.lines.length > 2,
                            onChanged: (line) =>
                                notifier.updateLine(entry.key, line),
                            onRemove: () => notifier.removeLine(entry.key),
                          ),
                        ),
                        Wrap(
                          spacing: ApexSpacing.sm,
                          runSpacing: ApexSpacing.sm,
                          children: [
                            TextButton.icon(
                              onPressed: notifier.addLine,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(
                                isMobile ? 'Add line' : 'Add line  Alt+N',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: notifier.autoBalance,
                              icon: const Icon(Icons.balance_rounded),
                              label: const Text('Auto-balance'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ApexSpacing.md),
                  ApexCard(
                    padding: EdgeInsets.all(
                      isMobile ? ApexSpacing.md : ApexSpacing.lg,
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Total(
                                label: 'Debit',
                                value: form.totalDebit,
                                colors: colors,
                              ),
                              const SizedBox(height: ApexSpacing.sm),
                              _Total(
                                label: 'Credit',
                                value: form.totalCredit,
                                colors: colors,
                              ),
                              const SizedBox(height: ApexSpacing.sm),
                              _Total(
                                label: 'Difference',
                                value: form.totalDebit - form.totalCredit,
                                colors: colors,
                                danger: !form.isBalanced,
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _Total(
                                label: 'Debit',
                                value: form.totalDebit,
                                colors: colors,
                              ),
                              const SizedBox(width: ApexSpacing.xl),
                              _Total(
                                label: 'Credit',
                                value: form.totalCredit,
                                colors: colors,
                              ),
                              const SizedBox(width: ApexSpacing.xl),
                              _Total(
                                label: 'Difference',
                                value: form.totalDebit - form.totalCredit,
                                colors: colors,
                                danger: !form.isBalanced,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderFields extends StatelessWidget {
  const _HeaderFields({
    required this.isMobile,
    required this.initialDate,
    required this.onDateChanged,
    required this.onReferenceChanged,
    required this.onDescriptionChanged,
  });

  final bool isMobile;
  final String initialDate;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String> onReferenceChanged;
  final ValueChanged<String> onDescriptionChanged;

  @override
  Widget build(BuildContext context) {
    final dateField = TextFormField(
      initialValue: initialDate,
      decoration: const InputDecoration(labelText: 'Posting date *'),
      onChanged: onDateChanged,
    );
    final referenceField = TextFormField(
      decoration: const InputDecoration(
        labelText: 'Reference',
        hintText: 'Auto-generated if blank',
      ),
      onChanged: onReferenceChanged,
    );
    final narrationField = TextFormField(
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Narration *'),
      onChanged: onDescriptionChanged,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          dateField,
          const SizedBox(height: ApexSpacing.md),
          referenceField,
          const SizedBox(height: ApexSpacing.md),
          narrationField,
        ],
      );
    }

    return Wrap(
      spacing: ApexSpacing.lg,
      runSpacing: ApexSpacing.md,
      children: [
        SizedBox(width: 180, child: dateField),
        SizedBox(width: 220, child: referenceField),
        SizedBox(width: 500, child: narrationField),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.colors});

  final String message;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(ApexSpacing.md),
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(ApexRadius_md),
          border: Border.all(color: colors.danger.withValues(alpha: .25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.danger, size: 18),
            const SizedBox(width: ApexSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: colors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalLineEditor extends StatelessWidget {
  const _JournalLineEditor({
    super.key,
    required this.line,
    required this.accounts,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final JournalLine line;
  final List<Account> accounts;
  final bool canRemove;
  final ValueChanged<JournalLine> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);

    final accountField = DropdownButtonFormField<String>(
      initialValue: line.accountId.isEmpty ? null : line.accountId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Account'),
      items: accounts
          .map(
            (account) => DropdownMenuItem(
              value: account.id,
              child: Text(
                '${account.code}  ${account.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        final account = accounts.where((a) => a.id == id).firstOrNull;
        if (account == null) return;
        onChanged(
          line.copyWith(
            accountId: account.id,
            accountName: account.name,
            accountCode: account.code,
          ),
        );
      },
    );

    final directionField = DropdownButtonFormField<Direction>(
      initialValue: line.direction,
      decoration: const InputDecoration(labelText: 'Dr / Cr'),
      items: const [
        DropdownMenuItem(value: Direction.debit, child: Text('Debit')),
        DropdownMenuItem(value: Direction.credit, child: Text('Credit')),
      ],
      onChanged: (value) =>
          onChanged(line.copyWith(direction: value ?? line.direction)),
    );

    final amountField = TextFormField(
      initialValue: line.amount == 0 ? '' : line.amount.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: const InputDecoration(labelText: 'Amount'),
      onChanged: (value) =>
          onChanged(line.copyWith(amount: double.tryParse(value) ?? 0)),
    );

    final narrationField = TextFormField(
      initialValue: line.narration,
      decoration: const InputDecoration(labelText: 'Line narration'),
      onChanged: (value) => onChanged(line.copyWith(narration: value)),
    );

    final removeButton = IconButton(
      onPressed: canRemove ? onRemove : null,
      tooltip: 'Remove line',
      icon: const Icon(Icons.close_rounded),
    );

    if (isMobile) {
      return Container(
        margin: const EdgeInsets.only(bottom: ApexSpacing.md),
        padding: const EdgeInsets.all(ApexSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(ApexRadius_md),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            accountField,
            const SizedBox(height: ApexSpacing.md),
            Row(
              children: [
                Expanded(child: directionField),
                const SizedBox(width: ApexSpacing.md),
                Expanded(child: amountField),
                removeButton,
              ],
            ),
            const SizedBox(height: ApexSpacing.md),
            narrationField,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: ApexSpacing.sm),
      child: Row(
        children: [
          Expanded(flex: 38, child: accountField),
          const SizedBox(width: ApexSpacing.sm),
          Expanded(flex: 16, child: directionField),
          const SizedBox(width: ApexSpacing.sm),
          Expanded(flex: 16, child: amountField),
          const SizedBox(width: ApexSpacing.sm),
          Expanded(flex: 24, child: narrationField),
          removeButton,
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.value,
    required this.colors,
    this.danger = false,
  });

  final String label;
  final double value;
  final ApexColors colors;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: TextStyle(
            color: danger ? colors.danger : colors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}
