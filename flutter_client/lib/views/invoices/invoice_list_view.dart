import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/providers/invoice_provider.dart';
import 'package:flutter_client/models/invoice.dart';
import 'package:flutter_client/views/invoices/invoice_detail_view.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';

class InvoiceListView extends StatefulWidget {
  const InvoiceListView({super.key});

  @override
  State<InvoiceListView> createState() => _InvoiceListViewState();
}

class _InvoiceListViewState extends State<InvoiceListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';

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
    );
  }

  String _balanceLabel(InvoiceModel invoice) {
    if (invoice.status == 'PAID') return 'Paid';
    if (invoice.status == 'PARTIALLY_PAID') return 'Partial';
    return 'Unpaid';
  }

  num _balanceAmount(InvoiceModel invoice) => invoice.total - invoice.amountPaid;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InvoiceProvider>();
    final invoices = provider.invoices;

    final totalCount = invoices.length;
    final draftCount = invoices.where((i) => i.status == 'DRAFT').length;
    final sentCount = invoices.where((i) => i.status == 'SENT' || i.status == 'POSTED').length;
    final paidCount = invoices.where((i) => i.status == 'PAID').length;
    final partialCount = invoices.where((i) => i.status == 'PARTIALLY_PAID').length;
    final cancelledCount = invoices.where((i) => i.status == 'CANCELLED').length;

    num totalAmount = 0, collectedAmount = 0, outstandingAmount = 0;
    for (final inv in invoices) {
      totalAmount += inv.total;
      collectedAmount += inv.amountPaid;
      final balance = inv.total - inv.amountPaid;
      if (balance > 0) outstandingAmount += balance;
    }

    return DocumentListView(
      title: 'Sale Invoices',
      detailBuilder: (ctx, item) => InvoiceDetailView(invoiceId: item.id),
      items: invoices.map((inv) {
        final partyName = inv.contactName ?? inv.contact?.name ?? '';
        final bal = _balanceAmount(inv);
        return DocumentItemData(
          id: inv.id.toString(),
          docNumber: inv.invoiceNumber,
          partyName: partyName.isNotEmpty ? partyName : null,
          date: inv.issueDate,
          amount: inv.total,
          status: inv.status,
          balanceLabel: _balanceLabel(inv),
          balanceAmount: bal > 0 ? bal : null,
        );
      }).toList(),
      filterTabs: [
        FilterTab('ALL', totalCount),
        FilterTab('DRAFT', draftCount),
        FilterTab('SENT', sentCount),
        FilterTab('PAID', paidCount),
        FilterTab('PARTIALLY_PAID', partialCount),
        FilterTab('CANCELLED', cancelledCount),
      ],
      activeFilter: _statusFilter,
      onFilterChanged: (tab) {
        setState(() => _statusFilter = tab);
        _fetch();
      },
      summary: ListSummaryData(
        totalAmount: totalAmount.toDouble(),
        paidAmount: collectedAmount.toDouble(),
        pendingAmount: outstandingAmount.toDouble(),
        totalCount: totalCount,
      ),
      searchController: _searchCtrl,
      searchHint: 'Search invoices...',
      onSearchChanged: (_) => _fetch(),
      onRefresh: () async => _fetch(),
      isLoading: provider.isLoading && invoices.isEmpty,
      emptyTitle: 'No invoices found',
      emptySubtitle: _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
          ? 'Try clearing your filters'
          : 'Create your first invoice to get started',
      emptyIcon: Icons.description_outlined,
    );
  }
}
