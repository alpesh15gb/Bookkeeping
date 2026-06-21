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
                  : _buildEnhancedTable(filteredInvoices),
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
  Widget _buildEnhancedTable(List<InvoiceModel> invoices) {
    final columns = [
      const AppTableColumn(
        label: 'Invoice #',
        width: 130,
        fieldKey: 'invoice_number',
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Customer',
        width: 200,
        fieldKey: 'contact_name',
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Date',
        width: 100,
        fieldKey: 'issue_date',
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Due Date',
        width: 100,
        fieldKey: 'due_date',
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Amount',
        width: 110,
        fieldKey: 'total',
        alignment: Alignment.centerRight,
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Paid',
        width: 100,
        fieldKey: 'amount_paid',
        alignment: Alignment.centerRight,
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Balance',
        width: 100,
        fieldKey: 'balance',
        alignment: Alignment.centerRight,
        isSortable: true,
      ),
      const AppTableColumn(
        label: 'Status',
        width: 120,
        fieldKey: 'status',
        alignment: Alignment.center,
        isSortable: true,
      ),
    ];

    final rows = invoices.map((inv) {
      final balance = inv.total - inv.amountPaid;
      return <String, dynamic>{
        'invoice_number': inv.invoice_number,
        'contact_name': inv.contactName ?? '',
        'issue_date': _formatDate(inv.issueDate),
        'due_date': _formatDate(inv.dueDate),
        'total': inv.total,
        'amount_paid': inv.amountPaid,
        'balance': balance,
        'status': inv.status,
        '_parseStatus': _parseStatus(inv.status),
        '_isOverdue': inv.status.toUpperCase() == 'OVERDUE',
        '_daysOverdue': _daysOverdue(inv.dueDate),
        '_id': inv.id,
      };
    }).toList();

    // Calculate totals for sticky footer
    final totalAmount = invoices.fold<double>(0, (sum, inv) => sum + inv.total);
    final totalPaid = invoices.fold<double>(0, (sum, inv) => sum + inv.amountPaid);
    final totalBalance = invoices.fold<double>(0, (sum, inv) => sum + (inv.total - inv.amountPaid));

    return AppTable(
      title: '${invoices.length} invoice${invoices.length == 1 ? '' : 's'}',
      columns: columns,
      rows: rows,
      stickyHeader: true,
      stickyFooter: true,
      density: AppTableDensity.comfortable,
      enableKeyboardNav: true,
      enableColumnChooser: true,
      enableExport: true,
      onRowTap: (row) => context.go('/invoices/${row['_id']}'),
      onRefresh: () async => context.read<InvoiceProvider>().fetchInvoices(),
      summaryRows: [
        {
          'invoice_number': 'TOTALS',
          'contact_name': '',
          'issue_date': '',
          'due_date': '',
          'total': totalAmount,
          'amount_paid': totalPaid,
          'balance': totalBalance,
          'status': '',
          'is_bold': true,
        },
      ],
    );
  }
}
