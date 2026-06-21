import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/banking_profile_provider.dart';
import '../../../providers/bank_reconciliation_provider.dart';
import '../../../providers/cash_book_provider.dart';
import '../../../providers/accounting_provider.dart';
import '../../../views/banking/banking_profile_form_view.dart';

String _formatDate(String date) {
  if (date.isEmpty) return '-';
  try {
    final d = DateTime.parse(date);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
  } catch (_) {
    return date;
  }
}

String _formatAmount(dynamic amount) {
  final val = double.tryParse((amount ?? 0).toString()) ?? 0.0;
  if (val >= 10000000) return '₹${(val / 10000000).toStringAsFixed(1)}Cr';
  if (val >= 100000) return '₹${(val / 100000).toStringAsFixed(1)}L';
  if (val >= 1000) return '₹${(val / 1000).toStringAsFixed(1)}K';
  return '₹${val.toStringAsFixed(0)}';
}

class BankingScreen extends StatefulWidget {
  const BankingScreen({super.key});
  @override
  State<BankingScreen> createState() => _BankingScreenState();
}

class _BankingScreenState extends State<BankingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankingProfileProvider>().fetchBankingProfiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankingProfileProvider>();
    final profiles = provider.profiles;
    final isLoading = provider.isLoading;

    double totalBalance = 0;
    for (final p in profiles) {
      final map = p is Map<String, dynamic> ? p : null;
      if (map != null && map['is_active'] != false) {
        totalBalance += double.tryParse((map['current_balance'] ?? 0).toString()) ?? 0.0;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Banking', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Bank Account', icon: Icons.add, onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => const BankingProfileFormView(defaultPrimary: true),
              ));
              if (mounted) {
                await context.read<BankingProfileProvider>().fetchBankingProfiles();
              }
            }),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppKpiCard(
                icon: Icons.account_balance,
                label: 'TOTAL BALANCE',
                value: _formatAmount(totalBalance),
                iconColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(
              child: AppKpiCard(
                icon: Icons.account_balance_wallet,
                label: 'ACCOUNTS',
                value: '${profiles.where((p) => (p is Map<String, dynamic> ? p['is_active'] : true) != false).length}',
                iconColor: AppColors.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Expanded(
          child: isLoading && profiles.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : profiles.isEmpty
                  ? AppEmptyState(icon: Icons.account_balance, title: 'No bank accounts', subtitle: 'Add your first bank account')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Bank', width: 200),
                        TableColumn(label: 'Account #', width: 180),
                        TableColumn(label: 'IFSC', width: 120),
                        TableColumn(label: 'Balance', width: 140),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: profiles.map((p) {
                        final map = p is Map<String, dynamic> ? p : <String, dynamic>{};
                        final isActive = map['is_active'] != false;
                        final isPrimary = map['is_primary'] == true;
                        return AppTableRow(
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => BankingProfileFormView(profile: map),
                            ));
                            if (mounted) {
                              await context.read<BankingProfileProvider>().fetchBankingProfiles();
                            }
                          },
                          cells: [
                            Row(children: [
                              Text(map['bank_name'] ?? '-', style: AppTypography.bodyMedium),
                              if (isPrimary) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                  child: Text('Primary', style: AppTypography.labelSmall.copyWith(color: AppColors.primary, fontSize: 9)),
                                ),
                              ],
                            ]),
                            Text(map['account_number'] ?? '-', style: AppTypography.bodySmall),
                            Text(map['ifsc_code'] ?? '-', style: AppTypography.bodySmall),
                            Text(_formatAmount(map['current_balance']), style: AppTypography.amountTiny),
                            AppStatusBadge(
                              status: isActive ? InvoiceStatus.paid : InvoiceStatus.cancelled,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class BankReconciliationScreen extends StatefulWidget {
  const BankReconciliationScreen({super.key});
  @override
  State<BankReconciliationScreen> createState() => _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends State<BankReconciliationScreen> {
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankReconciliationProvider>().fetchStatements();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankReconciliationProvider>();
    final statements = provider.statements;
    final isLoading = provider.isLoading;

    final filtered = _selectedStatus != null
        ? statements.where((s) {
            final map = s is Map<String, dynamic> ? s : <String, dynamic>{};
            return map['status']?.toString().toUpperCase() == _selectedStatus!.toUpperCase();
          }).toList()
        : statements;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Bank Reconciliation', style: AppTypography.headlineLarge),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: statements.length, isSelected: _selectedStatus == null, onTap: () => setState(() => _selectedStatus = null)),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Pending', count: statements.where((s) => (s is Map ? s['status'] : '').toString().toUpperCase() == 'PENDING').length, selectedColor: AppColors.warning, isSelected: _selectedStatus == 'PENDING', onTap: () => setState(() => _selectedStatus = 'PENDING')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Reconciled', count: statements.where((s) => (s is Map ? s['status'] : '').toString().toUpperCase() == 'RECONCILED').length, selectedColor: AppColors.success, isSelected: _selectedStatus == 'RECONCILED', onTap: () => setState(() => _selectedStatus = 'RECONCILED')),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && statements.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? AppEmptyState(icon: Icons.receipt_long, title: 'No statements', subtitle: 'Upload a bank statement to begin reconciliation')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Statement', width: 200),
                        TableColumn(label: 'Bank', width: 150),
                        TableColumn(label: 'Transactions', width: 120),
                        TableColumn(label: 'Status', width: 120),
                      ],
                      rows: filtered.map((s) {
                        final map = s is Map<String, dynamic> ? s : <String, dynamic>{};
                        final status = (map['status'] ?? 'PENDING').toString().toUpperCase();
                        return AppTableRow(
                          cells: [
                            Text(map['file_name'] ?? map['statement_date'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['bank_name'] ?? '', style: AppTypography.bodyMedium),
                            Text('${map['transaction_count'] ?? 0}', style: AppTypography.bodySmall),
                            AppStatusBadge(status: status == 'RECONCILED' ? InvoiceStatus.paid : InvoiceStatus.pending),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class CashBookScreen extends StatefulWidget {
  const CashBookScreen({super.key});
  @override
  State<CashBookScreen> createState() => _CashBookScreenState();
}

class _CashBookScreenState extends State<CashBookScreen> {
  late String _startDate;
  late String _endDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _startDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CashBookProvider>().fetchCashBook(_startDate, _endDate);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CashBookProvider>();
    final data = provider.data;
    final isLoading = provider.isLoading;

    final summary = data?.summary;
    final inflows = data?.inflows ?? [];
    final outflows = data?.outflows ?? [];
    final allEntries = [...inflows, ...outflows];
    allEntries.sort((a, b) => a.date.compareTo(b.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Cash Book', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: 'Export Excel', icon: Icons.download, style: AppButtonStyle.secondary, onPressed: () async {
              final bytes = await provider.downloadExcel(_startDate, _endDate);
              if (bytes != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Excel downloaded'), backgroundColor: AppColors.success),
                );
              }
            }),
            const SizedBox(width: AppSpacing.sm),
            AppButton(label: 'Export PDF', icon: Icons.picture_as_pdf, style: AppButtonStyle.secondary, onPressed: () async {
              final bytes = await provider.downloadPdf(_startDate, _endDate);
              if (bytes != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF downloaded'), backgroundColor: AppColors.success),
                );
              }
            }),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: AppKpiCard(icon: Icons.arrow_downward, label: 'CASH INFLOW', value: _formatAmount(summary?.cashInflow ?? 0), iconColor: AppColors.success)),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(child: AppKpiCard(icon: Icons.arrow_upward, label: 'CASH OUTFLOW', value: _formatAmount(summary?.cashOutflow ?? 0), iconColor: AppColors.error)),
            const SizedBox(width: AppSpacing.kpiGap),
            Expanded(child: AppKpiCard(icon: Icons.account_balance_wallet, label: 'CLOSING', value: _formatAmount(summary?.closingBalance ?? 0), iconColor: AppColors.primary)),
          ],
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : allEntries.isEmpty
                  ? AppEmptyState(icon: Icons.receipt, title: 'No cash book entries', subtitle: 'Entries will appear here')
                  : AppTable(
                      columns: [
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Details', width: 300),
                        TableColumn(label: 'Amount', width: 140),
                      ],
                      rows: allEntries.map((e) {
                        final isInflow = inflows.contains(e);
                        return AppTableRow(
                          cells: [
                            Text(_formatDate(e.date), style: AppTypography.bodySmall),
                            Text(e.transactionDetails, style: AppTypography.bodyMedium),
                            Text(
                              '${isInflow ? '+' : '-'}${_formatAmount(e.amount)}',
                              style: AppTypography.amountTiny.copyWith(
                                color: isInflow ? AppColors.success : AppColors.error,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class JournalEntriesScreen extends StatefulWidget {
  const JournalEntriesScreen({super.key});
  @override
  State<JournalEntriesScreen> createState() => _JournalEntriesScreenState();
}

class _JournalEntriesScreenState extends State<JournalEntriesScreen> {
  List<dynamic> _journals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final journals = await context.read<AccountingProvider>().fetchJournals();
      if (mounted) {
        setState(() {
          _journals = journals;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Journal Entries', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Journal Entry', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _journals.isEmpty
                  ? AppEmptyState(icon: Icons.book, title: 'No journal entries', subtitle: 'Create your first journal entry')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Entry #', width: 120),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Description', width: 250),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Status', width: 100),
                      ],
                      rows: _journals.map((e) {
                        final map = e is Map<String, dynamic> ? e : <String, dynamic>{};
                        final total = double.tryParse((map['total_debit'] ?? map['total'] ?? 0).toString()) ?? 0.0;
                        return AppTableRow(
                          cells: [
                            Text(map['entry_number'] ?? map['journal_number'] ?? '-', style: AppTypography.labelLarge),
                            Text(_formatDate(map['entry_date'] ?? map['date'] ?? ''), style: AppTypography.bodySmall),
                            Text(map['description'] ?? map['narration'] ?? '', style: AppTypography.bodySmall, overflow: TextOverflow.ellipsis),
                            Text(_formatAmount(total), style: AppTypography.amountTiny),
                            AppStatusBadge(status: (map['status'] ?? 'DRAFT') == 'POSTED' ? InvoiceStatus.paid : InvoiceStatus.draft),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}

class ChartOfAccountsScreen extends StatefulWidget {
  const ChartOfAccountsScreen({super.key});
  @override
  State<ChartOfAccountsScreen> createState() => _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState extends State<ChartOfAccountsScreen> {
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AccountingProvider>().fetchAccounts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AccountingProvider>();
    final accounts = provider.accountsList ?? [];
    final isLoading = provider.isLoading;

    final filtered = _selectedType != null
        ? accounts.where((a) {
            final map = a is Map<String, dynamic> ? a : <String, dynamic>{};
            return map['account_type']?.toString().toUpperCase() == _selectedType!.toUpperCase();
          }).toList()
        : accounts;

    final assetCount = accounts.where((a) => (a is Map ? a['account_type'] : '').toString().toUpperCase() == 'ASSET').length;
    final liabCount = accounts.where((a) => (a is Map ? a['account_type'] : '').toString().toUpperCase() == 'LIABILITY').length;
    final incomeCount = accounts.where((a) => (a is Map ? a['account_type'] : '').toString().toUpperCase() == 'INCOME').length;
    final expCount = accounts.where((a) => (a is Map ? a['account_type'] : '').toString().toUpperCase() == 'EXPENSE').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Chart of Accounts', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Account', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: accounts.length, isSelected: _selectedType == null, onTap: () => setState(() => _selectedType = null)),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Assets', count: assetCount, isSelected: _selectedType == 'ASSET', onTap: () => setState(() => _selectedType = 'ASSET')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Liabilities', count: liabCount, isSelected: _selectedType == 'LIABILITY', onTap: () => setState(() => _selectedType = 'LIABILITY')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Income', count: incomeCount, isSelected: _selectedType == 'INCOME', onTap: () => setState(() => _selectedType = 'INCOME')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Expenses', count: expCount, isSelected: _selectedType == 'EXPENSE', onTap: () => setState(() => _selectedType = 'EXPENSE')),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && accounts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? AppEmptyState(icon: Icons.account_tree, title: 'No accounts', subtitle: 'Set up your chart of accounts')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Code', width: 100),
                        TableColumn(label: 'Account Name', width: 250),
                        TableColumn(label: 'Type', width: 120),
                        TableColumn(label: 'Balance', width: 140),
                      ],
                      rows: filtered.map((a) {
                        final map = a is Map<String, dynamic> ? a : <String, dynamic>{};
                        final balance = double.tryParse((map['balance'] ?? 0).toString()) ?? 0.0;
                        return AppTableRow(
                          cells: [
                            Text(map['code'] ?? '-', style: AppTypography.labelLarge),
                            Text(map['name'] ?? '', style: AppTypography.bodyMedium),
                            Text(map['account_type'] ?? '', style: AppTypography.bodySmall),
                            Text(_formatAmount(balance), style: AppTypography.amountTiny),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }
}
