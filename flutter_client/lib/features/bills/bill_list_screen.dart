import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../providers/bill_provider.dart';

class BillListScreen extends StatefulWidget {
  const BillListScreen({super.key});

  @override
  State<BillListScreen> createState() => _BillListScreenState();
}

class _BillListScreenState extends State<BillListScreen> {
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BillProvider>().fetchBills();
    });
  }

  @override
  Widget build(BuildContext context) {
    final billProvider = context.watch<BillProvider>();
    final bills = billProvider.bills;
    final isLoading = billProvider.isLoading;

    final filtered = _selectedStatus != null
        ? bills.where((b) => b.status.toUpperCase() == _selectedStatus).toList()
        : bills;

    final allCount = bills.length;
    final overdueCount = bills.where((b) => b.status.toUpperCase() == 'OVERDUE').length;
    final pendingCount = bills.where((b) => b.status.toUpperCase() == 'PENDING' || b.status.toUpperCase() == 'SENT').length;
    final paidCount = bills.where((b) => b.status.toUpperCase() == 'PAID').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Vendor Bills', style: AppTypography.headlineLarge),
            const Spacer(),
            AppButton(label: '+ Bill', icon: Icons.add, onPressed: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            AppFilterChip(label: 'All', count: allCount, isSelected: _selectedStatus == null, onTap: () => setState(() => _selectedStatus = null)),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Overdue', count: overdueCount, selectedColor: AppColors.error, isSelected: _selectedStatus == 'OVERDUE', onTap: () => setState(() => _selectedStatus = 'OVERDUE')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Pending', count: pendingCount, selectedColor: AppColors.info, isSelected: _selectedStatus == 'PENDING', onTap: () => setState(() => _selectedStatus = 'PENDING')),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(label: 'Paid', count: paidCount, selectedColor: AppColors.success, isSelected: _selectedStatus == 'PAID', onTap: () => setState(() => _selectedStatus = 'PAID')),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: isLoading && bills.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? AppEmptyState(icon: Icons.receipt, title: 'No bills found')
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Bill #', width: 130),
                        TableColumn(label: 'Vendor', width: 200),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Due Date', width: 100),
                        TableColumn(label: 'Amount', width: 120),
                        TableColumn(label: 'Balance', width: 100),
                        TableColumn(label: 'Status', width: 120),
                      ],
                      showCheckbox: true,
                      rows: filtered.map((bill) {
                        final balance = bill.total - bill.amountPaid;
                        return AppTableRow(
                          cells: [
                            Text(bill.billNumber, style: AppTypography.labelLarge),
                            Text(bill.contact?.name ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(bill.billDate), style: AppTypography.bodySmall),
                            Text(_formatDate(bill.dueDate), style: AppTypography.bodySmall),
                            AppAmountText(amount: bill.total, style: AppTypography.amountTiny),
                            AppAmountText(amount: balance, style: AppTypography.amountTiny),
                            AppStatusBadge(status: _parseStatus(bill.status)),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  InvoiceStatus _parseStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID': return InvoiceStatus.paid;
      case 'PARTIAL': return InvoiceStatus.partial;
      case 'OVERDUE': return InvoiceStatus.overdue;
      case 'DRAFT': return InvoiceStatus.draft;
      case 'CANCELLED': return InvoiceStatus.cancelled;
      default: return InvoiceStatus.pending;
    }
  }

  String _formatDate(String date) {
    if (date.isEmpty) return '-';
    try {
      final d = DateTime.parse(date);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}';
    } catch (_) {
      return date;
    }
  }
}
