import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/invoices/invoice_form_view.dart';

import 'package:flutter_client/core/print_share_helper.dart';

class InvoiceDetailView extends StatefulWidget {
  final String invoiceId;

  const InvoiceDetailView({super.key, required this.invoiceId});

  @override
  State<InvoiceDetailView> createState() => _InvoiceDetailViewState();
}

class _InvoiceDetailViewState extends State<InvoiceDetailView> {
  InvoiceModel? _invoice;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<InvoiceProvider>().fetchInvoiceDetail(widget.invoiceId);
    if (mounted) {
      setState(() {
        _invoice = detail;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(_invoice?.invoiceNumber ?? 'Invoice Detail'),
        actions: [
          if (_invoice != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                PrintShareHelper.showShareSheet(
                  context,
                  docLabel: 'Invoice',
                  docNumber: _invoice!.invoiceNumber,
                  docType: 'invoices',
                  docId: _invoice!.id,
                );
              },
              tooltip: 'Share / Export',
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceFormView(editInvoice: _invoice),
                  ),
                ).then((_) => _fetchDetail());
              },
              tooltip: 'Edit invoice',
            ),
            const SizedBox(width: 8),
            StatusBadge.fromInvoiceStatus(_invoice!.status),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading invoice...')
          : _invoice == null
              ? const ErrorState(message: 'Invoice detail not found.')
              : SingleChildScrollView(
                  padding: AppSpacing.pagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.brandNavy,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.description_rounded,
                                    size: 20,
                                    color: AppColors.goldAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('INVOICE', style: AppTextStyles.labelSmall),
                                      Text(
                                        _invoice!.invoiceNumber,
                                        style: AppTextStyles.h2,
                                      ),
                                    ],
                                  ),
                                ),
                                StatusBadge.fromInvoiceStatus(_invoice!.status),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            InfoRow(label: 'Customer', value: _invoice!.contact?.name ?? 'N/A'),
                            InfoRow(label: 'Issue Date', value: _invoice!.issueDate),
                            InfoRow(label: 'Due Date', value: _invoice!.dueDate),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Line Items Card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(title: 'ITEMS'),
                            if (_invoice!.lines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('No items', style: AppTextStyles.bodySmall),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _invoice!.lines.length,
                                separatorBuilder: (context, _) => const Divider(),
                                itemBuilder: (context, i) {
                                  final line = _invoice!.lines[i];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                line.productName ?? 'Product',
                                                style: AppTextStyles.bodyMedium,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Qty: ${line.quantity} × ₹${line.rate.toStringAsFixed(2)}',
                                                style: AppTextStyles.caption,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '₹${line.total.toStringAsFixed(2)}',
                                          style: AppTextStyles.numeric,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Summary Card
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeader(title: 'TAX & TOTAL SUMMARY'),
                            SummaryRow(label: 'Subtotal', value: '₹${_invoice!.subtotal.toStringAsFixed(2)}'),
                            SummaryRow(label: 'CGST', value: '₹${_invoice!.cgstAmount.toStringAsFixed(2)}'),
                            SummaryRow(label: 'SGST', value: '₹${_invoice!.sgstAmount.toStringAsFixed(2)}'),
                            SummaryRow(label: 'IGST', value: '₹${_invoice!.igstAmount.toStringAsFixed(2)}'),
                            SummaryRow(label: 'Round Off', value: '₹${_invoice!.roundOff.toStringAsFixed(2)}'),
                            const Divider(),
                            SummaryRow(
                              label: 'Total',
                              value: '₹${_invoice!.total.toStringAsFixed(2)}',
                              isBold: true,
                              valueColor: AppColors.brandNavy,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_invoice!.status == 'DRAFT') ...[
                        ElevatedButton.icon(
                          onPressed: _finalizeInvoice,
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Finalize & Post'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _deleteInvoice,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete Draft'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                      if (_invoice!.status == 'SENT' || _invoice!.status == 'PARTIALLY_PAID') ...[
                        ElevatedButton.icon(
                          onPressed: _showRecordPaymentDialog,
                          icon: const Icon(Icons.payment),
                          label: const Text('Record Payment'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _cancelInvoice,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel Invoice'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  void _deleteInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Draft Invoice?',
      message: 'Are you sure you want to permanently delete this draft invoice?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<InvoiceProvider>();
      final success = await provider.deleteInvoice(widget.invoiceId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Failed to delete invoice'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _finalizeInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Finalize Invoice?',
      message: 'This will lock the invoice and generate journal postings. You cannot edit it after finalizing.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<InvoiceProvider>();
      final success = await provider.finalizeInvoice(widget.invoiceId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Failed to finalize'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _cancelInvoice() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Invoice?',
      message: 'Are you sure you want to cancel this invoice? This will post reversals.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<InvoiceProvider>();
      final success = await provider.cancelInvoice(widget.invoiceId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Failed to cancel'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _showRecordPaymentDialog() {
    final remaining = _invoice!.total - _invoice!.amountPaid;
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
              title: const Text('Record Payment'),
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
                    // Payment date picker
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
                    setState(() => _isLoading = true);

                    final formattedPayDate =
                        '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
                    final randSeq = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
                    final payload = {
                      'contact_id': _invoice!.contactId,
                      'payment_number': 'PAY/${payDate.year}-${(payDate.year + 1) % 100}/$randSeq',
                      'payment_date': formattedPayDate,
                      'payment_mode': mode,
                      'amount': amt,
                      if (refCtrl.text.isNotEmpty) 'reference_number': refCtrl.text,
                      'description': 'Payment for invoice ${_invoice!.invoiceNumber}',
                      'allocations': [
                        {
                          'invoice_id': widget.invoiceId,
                          'amount': amt,
                        }
                      ]
                    };

                    final provider = context.read<InvoiceProvider>();
                    final success = await provider.recordPayment(widget.invoiceId, payload);
                    if (mounted) {
                      setState(() => _isLoading = false);
                      if (success) {
                        _fetchDetail();
                      } else {
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
}
