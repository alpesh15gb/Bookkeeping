import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/models/bill.dart';
import 'package:flutter_client/providers/bill_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/bills/bill_detail_view.dart';
import 'package:flutter_client/utils/haptic_helper.dart';

class BillListView extends StatefulWidget {
  const BillListView({super.key});

  @override
  State<BillListView> createState() => _BillListViewState();
}

class _BillListViewState extends State<BillListView> {
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
    context.read<BillProvider>().fetchBills();
  }

  String _balanceLabel(BillModel bill) {
    if (bill.status == 'PAID') return 'Paid';
    if (bill.status == 'PARTIALLY_PAID') return 'Partial';
    return 'Unpaid';
  }

  num _balanceAmount(BillModel bill) => bill.total - bill.amountPaid;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BillProvider>();
    final bills = provider.bills;

    final totalCount = bills.length;
    final draftCount = bills.where((b) => b.status == 'DRAFT').length;
    final postedCount = bills.where((b) => b.status == 'POSTED').length;
    final paidCount = bills.where((b) => b.status == 'PAID').length;
    final partialCount = bills.where((b) => b.status == 'PARTIALLY_PAID').length;
    final cancelledCount = bills.where((b) => b.status == 'CANCELLED').length;

    num totalAmount = 0, paidAmount = 0, outstandingAmount = 0;
    for (final b in bills) {
      totalAmount += b.total;
      paidAmount += b.amountPaid;
      final bal = b.total - b.amountPaid;
      if (bal > 0) outstandingAmount += bal;
    }

    return DocumentListView(
      title: 'Vendor Bills',
      detailBuilder: (ctx, item) => BillDetailView(billId: item.id),
      items: bills.map((bill) {
        final partyName = bill.contact?.name ?? '';
        final bal = _balanceAmount(bill);
        return DocumentItemData(
          id: bill.id.toString(),
          docNumber: bill.billNumber,
          partyName: partyName.isNotEmpty ? partyName : null,
          date: bill.billDate,
          amount: bill.total,
          status: bill.status,
          balanceLabel: _balanceLabel(bill),
          balanceAmount: bal > 0 ? bal : null,
        );
      }).toList(),
      filterTabs: [
        FilterTab('ALL', totalCount),
        FilterTab('DRAFT', draftCount),
        FilterTab('POSTED', postedCount),
        FilterTab('PAID', paidCount),
        FilterTab('PARTIALLY_PAID', partialCount),
        FilterTab('CANCELLED', cancelledCount),
      ],
      activeFilter: _statusFilter,
      onFilterChanged: (tab) {
        setState(() => _statusFilter = tab);
      },
      summary: ListSummaryData(
        totalAmount: totalAmount.toDouble(),
        paidAmount: paidAmount.toDouble(),
        pendingAmount: outstandingAmount.toDouble(),
        totalCount: totalCount,
      ),
      searchController: _searchCtrl,
      searchHint: 'Search bills...',
      onSearchChanged: (_) {},
      onRefresh: () async => _fetch(),
      isLoading: provider.isLoading && bills.isEmpty,
      emptyTitle: 'No bills found',
      emptySubtitle: _statusFilter != 'ALL' || _searchCtrl.text.isNotEmpty
          ? 'Try clearing your filters'
          : 'Create your first bill to get started',
      emptyIcon: Icons.receipt_long_outlined,
    );
  }
}
