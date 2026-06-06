import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/bank_reconciliation_provider.dart';
import 'package:flutter_client/providers/banking_profile_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';

class BankReconciliationListView extends StatefulWidget {
  const BankReconciliationListView({super.key});

  @override
  State<BankReconciliationListView> createState() => _BankReconciliationListViewState();
}

class _BankReconciliationListViewState extends State<BankReconciliationListView> {
  String? _selectedStatementId;
  List<dynamic> _transactions = [];
  List<dynamic> _pendingInvoices = [];
  List<dynamic> _pendingBills = [];
  Map<String, dynamic>? _stats;
  bool _isLoadingTxns = false;
  Set<String> _selectedTxnIds = {};
  String _statusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BankReconciliationProvider>().fetchStatements();
      context.read<BankingProfileProvider>().fetchBankingProfiles();
    });
  }

  Future<void> _uploadStatement() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    // Pick banking profile
    final profileProvider = context.read<BankingProfileProvider>();
    if (profileProvider.profiles.isEmpty) {
      if (mounted) {
        AppToast.error(context, 'Add a banking profile first in Banking screen');
      }
      return;
    }

    String? profileId;
    if (profileProvider.profiles.length == 1) {
      profileId = profileProvider.profiles[0]['id'];
    } else {
      profileId = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select Bank Account'),
          children: profileProvider.profiles.map((p) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p['id']),
            child: ListTile(
              leading: const Icon(Icons.account_balance),
              title: Text(p['bank_name'] ?? ''),
              subtitle: Text(p['account_number'] ?? ''),
              contentPadding: EdgeInsets.zero,
            ),
          )).toList(),
        ),
      );
    }
    if (profileId == null) return;

    setState(() => _isLoadingTxns = true);
    try {
      final request = ApiClient().multipartRequest(
        '${ApiClient.baseUrl}/bank-reconciliation/upload?banking_profile_id=$profileId',
      );
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        final data = jsonDecode(body);
        if (mounted) {
          AppToast.success(context, 'Imported ${data['transactions_imported']} transactions');
          context.read<BankReconciliationProvider>().fetchStatements();
        }
      } else {
        if (mounted) AppToast.error(context, 'Import failed: $body');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Upload error: $e');
    }
    setState(() => _isLoadingTxns = false);
  }

  Future<void> _loadTransactions(String statementId) async {
    setState(() {
      _isLoadingTxns = true;
      _selectedStatementId = statementId;
      _selectedTxnIds.clear();
    });
    try {
      final provider = context.read<BankReconciliationProvider>();
      final txns = await provider.fetchStatementTransactions(statementId);
      final stats = await provider.fetchStatementStats(statementId);
      setState(() {
        _transactions = txns;
        _stats = stats;
      });
    } catch (e) {
      // ignore
    }
    setState(() => _isLoadingTxns = false);
  }

  Future<void> _autoMatch() async {
    if (_selectedStatementId == null) return;
    setState(() => _isLoadingTxns = true);
    try {
      final provider = context.read<BankReconciliationProvider>();
      final result = await provider.autoMatch(_selectedStatementId!);
      if (result != null && mounted) {
        AppToast.success(context, 'Auto-matched ${result['matched']} transactions');
        _loadTransactions(_selectedStatementId!);
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Auto-match failed: $e');
    }
    setState(() => _isLoadingTxns = false);
  }

  Future<void> _loadPendingDocuments() async {
    try {
      final provider = context.read<BankReconciliationProvider>();
      _pendingInvoices = await provider.fetchPendingInvoices();
      _pendingBills = await provider.fetchPendingBills();
    } catch (e) {
      // ignore
    }
  }

  Future<void> _manualReconcile(String txnId, String docType, String docId, String amount) async {
    final provider = context.read<BankReconciliationProvider>();
    final payload = {
      if (docType == 'payment') 'payment_id': docId,
      if (docType == 'bill_payment') 'bill_payment_id': docId,
      'amount': double.tryParse(amount) ?? 0,
    };
    final ok = await provider.reconcileTransaction(txnId, payload);
    if (ok) {
      if (mounted) AppToast.success(context, 'Reconciled');
      _loadTransactions(_selectedStatementId!);
    } else {
      if (mounted) AppToast.error(context, provider.errorMessage ?? 'Reconcile failed');
    }
  }

  Future<void> _bulkReconcile() async {
    if (_selectedTxnIds.isEmpty) return;
    await _loadPendingDocuments();

    for (final txnId in _selectedTxnIds) {
      final txn = _transactions.firstWhere((t) => t['id'].toString() == txnId, orElse: () => null);
      if (txn == null) continue;

      final result = await _showMatchDialog(txn);
      if (result != null) {
        await _manualReconcile(txnId, result['type']!, result['id']!, result['amount']!);
      }
    }
    setState(() => _selectedTxnIds.clear());
  }

  Future<Map<String, String>?> _showMatchDialog(Map<String, dynamic> txn) async {
    final txnAmount = txn['amount'].toString();
    final txnDate = txn['transaction_date'] ?? '';
    final txnDesc = txn['description'] ?? '';

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Match Transaction'),
        content: SizedBox(
          width: 500,
          height: 450,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: AppColors.bgLight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount: ₹$txnAmount', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700)),
                      Text('Date: $txnDate', style: AppTextStyles.caption),
                      if (txnDesc.isNotEmpty)
                        Text('Description: $txnDesc', style: AppTextStyles.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Select matching document:', style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        labelColor: AppColors.brandNavy,
                        indicatorColor: AppColors.brandNavy,
                        tabs: [
                          Tab(text: 'Invoices (${_pendingInvoices.length})'),
                          Tab(text: 'Bills (${_pendingBills.length})'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildDocList(_pendingInvoices, 'invoice', txnAmount, ctx),
                            _buildDocList(_pendingBills, 'bill', txnAmount, ctx),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildDocList(List<dynamic> docs, String type, String txnAmount, BuildContext ctx) {
    if (docs.isEmpty) {
      return Center(child: Text('No pending ${type}s'));
    }

    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        final number = type == 'invoice' ? doc['invoice_number'] : doc['bill_number'];
        final contactName = doc['contact_name'] ?? '';
        final outstanding = doc['outstanding'].toString();
        final dueDate = doc['due_date'] ?? '';
        final daysOverdue = doc['days_overdue'] ?? 0;
        final txnAmt = double.tryParse(txnAmount)?.abs() ?? 0;
        final outAmt = double.tryParse(outstanding) ?? 0;
        final isExactMatch = (txnAmt - outAmt).abs() < 0.01;

        return ListTile(
          leading: Icon(
            isExactMatch ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isExactMatch ? AppColors.success : AppColors.textMuted,
          ),
          title: Text('$number — $contactName', style: AppTextStyles.body.copyWith(fontSize: 13)),
          subtitle: Row(
            children: [
              Text('₹$outstanding', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('Due: $dueDate', style: AppTextStyles.caption),
              if (daysOverdue > 0) ...[
                const SizedBox(width: 8),
                Text('($daysOverdue days overdue)', style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              ],
            ],
          ),
          onTap: () => Navigator.pop(ctx, {
            'type': type == 'invoice' ? 'payment' : 'bill_payment',
            'id': doc['id'].toString(),
            'amount': outstanding,
          }),
        );
      },
    );
  }

  Future<void> _deleteStatement(String statementId) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Statement?',
      message: 'This will delete the statement and all its unreconciled transactions.',
    );
    if (confirm != true) return;

    final provider = context.read<BankReconciliationProvider>();
    final ok = await provider.deleteStatement(statementId);
    if (ok) {
      if (mounted) AppToast.success(context, 'Statement deleted');
      setState(() {
        _selectedStatementId = null;
        _transactions.clear();
        _stats = null;
      });
    } else {
      if (mounted) AppToast.error(context, provider.errorMessage ?? 'Delete failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankReconciliationProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: _selectedStatementId == null
          ? FloatingActionButton(
              onPressed: _uploadStatement,
              child: const Icon(Icons.upload_file),
            )
          : null,
      body: Column(
        children: [
          // Header
          AppCard(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.account_balance, color: AppColors.brandNavy, size: 20),
                const SizedBox(width: 8),
                Text('Bank Reconciliation', style: AppTextStyles.h2),
                const Spacer(),
                if (_selectedStatementId != null) ...[
                  if (!isMobile)
                    AppButton(
                      label: 'Auto Match',
                      icon: Icons.auto_fix_high,
                      isPrimary: true,
                      onTap: _autoMatch,
                    ),
                  if (!isMobile) const SizedBox(width: 8),
                  if (_selectedTxnIds.isNotEmpty)
                    AppButton(
                      label: 'Match (${_selectedTxnIds.length})',
                      icon: Icons.link,
                      onTap: _bulkReconcile,
                      color: AppColors.success,
                      isSmall: true,
                    ),
                  if (_selectedTxnIds.isNotEmpty) const SizedBox(width: 8),
                  AppButton(
                    label: isMobile ? '' : 'Back',
                    icon: Icons.arrow_back,
                    isSmall: true,
                    onTap: () {
                      setState(() {
                        _selectedStatementId = null;
                        _transactions.clear();
                        _stats = null;
                        _selectedTxnIds.clear();
                      });
                      provider.fetchStatements();
                    },
                  ),
                ] else if (isMobile) ...[
                  IconButton(
                    icon: const Icon(Icons.upload_file),
                    onPressed: _uploadStatement,
                  ),
                ] else ...[
                  AppButton(
                    label: 'Upload Statement',
                    icon: Icons.upload_file,
                    isPrimary: true,
                    onTap: _uploadStatement,
                  ),
                ],
              ],
            ),
          ),

          // Stats bar
          if (_stats != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 4),
              child: _buildStatsBar(),
            ),

          // Content
          Expanded(
            child: _isLoadingTxns
                ? const Center(child: CircularProgressIndicator())
                : _selectedStatementId != null
                    ? _buildTransactionList(isMobile)
                    : _buildStatementList(provider, isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final s = _stats!;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _stat('Total', '${s['total_transactions']}', AppColors.brandNavy),
          _stat('Reconciled', '${s['reconciled']}', AppColors.success),
          _stat('Pending', '${s['pending']}', AppColors.warning),
          _stat('Credits', '₹${s['total_credits']}', AppColors.info),
          _stat('Debits', '₹${s['total_debits']}', AppColors.error),
          _stat('Progress', '${s['reconciliation_pct']}%', AppColors.brandNavy),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textMuted, fontSize: 10)),
        Text(value, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
      ],
    );
  }

  Widget _buildStatementList(BankReconciliationProvider provider, bool isMobile) {
    if (provider.statements.isEmpty) {
      return AppEmptyState(
        icon: Icons.account_balance,
        title: 'No bank statements',
        subtitle: 'Upload a CSV or Excel bank statement to start reconciliation',
        actionLabel: 'Upload Statement',
        onAction: _uploadStatement,
      );
    }

    return RefreshIndicator(
      onRefresh: () async => provider.fetchStatements(),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 8),
        itemCount: provider.statements.length,
        itemBuilder: (context, i) {
          final stmt = provider.statements[i];
          return AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.brandNavy.withValues(alpha: 0.1),
                child: Icon(Icons.receipt_long, color: AppColors.brandNavy, size: 20),
              ),
              title: Text(
                stmt['bank_name'] ?? 'Bank Statement',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${stmt['account_number'] ?? ''} · ${stmt['statement_date'] ?? ''}',
                style: AppTextStyles.caption,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${stmt['ending_balance'] ?? 0}',
                        style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(stmt['status'] ?? '', style: AppTextStyles.caption),
                    ],
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert, size: 18),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    onSelected: (val) {
                      if (val == 'delete') _deleteStatement(stmt['id'].toString());
                    },
                  ),
                ],
              ),
              onTap: () => _loadTransactions(stmt['id'].toString()),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTransactionList(bool isMobile) {
    final filteredTxns = _statusFilter == 'ALL'
        ? _transactions
        : _transactions.where((t) => t['status'] == _statusFilter).toList();

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('ALL', _transactions.length),
                const SizedBox(width: 4),
                _filterChip('PENDING', _transactions.where((t) => t['status'] == 'PENDING').length),
                const SizedBox(width: 4),
                _filterChip('RECONCILED', _transactions.where((t) => t['status'] == 'RECONCILED').length),
              ],
            ),
          ),
        ),

        // Select all
        if (filteredTxns.any((t) => t['status'] == 'PENDING'))
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: _selectedTxnIds.length == filteredTxns.where((t) => t['status'] == 'PENDING').length &&
                         _selectedTxnIds.isNotEmpty,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedTxnIds = filteredTxns
                            .where((t) => t['status'] == 'PENDING')
                            .map((t) => t['id'].toString())
                            .toSet();
                      } else {
                        _selectedTxnIds.clear();
                      }
                    });
                  },
                ),
                Text('Select all pending', style: AppTextStyles.caption),
              ],
            ),
          ),

        // Transaction list
        Expanded(
          child: filteredTxns.isEmpty
              ? Center(child: Text('No transactions', style: AppTextStyles.body.copyWith(color: AppColors.textMuted)))
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 4),
                  itemCount: filteredTxns.length,
                  itemBuilder: (context, i) {
                    final txn = filteredTxns[i];
                    final id = txn['id'].toString();
                    final isSelected = _selectedTxnIds.contains(id);
                    final amount = double.tryParse(txn['amount'].toString()) ?? 0;
                    final isCredit = amount > 0;
                    final isReconciled = txn['status'] == 'RECONCILED';

                    return AppCard(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        leading: isReconciled
                            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                            : Checkbox(
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedTxnIds.add(id);
                                    } else {
                                      _selectedTxnIds.remove(id);
                                    }
                                  });
                                },
                              ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                txn['description'] ?? 'No description',
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: isReconciled ? FontWeight.normal : FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${isCredit ? '+' : '-'}₹${amount.abs().toStringAsFixed(2)}',
                              style: AppTextStyles.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isCredit ? AppColors.success : AppColors.error,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Text(txn['transaction_date'] ?? '', style: AppTextStyles.caption),
                            if (txn['reference_number'] != null && txn['reference_number'].toString().isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('Ref: ${txn['reference_number']}', style: AppTextStyles.caption),
                            ],
                            if (isReconciled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Reconciled', style: AppTextStyles.caption.copyWith(color: AppColors.success, fontSize: 10)),
                              ),
                            ],
                          ],
                        ),
                        onTap: isReconciled
                            ? null
                            : () async {
                                await _loadPendingDocuments();
                                final result = await _showMatchDialog(txn);
                                if (result != null) {
                                  await _manualReconcile(id, result['type']!, result['id']!, result['amount']!);
                                }
                              },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, int count) {
    return FilterChip(
      label: Text('$label ($count)', style: const TextStyle(fontSize: 12)),
      selected: _statusFilter == label,
      selectedColor: AppColors.brandNavy.withValues(alpha: 0.15),
      onSelected: (_) => setState(() => _statusFilter = label),
    );
  }
}
