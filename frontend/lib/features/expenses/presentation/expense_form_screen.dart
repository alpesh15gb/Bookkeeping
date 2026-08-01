/// Expense creation form screen with receipt upload, vendor autocomplete,
/// and GST calculation.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/design_system/layouts/apex_scaffold.dart';
import 'package:apexbooks/features/masters/accounts/data/models/account.dart';
import 'package:apexbooks/features/masters/accounts/presentation/account_controller.dart';
import 'package:apexbooks/features/masters/expense_categories/data/models/expense_category.dart';
import 'package:apexbooks/features/masters/expense_categories/presentation/expense_category_controller.dart';
import 'expense_form_notifier.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});
  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(expenseCategoryControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
      ref
          .read(accountControllerProvider.notifier)
          .load(const ListQuery(limit: 100));
    });
  }

  Future<void> _save() async {
    final saved = await ref.read(expenseFormProvider.notifier).save();
    if (saved && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(expenseFormProvider);
    final notifier = ref.read(expenseFormProvider.notifier);
    final colors = apexColors(context);

    final categoryState = ref.watch(expenseCategoryControllerProvider);
    final accountState = ref.watch(accountControllerProvider);

    final categories = categoryState is ListData<ExpenseCategory>
        ? categoryState.paged.items.where((c) => c.isActive).toList()
        : <ExpenseCategory>[];
    final accounts = accountState is ListData<Account>
        ? accountState.paged.items
              .where((a) => a.isActive && a.accountGroup == 'Cash & Bank')
              .toList()
        : <Account>[];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: ApexFormScaffold(
          title: 'New Expense',
          error: state.error,
          bottomBar: _buildBottomBar(state, colors),
          children: [
            // Main form card
            Card(
              color: colors.surfaceRaised,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ApexRadius.lg),
                side: BorderSide(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final twoCol = c.maxWidth >= 600;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: twoCol ? 400 : double.infinity,
                          child: DropdownButtonFormField<String>(
                            initialValue: state.categoryId,
                            decoration: const InputDecoration(
                              labelText: 'Expense category *',
                            ),
                            items: categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                )
                                .toList(),
                            onChanged: notifier.setCategory,
                          ),
                        ),
                        SizedBox(
                          width: twoCol ? 200 : double.infinity,
                          child: _DateField(
                            date: state.date,
                            colors: colors,
                            onChanged: notifier.setDate,
                          ),
                        ),
                        SizedBox(
                          width: twoCol ? 260 : double.infinity,
                          child: TextFormField(
                            initialValue: state.vendor,
                            decoration: const InputDecoration(
                              labelText: 'Paid to / vendor',
                            ),
                            onChanged: notifier.setVendor,
                          ),
                        ),
                        SizedBox(
                          width: twoCol ? 400 : double.infinity,
                          child: DropdownButtonFormField<String>(
                            initialValue: state.accountId,
                            decoration: const InputDecoration(
                              labelText: 'Paid from',
                              hintText: 'Default cash account',
                            ),
                            items: accounts
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a.id,
                                    child: Text('${a.code}  ${a.name}'),
                                  ),
                                )
                                .toList(),
                            onChanged: notifier.setAccount,
                          ),
                        ),
                        SizedBox(
                          width: twoCol ? 200 : double.infinity,
                          child: TextFormField(
                            initialValue: state.amount == 0
                                ? ''
                                : state.amount.toString(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Taxable amount *',
                            ),
                            onChanged: (v) =>
                                notifier.setAmount(double.tryParse(v) ?? 0),
                          ),
                        ),
                        SizedBox(
                          width: twoCol ? 160 : double.infinity,
                          child: DropdownButtonFormField<double>(
                            initialValue: state.gstRate,
                            decoration: const InputDecoration(
                              labelText: 'GST rate',
                            ),
                            items:
                                const <double>[
                                      0,
                                      0.1,
                                      0.25,
                                      1,
                                      1.5,
                                      3,
                                      5,
                                      6,
                                      7.5,
                                      12,
                                      18,
                                      28,
                                    ]
                                    .map(
                                      (r) => DropdownMenuItem(
                                        value: r,
                                        child: Text('$r%'),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) => notifier.setGstRate(v ?? 0),
                          ),
                        ),
                        if (state.gstRate > 0)
                          SizedBox(
                            width: twoCol ? 180 : double.infinity,
                            child: TextFormField(
                              maxLength: 2,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Place of supply',
                                hintText: 'GST state code',
                              ),
                              onChanged: notifier.setPlaceOfSupply,
                            ),
                          ),
                        SizedBox(
                          width: twoCol ? 220 : double.infinity,
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Receipt / reference no.',
                            ),
                            onChanged: notifier.setReference,
                          ),
                        ),
                        SizedBox(
                          width: twoCol ? 620 : double.infinity,
                          child: TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Description',
                            ),
                            onChanged: notifier.setDescription,
                          ),
                        ),
                        // Receipt upload placeholder
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Receipt upload coming soon.'),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 18,
                            ),
                            label: const Text('Upload receipt (PDF, JPG, PNG)'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            // Help text
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Saving creates a reviewable draft. Use Post from the expense list after checking the receipt and GST details.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ExpenseFormState state, ApexColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // GST summary
          if (state.gstRate > 0) ...[
            _tot('Taxable', state.amount.toStringAsFixed(2), colors),
            const SizedBox(width: 20),
            _tot(
              'GST @${state.gstRate}%',
              state.gstAmount.toStringAsFixed(2),
              colors,
            ),
            const SizedBox(width: 20),
          ],
          const Spacer(),
          _tot(
            'Total',
            state.totalAmount.toStringAsFixed(2),
            colors,
            emphasize: true,
          ),
          const SizedBox(width: 20),
          FilledButton.icon(
            onPressed: state.saving ? null : _save,
            icon: state.saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save draft  (Ctrl+S)'),
          ),
        ],
      ),
    );
  }

  Widget _tot(
    String label,
    String value,
    ApexColors colors, {
    bool emphasize = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: colors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(
          fontSize: emphasize ? 18 : 14,
          fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
          color: emphasize ? colors.primary : colors.textPrimary,
        ),
      ),
    ],
  );
}

// ── Date field ───────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.colors,
    required this.onChanged,
  });
  final String date;
  final ApexColors colors;
  final ValueChanged<String> onChanged;

  DateTime? _parse(String s) => DateTime.tryParse(s);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(ApexRadius.sm),
      onTap: () async {
        final init = _parse(date) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: init,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onChanged(
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Expense date *',
          prefixIcon: Icon(
            Icons.calendar_today_rounded,
            size: 16,
            color: colors.textMuted,
          ),
          isDense: true,
        ),
        child: Text(
          date.isEmpty ? 'Select…' : date,
          style: TextStyle(
            color: date.isEmpty ? colors.textMuted : colors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
