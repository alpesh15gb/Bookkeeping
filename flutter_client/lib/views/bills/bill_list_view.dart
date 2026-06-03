import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/bills/bill_detail_view.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/core/print_share_helper.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';

class BillListView extends StatefulWidget {
  const BillListView({super.key});

  @override
  State<BillListView> createState() => _BillListViewState();
}

class _BillListViewState extends State<BillListView> {
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  double _swipeProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BillProvider>().fetchBills();
    });
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
    final provider = context.read<BillProvider>();
    setState(() {
      if (_selectedIds.length == provider.bills.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = provider.bills.map((e) => e.id.toString()).toSet();
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
      title: 'Delete ${_selectedIds.length} bills?',
      message: 'This action cannot be undone.',
    );
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      for (final id in _selectedIds) {
        await provider.deleteBill(id);
      }
      HapticHelper.delete();
      _clearSelection();
      provider.fetchBills();
    }
  }

  void _bulkCancel() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${_selectedIds.length} bills?',
      message: 'This will reverse ledger entries for each selected bill.',
    );
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      int successCount = 0;
      for (final id in _selectedIds) {
        final ok = await provider.cancelBill(id);
        if (ok) successCount++;
      }
      HapticHelper.medium();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$successCount of ${_selectedIds.length} bills cancelled')),
        );
      }
      _clearSelection();
      provider.fetchBills();
    }
  }

  void _showForm({BillModel? bill}) async {
    BillModel? fullBill = bill;
    if (bill != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      fullBill = await context.read<BillProvider>().fetchBillDetail(bill.id);
      if (mounted) Navigator.pop(context);
      if (fullBill == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load bill details'), backgroundColor: AppColors.error),
          );
        }
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BillFormView(editBill: fullBill)),
      ).then((_) => context.read<BillProvider>().fetchBills());
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BillDetailView(billId: id)),
    ).then((_) => context.read<BillProvider>().fetchBills());
  }

  Future<void> _cancelBill(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel Bill?', message: 'Cancel this vendor bill?');
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      final success = await provider.cancelBill(id);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Cancel failed'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final billProvider = context.watch<BillProvider>();

    if (billProvider.isLoading && billProvider.bills.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bgLight,
        body: ListSkeleton(),
      );
    }
    if (billProvider.errorMessage != null && billProvider.bills.isEmpty) {
      return ErrorState(
        message: billProvider.errorMessage!,
        onRetry: () => context.read<BillProvider>().fetchBills(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: billProvider.bills.isEmpty
          ? RefreshIndicator(
              onRefresh: () async => context.read<BillProvider>().fetchBills(),
              child: ListView(
                children: [
                  const SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No vendor bills yet',
                    subtitle: 'Vendor bills will appear here once added',
                    actionLabel: 'Add Bill',
                    onAction: () => _showForm(),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () async => context.read<BillProvider>().fetchBills(),
                  child: ListView.separated(
                    padding: EdgeInsets.only(
                      left: isMobile ? 12 : 20,
                      right: isMobile ? 12 : 20,
                      top: isMobile ? 12 : 20,
                      bottom: _selectedIds.isNotEmpty ? 80 : (isMobile ? 12 : 20),
                    ),
                    itemCount: billProvider.bills.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final bill = billProvider.bills[i];
                      final id = bill.id.toString();
                      final isSelected = _selectedIds.contains(id);
                      return _buildSwipeableBill(
                        bill,
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
                                _showDetail(bill.id);
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
                                          Expanded(child: Text(bill.billNumber, style: AppTextStyles.h3)),
                                          StatusBadge(label: bill.status),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(Icons.person_outlined, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Text(bill.contact?.name ?? 'N/A', style: AppTextStyles.bodySmall),
                                          const SizedBox(width: 16),
                                          Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Text(bill.billDate, style: AppTextStyles.caption),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('₹${bill.total.toStringAsFixed(2)}', style: AppTextStyles.numericLarge),
                                          if (!_isSelectionMode)
                                            Row(
                                              children: [
                                                OutlinedButton.icon(
                                                  onPressed: () => _showDetail(bill.id),
                                                  icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                                                  label: const Text('View'),
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    textStyle: AppTextStyles.buttonSmall,
                                                    side: const BorderSide(color: AppColors.borderInput),
                                                  ),
                                                ),
                                                if (bill.status == 'DRAFT') ...[
                                                  const SizedBox(width: 8),
                                                  OutlinedButton.icon(
                                                    onPressed: () => _showForm(bill: bill),
                                                    icon: const Icon(Icons.edit_outlined, size: 14),
                                                    label: const Text('Edit'),
                                                    style: OutlinedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      textStyle: AppTextStyles.buttonSmall,
                                                      side: const BorderSide(color: AppColors.borderInput),
                                                    ),
                                                  ),
                                                ],
                                                if (bill.status != 'CANCELLED') ...[
                                                  const SizedBox(width: 8),
                                                  OutlinedButton.icon(
                                                    onPressed: () => _cancelBill(bill.id),
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
                                    _selectedIds.length == billProvider.bills.length
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 22,
                                    color: _selectedIds.length == billProvider.bills.length
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
    );
  }

  Widget _buildSwipeableBill(BillModel bill, Widget child) {
    if (_isSelectionMode) return child;

    return Dismissible(
      key: Key('bill_dismiss_${bill.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: Colors.green[700],
        child: const Row(
          children: [
            Icon(Icons.payment, color: Colors.white),
            SizedBox(width: 8),
            Text('Record Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          _showRecordPaymentDialog(bill);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if (_swipeProgress > 0.75) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Delete Bill?',
              message: 'Delete bill ${bill.billNumber}? This action can be undone.',
            );
            if (confirm == true) {
              _deleteSingleBill(bill);
              return true;
            }
            return false;
          } else {
            PrintShareHelper.showShareSheet(
              context,
              docLabel: 'Bill',
              docNumber: bill.billNumber,
              docType: 'bills',
              docId: bill.id,
            );
            return false;
          }
        }
        return false;
      },
      child: child,
    );
  }

  void _showRecordPaymentDialog(BillModel bill) {
    final remaining = bill.total - bill.amountPaid;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill is already fully paid')),
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
              title: Text('Record Payment for ${bill.billNumber}'),
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
                      'contact_id': bill.contactId,
                      'payment_number': 'PAY/${payDate.year}-${(payDate.year + 1) % 100}/$randSeq',
                      'payment_date': formattedPayDate,
                      'payment_mode': mode,
                      'amount': amt,
                      if (refCtrl.text.isNotEmpty) 'reference_number': refCtrl.text,
                      'description': 'Payment for bill ${bill.billNumber}',
                      'allocations': [
                        {
                          'bill_id': bill.id,
                          'amount': amt,
                        }
                      ]
                    };

                    final provider = context.read<BillProvider>();
                    final success = await provider.recordPayment(bill.id, payload);
                    if (mounted) {
                      if (success) {
                        HapticHelper.success();
                        provider.fetchBills();
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

  void _deleteSingleBill(BillModel bill) async {
    final provider = context.read<BillProvider>();
    final success = await provider.deleteBill(bill.id);
    if (success) {
      HapticHelper.delete();
      provider.fetchBills();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: AppColors.brandNavy,
          content: Text('Bill ${bill.billNumber} deleted'),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.goldAccent,
            onPressed: () async {
              final payload = bill.toJson();
              payload.remove('id');
              payload.remove('status');
              if (payload['lines'] != null) {
                payload['line_items'] = (payload['lines'] as List).map((l) {
                  return Map<String, dynamic>.from(l);
                }).toList();
                payload.remove('lines');
              }
              final ok = await provider.createBill(payload);
              if (ok) {
                HapticHelper.success();
                provider.fetchBills();
              }
            },
          ),
        ),
      );
    }
  }
}
