import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/features/masters/accounts/data/models/account.dart';
import 'package:apexbooks/features/masters/accounts/presentation/account_controller.dart';
import '../models/direction.dart';
import '../models/journal_entry.dart';
import '../models/journal_line.dart';
import '../services/journal_service.dart';

class JournalFormScreen extends ConsumerStatefulWidget {
  const JournalFormScreen({super.key});

  @override
  ConsumerState<JournalFormScreen> createState() => _JournalFormScreenState();
}

class _JournalFormScreenState extends ConsumerState<JournalFormScreen> {
  late String _date;
  String _reference = '';
  String _description = '';
  bool _saving = false;
  String? _error;
  List<JournalLine> _lines = const [
    JournalLine(direction: Direction.debit),
    JournalLine(direction: Direction.credit),
  ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _date =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    Future.microtask(
      () => ref
          .read(accountControllerProvider.notifier)
          .load(const ListQuery(limit: 100)),
    );
  }

  double get _debit => _lines
      .where((line) => line.direction.isDebit)
      .fold(0, (sum, line) => sum + line.amount);
  double get _credit => _lines
      .where((line) => line.direction.isCredit)
      .fold(0, (sum, line) => sum + line.amount);

  void _update(int index, JournalLine line) {
    setState(() => _lines = [..._lines]..[index] = line);
  }

  Future<void> _save() async {
    if (_saving) return;
    final difference = (_debit - _credit).abs();
    if (DateTime.tryParse(_date) == null) {
      setState(() => _error = 'Enter a valid posting date.');
      return;
    }
    if (_description.trim().isEmpty) {
      setState(() => _error = 'Enter a clear journal narration.');
      return;
    }
    if (_lines.length < 2 || _lines.any((line) => !line.isValid)) {
      setState(
        () => _error = 'Select an account and positive amount on every line.',
      );
      return;
    }
    if (_debit <= 0 || difference >= 0.005) {
      setState(
        () => _error =
            'Journal is out of balance. Debit and credit totals must match.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(journalServiceProvider)
        .create(
          JournalEntry(
            id: '',
            entryDate: _date,
            referenceNumber: _reference.trim(),
            description: _description.trim(),
            lines: _lines,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Success<JournalEntry>) {
      Navigator.of(context).pop(true);
    } else if (result is Failure<JournalEntry>) {
      setState(() => _error = result.error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final accountState = ref.watch(accountControllerProvider);
    final accounts = accountState is ListData<Account>
        ? accountState.paged.items.where((account) => account.isActive).toList()
        : <Account>[];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyN, alt: true): () =>
            setState(() => _lines = [..._lines, const JournalLine()]),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surfaceMuted,
          appBar: AppBar(
            title: const Text('New Journal Entry'),
            actions: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Post journal  Ctrl+S'),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      color: colors.danger.withValues(alpha: .1),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.danger),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 180,
                            child: TextFormField(
                              initialValue: _date,
                              decoration: const InputDecoration(
                                labelText: 'Posting date *',
                              ),
                              onChanged: (value) => _date = value,
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Reference',
                                hintText: 'Auto-generated if blank',
                              ),
                              onChanged: (value) => _reference = value,
                            ),
                          ),
                          SizedBox(
                            width: 500,
                            child: TextFormField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'Narration *',
                              ),
                              onChanged: (value) => _description = value,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          ..._lines.asMap().entries.map(
                            (entry) => _JournalLineEditor(
                              key: ValueKey('journal-line-${entry.key}'),
                              line: entry.value,
                              accounts: accounts,
                              canRemove: _lines.length > 2,
                              onChanged: (line) => _update(entry.key, line),
                              onRemove: () => setState(
                                () => _lines = [..._lines]..removeAt(entry.key),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => _lines = [..._lines, const JournalLine()],
                              ),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add line  Alt+N'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _Total(label: 'Debit', value: _debit, colors: colors),
                      const SizedBox(width: 24),
                      _Total(label: 'Credit', value: _credit, colors: colors),
                      const SizedBox(width: 24),
                      _Total(
                        label: 'Difference',
                        value: _debit - _credit,
                        colors: colors,
                        danger: (_debit - _credit).abs() >= .005,
                      ),
                    ],
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 900 ? 900 : constraints.maxWidth,
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  initialValue: line.accountId.isEmpty ? null : line.accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: accounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            '${a.code}  ${a.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    final account = accounts
                        .where((a) => a.id == id)
                        .firstOrNull;
                    if (account != null) {
                      onChanged(
                        JournalLine(
                          accountId: account.id,
                          accountName: account.name,
                          accountCode: account.code,
                          amount: line.amount,
                          direction: line.direction,
                          narration: line.narration,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<Direction>(
                  initialValue: line.direction,
                  decoration: const InputDecoration(labelText: 'Dr / Cr'),
                  items: const [
                    DropdownMenuItem(
                      value: Direction.debit,
                      child: Text('Debit'),
                    ),
                    DropdownMenuItem(
                      value: Direction.credit,
                      child: Text('Credit'),
                    ),
                  ],
                  onChanged: (value) => onChanged(
                    JournalLine(
                      accountId: line.accountId,
                      accountName: line.accountName,
                      accountCode: line.accountCode,
                      amount: line.amount,
                      direction: value ?? line.direction,
                      narration: line.narration,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: TextFormField(
                  initialValue: line.amount == 0
                      ? ''
                      : line.amount.toStringAsFixed(2),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(labelText: 'Amount'),
                  onChanged: (value) => onChanged(
                    JournalLine(
                      accountId: line.accountId,
                      accountName: line.accountName,
                      accountCode: line.accountCode,
                      amount: double.tryParse(value) ?? 0,
                      direction: line.direction,
                      narration: line.narration,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextFormField(
                  initialValue: line.narration,
                  decoration: const InputDecoration(
                    labelText: 'Line narration',
                  ),
                  onChanged: (value) => onChanged(
                    JournalLine(
                      accountId: line.accountId,
                      accountName: line.accountName,
                      accountCode: line.accountCode,
                      amount: line.amount,
                      direction: line.direction,
                      narration: value,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                tooltip: 'Remove line',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: colors.textMuted)),
      Text(
        value.toStringAsFixed(2),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: danger ? colors.danger : colors.textPrimary,
        ),
      ),
    ],
  );
}
