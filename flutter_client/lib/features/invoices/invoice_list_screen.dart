import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../design_system/design_system.dart';
import '../../../models/invoice.dart';
import '../../../providers/invoice_provider.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  String? _selectedStatus;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InvoiceProvider>().fetchInvoices();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoiceProvider = context.watch<InvoiceProvider>();
    final invoices = invoiceProvider.invoices;
    final isLoading = invoiceProvider.isLoading;

    final filteredInvoices = _filterInvoices(invoices);

    final allCount = invoices.length;
    final overdueCount = invoices.where((i) => i.status.toUpperCase() == 'OVERDUE').length;
    final pendingCount = invoices.where((i) => i.status.toUpperCase() == 'PENDING' || i.status.toUpperCase() == 'SENT').length;
    final partialCount = invoices.where((i) => i.status.toUpperCase() == 'PARTIAL').length;
    final paidCount = invoices.where((i) => i.status.toUpperCase() == 'PAID').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Invoices', style: AppTypography.headlineLarge),
            const Spacer(),
            SizedBox(
              width: 400,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search invoice #, customer...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.gray200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.gray200),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppButton(
              label: '+ Invoice',
              icon: Icons.add,
              onPressed: () => context.go('/invoices/create'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Row(
          children: [
            AppFilterChip(
              label: 'All',
              count: allCount,
              isSelected: _selectedStatus == null,
              onTap: () => setState(() => _selectedStatus = null),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Overdue',
              count: overdueCount,
              selectedColor: AppColors.error,
              isSelected: _selectedStatus == 'OVERDUE',
              onTap: () => setState(() => _selectedStatus = 'OVERDUE'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Pending',
              count: pendingCount,
              selectedColor: AppColors.info,
              isSelected: _selectedStatus == 'PENDING',
              onTap: () => setState(() => _selectedStatus = 'PENDING'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Partial',
              count: partialCount,
              selectedColor: AppColors.warning,
              isSelected: _selectedStatus == 'PARTIAL',
              onTap: () => setState(() => _selectedStatus = 'PARTIAL'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Paid',
              count: paidCount,
              selectedColor: AppColors.success,
              isSelected: _selectedStatus == 'PAID',
              onTap: () => setState(() => _selectedStatus = 'PAID'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        Expanded(
          child: isLoading && invoices.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filteredInvoices.isEmpty
                  ? AppEmptyState(
                      icon: Icons.receipt_long,
                      title: 'No invoices found',
                      subtitle: _searchQuery.isNotEmpty ? 'Try a different search' : 'Create your first invoice',
                    )
                  : AppTable(
                      columns: const [
                        TableColumn(label: 'Invoice #', width: 130),
                        TableColumn(label: 'Customer', width: 200),
                        TableColumn(label: 'Date', width: 100),
                        TableColumn(label: 'Due Date', width: 100),
                        TableColumn(label: 'Amount', width: 110),
                        TableColumn(label: 'Paid', width: 100),
                        TableColumn(label: 'Balance', width: 100),
                        TableColumn(label: 'Status', width: 120),
                      ],
                      showCheckbox: true,
                      rows: filteredInvoices.map((inv) {
                        final isOverdue = inv.status.toUpperCase() == 'OVERDUE';
                        final balance = inv.total - inv.amountPaid;

                        return AppTableRow(
                          onTap: () => context.go('/invoices/${inv.id}'),
                          backgroundColor: isOverdue ? AppColors.error.withOpacity(0.03) : null,
                          cells: [
                            Text(inv.invoiceNumber, style: AppTypography.labelLarge),
                            Text(inv.contactName ?? '', style: AppTypography.bodyMedium),
                            Text(_formatDate(inv.issueDate), style: AppTypography.bodySmall),
                            Text(_formatDate(inv.dueDate), style: AppTypography.bodySmall),
                            AppAmountText(amount: inv.total, style: AppTypography.amountTiny),
                            AppAmountText(amount: inv.amountPaid, style: AppTypography.amountTiny),
                            AppAmountText(
                              amount: balance,
                              style: AppTypography.amountTiny.copyWith(
                                color: balance > 0 ? AppColors.error : null,
                              ),
                            ),
                            AppStatusBadge(
                              status: _parseStatus(inv.status),
                              additionalInfo: isOverdue ? _daysOverdue(inv.dueDate) : null,
                            ),
                          ],
                        );
                      }).toList(),
                    ),
        ),
      ],
    );
  }

  List<InvoiceModel> _filterInvoices(List<InvoiceModel> invoices) {
    var result = invoices;

    if (_selectedStatus != null) {
      result = result.where((i) => i.status.toUpperCase() == _selectedStatus).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((i) =>
        i.invoiceNumber.toLowerCase().contains(q) ||
        (i.contactName?.toLowerCase().contains(q) ?? false)
      ).toList();
    }

    return result;
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

  String? _daysOverdue(String dueDate) {
    try {
      final due = DateTime.parse(dueDate);
      final diff = DateTime.now().difference(due).inDays;
      return diff > 0 ? '$diff days' : null;
    } catch (_) {
      return null;
    }
  }
}
