import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/core/api_client.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';
import 'package:flutter_client/views/invoices/invoice_detail_view.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/utils/download_stub.dart' if (dart.library.html) 'package:flutter_client/utils/download_web.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/core/print_share_helper.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';

class InvoiceListView extends StatefulWidget {
  const InvoiceListView({super.key});

  @override
  State<InvoiceListView> createState() => _InvoiceListViewState();
}

class _InvoiceListViewState extends State<InvoiceListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  final _statusOptions = ['ALL', 'DRAFT', 'SENT', 'PARTIALLY_PAID', 'PAID', 'CANCELLED'];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetch());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch() {
    String? apiStatus = _statusFilter == 'ALL' ? null : _statusFilter;
    if (apiStatus == 'SENT') apiStatus = 'POSTED';
    context.read<InvoiceProvider>().fetchInvoices(
      search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
      status: apiStatus,
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    final provider = context.read<InvoiceProvider>();
    setState(() {
      if (_selectedIds.length == provider.invoices.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = provider.invoices.map((e) => e.id.toString()).toSet();
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _bulkDelete() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete ${_selectedIds.length} items?',
      message: 'This action cannot be undone.',
    );
    if (confirm == true) {
      final provider = context.read<InvoiceProvider>();
      for (final id in _selectedIds) {
        await provider.deleteInvoice(id);
      }
      _clearSelection();
      _fetch();
    }
  }

  void _bulkCancel() async {
    final provider = context.read<InvoiceProvider>();
    final cancellable = _selectedIds.where((id) {
      final match = provider.invoices.where((i) => i.id.toString() == id);
      if (match.isEmpty) return false;
      final inv = match.first;
      return inv.status == 'POSTED' || inv.status == 'PARTIALLY_PAID';
    }).toList();
    if (cancellable.isEmpty) {
      AppToast.info(context, 'No cancellable invoices selected (only Sent/Partial can be cancelled)');
      return;
    }
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${cancellable.length} invoices?',
      message: 'This will reverse ledger entries for each selected invoice.',
    );
    if (confirm == true) {
      int successCount = 0;
      for (final id in cancellable) {
        final ok = await provider.cancelInvoice(id);
        if (ok) successCount++;
      }
      if (mounted) {
        AppToast.info(context, '$successCount of ${cancellable.length} invoices cancelled');
      }
      _clearSelection();
      _fetch();
    }
  }

  void _bulkEmail() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Email ${_selectedIds.length} invoices?',
      message: 'Invoice PDFs will be emailed to each customer.',
    );
    if (confirm == true) {
      int successCount = 0;
      for (final id in _selectedIds) {
        try {
          final response = await ApiClient().post(
            Uri.parse('${ApiClient.baseUrl}/invoices/$id/email'),
          );
          if (response.statusCode == 200) successCount++;
        } catch (_) {}
      }
      if (mounted) {
        AppToast.info(context, '$successCount of ${_selectedIds.length} emails queued');
      }
      _clearSelection();
    }
  }

  void _showForm({InvoiceModel? invoice}) async {
    InvoiceModel? fullInvoice = invoice;
    if (invoice != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      fullInvoice = await context.read<InvoiceProvider>().fetchInvoiceDetail(invoice.id);
      if (mounted) Navigator.pop(context);
      if (fullInvoice == null) {
        if (mounted) AppToast.error(context, 'Failed to load invoice details');
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => InvoiceFormView(editInvoice: fullInvoice)),
      ).then((_) => _fetch());
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: id)),
    ).then((_) => _fetch());
  }

  String _balanceLabel(InvoiceModel invoice) {
    if (invoice.status == 'PAID') return 'Paid';
    if (invoice.status == 'PARTIALLY_PAID') return 'Partial';
    return 'Unpaid';
  }

  num _balanceAmount(InvoiceModel invoice) {
    return invoice.total - invoice.amountPaid;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InvoiceProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);
    final invoices = provider.invoices;

    // Compute stats
    final totalCount = invoices.length;
    final draftCount = invoices.where((i) => i.status == 'DRAFT').length;
    final sentCount = invoices.where((i) => i.status == 'SENT').length;
    final paidCount = invoices.where((i) => i.status == 'PAID').length;
    final partialCount = invoices.where((i) => i.status == 'PARTIALLY_PAID').length;
    final cancelledCount = invoices.where((i) => i.status == 'CANCELLED').length;

    // Compute amounts
    num totalAmount = 0;
    num collectedAmount = 0;
    num outstandingAmount = 0;
    num overdueAmount = 0;
    for (final inv in invoices) {
      totalAmount += inv.total;
      collectedAmount += inv.amountPaid;
      final balance = inv.total - inv.amountPaid;
      if (balance > 0) {
        outstandingAmount += balance;
        if (inv.status == 'PARTIALLY_PAID' && inv.dueDate != null && DateTime.tryParse(inv.dueDate!)?.isBefore(DateTime.now()) == true) overdueAmount += balance;
      }
    }

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showForm(),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  AppInput(
                    controller: _searchCtrl,
                    hint: 'Search invoices...',
                    prefix: const Icon(Icons.search_rounded, size: 18),
                    suffix: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              _fetch();
                            },
                          )
                        : null,
                    onSubmitted: (_) => _fetch(),
                    onChanged: (v) {
                      if (v.isEmpty) _fetch();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            AppStatusTabBar(
              tabs: const ['ALL', 'DRAFT', 'SENT', 'PAID', 'PARTIALLY_PAID', 'CANCELLED'],
              activeTab: _statusFilter,
              onTabChanged: (tab) {
                setState(() => _statusFilter = tab);
                _fetch();
              },
              badges: {
                'ALL': totalCount,
                'DRAFT': draftCount,
                'SENT': sentCount,
                'PAID': paidCount,
                'PARTIALLY_PAID': partialCount,
                'CANCELLED': cancelledCount,
              },
            ),
            Expanded(
              child: provider.isLoading && invoices.isEmpty
                  ? const ListSkeleton()
                  : provider.errorMessage != null && invoices.isEmpty
                      ? ErrorState(message: provider.errorMessage!, onRetry: _fetch)
                      : invoices.isEmpty
                          ? AppEmptyState(
                              icon: Icons.description_outlined,
                              title: 'No invoices found',
                              subtitle: _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
                                  ? 'Try clearing your filters'
                                  : 'Create your first invoice to get started',
                              actionLabel: 'Create Invoice',
                              onAction: () => _showForm(),
                            )
                          : RefreshIndicator(
                              onRefresh: () async => _fetch(),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: invoices.length,
                                separatorBuilder: (context, _) => const SizedBox(height: 4),
                                itemBuilder: (context, i) {
                                  final invoice = invoices[i];
                                  final id = invoice.id.toString();
                                  final isSelected = _selectedIds.contains(id);
                                  final partyName = invoice.contactName ?? invoice.contact?.name ?? '';
                                  final bal = _balanceAmount(invoice);

                                  return _buildSwipeableInvoice(
                                    invoice,
                                    CompactDocumentCard(
                                      docNumber: invoice.invoiceNumber,
                                      partyName: partyName.isNotEmpty ? partyName : null,
                                      date: invoice.issueDate,
                                      amount: invoice.total,
                                      status: invoice.status,
                                      balanceLabel: _balanceLabel(invoice),
                                      balanceAmount: bal > 0 ? bal : null,
                                      isSelected: isSelected,
                                      isSelectionMode: _isSelectionMode,
                                      onTap: () {
                                        if (_isSelectionMode) {
                                          _toggleSelection(id);
                                        } else {
                                          _showDetail(invoice.id);
                                        }
                                      },
                                      onLongPress: () {
                                        if (!_isSelectionMode) {
                                          setState(() {
                                            _isSelectionMode = true;
                                            _selectedIds.add(id);
                                          });
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
            if (_selectedIds.isNotEmpty)
              AppStickyBottomBar(
                children: [
                  Text('${_selectedIds.length} selected', style: AppTextStyles.bodyMedium),
                  Row(
                    children: [
                      AppButton(
                        label: 'Cancel',
                        icon: Icons.cancel_outlined,
                        onTap: _bulkCancel,
                        color: AppColors.error,
                        isSmall: true,
                      ),
                      const SizedBox(width: 4),
                      AppButton(
                        label: 'Delete',
                        icon: Icons.delete_outline,
                        onTap: _bulkDelete,
                        color: AppColors.error,
                        isSmall: true,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          AppCommandBar(
            title: 'Sale Invoices',
            searchWidget: AppInput(
              controller: _searchCtrl,
              hint: 'Search invoices...',
              prefix: const Icon(Icons.search_rounded, size: 18),
              onSubmitted: (_) => _fetch(),
              onChanged: (v) {
                if (v.isEmpty) _fetch();
                setState(() {});
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: _exportGstr1,
                tooltip: 'Export GSTR-1',
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Create Invoice',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => _showForm(),
              ),
            ],
          ),
          AppStatusTabBar(
            tabs: const ['ALL', 'DRAFT', 'SENT', 'PAID', 'PARTIALLY_PAID', 'CANCELLED'],
            activeTab: _statusFilter,
            onTabChanged: (tab) {
              setState(() => _statusFilter = tab);
              _fetch();
            },
            badges: {
              'ALL': totalCount,
              'DRAFT': draftCount,
              'SENT': sentCount,
              'PAID': paidCount,
              'PARTIALLY_PAID': partialCount,
              'CANCELLED': cancelledCount,
            },
          ),
          Expanded(
            child: provider.isLoading && invoices.isEmpty
                ? const ListSkeleton()
                : provider.errorMessage != null && invoices.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: _fetch)
                    : invoices.isEmpty
                        ? AppEmptyState(
                            icon: Icons.description_outlined,
                            title: 'No invoices found',
                            subtitle: 'Create your first invoice to get started',
                            actionLabel: 'Create Invoice',
                            onAction: () => _showForm(),
                          )
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: AppColors.bgSurface,
                                  border: Border(bottom: BorderSide(color: AppColors.border)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Checkbox(
                                        value: _selectedIds.length == invoices.length && invoices.isNotEmpty,
                                        onChanged: (_) => _selectAll(),
                                      ),
                                    ),
                                    const Expanded(flex: 2, child: Text('DATE', style: AppTextStyles.labelSmall)),
                                    const Expanded(flex: 2, child: Text('NUMBER', style: AppTextStyles.labelSmall)),
                                    const Expanded(flex: 4, child: Text('PARTY / CUSTOMER', style: AppTextStyles.labelSmall)),
                                    const Expanded(flex: 3, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                    const Expanded(flex: 3, child: Text('BALANCE', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                    const Expanded(flex: 2, child: Text('STATUS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                    const SizedBox(width: 120, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: invoices.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                                  itemBuilder: (context, index) {
                                    final inv = invoices[index];
                                    final id = inv.id.toString();
                                    final isSelected = _selectedIds.contains(id);
                                    final partyName = inv.contactName ?? inv.contact?.name ?? 'Guest';
                                    final bal = _balanceAmount(inv);

                                    return InkWell(
                                      onTap: () => _showDetail(inv.id),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        color: isSelected ? AppColors.bgLight : Colors.transparent,
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 40,
                                              child: Checkbox(
                                                value: isSelected,
                                                onChanged: (_) => _toggleSelection(id),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                AppDate.format(inv.issueDate),
                                                style: AppTextStyles.bodySmall,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                inv.invoiceNumber,
                                                style: AppTextStyles.bodyMedium.copyWith(
                                                  color: AppColors.brandNavy,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 4,
                                              child: Row(
                                                children: [
                                                  AppAvatar(name: partyName, size: 24),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      partyName,
                                                      style: AppTextStyles.partyName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                AmountFormat.format(inv.total),
                                                style: AppTextStyles.amount,
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                AmountFormat.format(bal),
                                                style: AppTextStyles.amount.copyWith(
                                                  color: bal > 0 ? AppColors.warning : AppColors.success,
                                                ),
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Center(
                                                child: AppInlineStatus(status: inv.status),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 120,
                                              child: AppRowActions(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.visibility_outlined, size: 16),
                                                    onPressed: () => _showDetail(inv.id),
                                                    tooltip: 'View Detail',
                                                  ),
                                                  if (inv.status == 'DRAFT')
                                                    IconButton(
                                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                                      onPressed: () => _showForm(invoice: inv),
                                                      tooltip: 'Edit',
                                                    ),
                                                  IconButton(
                                                    icon: const Icon(Icons.print_outlined, size: 16),
                                                    onPressed: () => _printInvoice(inv),
                                                    tooltip: 'Print',
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
          ),
          if (_selectedIds.isNotEmpty)
            AppStickyBottomBar(
              children: [
                Text(
                  '${_selectedIds.length} selected',
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    AppButton(
                      label: 'Cancel Selected',
                      icon: Icons.cancel_outlined,
                      onTap: _bulkCancel,
                      color: AppColors.error,
                      isSmall: true,
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Email Selected',
                      icon: Icons.email_outlined,
                      onTap: _bulkEmail,
                      isSmall: true,
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Delete Selected',
                      icon: Icons.delete_outline,
                      onTap: _bulkDelete,
                      color: AppColors.error,
                      isSmall: true,
                    ),
                  ],
                ),
              ],
            )
          else
            AppStickyBottomBar(
              children: [
                Text(
                  'Total: ${AmountFormat.format(totalAmount)}',
                  style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Collected: ${AmountFormat.format(collectedAmount)}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.success, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Outstanding: ${AmountFormat.format(outstandingAmount)}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700),
                ),
              ],
            ),
        ],
      ),
    );
  }

  final Map<String, double> _swipeProgress = {};

  Widget _buildSwipeableInvoice(InvoiceModel invoice, Widget child) {
    if (_isSelectionMode) return child;
    final invoiceId = invoice.id.toString();

    return Dismissible(
      key: Key('invoice_dismiss_$invoiceId'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.green[700],
        child: const Row(
          children: [
            Icon(Icons.payment, color: Colors.white),
            SizedBox(width: 8),
            Text('Receive Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: (_swipeProgress[invoiceId] ?? 0) > 0.70 ? AppColors.error : AppColors.info,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              (_swipeProgress[invoiceId] ?? 0) > 0.70 ? 'Delete Invoice' : 'Share PDF',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Icon((_swipeProgress[invoiceId] ?? 0) > 0.70 ? Icons.delete : Icons.share, color: Colors.white),
          ],
        ),
      ),
      onUpdate: (details) {
        setState(() {
          _swipeProgress[invoiceId] = details.progress;
        });
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showRecordPaymentDialog(invoice);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if ((_swipeProgress[invoiceId] ?? 0) > 0.70) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Delete Invoice?',
              message: 'Delete invoice ${invoice.invoiceNumber}? This action cannot be undone. Only DRAFT invoices can be deleted.',
            );
            if (confirm == true) {
              _deleteSingleInvoice(invoice);
              return true;
            }
            return false;
          } else {
            PrintShareHelper.showShareSheet(
              context,
              docLabel: 'Invoice',
              docNumber: invoice.invoiceNumber,
              docType: 'invoices',
              docId: invoice.id,
            );
            return false;
          }
        }
        return false;
      },
      child: child,
    );
  }

  void _showRecordPaymentDialog(InvoiceModel invoice) {
    final remaining = invoice.total - invoice.amountPaid;
    if (remaining <= 0) {
      AppToast.error(context, 'Invoice is already fully paid');
      return;
    }
    final amountCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    String mode = 'BANK';
    DateTime payDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final formattedDate = '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
            return AlertDialog(
              title: Text('Record Payment for ${invoice.invoiceNumber}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                        prefixIcon: Icon(Icons.currency_rupee_outlined, size: 16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: payDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                        );
                        if (picked != null) setDialogState(() => payDate = picked);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Payment Date',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                          suffixIcon: Icon(Icons.arrow_drop_down, size: 18),
                        ),
                        child: Text(formattedDate, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: mode,
                      decoration: const InputDecoration(labelText: 'Payment Mode'),
                      items: const [
                        DropdownMenuItem(value: 'BANK', child: Text('Bank Transfer / Cheque')),
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(value: 'POS', child: Text('Card / POS')),
                        DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                      ],
                      onChanged: (val) { if (val != null) setDialogState(() => mode = val); },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(labelText: 'Reference Number (e.g. Txn ID)'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
                TextButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                    if (amt <= 0) {
                      AppToast.info(context, 'Please enter a valid amount');
                      return;
                    }
                    Navigator.pop(context);
                    final formattedPayDate = '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
                    final randSeq = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
                    final payload = {
                      'contact_id': invoice.contactId,
                      'payment_date': formattedPayDate,
                      'payment_mode': mode,
                      'amount': amt,
                      if (refCtrl.text.isNotEmpty) 'reference_number': refCtrl.text,
                      'description': 'Payment for invoice ${invoice.invoiceNumber}',
                      'allocations': [{'invoice_id': invoice.id, 'amount': amt}]
                    };
                    final provider = context.read<InvoiceProvider>();
                    final success = await provider.recordPayment(invoice.id, payload);
                    if (mounted) {
                      if (success) {
                        HapticHelper.success();
                        _fetch();
                      } else {
                        HapticHelper.error();
                        AppToast.error(context, provider.errorMessage ?? 'Failed to record payment');
                      }
                    }
                  },
                  child: const Text('SAVE'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      amountCtrl.dispose();
      refCtrl.dispose();
    });
  }

  void _deleteSingleInvoice(InvoiceModel invoice) async {
    final provider = context.read<InvoiceProvider>();
    final success = await provider.deleteInvoice(invoice.id);
    if (success) {
      HapticHelper.delete();
      _fetch();
      AppToast.info(context, 'Invoice ${invoice.invoiceNumber} deleted');
    }
  }

  Future<void> _cancelInvoice(InvoiceModel invoice) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Invoice?',
      message: 'Cancel ${invoice.invoiceNumber}? This will reverse ledger entries.',
    );
    if (confirm == true) {
      final provider = context.read<InvoiceProvider>();
      final success = await provider.cancelInvoice(invoice.id);
      if (!success && mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  void _printInvoice(InvoiceModel invoice) {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Invoice',
      docNumber: invoice.invoiceNumber,
      docType: 'invoices',
      docId: invoice.id,
    );
  }

  void _shareInvoice(InvoiceModel invoice) {
    PrintShareHelper.showShareSheet(
      context,
      docLabel: 'Invoice',
      docNumber: invoice.invoiceNumber,
      docType: 'invoices',
      docId: invoice.id,
    );
  }

  void _exportGstr1() async {
    final now = DateTime.now();
    final fyStart = now.month >= 4
        ? DateTime(now.year, 4, 1)
        : DateTime(now.year - 1, 4, 1);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      initialDateRange: DateTimeRange(start: fyStart, end: now),
    );
    if (range == null) return;
    final fmt = (DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final response = await ApiClient().get(
      Uri.parse('${ApiClient.baseUrl}/gst/gstr1/export?start_date=${fmt(range.start)}&end_date=${fmt(range.end)}'),
    );
    if (response.statusCode == 200 && mounted) {
      final data = jsonDecode(response.body);
      final json = const JsonEncoder.withIndent('  ').convert(data);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'gstr1_export_$timestamp.json';
      final bytes = utf8.encode(json);
      if (kIsWeb) {
        triggerWebDownload(fileName, bytes);
        AppToast.info(context, 'GSTR-1 downloaded: $fileName');
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save GSTR-1 Export',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(bytes),
        );
        AppToast.success(context, savePath == null ? 'Export cancelled' : 'GSTR-1 saved to $savePath');
      }
    } else if (mounted) {
      AppToast.error(context, 'Export failed');
    }
  }
}

class _CompactAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _CompactAction({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: (color ?? AppColors.brandNavy).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: color ?? AppColors.brandNavy),
        ),
      ),
    );
  }
}
