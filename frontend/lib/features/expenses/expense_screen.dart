import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/api/base_model.dart';
import 'package:apexbooks/core/crud/base_crud.dart';
import 'package:apexbooks/core/network/api_client.dart';
import 'package:apexbooks/core/network/dio_extensions.dart';
import 'package:apexbooks/core/result/result.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/widgets/page_header.dart';
import 'package:apexbooks/core/widgets/states.dart';
import 'package:apexbooks/core/widgets/status_badge.dart';
import 'package:apexbooks/features/masters/accounts/data/models/account.dart';
import 'package:apexbooks/features/masters/accounts/presentation/account_controller.dart';
import 'package:apexbooks/features/masters/expense_categories/data/models/expense_category.dart';
import 'package:apexbooks/features/masters/expense_categories/presentation/expense_category_controller.dart';
import 'package:apexbooks/core/errors/user_message.dart';

double _amount(dynamic value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.number,
    required this.date,
    required this.amount,
    required this.total,
    required this.status,
    this.category,
    this.vendor,
    this.description,
  });
  final String id;
  final String number;
  final String date;
  final double amount;
  final double total;
  final String status;
  final String? category;
  final String? vendor;
  final String? description;

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) => ExpenseRecord(
    id: (json['id'] ?? '').toString(),
    number: json['expense_number'] as String? ?? '',
    date: json['expense_date'] as String? ?? '',
    amount: _amount(json['amount']),
    total: _amount(json['total']),
    status: json['status'] as String? ?? 'DRAFT',
    category: json['category_name'] as String?,
    vendor: json['vendor_name'] as String?,
    description: json['description'] as String?,
  );
}

class ExpenseService {
  ExpenseService(this._dio);
  final Dio _dio;

  Future<Result<List<ExpenseRecord>>> list() => guardDio(() async {
    final response = await _dio.get(
      '/expenses',
      queryParameters: {'limit': 100},
    );
    return (response.data as List)
        .map((row) => ExpenseRecord.fromJson(row as Map<String, dynamic>))
        .toList();
  });

  Future<Result<ExpenseRecord>> create(Map<String, dynamic> body) =>
      guardDio(() async {
        final response = await _dio.post('/expenses', data: body);
        return ExpenseRecord.fromJson(response.data as Map<String, dynamic>);
      });

  Future<Result<ExpenseRecord>> action(String id, String action) =>
      guardDio(() async {
        final response = await _dio.post('/expenses/$id/$action');
        return ExpenseRecord.fromJson(response.data as Map<String, dynamic>);
      });
}

final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(ref.watch(apiClientProvider)),
);
final expenseListProvider = FutureProvider.autoDispose<List<ExpenseRecord>>((
  ref,
) async {
  final result = await ref.watch(expenseServiceProvider).list();
  return switch (result) {
    Success(:final value) => value,
    Failure(:final error) => throw error,
    _ => <ExpenseRecord>[],
  };
});

class ExpenseScreen extends ConsumerWidget {
  const ExpenseScreen({super.key});

