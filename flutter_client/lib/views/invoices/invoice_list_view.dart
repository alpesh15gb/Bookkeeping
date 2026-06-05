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
    context.read<InvoiceProvider>().fetchInvoices(
      search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
      status: _statusFilter == 'ALL' ? null : _statusFilter,
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
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${_selectedIds.length} invoices?',
      message: 'This will reverse ledger entries for each selected invoice.',
    );
    if (confirm == true) {
      final provider = context.read<InvoiceProvider>();
      int successCount = 0;
      for (final id in _selectedIds) {
        final ok = await provider.cancelInvoice(id);
        if (ok) successCount++;
      }
      if (mounted) {
        AppToast.info(context, '$successCount of ${_selectedIds.length} invoices cancelled');
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
    final paid = invoice.amountPaid;
    if (paid <= 0) return 'Unpaid';
    if (paid >= invoice.total) return 'Paid';
    return 'Partial';
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
        if (inv.status == 'PARTIALLY_PAID') overdueAmount += balance;
      }
    }
    final avgInvoice = totalCount > 0 ? totalAmount / totalCount : 0;

    String formatAmt(num v) {
      if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: () => _showForm(),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          // ── Search + Filter Bar ──
          AppCard(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 8,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: AppInput(
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
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Export GSTR-1',
                        child: IconButton(
                          icon: const Icon(Icons.download_rounded, size: 18),
                          onPressed: _exportGstr1,
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.borderLight,
                            padding: const EdgeInsets.all(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Create Invoice',
                        icon: Icons.add,
                        isPrimary: true,
                        onTap: () => _showForm(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChipWithCount(
                        label: 'All',
                        count: totalCount,
                        isSelected: _statusFilter == 'ALL',
                        onTap: () { setState(() => _statusFilter = 'ALL'); _fetch(); },
                      ),
                      const SizedBox(width: 4),
                      FilterChipWithCount(
                        label: 'Draft',
                        count: draftCount,
                        isSelected: _statusFilter == 'DRAFT',
                        onTap: () { setState(() => _statusFilter = 'DRAFT'); _fetch(); },
                      ),
                      const SizedBox(width: 4),
                      FilterChipWithCount(
                        label: 'Sent',
                        count: sentCount,
                        isSelected: _statusFilter == 'SENT',
                        onTap: () { setState(() => _statusFilter = 'SENT'); _fetch(); },
                      ),
                      const SizedBox(width: 4),
                      FilterChipWithCount(
                        label: 'Paid',
                        count: paidCount,
                        isSelected: _statusFilter == 'PAID',
                        onTap: () { setState(() => _statusFilter = 'PAID'); _fetch(); },
                      ),
                      const SizedBox(width: 4),
                      FilterChipWithCount(
                        label: 'Partial',
                        count: partialCount,
                        isSelected: _statusFilter == 'PARTIALLY_PAID',
                        onTap: () { setState(() => _statusFilter = 'PARTIALLY_PAID'); _fetch(); },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Hero Summary Card ──
          if (invoices.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 20,
                vertical: 8,
              ),
              child: HeroSummaryCard(
                title: 'Total Sales',
                amount: totalAmount,
                subtitle: '${AmountFormat.format(collectedAmount)} collected · ${AmountFormat.format(outstandingAmount)} outstanding',
                icon: Icons.receipt_long_outlined,
              ),
            ),

          // ── Summary Stats ──
          if (invoices.isNotEmpty)
            SummaryStatsBar(stats: [
              SummaryStat(label: 'Total', count: totalCount, color: AppColors.brandNavy),
              SummaryStat(label: 'Draft', count: draftCount, color: AppColors.textMuted),
              SummaryStat(label: 'Sent', count: sentCount, color: AppColors.info),
              SummaryStat(label: 'Paid', count: paidCount, color: AppColors.success),
              SummaryStat(label: 'Partial', count: partialCount, color: AppColors.warning),
            ]),

          // ── List Body ──
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
                        : Stack(
                            children: [
                              RefreshIndicator(
                                onRefresh: () async => _fetch(),
                                child: ListView.separated(
                                  padding: EdgeInsets.only(
                                    left: isMobile ? 12 : 20,
                                    right: isMobile ? 12 : 20,
                                    top: 4,
                                    bottom: _selectedIds.isNotEmpty ? 80 : (isMobile ? 80 : 20),
                                  ),
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
                                        actions: _isSelectionMode
                                            ? null
                                            : [
                                                if (invoice.status == 'DRAFT')
                                                  _CompactAction(
                                                    icon: Icons.edit_outlined,
                                                    tooltip: 'Edit',
                                                    onTap: () => _showForm(invoice: invoice),
                                                  ),
                                                if (invoice.status == 'SENT' || invoice.status == 'PARTIALLY_PAID')
                                                  _CompactAction(
                                                    icon: Icons.cancel_outlined,
                                                    tooltip: 'Cancel',
                                                    color: AppColors.error,
                                                    onTap: () => _cancelInvoice(invoice),
                                                  ),
                                              ],
                                        hoverActions: _isSelectionMode
                                            ? null
                                            : [
                                                _CompactAction(
                                                  icon: Icons.edit_outlined,
                                                  tooltip: 'Edit',
                                                  onTap: () => _showForm(invoice: invoice),
                                                ),
                                                _CompactAction(
                                                  icon: Icons.print_outlined,
                                                  tooltip: 'Print',
                                                  onTap: () => _printInvoice(invoice),
                                                ),
                                                _CompactAction(
                                                  icon: Icons.share_outlined,
                                                  tooltip: 'Share',
                                                  onTap: () => _shareInvoice(invoice),
                                                ),
                                              ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (_selectedIds.isNotEmpty)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.bgSurface,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, -2),
                                        ),
                                      ],
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isMobile ? 12 : 20,
                                      vertical: 10,
                                    ),
                                    child: SafeArea(
                                      top: false,
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: _selectAll,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _selectedIds.length == invoices.length
                                                      ? Icons.check_circle
                                                      : Icons.circle_outlined,
                                                  size: 20,
                                                  color: _selectedIds.length == invoices.length
                                                      ? AppColors.brandNavy
                                                      : AppColors.textMuted,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'All',
                                                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${_selectedIds.length} selected',
                                            style: AppTextStyles.caption,
                                          ),
                                          const Spacer(),
                                          AppButton(
                                            label: 'Clear',
                                            icon: Icons.close,
                                            onTap: _clearSelection,
                                            isSmall: true,
                                          ),
                                          const SizedBox(width: 4),
                                          AppButton(
                                            label: 'Cancel',
                                            icon: Icons.cancel_outlined,
                                            onTap: _bulkCancel,
                                            color: AppColors.error,
                                            isSmall: true,
                                          ),
                                          const SizedBox(width: 4),
                                          AppButton(
                                            label: 'Email',
                                            icon: Icons.email_outlined,
                                            onTap: _bulkEmail,
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
                                    ),
                                  ),
                                ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  double _swipeProgress = 0.0;

  Widget _buildSwipeableInvoice(InvoiceModel invoice, Widget child) {
    if (_isSelectionMode) return child;

    return Dismissible(
      key: Key('invoice_dismiss_${invoice.id}'),
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
        color: _swipeProgress > 0.70 ? AppColors.error : AppColors.info,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              _swipeProgress > 0.70 ? 'Delete Invoice' : 'Share PDF',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Icon(_swipeProgress > 0.70 ? Icons.delete : Icons.share, color: Colors.white),
          ],
        ),
      ),
      onUpdate: (details) {
        setState(() {
          _swipeProgress = details.progress;
        });
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showRecordPaymentDialog(invoice);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (_swipeProgress > 0.70) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Delete Invoice?',
              message: 'Delete invoice ${invoice.invoiceNumber}? This action can be undone.',
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
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
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
                      'payment_number': 'PAY/${payDate.year}-${(payDate.year + 1) % 100}/$randSeq',
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
    );
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
    final response = await ApiClient().get(
      Uri.parse('${ApiClient.baseUrl}/gst/gstr1/export'),
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
