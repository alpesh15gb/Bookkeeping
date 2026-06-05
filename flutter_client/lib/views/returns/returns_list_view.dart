import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/providers/document_provider.dart';
import 'package:flutter_client/views/shared/app_components.dart' show StatusBadge, AppConfirmDialog, AppToast;
import 'package:flutter_client/views/shared/design_system.dart';
import 'package:flutter_client/views/shared/toast.dart';
import 'package:flutter_client/views/shared/adaptive_layout.dart';
import 'package:flutter_client/views/shared/transaction_form_view.dart';

class ReturnsListView extends StatefulWidget {
  const ReturnsListView({super.key});

  @override
  State<ReturnsListView> createState() => _ReturnsListViewState();
}

class _ReturnsListViewState extends State<ReturnsListView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _salesReturns = [];
  List<dynamic> _purchaseReturns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetch();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Returns'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sales Returns'),
            Tab(text: 'Purchase Returns'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(_tabController.index == 0),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_salesReturns, true),
                _buildList(_purchaseReturns, false),
              ],
            ),
    );
  }

  Widget _buildList(List<dynamic> items, bool isSales) {
    if (items.isEmpty) return const AppEmptyState(icon: Icons.assignment_return_outlined, title: 'No returns found');
    num totalAmount = 0;
    for (final item in items) {
      totalAmount += double.tryParse((item['total'] ?? 0).toString()) ?? 0;
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, left: 12, right: 12, bottom: 80),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: HeroSummaryCard(
              title: isSales ? 'Total Sales Returns' : 'Total Purchase Returns',
              amount: totalAmount,
              subtitle: '${items.length} returns',
              icon: Icons.assignment_return_outlined,
            ),
          );
        }
        final item = items[index - 1];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: AppCard(
            child: AppListTile(
              leadingText: (item['return_number'] ?? 'R')[0].toString().toUpperCase(),
              title: item['return_number'] ?? 'N/A',
              subtitle: '${item['contact_name'] ?? 'N/A'} | ${AppDate.format(item['issue_date'])}',
              badge: StatusBadge(label: item['status'] ?? 'DRAFT'),
              hoverActions: item['status'] == 'POSTED'
                ? [
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.error),
                      onPressed: () => _cancelItem(item, isSales),
                    ),
                  ]
                : null,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReturnsDetailView(item: item, isSalesReturn: isSales)),
                ).then((_) => _fetch());
              },
            ),
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
                  AppInfoRow(label: 'Subtotal', value: AmountFormat.format(m['subtotal'] ?? 0)),
                  AppInfoRow(label: 'Total', value: AmountFormat.format(m['total'] ?? 0)),
                  if (m['notes'] != null) AppInfoRow(label: 'Notes', value: '${m['notes']}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppSection(
            title: 'Line Items',
            child: Column(
              children: ((m['lines'] is List ? m['lines'] as List : [])).whereType<Map<String, dynamic>>().map((l) => AppCard(
                child: AppListTile(
                  title: '${l['product_name'] ?? 'Product'}',
                  subtitle: 'Qty: ${l['quantity'] ?? 0} @ ${AmountFormat.format(l['rate'] ?? 0)}',
                  trailingWidget: AppAmount(amount: (l['total'] ?? 0).toDouble()),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
