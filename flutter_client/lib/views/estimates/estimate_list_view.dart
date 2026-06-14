import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/estimates/estimate_form_view.dart';
import 'package:flutter_client/views/estimates/estimate_detail_view.dart';

class EstimateListView extends StatefulWidget {
  const EstimateListView({super.key});

  @override
  State<EstimateListView> createState() => _EstimateListViewState();
}

class _EstimateListViewState extends State<EstimateListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';
  List<dynamic> _estimates = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const _statusOptions = ['ALL', 'DRAFT', 'CONFIRMED', 'ACCEPTED', 'CANCELLED'];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final list = await context.read<DocumentProvider>().fetchEstimates();
    if (mounted) {
      setState(() {
        _estimates = list;
        _isLoading = false;
      });
    }
  }

  void _showForm({Map<String, dynamic>? estimate}) async {
    Map<String, dynamic>? fullEstimate = estimate;
    if (estimate != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      fullEstimate = await context.read<DocumentProvider>().fetchEstimateDetail(estimate['id']);
      if (mounted) Navigator.pop(context);
      if (fullEstimate == null) {
        if (mounted) AppToast.error(context, 'Failed to load estimate details');
        return;
      }
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => EstimateFormView(editEstimate: fullEstimate)),
      ).then((_) => _fetch());
    }
  }

  void _showDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EstimateDetailView(estimateId: id)),
    ).then((_) => _fetch());
  }

  Future<void> _cancelEstimate(String id) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this estimate?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = await provider.cancelEstimate(id);
      if (success) {
        _fetch();
      } else if (mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  List<dynamic> get _filteredEstimates {
    var list = _estimates;
    if (_statusFilter != 'ALL') {
      list = list.where((e) => e['status'] == _statusFilter).toList();
    }
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((e) {
        final number = (e['proforma_number'] ?? '').toString().toLowerCase();
        final party = (e['contact_name'] ?? '').toString().toLowerCase();
        return number.contains(query) || party.contains(query);
      }).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEstimates;

    final totalCount = _estimates.length;
    final draftCount = _estimates.where((e) => e['status'] == 'DRAFT').length;
    final confirmedCount = _estimates.where((e) => e['status'] == 'CONFIRMED').length;
    final acceptedCount = _estimates.where((e) => e['status'] == 'ACCEPTED').length;
    final cancelledCount = _estimates.where((e) => e['status'] == 'CANCELLED').length;

    num totalAmount = 0;
    for (final e in filtered) {
      totalAmount += double.tryParse((e['total'] ?? 0).toString()) ?? 0;
    }

    final items = filtered.map((est) {
      return DocumentItemData(
        id: est['id'].toString(),
        docNumber: est['proforma_number']?.toString() ?? 'PROFORMA',
        partyName: est['contact_name']?.toString() ?? 'Guest',
        date: (est['issue_date'] ?? est['created_at'] ?? '').toString(),
        amount: double.tryParse((est['total'] ?? 0).toString()) ?? 0,
        status: est['status'] ?? 'DRAFT',
      );
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: DocumentListView(
        title: 'Estimates & Proformas',
        searchController: _searchCtrl,
        searchHint: 'Search by estimate no, contact...',
        onSearchChanged: (_) => setState(() {}),
        filterTabs: [
          FilterTab('ALL', totalCount),
          FilterTab('DRAFT', draftCount),
          FilterTab('CONFIRMED', confirmedCount),
          FilterTab('ACCEPTED', acceptedCount),
          FilterTab('CANCELLED', cancelledCount),
        ],
        activeFilter: _statusFilter,
        onFilterChanged: (tab) => setState(() => _statusFilter = tab),
        summary: ListSummaryData(totalAmount: totalAmount.toDouble(), totalCount: totalCount),
        items: items,
        isLoading: _isLoading && _estimates.isEmpty,
        onRefresh: () async => _fetch(),
        emptyTitle: 'No estimates found',
        emptySubtitle: 'Create estimates or proformas to send to your customers',
        emptyIcon: Icons.request_quote_outlined,
        detailBuilder: (ctx, item) => EstimateDetailView(estimateId: item.id),
        itemBuilder: (context, item, index) {
          final actions = <Widget>[
            if (item.status == 'DRAFT')
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: () {
                  final match = _estimates.firstWhere((e) => e['id'].toString() == item.id, orElse: () => {});
                  _showForm(estimate: match);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            if (item.status != 'CANCELLED')
              IconButton(
                icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                onPressed: () => _cancelEstimate(item.id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ];

          return CompactDocumentCard(
            docNumber: item.docNumber,
            partyName: item.partyName,
            date: item.date?.isNotEmpty == true ? item.date : null,
            amount: item.amount,
            status: item.status,
            onTap: () => _showDetail(item.id),
            actions: actions,
          );
        },
      ),
    );
  }
}
