import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/design_system.dart' as ds;
import 'package:flutter_client/views/bills/bill_form_view.dart';
import 'package:flutter_client/views/bills/bill_detail_view.dart';
import 'package:flutter_client/utils/haptic_helper.dart';
import 'package:flutter_client/core/print_share_helper.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';
import 'package:flutter_client/views/shared/toast.dart';

class BillListView extends StatefulWidget {
  const BillListView({super.key});

  @override
  State<BillListView> createState() => _BillListViewState();
}

class _BillListViewState extends State<BillListView> {
  final _searchCtrl = TextEditingController();
  Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  final Map<String, double> _swipeProgress = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BillProvider>().fetchBills();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
    final provider = context.read<BillProvider>();
    final cancellable = _selectedIds.where((id) {
      final match = provider.bills.where((b) => b.id.toString() == id);
      if (match.isEmpty) return false;
      return match.first.status == 'POSTED' || match.first.status == 'PARTIALLY_PAID';
    }).toList();
    if (cancellable.isEmpty) {
      AppToast.info(context, 'No cancellable bills selected (only Posted/Partial can be cancelled)');
      return;
    }
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel ${cancellable.length} bills?',
      message: 'This will reverse ledger entries for each selected bill.',
    );
    if (confirm == true) {
      int successCount = 0;
      for (final id in cancellable) {
        final ok = await provider.cancelBill(id);
        if (ok) successCount++;
      }
      HapticHelper.medium();
      if (mounted) {
        AppToast.info(context, '$successCount of ${cancellable.length} bills cancelled');
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
          AppToast.error(context, 'Failed to load bill details');
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
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Cancel Bill?',
      message: 'Cancel this vendor bill?',
    );
    if (confirm == true) {
      final provider = context.read<BillProvider>();
      final success = await provider.cancelBill(id);
      if (!success && mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  String _balanceLabel(BillModel bill) {
    if (bill.status == 'PAID') return 'Paid';
    if (bill.status == 'PARTIALLY_PAID') return 'Partial';
    return 'Unpaid';
  }

  num _balanceAmount(BillModel bill) {
    return bill.total - bill.amountPaid;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AdaptiveLayout.isMobile(context);
    final billProvider = context.watch<BillProvider>();
    final allBills = billProvider.bills;
    final search = _searchCtrl.text.trim().toLowerCase();
    final bills = search.isEmpty
        ? allBills
        : allBills.where((b) {
            return b.billNumber.toLowerCase().contains(search) ||
                (b.contact?.name ?? '').toLowerCase().contains(search);
          }).toList();

    final draftCount = allBills.where((b) => b.status == 'DRAFT').length;
    final paidCount = allBills.where((b) => b.status == 'PAID').length;
    final partialCount = allBills.where((b) => b.status == 'PARTIALLY_PAID').length;
    final totalCount = allBills.length;

    num totalAmount = 0;
    num paidAmount = 0;
    num outstandingAmount = 0;
    for (final b in allBills) {
      totalAmount += b.total;
      paidAmount += b.amountPaid;
      final bal = b.total - b.amountPaid;
      if (bal > 0) outstandingAmount += bal;
    }

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
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ds.AppInput(
                    controller: _searchCtrl,
                    hint: 'Search bills...',
                    prefix: const Icon(Icons.search_rounded, size: 18),
                    suffix: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => setState(() {}),
                  ),
                ),
                if (!isMobile) ...[
                  const SizedBox(width: 8),
                  ds.AppButton(
                    label: 'Create Bill',
                    icon: Icons.add,
                    isPrimary: true,
                    onTap: () => _showForm(),
                  ),
                ],
              ],
            ),
          ),

          // ── Hero Summary Card ──
          if (bills.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 20,
                vertical: 8,
              ),
              child: HeroSummaryCard(
                title: 'Total Bills',
                amount: totalAmount,
                subtitle: '${AmountFormat.format(paidAmount)} paid · ${AmountFormat.format(outstandingAmount)} outstanding',
                icon: Icons.receipt_long_outlined,
              ),
            ),

          if (bills.isNotEmpty)
            SummaryStatsBar(stats: [
              SummaryStat(label: 'Total', count: totalCount, color: AppColors.brandNavy),
              SummaryStat(label: 'Draft', count: draftCount, color: AppColors.textMuted),
              SummaryStat(label: 'Paid', count: paidCount, color: AppColors.success),
              SummaryStat(label: 'Partial', count: partialCount, color: AppColors.warning),
            ]),

          Expanded(
            child: billProvider.isLoading && bills.isEmpty
                ? const ListSkeleton()
                : billProvider.errorMessage != null && bills.isEmpty
                    ? ErrorState(
                        message: billProvider.errorMessage!,
                        onRetry: () => context.read<BillProvider>().fetchBills(),
                      )
                    : bills.isEmpty
                        ? ds.AppEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No vendor bills yet',
                            subtitle: 'Vendor bills will appear here once added',
                            actionLabel: 'Add Bill',
                            onAction: () => _showForm(),
                          )
                        : RefreshIndicator(
                            onRefresh: () async => context.read<BillProvider>().fetchBills(),
                            child: Stack(
                              children: [
                                ListView.separated(
                                  padding: EdgeInsets.only(
                                    left: isMobile ? 12 : 20,
                                    right: isMobile ? 12 : 20,
                                    top: 8,
                                    bottom: _selectedIds.isNotEmpty ? 80 : (isMobile ? 12 : 20),
                                  ),
                                  itemCount: bills.length,
                                  separatorBuilder: (context, _) => const SizedBox(height: 6),
                                  itemBuilder: (context, i) {
                                    final bill = bills[i];
                                    final id = bill.id.toString();
                                    final isSelected = _selectedIds.contains(id);
                                    final partyName = bill.contact?.name ?? '';
                                    final bal = _balanceAmount(bill);

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
                                        child: Row(
                                          children: [
                                            if (_isSelectionMode)
                                              Padding(
                                                padding: const EdgeInsets.only(right: 8),
                                                child: Icon(
                                                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                                                  size: 20,
                                                  color: isSelected ? AppColors.brandNavy : AppColors.textMuted,
                                                ),
                                              ),
                                            Expanded(
                                              child: ds.AppListTile(
                                                title: partyName.isNotEmpty ? partyName : bill.billNumber,
                                                subtitle: partyName.isNotEmpty
                                                    ? '#${bill.billNumber}${bill.billDate != null && bill.billDate!.isNotEmpty ? ' • ${ds.AppDate.format(bill.billDate)}' : ''}'
                                                    : (bill.billDate != null && bill.billDate!.isNotEmpty ? ds.AppDate.format(bill.billDate) : null),
                                                trailingWidget: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    ds.AppAmount(amount: bill.total.toDouble()),
                                                    const SizedBox(height: 2),
                                                    if (bal > 0)
                                                      Text(
                                                        '${_balanceLabel(bill)} ${AmountFormat.format(bal)}',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w500,
                                                          color: AppColors.error,
                                                          fontFeatures: [FontFeature.tabularFigures()],
                                                        ),
                                                      )
                                                    else
                                                      Text(
                                                        _balanceLabel(bill).toUpperCase(),
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w500,
                                                          color: _balanceLabel(bill) == 'Paid' ? AppColors.success : AppColors.textMuted,
                                                          fontFeatures: const [FontFeature.tabularFigures()],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                badge: StatusBadge(label: bill.status),
                                                hoverActions: _isSelectionMode
                                                    ? null
                                                    : [
                                                        if (bill.status == 'DRAFT')
                                                          ds.AppButton(
                                                            label: 'Edit',
                                                            icon: Icons.edit_outlined,
                                                            isSmall: true,
                                                            onTap: () => _showForm(bill: bill),
                                                          ),
                                                        if (bill.status != 'CANCELLED')
                                                          ds.AppButton(
                                                            label: 'Cancel',
                                                            icon: Icons.cancel_outlined,
                                                            isSmall: true,
                                                            color: AppColors.error,
                                                            textColor: AppColors.textWhite,
                                                            onTap: () => _cancelBill(bill.id),
                                                          ),
                                                      ],
                                                onTap: () {
                                                  if (_isSelectionMode) {
                                                    _toggleSelection(id);
                                                  } else {
                                                    _showDetail(bill.id);
                                                  }
                                                },
                                                isSelected: isSelected,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
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
                                                    _selectedIds.length == bills.length
                                                        ? Icons.check_circle
                                                        : Icons.circle_outlined,
                                                    size: 20,
                                                    color: _selectedIds.length == bills.length
                                                        ? AppColors.brandNavy
                                                        : AppColors.textMuted,
                                                  ),
                                                  const SizedBox(width: 6),
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
                                            ds.AppButton(
                                              label: 'Clear',
                                              icon: Icons.close,
                                              onTap: _clearSelection,
                                            ),
                                            const SizedBox(width: 6),
                                            ds.AppButton(
                                              label: 'Cancel',
                                              icon: Icons.cancel_outlined,
                                              color: AppColors.error,
                                              textColor: AppColors.textWhite,
                                              onTap: _bulkCancel,
                                            ),
                                            const SizedBox(width: 6),
                                            ds.AppButton(
                                              label: 'Delete',
                                              icon: Icons.delete_outline,
                                              color: AppColors.error,
                                              textColor: AppColors.textWhite,
                                              onTap: _bulkDelete,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeableBill(BillModel bill, Widget child) {
    if (_isSelectionMode) return child;
    final billId = bill.id.toString();

    return Dismissible(
      key: Key('bill_dismiss_$billId'),
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
        color: (_swipeProgress[billId] ?? 0) > 0.70 ? AppColors.error : AppColors.info,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              (_swipeProgress[billId] ?? 0) > 0.70 ? 'Delete Bill' : 'Share PDF',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Icon((_swipeProgress[billId] ?? 0) > 0.70 ? Icons.delete : Icons.share, color: Colors.white),
          ],
        ),
      ),
      onUpdate: (details) {
        setState(() {
          _swipeProgress[billId] = details.progress;
        });
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _showRecordPaymentDialog(bill);
          return false;
        } else if (direction == DismissDirection.endToStart) {
          if ((_swipeProgress[billId] ?? 0) > 0.70) {
            final confirm = await AppConfirmDialog.show(
              context,
              title: 'Delete Bill?',
              message: 'Delete bill ${bill.billNumber}? This action cannot be undone. Only DRAFT bills can be deleted.',
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
      AppToast.error(context, 'Bill is already fully paid');
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
                      AppToast.error(context, 'Please enter a valid amount');
                      return;
                    }
                    Navigator.pop(context);

                    final formattedPayDate =
                        '${payDate.year}-${payDate.month.toString().padLeft(2, '0')}-${payDate.day.toString().padLeft(2, '0')}';
                    final payload = {
                      'contact_id': bill.contactId,
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

  void _deleteSingleBill(BillModel bill) async {
    final provider = context.read<BillProvider>();
    final success = await provider.deleteBill(bill.id);
    if (success) {
      HapticHelper.delete();
      provider.fetchBills();
      AppToast.info(context, 'Bill ${bill.billNumber} deleted');
    }
  }
}
