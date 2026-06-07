import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/estimates/estimate_form_view.dart';
import 'package:flutter_client/views/estimates/estimate_detail_view.dart';
import 'package:flutter_client/views/shared/skeleton_loading.dart';

class EstimateListView extends StatefulWidget {
  const EstimateListView({super.key});

  @override
  State<EstimateListView> createState() => _EstimateListViewState();
}

class _EstimateListViewState extends State<EstimateListView> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'ALL';

  static const _statusOptions = ['ALL', 'DRAFT', 'CONFIRMED', 'ACCEPTED', 'CANCELLED'];

  List<dynamic> _estimates = [];
  bool _isLoading = true;
  String? _errorMessage;

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
        if (mounted) {
          AppToast.error(context, 'Failed to load estimate details');
        }
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
    final isMobile = AdaptiveLayout.isMobile(context);
    final filtered = _filteredEstimates;

    final totalCount = _estimates.length;
    final draftCount = _estimates.where((e) => e['status'] == 'DRAFT').length;
    final confirmedCount = _estimates.where((e) => e['status'] == 'CONFIRMED').length;
    final acceptedCount = _estimates.where((e) => e['status'] == 'ACCEPTED').length;

    num totalAmount = 0;
    for (final e in _estimates) {
      totalAmount += double.tryParse((e['total'] ?? 0).toString()) ?? 0;
    }

    if (isMobile) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showForm(),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: AppInput(
                controller: _searchCtrl,
                hint: 'Search estimates...',
                prefix: const Icon(Icons.search_rounded, size: 16),
                suffix: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            AppStatusTabBar(
              tabs: const ['ALL', 'DRAFT', 'CONFIRMED', 'ACCEPTED', 'CANCELLED'],
              activeTab: _statusFilter,
              onTabChanged: (tab) {
                setState(() => _statusFilter = tab);
              },
              badges: {
                'ALL': totalCount,
                'DRAFT': draftCount,
                'CONFIRMED': confirmedCount,
                'ACCEPTED': acceptedCount,
                'CANCELLED': _estimates.where((e) => e['status'] == 'CANCELLED').length,
              },
            ),
            Expanded(
              child: _isLoading && _estimates.isEmpty
                  ? ListSkeleton()
                  : _errorMessage != null && _estimates.isEmpty
                      ? ErrorState(message: _errorMessage!, onRetry: _fetch)
                      : filtered.isEmpty
                          ? AppEmptyState(
                              icon: Icons.request_quote_outlined,
                              title: 'No estimates match your search',
                              subtitle: 'Try clearing the filters or create an estimate',
                              actionLabel: 'Create Estimate',
                              onAction: () => _showForm(),
                            )
                          : RefreshIndicator(
                              onRefresh: () async => _fetch(),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (context, _) => const SizedBox(height: 4),
                                itemBuilder: (context, i) {
                                  final est = filtered[i];
                                  final status = (est['status'] ?? 'DRAFT').toString();
                                  final dateStr = (est['issue_date'] ?? est['created_at'] ?? '').toString();
                                  final amount = double.tryParse((est['total'] ?? 0).toString()) ?? 0;
                                  final docNo = est['proforma_number']?.toString() ?? 'PROFORMA';
                                  final partyName = est['contact_name']?.toString() ?? 'Guest';

                                  return CompactDocumentCard(
                                    docNumber: docNo,
                                    partyName: partyName,
                                    date: dateStr.isNotEmpty ? dateStr : null,
                                    amount: amount,
                                    status: status,
                                    onTap: () => _showDetail(est['id']),
                                    actions: [
                                      if (status == 'DRAFT')
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 16),
                                          onPressed: () => _showForm(estimate: est),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      if (status != 'CANCELLED')
                                        IconButton(
                                          icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.error),
                                          onPressed: () => _cancelEstimate(est['id']),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Column(
        children: [
          AppCommandBar(
            title: 'Estimates & Proformas',
            searchWidget: AppInput(
              controller: _searchCtrl,
              hint: 'Search by estimate no, contact...',
              prefix: const Icon(Icons.search_rounded, size: 16),
              onChanged: (_) => setState(() {}),
            ),
            actions: [
              AppButton(
                label: 'Create Estimate',
                icon: Icons.add,
                isPrimary: true,
                onTap: () => _showForm(),
              ),
            ],
          ),
          AppStatusTabBar(
            tabs: const ['ALL', 'DRAFT', 'CONFIRMED', 'ACCEPTED', 'CANCELLED'],
            activeTab: _statusFilter,
            onTabChanged: (tab) {
              setState(() => _statusFilter = tab);
            },
            badges: {
              'ALL': totalCount,
              'DRAFT': draftCount,
              'CONFIRMED': confirmedCount,
              'ACCEPTED': acceptedCount,
              'CANCELLED': _estimates.where((e) => e['status'] == 'CANCELLED').length,
            },
          ),
          Expanded(
            child: _isLoading && _estimates.isEmpty
                ? ListSkeleton()
                : _errorMessage != null && _estimates.isEmpty
                    ? ErrorState(message: _errorMessage!, onRetry: _fetch)
                    : filtered.isEmpty
                        ? AppEmptyState(
                            icon: Icons.request_quote_outlined,
                            title: 'No estimates found',
                            subtitle: 'Create estimates or proformas to send to your customers',
                            actionLabel: 'Create Estimate',
                            onAction: () => _showForm(),
                          )
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: AppColors.bgSurface,
                                  border: Border(bottom: BorderSide(color: AppColors.border)),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(flex: 2, child: Text('DATE', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 2, child: Text('ESTIMATE NO', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 4, child: Text('PARTY / CUSTOMER', style: AppTextStyles.labelSmall)),
                                    Expanded(flex: 3, child: Text('AMOUNT', style: AppTextStyles.labelSmall, textAlign: TextAlign.right)),
                                    Expanded(flex: 2, child: Text('STATUS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                    SizedBox(width: 100, child: Text('ACTIONS', style: AppTextStyles.labelSmall, textAlign: TextAlign.center)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.borderLight),
                                  itemBuilder: (context, index) {
                                    final est = filtered[index];
                                    final id = est['id'].toString();
                                    final docNo = est['proforma_number']?.toString() ?? 'PROFORMA';
                                    final partyName = est['contact_name']?.toString() ?? 'Guest';
                                    final amount = double.tryParse((est['total'] ?? 0).toString()) ?? 0;
                                    final status = est['status']?.toString() ?? 'DRAFT';
                                    final dateStr = (est['issue_date'] ?? est['created_at'] ?? '').toString();

                                    return InkWell(
                                      onTap: () => _showDetail(id),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                dateStr.isNotEmpty ? AppDate.format(dateStr) : '--',
                                                style: AppTextStyles.bodySmall,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                docNo,
                                                style: AppTextStyles.bodyMedium.copyWith(
                                                  color: AppColors.brandNavy,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 4,
                                              child: Row(
                                                children: [
                                                  AppAvatar(name: partyName, size: 24),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      partyName,
                                                      style: AppTextStyles.partyName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                AmountFormat.format(amount),
                                                style: AppTextStyles.amount,
                                                textAlign: TextAlign.right,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Center(
                                                child: AppInlineStatus(status: status),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 100,
                                              child: AppRowActions(
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.visibility_outlined, size: 16),
                                                    onPressed: () => _showDetail(id),
                                                    tooltip: 'View Detail',
                                                  ),
                                                  if (status == 'DRAFT')
                                                    IconButton(
                                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                                      onPressed: () => _showForm(estimate: est),
                                                      tooltip: 'Edit',
                                                    ),
                                                  if (status != 'CANCELLED')
                                                    IconButton(
                                                      icon: const Icon(Icons.cancel_outlined, size: 16),
                                                      color: AppColors.error,
                                                      onPressed: () => _cancelEstimate(id),
                                                      tooltip: 'Cancel',
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}
