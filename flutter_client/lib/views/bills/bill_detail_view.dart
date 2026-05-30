import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';

import 'package:flutter_client/core/print_share_helper.dart';

class BillDetailView extends StatefulWidget {
  final String billId;

  const BillDetailView({super.key, required this.billId});

  @override
  State<BillDetailView> createState() => _BillDetailViewState();
}

class _BillDetailViewState extends State<BillDetailView> {
  BillModel? _bill;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  void _fetchDetail() async {
    final detail = await context.read<BillProvider>().fetchBillDetail(widget.billId);
    if (mounted) {
      setState(() {
        _bill = detail;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(_bill?.billNumber ?? 'Bill Detail'),
        actions: [
          if (_bill != null) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                PrintShareHelper.showShareSheet(
                  context,
                  docLabel: 'Bill',
                  docNumber: _bill!.billNumber,
                  docType: 'bills',
                  docId: _bill!.id,
                );
              },
              tooltip: 'Share / Export',
            ),
            if (_bill!.status == 'DRAFT')
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillFormView(editBill: _bill),
                    ),
                  ).then((_) => _fetchDetail());
                },
                tooltip: 'Edit bill',
              ),
            const SizedBox(width: 8),
            StatusBadge(label: _bill!.status),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Loading vendor bill...')
          : _bill == null
              ? const ErrorState(message: 'Vendor bill details not found.')
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
                                    Icons.receipt_long_outlined,
                                    size: 20,
                                    color: AppColors.goldAccent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('VENDOR BILL', style: AppTextStyles.labelSmall),
                                      Text(
                                        _bill!.billNumber,
                                        style: AppTextStyles.h2,
                                      ),
                                    ],
                                  ),
                                ),
                                StatusBadge(label: _bill!.status),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            InfoRow(label: 'Vendor', value: _bill!.contact?.name ?? 'N/A'),
                            InfoRow(label: 'Bill Date', value: _bill!.billDate),
                            InfoRow(label: 'Due Date', value: _bill!.dueDate),
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
                            if (_bill!.lines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('No items', style: AppTextStyles.bodySmall),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _bill!.lines.length,
                                separatorBuilder: (context, _) => const Divider(),
                                itemBuilder: (context, i) {
                                  final line = _bill!.lines[i];
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
                            SummaryRow(label: 'Subtotal', value: '₹${_bill!.subtotal.toStringAsFixed(2)}'),
                            SummaryRow(label: 'Discount Total', value: '₹${_bill!.discountTotal.toStringAsFixed(2)}'),
                            SummaryRow(label: 'CGST', value: '₹${_bill!.cgstAmount.toStringAsFixed(2)}'),
                            SummaryRow(label: 'SGST', value: '₹${_bill!.sgstAmount.toStringAsFixed(2)}'),
                            SummaryRow(label: 'IGST', value: '₹${_bill!.igstAmount.toStringAsFixed(2)}'),
                            SummaryRow(label: 'Round Off', value: '₹${_bill!.roundOff.toStringAsFixed(2)}'),
                            const Divider(),
                            SummaryRow(
                              label: 'Total Amount',
                              value: '₹${_bill!.total.toStringAsFixed(2)}',
                              isBold: true,
                              valueColor: AppColors.brandNavy,
                            ),
                            SummaryRow(
                              label: 'Amount Paid',
                              value: '₹${_bill!.amountPaid.toStringAsFixed(2)}',
                              valueColor: Colors.green[700],
                            ),
                            SummaryRow(
                              label: 'Remaining Balance',
                              value: '₹${(_bill!.total - _bill!.amountPaid).toStringAsFixed(2)}',
                              isBold: true,
                              valueColor: (_bill!.total - _bill!.amountPaid) > 0 ? AppColors.error : Colors.green[700],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_bill!.status == 'DRAFT') ...[
                        ElevatedButton.icon(
                          onPressed: _finalizeBill,
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Finalize & Post Bill'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _deleteBill,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete Draft'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                      if (_bill!.status == "UNPAID" || _bill!.status == 'PARTIALLY_PAID') ...[
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
                          onPressed: _cancelBill,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel Bill'),
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

  void _deleteBill() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete Draft Bill?',
      message: 'Are you sure you want to permanently delete this draft bill?',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<BillProvider>();
      final success = await provider.deleteBill(widget.billId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Failed to delete bill'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _finalizeBill() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Finalize Bill?',
      message: 'This will lock the bill and generate journal entries. You cannot edit it after finalizing.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<BillProvider>();
      final success = await provider.finalizeBill(widget.billId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Failed to finalize bill'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _cancelBill() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Vendor Bill?',
      message: 'Are you sure you want to cancel this bill? This will post reversals.',
    );
    if (confirm == true) {
      setState(() => _isLoading = true);
      final provider = context.read<BillProvider>();
      final success = await provider.cancelBill(widget.billId);
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _fetchDetail();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(provider.errorMessage ?? 'Failed to cancel bill'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _showRecordPaymentDialog() {
    final remaining = _bill!.total - _bill!.amountPaid;
    final amountCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    String mode = 'BANK'; // Match regex: CASH, BANK, UPI, POS, OTHER
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
                        DropdownMenuItem(value: 'BANK', child: Text('Bank')),
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(value: 'POS', child: Text('POS')),
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
                      'contact_id': _bill!.contactId,
                      'payment_number': 'PMT/${payDate.year}-${(payDate.year + 1) % 100}/$randSeq',
                      'payment_date': formattedPayDate,
                      'payment_mode': mode,
                      'amount': amt,
                      if (refCtrl.text.isNotEmpty) 'reference_number': refCtrl.text,
                      'description': 'Payment for vendor bill ${_bill!.billNumber}',
                      'allocations': [
                        {
                          'bill_id': widget.billId,
                          'amount': amt,
                        }
                      ]
                    };

                    final provider = context.read<BillProvider>();
                    final success = await provider.recordPayment(widget.billId, payload);
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