  Future<void> _newExpense(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ExpenseFormScreen()));
    if (created == true) ref.invalidate(expenseListProvider);
  }

  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    ExpenseRecord expense,
    String action,
  ) async {
    final result = await ref
        .read(expenseServiceProvider)
        .action(expense.id, action);
    if (!context.mounted) return;
    if (result is Success<ExpenseRecord>) {
      ref.invalidate(expenseListProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'post'
                ? 'Expense posted to the ledger.'
                : 'Expense cancelled and reversed.',
          ),
        ),
      );
    } else if (result is Failure<ExpenseRecord>) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = apexColors(context);
    final expenses = ref.watch(expenseListProvider);
    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: Column(
        children: [
          PageHeader(
            title: 'Expenses',
            subtitle:
                'Record, review and post operating expenses with GST input credit.',
            actions: [
              FilledButton.icon(
                onPressed: () => _newExpense(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New expense'),
              ),
            ],
          ),
          Expanded(
            child: expenses.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorView(
                message: userFacingErrorMessage(error),
                onRetry: () => ref.invalidate(expenseListProvider),
              ),
              data: (rows) => rows.isEmpty
                  ? EmptyState(
                      icon: Icons.payments_outlined,
                      title: 'No expenses recorded',
                      subtitle:
                          'Record rent, utilities, travel and other operating costs.',
                      actionLabel: 'New expense',
                      onAction: () => _newExpense(context, ref),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.receipt_outlined),
                            ),
                            title: Text(
                              '${row.number}  ${row.category ?? 'Expense'}',
                            ),
                            subtitle: Text(
                              [
                                row.date,
                                if ((row.vendor ?? '').isNotEmpty) row.vendor!,
                                if ((row.description ?? '').isNotEmpty)
                                  row.description!,
                              ].join('  •  '),
                            ),
                            trailing: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                  '₹${row.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                StatusBadge(
                                  label: row.status,
                                  tone: row.status == 'POSTED'
                                      ? StatusTone.success
                                      : row.status == 'CANCELLED'
                                      ? StatusTone.danger
                                      : StatusTone.neutral,
                                ),
                                if (row.status == 'DRAFT' ||
                                    row.status == 'POSTED')
                                  PopupMenuButton<String>(
                                    onSelected: (value) =>
                                        _action(context, ref, row, value),
                                    itemBuilder: (_) => [
                                      if (row.status == 'DRAFT')
                                        const PopupMenuItem(
                                          value: 'post',
                                          child: Text('Review complete — post'),
                                        ),
                                      if (row.status == 'POSTED')
                                        const PopupMenuItem(
                                          value: 'cancel',
                                          child: Text('Cancel and reverse'),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});
  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  String? _categoryId;
  String? _accountId;
  late String _date;
  String _vendor = '';
  String _description = '';
  String _reference = '';
  String _pos = '';
  double _amount = 0;
  double _gstRate = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
    if (_saving) return;
    if (_categoryId == null ||
        _amount <= 0 ||
        DateTime.tryParse(_date) == null) {
      setState(
        () => _error =
            'Select a category and enter a valid date and positive amount.',
      );
      return;
    }
    if (_pos.isNotEmpty && !RegExp(r'^\d{2}$').hasMatch(_pos)) {
      setState(
        () => _error = 'Place of supply must be a two-digit GST state code.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref.read(expenseServiceProvider).create({
      'expense_category_id': _categoryId,
      if (_accountId != null) 'bank_account_id': _accountId,
      'expense_date': _date,
      if (_vendor.trim().isNotEmpty) 'vendor_name': _vendor.trim(),
      if (_description.trim().isNotEmpty) 'description': _description.trim(),
      'amount': _amount,
      'gst_rate': _gstRate,
      if (_pos.isNotEmpty) 'place_of_supply_state_code': _pos,
      if (_reference.trim().isNotEmpty) 'reference_number': _reference.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Success<ExpenseRecord>) {
      Navigator.of(context).pop(true);
    } else if (result is Failure<ExpenseRecord>) {
      setState(() => _error = result.error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final categoryState = ref.watch(expenseCategoryControllerProvider);
    final accountState = ref.watch(accountControllerProvider);
    final categories = categoryState is ListData<ExpenseCategory>
        ? categoryState.paged.items.where((item) => item.isActive).toList()
        : <ExpenseCategory>[];
    final accounts = accountState is ListData<Account>
        ? accountState.paged.items
              .where(
                (item) => item.isActive && item.accountGroup == 'Cash & Bank',
              )
              .toList()
        : <Account>[];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.surfaceMuted,
          appBar: AppBar(
            title: const Text('New Expense'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save draft  Ctrl+S'),
                ),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.danger),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: 400,
                            child: DropdownButtonFormField<String>(
                              initialValue: _categoryId,
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
                              onChanged: (value) =>
                                  setState(() => _categoryId = value),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextFormField(
                              initialValue: _date,
                              decoration: const InputDecoration(
                                labelText: 'Expense date *',
                              ),
                              onChanged: (value) => _date = value,
                            ),
                          ),
                          SizedBox(
                            width: 260,
                            child: TextFormField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'Paid to / vendor',
                              ),
                              onChanged: (value) => _vendor = value,
                            ),
                          ),
                          SizedBox(
                            width: 400,
                            child: DropdownButtonFormField<String>(
                              initialValue: _accountId,
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
                              onChanged: (value) =>
                                  setState(() => _accountId = value),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextFormField(
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                              onChanged: (value) =>
                                  _amount = double.tryParse(value) ?? 0,
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<double>(
                              initialValue: _gstRate,
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
                                        (rate) => DropdownMenuItem(
                                          value: rate,
                                          child: Text('$rate%'),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) =>
                                  setState(() => _gstRate = value ?? 0),
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            child: TextFormField(
                              maxLength: 2,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Place of supply',
                                hintText: 'GST state code',
                              ),
                              onChanged: (value) => _pos = value,
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Receipt / reference no.',
                              ),
                              onChanged: (value) => _reference = value,
                            ),
                          ),
                          SizedBox(
                            width: 620,
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'Description',
                              ),
                              onChanged: (value) => _description = value,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Saving creates a reviewable draft. Use Post from the expense list only after checking the receipt and GST details.',
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
