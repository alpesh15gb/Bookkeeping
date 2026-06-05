import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
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
          // ── Search + Filter Bar ──
          Container(
            color: AppColors.bgSurface,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 8,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search estimates...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppColors.borderInput),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            borderSide: const BorderSide(color: AppColors.borderInput),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showForm(),
                        icon: const Icon(Icons.add, size: 16, color: AppColors.textWhite),
                        label: const Text('Create Estimate', style: TextStyle(fontSize: 12, color: AppColors.textWhite)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandNavy,
                          foregroundColor: AppColors.textWhite,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChipWithCount(
                        label: 'All', count: totalCount,
                        isSelected: _statusFilter == 'ALL',
                        onTap: () => setState(() => _statusFilter = 'ALL'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Draft', count: draftCount,
                        isSelected: _statusFilter == 'DRAFT',
                        onTap: () => setState(() => _statusFilter = 'DRAFT'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Confirmed', count: confirmedCount,
                        isSelected: _statusFilter == 'CONFIRMED',
                        onTap: () => setState(() => _statusFilter = 'CONFIRMED'),
                      ),
                      const SizedBox(width: 6),
                      FilterChipWithCount(
                        label: 'Accepted', count: acceptedCount,
                        isSelected: _statusFilter == 'ACCEPTED',
                        onTap: () => setState(() => _statusFilter = 'ACCEPTED'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Amount Summary ──
          if (_estimates.isNotEmpty)
            AmountSummaryCards(cards: [
              AmountSummaryCardData(label: 'Total Value', value: formatAmt(totalAmount), color: AppColors.brandNavy),
              AmountSummaryCardData(label: 'Accepted', value: '$acceptedCount', color: AppColors.success),
              AmountSummaryCardData(label: 'Draft', value: '$draftCount', color: AppColors.textMuted),
            ]),

          // ── Summary Stats ──
          if (_estimates.isNotEmpty)
            SummaryStatsBar(stats: [
              SummaryStat(label: 'Total', count: totalCount, color: AppColors.brandNavy),
              SummaryStat(label: 'Draft', count: draftCount, color: AppColors.textMuted),
              SummaryStat(label: 'Confirmed', count: confirmedCount, color: AppColors.info),
              SummaryStat(label: 'Accepted', count: acceptedCount, color: AppColors.success),
            ]),

          // ── List Body ──
          Expanded(
            child: _isLoading && _estimates.isEmpty
                ? const LoadingState(message: 'Loading estimates...')
                : _errorMessage != null && _estimates.isEmpty
                    ? ErrorState(message: _errorMessage!, onRetry: _fetch)
                    : _estimates.isEmpty
                        ? EmptyState(
                            icon: Icons.request_quote_outlined,
                            title: 'No estimates yet',
                            subtitle: 'Estimates and proforma invoices will appear here',
                            actionLabel: 'Create Estimate',
                            onAction: () => _showForm(),
                          )
                        : filtered.isEmpty
                            ? EmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No matches',
                                subtitle: 'Try adjusting your search or filters',
                                actionLabel: 'Create Estimate',
                                onAction: () => _showForm(),
                              )
                            : RefreshIndicator(
                                onRefresh: () async => _fetch(),
                                child: ListView.separated(
                                  padding: EdgeInsets.only(
                                    left: isMobile ? 12 : 20,
                                    right: isMobile ? 12 : 20,
                                    top: 8,
                                    bottom: isMobile ? 80 : 20,
                                  ),
                                  itemCount: filtered.length,
                                  separatorBuilder: (context, _) => const SizedBox(height: 6),
                                  itemBuilder: (context, i) {
                                    final est = filtered[i];
                                    final status = (est['status'] ?? 'DRAFT').toString();
                                    final dateStr = (est['issue_date'] ?? est['created_at'] ?? '').toString();
                                    final amount = double.tryParse((est['total'] ?? 0).toString()) ?? 0;

                                    return CompactDocumentCard(
                                      docNumber: est['proforma_number']?.toString() ?? 'PROFORMA',
                                      partyName: est['contact_name']?.toString(),
                                      date: dateStr.isNotEmpty ? dateStr : null,
                                      amount: amount,
                                      status: status,
                                      onTap: () => _showDetail(est['id']),
                                      actions: [
                                        if (status == 'DRAFT')
                                          _CompactAction(
                                            icon: Icons.edit_outlined,
                                            tooltip: 'Edit',
                                            onTap: () => _showForm(estimate: est),
                                          ),
                                        if (status != 'CANCELLED')
                                          _CompactAction(
                                            icon: Icons.cancel_outlined,
                                            tooltip: 'Cancel',
                                            color: AppColors.error,
                                            onTap: () => _cancelEstimate(est['id']),
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
}

class _CompactAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _CompactAction({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: (color ?? AppColors.brandNavy).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: color ?? AppColors.brandNavy),
        ),
      ),
    );
  }
}
