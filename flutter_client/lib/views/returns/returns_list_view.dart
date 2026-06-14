import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart';
import 'package:flutter_client/views/shared/design_system.dart' hide AppCard;
import 'package:flutter_client/views/shared/document_list_view.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class ReturnsListView extends StatefulWidget {
  const ReturnsListView({super.key});

  @override
  State<ReturnsListView> createState() => _ReturnsListViewState();
}

class _ReturnsListViewState extends State<ReturnsListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchCtrl = TextEditingController();
  List<dynamic> _salesReturns = [];
  List<dynamic> _purchaseReturns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _fetch() async {
    setState(() => _isLoading = true);
    final sr = await context.read<DocumentProvider>().fetchSalesReturns();
    final pr = await context.read<DocumentProvider>().fetchPurchaseReturns();
    if (mounted) {
      setState(() {
        _salesReturns = sr;
        _purchaseReturns = pr;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelItem(dynamic item, bool isSales) async {
    final confirm = await AppConfirmDialog.show(context, title: 'Cancel?', message: 'Cancel this return?');
    if (confirm == true) {
      final provider = context.read<DocumentProvider>();
      final success = isSales
          ? await provider.cancelSalesReturn(item['id'])
          : await provider.cancelPurchaseReturn(item['id']);
      if (success) {
        _fetch();
      } else if (mounted) {
        AppToast.error(context, provider.errorMessage ?? 'Cancel failed');
      }
    }
  }

  void _showForm(bool isSales) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReturnsFormView(isSalesReturn: isSales)),
    ).then((_) => _fetch());
  }

  List<dynamic> _filterList(List<dynamic> list) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return list;
    return list.where((item) {
      final number = (item['return_number'] ?? '').toString().toLowerCase();
      final contact = (item['contact_name'] ?? '').toString().toLowerCase();
      return number.contains(query) || contact.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(_tabController.index == 0),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.bgSurface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.brandNavy,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.goldAccent,
              indicatorWeight: 3,
              labelStyle: AppTextStyles.tabLabel.copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: AppTextStyles.tabLabel,
              onTap: (_) => setState(() {}),
              tabs: const [
                Tab(text: 'SALES RETURNS'),
                Tab(text: 'PURCHASE RETURNS'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const LoadingState(message: 'Loading returns...')
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTab(_salesReturns, true),
                      _buildTab(_purchaseReturns, false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(List<dynamic> allItems, bool isSales) {
    final filtered = _filterList(allItems);

    final totalCount = allItems.length;
    final draftCount = allItems.where((e) => e['status'] == 'DRAFT').length;
    final postedCount = allItems.where((e) => e['status'] == 'POSTED').length;
    final cancelledCount = allItems.where((e) => e['status'] == 'CANCELLED').length;

    num totalAmount = 0;
    for (final item in allItems) {
      totalAmount += double.tryParse((item['total'] ?? 0).toString()) ?? 0;
    }

    final items = filtered.map((item) {
      return DocumentItemData(
        id: item['id'].toString(),
        docNumber: item['return_number'] ?? 'RET',
        partyName: item['contact_name'] ?? 'N/A',
        date: item['issue_date']?.toString(),
        amount: double.tryParse((item['total'] ?? 0).toString()) ?? 0,
        status: item['status'] ?? 'DRAFT',
      );
    }).toList();

    return DocumentListView(
      title: isSales ? 'Sales Returns' : 'Purchase Returns',
      searchController: _searchCtrl,
      searchHint: 'Search returns...',
      onSearchChanged: (_) => setState(() {}),
      filterTabs: [
        FilterTab('ALL', totalCount),
        FilterTab('DRAFT', draftCount),
        FilterTab('POSTED', postedCount),
        FilterTab('CANCELLED', cancelledCount),
      ],
      activeFilter: 'ALL',
      onFilterChanged: (_) {},
      summary: ListSummaryData(totalAmount: totalAmount.toDouble(), totalCount: totalCount),
      items: items,
      isLoading: false,
      onRefresh: () async => _fetch(),
      emptyTitle: 'No ${isSales ? "Sales" : "Purchase"} Returns',
      emptySubtitle: '${isSales ? "Sales" : "Purchase"} returns will appear here once created',
      emptyIcon: Icons.assignment_return_outlined,
      detailBuilder: (ctx, item) {
        final match = allItems.firstWhere((e) => e['id'].toString() == item.id, orElse: () => {});
        return ReturnsDetailView(item: match, isSalesReturn: isSales);
      },
      itemBuilder: (context, item, index) {
        return AppCard(
          child: AppListTile(
            leadingText: item.docNumber[0].toUpperCase(),
            title: item.docNumber,
            subtitle: '${item.partyName} · ${item.date != null ? AppDate.format(item.date) : ""}',
            badge: StatusBadge(label: item.status),
            hoverActions: item.status == 'POSTED'
                ? [
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                      onPressed: () {
                        final match = allItems.firstWhere((e) => e['id'].toString() == item.id, orElse: () => {});
                        _cancelItem(match, isSales);
                      },
                    ),
                  ]
                : null,
            onTap: () {
              final match = allItems.firstWhere((e) => e['id'].toString() == item.id, orElse: () => {});
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReturnsDetailView(item: match, isSalesReturn: isSales)),
              ).then((_) => _fetch());
            },
          ),
        );
      },
    );
  }
}

class ReturnsFormView extends StatelessWidget {
  final bool isSalesReturn;
  const ReturnsFormView({super.key, required this.isSalesReturn});

  @override
  Widget build(BuildContext context) {
    final title = isSalesReturn ? 'Sales Return' : 'Purchase Return';
    return TransactionFormView(
      config: TransactionConfig(
        title: title,
        contactLabel: isSalesReturn ? 'Customer' : 'Vendor',
        contactType: isSalesReturn ? 'CUSTOMER' : 'VENDOR',
        numberLabel: 'Return Number',
        numberKey: 'return_number',
        isPurchase: !isSalesReturn,
        hasReferenceNo: false,
        hasShippingAddress: false,
        hasLinkedInvoice: false,
        allowScanning: false,
        successMessage: '$title saved successfully',
        onSave: (ctx, payload) async {
          final provider = ctx.read<DocumentProvider>();
          final success = isSalesReturn
              ? await provider.createSalesReturn(payload)
              : await provider.createPurchaseReturn(payload);
          if (!success && ctx.mounted) {
            AppToast.error(ctx, provider.errorMessage ?? 'Failed to save return');
          }
          return success;
        },
        onPreview: null,
      ),
    );
  }
}

class ReturnsDetailView extends StatelessWidget {
  final dynamic item;
  final bool isSalesReturn;
  const ReturnsDetailView({super.key, required this.item, required this.isSalesReturn});

  @override
  Widget build(BuildContext context) {
    final title = isSalesReturn ? 'Sales Return' : 'Purchase Return';
    final m = item is Map<String, dynamic> ? item as Map<String, dynamic> : <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(title: Text('$title Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m['return_number'] ?? 'N/A', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  AppInfoRow(label: 'Status', value: '${m['status'] ?? 'N/A'}'),
                  AppInfoRow(label: 'Issue Date', value: AppDate.format(m['issue_date'])),
                  AppInfoRow(label: 'Subtotal', value: AmountFormat.format(double.tryParse((m['subtotal'] ?? 0).toString()) ?? 0)),
                  AppInfoRow(label: 'Total', value: AmountFormat.format(double.tryParse((m['total'] ?? 0).toString()) ?? 0)),
                  if (m['notes'] != null) AppInfoRow(label: 'Notes', value: '${m['notes']}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppSection(
            title: 'Line Items',
            child: Column(
              children: ((m['lines'] is List ? m['lines'] as List : []))
                  .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
                  .whereType<Map<String, dynamic>>()
                  .map((l) => AppCard(
                child: AppListTile(
                  title: '${l['product_name'] ?? 'Product'}',
                  subtitle: 'Qty: ${l['quantity'] ?? 0} @ ${AmountFormat.format(double.tryParse((l['rate'] ?? 0).toString()) ?? 0)}',
                  trailingWidget: AppAmount(amount: double.tryParse((l['total'] ?? 0).toString()) ?? 0),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
