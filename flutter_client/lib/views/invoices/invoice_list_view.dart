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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$successCount of ${_selectedIds.length} invoices cancelled')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$successCount of ${_selectedIds.length} emails queued')),
        );
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load invoice details'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceFormView(editInvoice: fullInvoice),
        ),
      ).then((_) {
        if (mounted) _fetch();
      });
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvoiceDetailView(invoiceId: id)),
    ).then((_) => _fetch());
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GSTR-1 downloaded: $fileName')),
          );
        }
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save GSTR-1 Export',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(bytes),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(savePath == null ? 'Export cancelled' : 'GSTR-1 saved to $savePath')),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InvoiceProvider>();
    final isMobile = AdaptiveLayout.isMobile(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // ── Search + Filter Bar ──
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 10,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by invoice number or party...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _fetch();
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppColors.borderInput),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppColors.borderInput),
                          ),
                        ),
                        onSubmitted: (_) => _fetch(),
                        onChanged: (v) {
                          if (v.isEmpty) _fetch();
                          setState(() {}); // update suffix icon
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Export GSTR-1',
                      child: IconButton(
                        icon: const Icon(Icons.download_rounded, size: 20),
                        onPressed: _exportGstr1,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.borderLight,
                          padding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Status filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusOptions.map((s) {
                      final isSelected = _statusFilter == s;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            s == 'ALL' ? 'All' : s.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _statusFilter = s);
                            _fetch();
                          },
                          selectedColor: AppColors.brandNavy,
                          backgroundColor: AppColors.borderLight,
                          side: BorderSide.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // ── List Body ──
          Expanded(
            child: provider.isLoading && provider.invoices.isEmpty
                ? const ListSkeleton()
                : provider.errorMessage != null && provider.invoices.isEmpty
                    ? ErrorState(message: provider.errorMessage!, onRetry: _fetch)
                    : provider.invoices.isEmpty
                        ? EmptyState(
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
                                    top: isMobile ? 12 : 20,
                                    bottom: _selectedIds.isNotEmpty ? 80 : (isMobile ? 12 : 20),
                                  ),
                                  itemCount: provider.invoices.length,
                                  separatorBuilder: (context, _) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final invoice = provider.invoices[i];
                                    final id = invoice.id.toString();
                                    final isSelected = _selectedIds.contains(id);
                                    return _buildSwipeableInvoice(
                                      invoice,
                                      GestureDetector(
                                        onLongPress: () {
                                          if (!_isSelectionMode) {
                                            setState(() {
                                              _isSelectionMode = true;
                                              _selectedIds.add(id);
                                            });
                                          }
                                        },
                                        child: AppCard(
                                          onTap: () {
                                            if (_isSelectionMode) {
                                              _toggleSelection(id);
                                            } else {
                                              _showDetail(invoice.id);
                                            }
                                          },
                                          child: Row(
                                            children: [
                                              if (_isSelectionMode)
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 12),
                                                  child: Icon(
                                                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                                                    size: 22,
                                                    color: isSelected ? AppColors.brandNavy : AppColors.textMuted,
                                                  ),
                                                ),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(invoice.invoiceNumber, style: AppTextStyles.h3),
                                                        ),
                                                        StatusBadge.fromInvoiceStatus(invoice.status),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Icon(Icons.person_outlined, size: 14, color: AppColors.textMuted),
                                                        const SizedBox(width: 6),
                                                         Text(invoice.contactName ?? invoice.contact?.name ?? 'N/A', style: AppTextStyles.bodySmall),
                                                        const SizedBox(width: 16),
                                                        Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                                                        const SizedBox(width: 6),
                                                        Text(invoice.issueDate, style: AppTextStyles.caption),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                      children: [
                                                        Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text('₹${invoice.total.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                                                            if (invoice.amountPaid > 0)
                                                              Text(
                                                                'Paid: ₹${invoice.amountPaid.toStringAsFixed(2)}',
                                                                style: AppTextStyles.caption.copyWith(color: AppColors.success),
                                                              ),
                                                          ],
                                                        ),
                                                        if (!_isSelectionMode)
                                                          Row(
                                                            children: [
                                                              OutlinedButton.icon(
                                                                onPressed: () => _showForm(invoice: invoice),
                                                                icon: const Icon(Icons.edit_outlined, size: 14),
                                                                label: const Text('Edit'),
                                                                style: OutlinedButton.styleFrom(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                                  textStyle: AppTextStyles.buttonSmall,
                                                                  side: const BorderSide(color: AppColors.borderInput),
                                                                ),
                                                              ),
                                                              if (invoice.status == 'SENT' || invoice.status == 'PARTIALLY_PAID') ...[
                                                                const SizedBox(width: 8),
                                                                OutlinedButton.icon(
                                                                  onPressed: () => _cancelInvoice(invoice),
                                                                  icon: const Icon(Icons.cancel_outlined, size: 14),
                                                                  label: const Text('Cancel'),
                                                                  style: OutlinedButton.styleFrom(
                                                                    foregroundColor: AppColors.error,
                                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                                    textStyle: AppTextStyles.buttonSmall,
                                                                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                                                  ),
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                                      vertical: 12,
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
                                                  _selectedIds.length == provider.invoices.length
                                                      ? Icons.check_circle
                                                      : Icons.circle_outlined,
                                                  size: 22,
                                                  color: _selectedIds.length == provider.invoices.length
                                                      ? AppColors.brandNavy
                                                      : AppColors.textMuted,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Select All',
                                                  style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                            '${_selectedIds.length} selected',
                                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                          ),
                                          const Spacer(),
                                          OutlinedButton.icon(
                                            onPressed: _clearSelection,
                                            icon: const Icon(Icons.close, size: 14),
                                            label: const Text('Clear'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              textStyle: AppTextStyles.buttonSmall,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: _bulkCancel,
                                            icon: const Icon(Icons.cancel_outlined, size: 14),
                                            label: const Text('Cancel'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppColors.error,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              textStyle: AppTextStyles.buttonSmall,
                                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: _bulkEmail,
                                            icon: const Icon(Icons.email_outlined, size: 14),
                                            label: const Text('Email'),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              textStyle: AppTextStyles.buttonSmall,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            onPressed: _bulkDelete,
                                            icon: const Icon(Icons.delete_outline, size: 14),
                                            label: const Text('Delete'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppColors.error,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              textStyle: AppTextStyles.buttonSmall,
                                              side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
                                            ),
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
        color: AppColors.info,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Share PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            Icon(Icons.share, color: Colors.white),
          ],
        ),
      ),
      onUpdate: (details) {
        _swipeProgress = details.progress;
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showRecordPaymentDialog(invoice);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (_swipeProgress > 0.90) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice is already fully paid')),
      );
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
            final formattedDate =
                '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
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
                      onChanged: (val) {
                        if (val != null) setDialogState(() => mode = val);
                      },
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
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                    if (amt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: AppColors.error),
                      );
                      return;
                    }
                    Navigator.pop(context);

                    final formattedPayDate =
                        '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
                    final randSeq = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
                    final payload = {
                      'contact_id': invoice.contactId,
                      'payment_number': 'PAY/${payDate.year}-${(payDate.year + 1) % 100}/$randSeq',
                      'payment_date': formattedPayDate,
                      'payment_mode': mode,
                      'amount': amt,
                      if (refCtrl.text.isNotEmpty) 'reference_number': refCtrl.text,
                      'description': 'Payment for invoice ${invoice.invoiceNumber}',
                      'allocations': [
                        {
                          'invoice_id': invoice.id,
                          'amount': amt,
                        }
                      ]
                    };

                    final provider = context.read<InvoiceProvider>();
                    final success = await provider.recordPayment(invoice.id, payload);
                    if (mounted) {
                      if (success) {
                        HapticHelper.success();
                        _fetch();
                      } else {
                        HapticHelper.error();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(provider.errorMessage ?? 'Failed to record payment'), backgroundColor: AppColors.error),
                        );
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: AppColors.brandNavy,
          content: Text('Invoice ${invoice.invoiceNumber} deleted'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.goldAccent,
            onPressed: () async {
              final payload = invoice.toJson();
              payload.remove('id');
              payload.remove('status');
              payload.remove('irn');
              payload.remove('qr_code');
              if (payload['lines'] != null) {
                payload['line_items'] = (payload['lines'] as List).map((l) {
                  final m = Map<String, dynamic>.from(l);
                  return m;
                }).toList();
                payload.remove('lines');
              }
              final ok = await provider.createInvoice(payload);
              if (ok) {
                HapticHelper.success();
                _fetch();
              }
            },
          ),
        ),
      );
    }
  }
}

